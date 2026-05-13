import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:atomic_x_core/api/call/call_store.dart';
import 'package:atomic_x_core/api/device/device_store.dart';
import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/features/push/data/push_service.dart';
import 'package:emergency_helper/src/features/trtc/data/call_phase.dart';
import 'package:emergency_helper/src/features/trtc/data/custom_call_navigator.dart';
import 'package:emergency_helper/src/features/trtc/data/participant_name_registry.dart';
import 'package:emergency_helper/src/features/trtc/data/trtc_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart' as rtc;
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

class TUICallSessionService {
  TUICallSessionService._();

  static final TUICallSessionService instance = TUICallSessionService._();

  /// Generate a unique room ID based on timestamp + random suffix.
  /// Room ID format: (timestamp_ms % 10B) * 100 + [0-99]
  static int generateRoomId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(100);
    return (now % 10000000000) * 100 + random;
  }

  static const Duration _ensureLoginTimeout = Duration(seconds: 20);
  static const List<Duration> _warmupRetryBackoffs = <Duration>[
    Duration.zero,
    Duration(seconds: 2),
    Duration(seconds: 5),
  ];

  final TrtcService _trtcService = const TrtcService();
  Future<TUICallSessionState>? _ongoingEnsureTask;
  Future<void>? _ongoingWarmupTask;
  Future<void> _sessionTransitionQueue = Future<void>.value();
  String? _activeUserId;
  int? _activeSdkAppId;
  String? _activeUserSig;
  DateTime? _activeUserSigFetchedAt;
  int _sessionEpoch = 0;
  static const Duration _activeSigReuseWindow = Duration(minutes: 30);

  /// Global call observer for multi-device sync notifications.
  rtc.TUICallObserver? _globalCallObserver;
  final List<void Function(String message)> _callNotificationListeners = [];

  /// Global IM message listener to detect TUICall signaling messages
  /// that the FFI layer fails to forward (e.g., otherDeviceAccepted).
  V2TimAdvancedMsgListener? _imSignalingListener;
  final Set<String> _handledCallIds = {};

  /// Set to true when the local user actively rejects a call.
  /// Prevents the observer from showing a "通话被拒绝" toast on the callee's
  /// own device (the local UI already handles dismissal).
  bool _isLocalRejection = false;

  /// Mark whether the local device is actively rejecting a call.
  /// Called by IncomingCallPage before/after CallStore.shared.reject().
  void markLocalRejection(bool value) {
    _isLocalRejection = value;
  }

  /// Register listener to receive multi-device call sync events.
  void addCallNotificationListener(void Function(String) listener) {
    _callNotificationListeners.add(listener);
  }

  void removeCallNotificationListener(void Function(String) listener) {
    _callNotificationListeners.remove(listener);
  }

  void _notifyCall(String message) {
    for (final listener in List.of(_callNotificationListeners)) {
      listener(message);
    }
  }

  /// Stop everything and notify — await native cleanup before showing toast.
  Future<void> _stopAndNotify(String message) async {
    await _stopIncomingCall();
    CustomCallNavigator.instance.dismissAllCallScreens();
    CallSessionManager.instance.resetToIdle();
    _notifyCall(message);
  }

  /// Stop incoming call ringtone, vibration, and close incoming UI.
  Future<void> _stopIncomingCall() async {
    // Native-side: stop vibration, ringtone, and close incoming call UI.
    // This uses reflection to call TUICallEngine.hangup() and
    // CallingVibrator.stopVibration() directly on the Android side.
    try {
      debugPrint('[TRTC-Session] stopping incoming call via native workaround');
      const channel = MethodChannel('com.tianyanzhiyun/trtc_workaround');
      await channel.invokeMethod('stopIncomingCallAndFinish', {});
    } catch (error, stackTrace) {
      debugPrint('[TRTC-Session] stopIncomingCallAndFinish failed: $error');
      debugPrint('[TRTC-Session] stack: $stackTrace');
    }
  }

  AppDependencies? _observerDependencies;

  /// Initialize global call observer. Should be called once after login.
  void initCallObserver({AppDependencies? dependencies}) {
    _observerDependencies = dependencies;
    if (_globalCallObserver != null) {
      disposeCallObserver();
    }
    _globalCallObserver = rtc.TUICallObserver(
      onCallReceived: (callId, callerId, calleeIdList, mediaType, info) {
        debugPrint(
          '[TRTC-DEBUG][Observer] onCallReceived callId=$callId '
          'callerId=$callerId mediaType=$mediaType calleeList=$calleeIdList',
        );
        final mediaStr = _mediaTypeToString(mediaType);
        final sessionBefore = CallSessionManager.instance.current;
        debugPrint('[TRTC-DEBUG][Observer] onCallReceived currentPhase=${sessionBefore.phase}');

        // If we are the caller (outgoingRinging), update callId and send push
        // with real callId so cold-starting callees can join the active call.
        if (sessionBefore.phase == CallPhase.outgoingRinging) {
          debugPrint('[TRTC-DEBUG][Observer] onCallReceived on caller side, updating callId=$callId');
          CallSessionManager.instance.updateCallId(callId);
          final selfId = instance.activeUserId;
          final callerName = _resolveCallerNameForPush(selfId);
          for (final calleeId in calleeIdList) {
            if (calleeId == selfId) continue;
            unawaited(_sendMissedCallPushNotification(
              calleeUserId: calleeId,
              callerId: selfId,
              callerName: callerName,
              callId: callId,
              mediaType: sessionBefore.mediaType,
            ));
          }
          // Don't create incoming call session on caller side.
          return;
        }

        // If already on an incoming call screen (stale state from a previous
        // uncleaned call), dismiss it and reset to idle before navigating
        // to the new incoming call.
        if (sessionBefore.phase == CallPhase.incomingRinging) {
          debugPrint('[TRTC-DEBUG][Observer] onCallReceived: stale incomingRinging state, dismissing first');
          CallSessionManager.instance.resetToIdle();
          CustomCallNavigator.instance.dismissAllCallScreens();
        }

        CallSessionManager.instance.markIncomingCall(
          callId: callId,
          callerId: callerId,
          mediaType: mediaStr,
        );
        // Navigate to custom incoming call UI.
        // Priority: info.userData (from TUICallParams) > ParticipantNameRegistry > CallStore > callerId
        final callerName = _resolveCallerName(callerId, info);
        // Register caller name for display in call UI
        ParticipantNameRegistry.register(callerId, callerName);
        debugPrint('[TRTC-DEBUG][Observer] navigating to trtcIncomingCall for callId=$callId, callerName=$callerName');
        CustomCallNavigator.instance.navigateToIncomingCall(
          callId: callId,
          callerId: callerId,
          callerName: callerName,
          mediaType: mediaStr,
        );
      },
      onCallNotConnected: (callId, mediaType, reason, userId, info) {
        debugPrint(
          '[TRTC-DEBUG][Observer] onCallNotConnected callId=$callId '
          'reason=$reason(${reason.index}) userId=$userId mediaType=${_mediaTypeToString(mediaType)}',
        );
        // Save session state BEFORE _dismissCall resets it to idle.
        // This is critical for distinguishing "caller hung up" from
        // "other device accepted" — both arrive as hangup(1).
        final sessionBefore = CallSessionManager.instance.current;
        final wasIncomingRinging = sessionBefore.phase == CallPhase.incomingRinging && sessionBefore.callId == callId;
        debugPrint('[TRTC-DEBUG][Observer] wasIncomingRinging=$wasIncomingRinging phase=${sessionBefore.phase}');
        _dismissCall(callId);
        switch (reason) {
          case rtc.CallEndReason.otherDeviceAccepted:
            debugPrint('[TRTC-DEBUG][Observer] branch: otherDeviceAccepted');
            _notifyCall('通话已在其他设备接听');
            CallSessionManager.instance.resetToIdle();
            CustomCallNavigator.instance.dismissAllCallScreens();
            break;
          case rtc.CallEndReason.hangup:
            debugPrint('[TRTC-DEBUG][Observer] branch: hangup');
            // If we were in incoming ringing and didn't answer locally,
            // the call was accepted on another device — NOT caller hangup.
            if (wasIncomingRinging) {
              debugPrint('[TRTC-DEBUG][Observer] onCallNotConnected: hangup during incomingRinging → other device accepted');
              _notifyCall('通话已在其他设备接听');
              CallSessionManager.instance.resetToIdle();
              CustomCallNavigator.instance.dismissAllCallScreens();
            } else {
              final selfUserId = instance.activeUserId;
              if (userId.isNotEmpty && selfUserId.isNotEmpty && userId != selfUserId) {
                debugPrint('[TRTC-DEBUG][Observer] onCallNotConnected: hangup by remote (userId=$userId)');
                _notifyCall('对方已挂断通话');
                CallSessionManager.instance.resetToIdle();
                CustomCallNavigator.instance.dismissAllCallScreens();
              } else {
                debugPrint('[TRTC-DEBUG][Observer] onCallNotConnected: hangup by self (userId=$userId)');
                CallSessionManager.instance.resetToIdle();
                CustomCallNavigator.instance.dismissAllCallScreens();
              }
            }
            break;
          case rtc.CallEndReason.reject:
          case rtc.CallEndReason.unknown:
            // ⚠️ rtc_room_engine 4.0.1 FFI bug:
            // otherDeviceAccepted(7) 被映射为 unknown(0) 或 reject(2)
            debugPrint('[TRTC-DEBUG][Observer] branch: reject/unknown');
            final session = CallSessionManager.instance.current;
            if (session.phase == CallPhase.incomingRinging && session.callId == callId) {
              // Incoming call not answered locally → other device handled
              debugPrint('[TRTC-DEBUG][Observer] incomingRinging not answered → other device handled');
              unawaited(_stopAndNotify('通话已在其他设备接听'));
            } else {
              CallSessionManager.instance.resetToIdle();
              CustomCallNavigator.instance.dismissAllCallScreens();
              // If this device actively rejected the call, skip the toast —
              // the local UI in IncomingCallPage already handles dismissal.
              if (_isLocalRejection) {
                debugPrint('[TRTC-DEBUG][Observer] local rejection, skipping toast');
                return;
              }
              if (reason == rtc.CallEndReason.unknown) {
                debugPrint('[TRTC-DEBUG][Observer] real unknown, ignoring');
                _notifyCall('通话未接通');
              } else {
                _notifyCall('通话被拒绝');
              }
            }
            break;
          case rtc.CallEndReason.otherDeviceReject:
            debugPrint('[TRTC-DEBUG][Observer] branch: otherDeviceReject');
            _notifyCall('通话已在其他设备拒绝');
            CallSessionManager.instance.resetToIdle();
            CustomCallNavigator.instance.dismissAllCallScreens();
            break;
          case rtc.CallEndReason.canceled:
            debugPrint('[TRTC-DEBUG][Observer] branch: canceled');
            final selfUserId = instance.activeUserId;
            if (userId.isNotEmpty && selfUserId.isNotEmpty && userId != selfUserId) {
              debugPrint('[TRTC-DEBUG][Observer] onCallNotConnected: canceled by remote (userId=$userId)');
              _notifyCall('对方已取消通话');
            } else {
              debugPrint('[TRTC-DEBUG][Observer] onCallNotConnected: canceled by self (userId=$userId)');
              _notifyCall('通话已取消');
            }
            CallSessionManager.instance.resetToIdle();
            CustomCallNavigator.instance.dismissAllCallScreens();
            break;
          case rtc.CallEndReason.noResponse:
            debugPrint('[TRTC-DEBUG][Observer] branch: noResponse');
            // Cold-start scenario: user clicked push notification but by the
            // time warmup completed and observer registered, the call had
            // already timed out. Show "call ended" toast.
            if (wasIncomingRinging) {
              debugPrint('[TRTC-DEBUG][Observer] noResponse during incomingRinging → call expired before user could answer');
              _notifyCall('通话已结束');
              CallSessionManager.instance.resetToIdle();
              CustomCallNavigator.instance.dismissAllCallScreens();
              break;
            }
            // Cold-start from push: warmup completed after call already expired,
            // phase is still idle. Show "call ended" toast.
            if (sessionBefore.phase == CallPhase.idle) {
              debugPrint('[TRTC-DEBUG][Observer] noResponse on cold-start (idle phase) → call expired before warmup completed');
              CustomCallNavigator.showCallEndedToast = true;
              CustomCallNavigator.instance.dismissAllCallScreens();
              break;
            }
            // If this device was the caller (outgoingRinging), send a missed
            // call push notification to the callee.
            // Note: markOutgoingCall sets callId='' because SDK hasn't assigned
            // one yet, so we only check phase, not callId match.
            if (sessionBefore.phase == CallPhase.outgoingRinging) {
              debugPrint('[TRTC-DEBUG][Observer] noResponse on caller side, sending missed call push');
              final calleeIds = sessionBefore.inviteeIds;
              if (calleeIds.isNotEmpty) {
                final selfId = instance.activeUserId;
                final callerName = _resolveCallerNameForPush(selfId);
                for (final calleeId in calleeIds) {
                  unawaited(_sendMissedCallPushNotification(
                    calleeUserId: calleeId,
                    callerId: selfId,
                    callerName: callerName,
                    callId: callId,
                    mediaType: sessionBefore.mediaType,
                  ));
                }
              }
            }
            _notifyCall('对方无应答');
            CallSessionManager.instance.resetToIdle();
            CustomCallNavigator.instance.dismissAllCallScreens();
            break;
          case rtc.CallEndReason.lineBusy:
            debugPrint('[TRTC-DEBUG][Observer] branch: lineBusy');
            // If this device was the caller (outgoingRinging), send a missed
            // call push notification to the callee.
            // Note: markOutgoingCall sets callId='' because SDK hasn't assigned
            // one yet, so we only check phase, not callId match.
            if (sessionBefore.phase == CallPhase.outgoingRinging) {
              debugPrint('[TRTC-DEBUG][Observer] lineBusy on caller side, sending missed call push');
              final calleeIds = sessionBefore.inviteeIds;
              if (calleeIds.isNotEmpty) {
                final selfId = instance.activeUserId;
                final callerName = _resolveCallerNameForPush(selfId);
                for (final calleeId in calleeIds) {
                  unawaited(_sendMissedCallPushNotification(
                    calleeUserId: calleeId,
                    callerId: selfId,
                    callerName: callerName,
                    callId: callId,
                    mediaType: sessionBefore.mediaType,
                  ));
                }
              }
            }
            _notifyCall('对方正忙');
            CallSessionManager.instance.resetToIdle();
            CustomCallNavigator.instance.dismissAllCallScreens();
            break;
          default:
            debugPrint('[TRTC-DEBUG][Observer] branch: DEFAULT (unhandled reason=${reason.index})');
            CallSessionManager.instance.resetToIdle();
            CustomCallNavigator.instance.dismissAllCallScreens();
        }
      },
      onCallBegin: (callId, mediaType, info) {
        final mediaStr = _mediaTypeToString(mediaType);
        CallSessionManager.instance.markInCall(callId: callId);
        debugPrint(
          '[TRTC-DEBUG][Observer] onCallBegin callId=$callId '
          'mediaType=$mediaStr',
        );
        debugPrint('[TRTC-DEBUG][Observer] onCallBegin: current session phase=${CallSessionManager.instance.current.phase}');
        debugPrint('[TRTC-DEBUG][Observer] onCallBegin: onCallBeginForInCallPage=${CustomCallNavigator.instance.onCallBeginForInCallPage != null}');
        // NOTE: Do NOT call DeviceStore.openLocalCamera here.
        // The camera is opened by CallParticipantView when InCallPage renders,
        // which needs the view to be created for proper video binding.
        // Call _initDeviceStates in InCallPage to open microphone.

        // For the caller side (already on InCallPage), trigger video re-mount
        // via callback instead of navigating (which would pop the existing page).
        if (CustomCallNavigator.instance.onCallBeginForInCallPage != null) {
          debugPrint('[TRTC-DEBUG][Observer] caller already on InCallPage, triggering callback');
          CustomCallNavigator.instance.onCallBeginForInCallPage!();
          return;
        }

        // For the callee side (on IncomingCallPage), navigate to InCallPage.
        // For the callee side (on IncomingCallPage), navigate to InCallPage.
        debugPrint('[TRTC-DEBUG][Observer] navigating to trtcInCall callId=$callId mediaType=$mediaStr');
        CustomCallNavigator.instance.navigateToInCall(
          callId: callId,
          mediaType: mediaStr,
          selfUserId: instance.activeUserId,
          isCallerSide: false,
        );
      },
      onCallEnd: (callId, mediaType, reason, userId, totalTime, info) {
        debugPrint(
          '[TRTC-DEBUG][Observer] onCallEnd callId=$callId '
          'reason=$reason(${reason.index}) userId=$userId totalTime=${totalTime}s',
        );
        // Save session state BEFORE _dismissCall resets it to idle.
        final sessionBefore = CallSessionManager.instance.current;
        final wasIncomingRinging = sessionBefore.phase == CallPhase.incomingRinging && sessionBefore.callId == callId;
        debugPrint('[TRTC-DEBUG][Observer] onCallEnd wasIncomingRinging=$wasIncomingRinging phase=${sessionBefore.phase}');
        _dismissCall(callId);
        switch (reason) {
          case rtc.CallEndReason.otherDeviceAccepted:
            debugPrint('[TRTC-DEBUG][Observer] onCallEnd branch: otherDeviceAccepted');
            _notifyCall('通话已在其他设备接听');
            CallSessionManager.instance.resetToIdle();
            CustomCallNavigator.instance.dismissAllCallScreens();
            break;
          case rtc.CallEndReason.lineBusy:
          case rtc.CallEndReason.otherDeviceReject:
            debugPrint('[TRTC-DEBUG][Observer] onCallEnd branch: lineBusy/otherDeviceReject');
            // If this device was the caller, send a missed call push.
            // Note: markOutgoingCall sets callId='' because SDK hasn't assigned
            // one yet, so we only check phase, not callId match.
            if (sessionBefore.phase == CallPhase.outgoingRinging) {
              debugPrint('[TRTC-DEBUG][Observer] lineBusy on caller side in onCallEnd, sending missed call push');
              final session = CallSessionManager.instance.current;
              final calleeIds = session.inviteeIds;
              if (calleeIds.isNotEmpty) {
                final selfId = instance.activeUserId;
                final callerName = _resolveCallerNameForPush(selfId);
                for (final calleeId in calleeIds) {
                  unawaited(_sendMissedCallPushNotification(
                    calleeUserId: calleeId,
                    callerId: selfId,
                    callerName: callerName,
                    callId: callId,
                    mediaType: session.mediaType,
                  ));
                }
              }
            }
            _notifyCall('对方正忙');
            CallSessionManager.instance.resetToIdle();
            CustomCallNavigator.instance.dismissAllCallScreens();
            break;
          case rtc.CallEndReason.hangup:
            // If we were in incoming ringing and didn't answer locally,
            // the call was accepted on another device — NOT caller hangup.
            if (wasIncomingRinging) {
              debugPrint('[TRTC-DEBUG][Observer] onCallEnd: hangup during incomingRinging → other device accepted');
              _notifyCall('通话已在其他设备接听');
              CallSessionManager.instance.resetToIdle();
              CustomCallNavigator.instance.dismissAllCallScreens();
            } else {
              final selfUserId = instance.activeUserId;
              if (userId.isNotEmpty && selfUserId.isNotEmpty && userId != selfUserId) {
                debugPrint('[TRTC-DEBUG][Observer] onCallEnd branch: hangup by remote (userId=$userId)');
                _notifyCall('对方已挂断通话');
                CallSessionManager.instance.resetToIdle();
                CustomCallNavigator.instance.dismissAllCallScreens();
              } else {
                debugPrint('[TRTC-DEBUG][Observer] onCallEnd branch: hangup by self (userId=$userId)');
                CallSessionManager.instance.resetToIdle();
                CustomCallNavigator.instance.dismissAllCallScreens();
              }
            }
            break;
          default:
            debugPrint('[TRTC-DEBUG][Observer] onCallEnd branch: default');
            CallSessionManager.instance.resetToIdle();
            CustomCallNavigator.instance.dismissAllCallScreens();
            break;
        }
      },
    );
    rtc.TUICallEngine.instance.addObserver(_globalCallObserver!);
    debugPrint('[TRTC-GlobalObserver] ✅ registered after login');

    // Also register a global IM message listener to detect TUICall signaling
    // messages that the FFI layer fails to forward (e.g., otherDeviceAccepted).
    _initImSignalingListener();
  }

  /// Register a global IM message listener to intercept TUICall signaling
  /// messages. The rtc_room_engine FFI layer has a bug where it doesn't
  /// forward certain events (e.g., otherDeviceAccepted) to Flutter callbacks.
  /// This listener monitors raw IM custom messages and detects call signaling.
  void _initImSignalingListener() {
    _imSignalingListener = V2TimAdvancedMsgListener(
      onRecvNewMessage: _onImSignalingMessage,
      onRecvC2CReadReceipt: (receiptList) {
        debugPrint('[TRTC-IM-Signaling] onRecvC2CReadReceipt: ${receiptList.length} receipts');
      },
    );
    TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .addAdvancedMsgListener(listener: _imSignalingListener!);
    debugPrint('[TRTC-IM-Signaling] ✅ global IM listener registered');
  }

  /// Handle incoming IM messages — look for TUICall signaling that indicates
  /// another device accepted or rejected the call.
  /// During debugging, logs ALL messages received while ringing to identify
  /// the TUICall signaling format.
  void _onImSignalingMessage(V2TimMessage message) {
    final session = CallSessionManager.instance.current;
    final isRinging = session.phase == CallPhase.incomingRinging;

    // Log ALL message types during ringing to identify the signaling format.
    if (isRinging) {
      final msgType = message.elemType ?? 0;
      String summary = 'elemType=$msgType';
      if (message.customElem != null) {
        final data = message.customElem!.data ?? '';
        summary += ', customData=${data.substring(0, data.length.clamp(0, 200))}';
      }
      if (message.textElem != null) {
        final text = message.textElem!.text ?? '';
        summary += ', text=${text.substring(0, text.length.clamp(0, 100))}';
      }
      final cloudData = message.cloudCustomData;
      if (cloudData != null && cloudData.isNotEmpty) {
        summary += ', cloudCustomData=${cloudData.substring(0, cloudData.length.clamp(0, 200))}';
      }
      debugPrint('[TRTC-IM-Signaling] msg while ringing: msgID=${message.msgID ?? "?"}, $summary');
    }

    try {
      final customData = message.customElem?.data;
      if (customData == null || customData.isEmpty) return;

      final data = jsonDecode(customData) as Map<String, dynamic>;
      final businessID = data['businessID'] ?? data['businessId'] ?? '';
      final action = data['action'] ?? '';
      final callId = data['callId'] ?? data['callID'] ?? '';
      final dataStr = data['data'] ?? '';

      final isCallSignaling =
          businessID.toString().contains('call') ||
          action.toString().contains('call') ||
          dataStr.toString().contains('accept') ||
          dataStr.toString().contains('hangup');

      if (!isCallSignaling) return;

      debugPrint('[TRTC-IM-Signaling] call signaling detected: businessID=$businessID, action=$action, callId=$callId, data=$dataStr');

      if (session.phase != CallPhase.incomingRinging) return;
      if (callId.isNotEmpty && session.callId.isNotEmpty && callId != session.callId) return;

      String? notificationMessage;
      if (action.toString().contains('accept') ||
          dataStr.toString().contains('accept') ||
          dataStr.toString().contains('otherDevice')) {
        notificationMessage = '通话已在其他设备接听';
      } else if (action.toString().contains('hangup') ||
          action.toString().contains('cancel') ||
          dataStr.toString().contains('hangup') ||
          dataStr.toString().contains('cancel')) {
        notificationMessage = '对方已挂断通话';
      }

      if (notificationMessage == null) return;

      final key = '$callId:$action';
      if (_handledCallIds.contains(key)) return;
      _handledCallIds.add(key);

      debugPrint('[TRTC-IM-Signaling] >>> triggering dismiss for: $notificationMessage');
      _notifyCall(notificationMessage);
      CallSessionManager.instance.resetToIdle();
      CustomCallNavigator.instance.dismissAllCallScreens();
    } catch (e) {
      // Not JSON or not a TUICall signaling message — ignore.
    }
  }

  /// Common dismissal: clear session tracking for this callId.
  void _dismissCall(String callId) {
    final session = CallSessionManager.instance.current;
    if (session.callId == callId) {
      CallSessionManager.instance.resetToIdle();
    }
  }

  void disposeCallObserver() {
    final observer = _globalCallObserver;
    if (observer != null) {
      rtc.TUICallEngine.instance.removeObserver(observer);
      _globalCallObserver = null;
      debugPrint('[TRTC-GlobalObserver] disposed');
    }
    final imListener = _imSignalingListener;
    if (imListener != null) {
      try {
        TencentImSDKPlugin.v2TIMManager
            .getMessageManager()
            .removeAdvancedMsgListener(listener: imListener);
        debugPrint('[TRTC-IM-Signaling] IM listener disposed');
      } catch (e) {
        debugPrint('[TRTC-IM-Signaling] failed to dispose IM listener: $e');
      }
      _imSignalingListener = null;
    }
    _handledCallIds.clear();
  }

  /// The sdkAppId of the currently active IM session, or null if not logged in.
  int? get activeSdkAppId => _activeSdkAppId;

  String _mediaTypeToString(dynamic mediaType) {
    final str = mediaType.toString().toLowerCase();
    return str.contains('video') ? 'video' : 'audio';
  }

  String _resolveCallerName(String callerId, [dynamic info]) {
    // 0. Try info.userData (from TUICallParams.userData set by caller).
    // This is the most reliable source — it contains the callerName we set
    // when initiating the call, available even on cold-start.
    try {
      final userData = info?.userData as String?;
      if (userData != null && userData.isNotEmpty) {
        final data = jsonDecode(userData) as Map<String, dynamic>;
        final name = _asText(data['callerName']);
        if (name != null && name.isNotEmpty) {
          return name;
        }
      }
    } catch (_) {}
    // 1. Try ParticipantNameRegistry (preloaded from contacts API).
    final registered = ParticipantNameRegistry.resolve(callerId);
    if (registered.isNotEmpty) return registered;
    // 2. Try CallStore participant info.
    try {
      final participants = CallStore.shared.state.allParticipants.value;
      for (final p in participants) {
        if (p.id == callerId) {
          final name = p.remark.isNotEmpty ? p.remark : p.name;
          if (name.isNotEmpty) return name;
        }
      }
    } catch (_) {}
    return callerId;
  }

  /// Preload all contacts from the API into ParticipantNameRegistry,
  /// so that incoming call display can resolve caller names by userId.
  Future<void> _preloadContactNames(AppDependencies dependencies) async {
    try {
      final userResponse = await dependencies.apiClient.getJson(
        AppConstants.userSimpleListPath,
      );
      final userCode = _asInt(userResponse['code']) ?? -1;
      if (userCode != 0) return;

      final userMaps = _asMapList(userResponse['data']);
      var count = 0;
      for (var i = 0; i < userMaps.length; i++) {
        final item = userMaps[i];
        final userId = _idText(item['id']);
        if (userId == null || userId.isEmpty) continue;
        final name = _asText(item['nickname']) ??
            _asText(item['username']) ??
            _asText(item['name']) ??
            _asText(item['realName']);
        if (name == null || name.isEmpty) continue;
        ParticipantNameRegistry.register(userId, name);
        count++;
      }
      debugPrint('[TRTC-Session] preloaded $count contact names into ParticipantNameRegistry');
      // Persist to SharedPreferences for cold-start name resolution.
      unawaited(ParticipantNameRegistry.saveToCache());
    } catch (e) {
      debugPrint('[TRTC-Session] preload contact names failed: $e');
    }
  }

  String? _idText(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty || text == 'null' ? null : text;
  }

  List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) =>
            item.map((key, data) => MapEntry(key.toString(), data)))
        .toList(growable: false);
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  void clearLocalSessionState() {
    _sessionEpoch++;
    _ongoingEnsureTask = null;
    _ongoingWarmupTask = null;
    _sessionTransitionQueue = Future<void>.value();
    _activeUserId = null;
    _activeSdkAppId = null;
    _activeUserSig = null;
    _activeUserSigFetchedAt = null;
    CallSessionManager.instance.resetToIdle();
  }

  Future<void> warmupSessionAndPushInBackground({
    required AppDependencies dependencies,
    int roomIdHint = 0,
    String? userIdHint,
  }) async {
    debugPrint('[TRTC-DEBUG][Warmup] warmupSessionAndPushInBackground STARTED, userIdHint=$_maskSensitive(userIdHint)');
    final running = _ongoingWarmupTask;
    if (running != null) {
      debugPrint('[TRTC-DEBUG][Warmup] warmupSessionAndPushInBackground EARLY RETURN: already running');
      await running;
      return;
    }
    final epoch = _sessionEpoch;
    final task = _warmupSessionAndPushInBackgroundInternal(
      dependencies: dependencies,
      roomIdHint: roomIdHint,
      userIdHint: userIdHint,
      epoch: epoch,
    );
    _ongoingWarmupTask = task;
    try {
      await task;
    } finally {
      if (identical(_ongoingWarmupTask, task)) {
        _ongoingWarmupTask = null;
      }
    }
  }

  Future<void> _warmupSessionAndPushInBackgroundInternal({
    required AppDependencies dependencies,
    required int roomIdHint,
    required String? userIdHint,
    required int epoch,
  }) async {
    debugPrint('[TRTC-DEBUG][Warmup] _warmupSessionAndPushInBackgroundInternal STARTED, epoch=$epoch');
    final totalAttempts = _warmupRetryBackoffs.length;
    for (var index = 0; index < totalAttempts; index++) {
      if (_isEpochStale(epoch)) {
        dependencies.logger.debug(
          '[PUSH-DEBUG] warmup cancelled by session epoch switch',
        );
        return;
      }
      final backoff = _warmupRetryBackoffs[index];
      if (backoff > Duration.zero) {
        await Future<void>.delayed(backoff);
      }
      if (_isEpochStale(epoch)) {
        return;
      }
      final attempt = index + 1;
      try {
        final result = await ensureLoggedIn(
          dependencies: dependencies,
          roomIdHint: roomIdHint,
          userIdHint: userIdHint,
        ).timeout(_ensureLoginTimeout);
        if (_isEpochStale(epoch)) {
          return;
        }
        if (result.success) {
          dependencies.logger.info(
            '[PUSH-DEBUG] warmup IM+push completed on attempt '
            '$attempt/$totalAttempts',
          );
          return;
        }
        dependencies.logger.error(
          '[PUSH-DEBUG] warmup IM+push failed on attempt '
          '$attempt/$totalAttempts: ${result.message}',
        );
      } on TimeoutException catch (error, stackTrace) {
        dependencies.logger.error(
          '[PUSH-DEBUG] warmup IM+push timeout on attempt '
          '$attempt/$totalAttempts',
          error: error,
          stackTrace: stackTrace,
        );
      } catch (error, stackTrace) {
        dependencies.logger.error(
          '[PUSH-DEBUG] warmup IM+push threw on attempt '
          '$attempt/$totalAttempts',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    dependencies.logger.error(
      '[PUSH-DEBUG] warmup IM+push reached retry limit ($totalAttempts)',
    );
  }

  Future<TUICallSessionState> ensureLoggedIn({
    required AppDependencies dependencies,
    int roomIdHint = 0,
    bool forceRefreshSig = false,
    String? userIdHint,
  }) async {
    debugPrint('[TRTC-DEBUG][Warmup] ensureLoggedIn STARTED, userIdHint=$_maskSensitive(userIdHint)');
    final runningTask = _ongoingEnsureTask;
    if (runningTask != null) {
      return runningTask;
    }
    final task = _enqueueSessionTransition<TUICallSessionState>(() {
      return _ensureLoggedInInternal(
        dependencies: dependencies,
        roomIdHint: roomIdHint,
        forceRefreshSig: forceRefreshSig,
        userIdHint: userIdHint,
      );
    });
    _ongoingEnsureTask = task;
    try {
      return await task;
    } finally {
      if (identical(_ongoingEnsureTask, task)) {
        _ongoingEnsureTask = null;
      }
    }
  }

  Future<TUICallSessionState> _ensureLoggedInInternal({
    required AppDependencies dependencies,
    required int roomIdHint,
    required bool forceRefreshSig,
    String? userIdHint,
  }) async {
    debugPrint('[TRTC-DEBUG][Warmup] _ensureLoggedInInternal STARTED');
    final epoch = _sessionEpoch;
    String? currentUserId;

    // Try 1: userIdHint provided directly
    if (userIdHint != null && userIdHint.isNotEmpty) {
      currentUserId = userIdHint.trim();
      dependencies.logger.debug(
        '[PUSH-DEBUG] using userIdHint=${_maskSensitive(currentUserId)}',
      );
      debugPrint('[TRTC-DEBUG][Warmup] Try1 userIdHint=${_maskSensitive(currentUserId)}');
    }

    // Try 2: extract from permission info
    if (currentUserId == null || currentUserId.isEmpty) {
      debugPrint('[TRTC-DEBUG][Warmup] Try2 fetching permission info');
      Map<String, dynamic>? sessionInfo = await dependencies.authService
          .getCachedPermissionInfo();
      sessionInfo ??= await dependencies.authService
          .fetchPermissionInfoAndCache();
      currentUserId = _trtcService.extractCurrentUserId(sessionInfo)?.trim();
      debugPrint('[TRTC-DEBUG][Warmup] Try2 result=${_maskSensitive(currentUserId)}');
      dependencies.logger.debug(
        '[PUSH-DEBUG] extractCurrentUserId result='
        '${_maskSensitive(currentUserId)}',
      );
    }

    // Try 3: fallback to auth-based extraction
    if (currentUserId == null || currentUserId.isEmpty) {
      debugPrint('[TRTC-DEBUG][Warmup] Try3 fallback _tryGetUserIdFromAuth');
      dependencies.logger.debug(
        '[PUSH-DEBUG] falling back to _tryGetUserIdFromAuth',
      );
      currentUserId = await _tryGetUserIdFromAuth(dependencies: dependencies);
      dependencies.logger.debug(
        '[PUSH-DEBUG] fallbackUserId=${_maskSensitive(currentUserId)}',
      );
      debugPrint('[TRTC-DEBUG][Warmup] Try3 result=${_maskSensitive(currentUserId)}');
    }

    if (currentUserId == null || currentUserId.isEmpty) {
      debugPrint('[TRTC-DEBUG][Warmup] FAIL: no userId found');
      return const TUICallSessionState.failure('未获取到当前登录用户ID');
    }

    debugPrint('[TRTC-DEBUG][Warmup] proceeding to _loginWithUserId');
    return _loginWithUserId(
      dependencies: dependencies,
      userId: currentUserId,
      roomIdHint: roomIdHint,
      forceRefreshSig: forceRefreshSig,
      epoch: epoch,
    );
  }

  Future<TUICallSessionState> _loginWithUserId({
    required AppDependencies dependencies,
    required String userId,
    required int roomIdHint,
    required bool forceRefreshSig,
    required int epoch,
  }) async {
    if (_isEpochStale(epoch)) {
      return const TUICallSessionState.failure('SESSION_CANCELLED');
    }
    final currentUserId = userId;
    final nickname =
        _extractNickname(
          await dependencies.authService.getCachedPermissionInfo(),
        ) ??
        currentUserId;
    final avatar =
        _extractAvatar(
          await dependencies.authService.getCachedPermissionInfo(),
        ) ??
        '';
    final roomId = roomIdHint > 0 ? roomIdHint : generateRoomId();

    // TUICallKit.login() internally calls TUICallEngine.init(), which must be
    // called on every ensureLoggedIn invocation. Skipping it causes
    // "TUICallEngine is not initialized" errors. The SDK handles "already
    // login" gracefully, so repeated calls are safe.
    // The only case we skip is when the user is switching accounts — we reset
    // markers above to avoid native logout contention.

    TrtcUserSigInfo userSigInfo;
    var canReuseActiveSig =
        !forceRefreshSig &&
        _activeUserId == currentUserId &&
        (_activeUserSig?.isNotEmpty ?? false) &&
        (_activeSdkAppId ?? 0) > 0 &&
        _isWithinReuseWindow(_activeUserSigFetchedAt);

    if (canReuseActiveSig) {
      try {
        final valid = await _trtcService.verifyUserSig(
          dependencies.apiClient,
          userId: currentUserId,
          userSig: _activeUserSig!,
          logger: dependencies.logger,
        );
        if (!valid) {
          dependencies.logger.info(
            'cached userSig invalid, fallback to fetching a new one',
          );
          canReuseActiveSig = false;
        }
      } catch (error, stackTrace) {
        dependencies.logger.error(
          'verify cached userSig failed, fallback to refresh',
          error: error,
          stackTrace: stackTrace,
        );
        canReuseActiveSig = false;
      }
    }

    if (canReuseActiveSig) {
      userSigInfo = TrtcUserSigInfo(
        sdkAppId: _activeSdkAppId!,
        userId: currentUserId,
        userSig: _activeUserSig!,
        roomId: roomId,
      );
    } else {
      try {
        userSigInfo = await _trtcService.getUserSig(
          dependencies.apiClient,
          userId: currentUserId,
          roomId: roomId,
          logger: dependencies.logger,
        );
      } on AppException catch (error) {
        return TUICallSessionState.failure(error.message);
      } catch (error) {
        return TUICallSessionState.failure('获取音视频签名失败: $error');
      }
    }

    if (userSigInfo.sdkAppId <= 0 || userSigInfo.userSig.trim().isEmpty) {
      return const TUICallSessionState.failure('音视频签名数据无效');
    }

    try {
      if (_isEpochStale(epoch)) {
        return const TUICallSessionState.failure('SESSION_CANCELLED');
      }
      if (_activeUserId != null && _activeUserId != currentUserId) {
        // Avoid native logout during account switch.
        // On some devices this can contend with login/warmup and trigger UI
        // stalls (ANR). We reset in-memory session markers and proceed to
        // login directly.
        _activeUserId = null;
        _activeSdkAppId = null;
        _activeUserSig = null;
        _activeUserSigFetchedAt = null;
      }

      dependencies.logger.debug(
        '[TRTC] >>> TUIRoomEngine.login starting for userId=${_maskSensitive(userSigInfo.userId)} sdkAppId=${userSigInfo.sdkAppId}',
      );
      debugPrint('[TRTC-DEBUG][Warmup] >>> TUIRoomEngine.login starting');
      final roomLoginResult = await rtc.TUIRoomEngine.login(
        userSigInfo.sdkAppId,
        userSigInfo.userId,
        userSigInfo.userSig,
      ).timeout(const Duration(seconds: 15));
      if (_isEpochStale(epoch)) {
        return const TUICallSessionState.failure('SESSION_CANCELLED');
      }
      debugPrint('[TRTC-DEBUG][Warmup] <<< TUIRoomEngine.login: code=${roomLoginResult.code} message=${roomLoginResult.message}');
      dependencies.logger.debug(
        '[TRTC] <<< TUIRoomEngine.login: code=${roomLoginResult.code} message=${roomLoginResult.message}',
      );

      dependencies.logger.debug(
        '[TRTC] >>> TUICallEngine.init starting for userId=${_maskSensitive(userSigInfo.userId)} sdkAppId=${userSigInfo.sdkAppId}',
      );
      final callKitLoginResult = await rtc.TUICallEngine.instance
          .init(userSigInfo.sdkAppId, userSigInfo.userId, userSigInfo.userSig)
          .timeout(const Duration(seconds: 15));
      if (_isEpochStale(epoch)) {
        return const TUICallSessionState.failure('SESSION_CANCELLED');
      }

      // rtc_room_engine uses TUIError enum, success means init OK.
      final callKitReady = callKitLoginResult.code == rtc.TUIError.success;
      debugPrint('[TRTC-DEBUG][Warmup] <<< TUICallEngine.init: code=${callKitLoginResult.code} ready=$callKitReady');
      if (!callKitReady) {
        return TUICallSessionState.failure(
          '音视频初始化失败: ${callKitLoginResult.message ?? "未知错误"}',
        );
      }

      // ✅ Register observer IMMEDIATELY after engine init — the SDK may
      // replay pending call events (onCallReceived) as soon as the IM session
      // is established. Delaying observer registration until after warmup
      // causes these events to be missed on cold-start.
      try {
        initCallObserver(dependencies: dependencies);
      } catch (error, stackTrace) {
        dependencies.logger.error(
          'initCallObserver threw',
          error: error,
          stackTrace: stackTrace,
        );
      }

      // Enable multi-device call notification so that when the same user
      // logs in on multiple devices (PC + mobile), all devices receive
      // incoming calls and auto-dismiss when one device answers/hangs up.
      debugPrint('[TRTC-DEBUG][Warmup] >>> enabling multi-device ability');
      final multiDeviceResult = await rtc.TUICallEngine.instance
          .enableMultiDeviceAbility(true)
          .timeout(const Duration(seconds: 10));
      debugPrint('[TRTC-DEBUG][Warmup] <<< enableMultiDeviceAbility: code=${multiDeviceResult.code} message=${multiDeviceResult.message}');

      dependencies.logger.debug(
        '[TRTC] <<< TUICallEngine.init completed: code=${callKitLoginResult.code} message=${callKitLoginResult.message}',
      );

      // Ensure native engine state is fully established before making calls.
      await Future<void>.delayed(const Duration(seconds: 2));

      // Do not mirror-login via the extra native channel here.
      // TUICallKit login already establishes IM session; duplicate native login
      // increases contention risk in `libdart_native_imsdk` on some devices.

      _activeUserId = currentUserId;
      _activeSdkAppId = userSigInfo.sdkAppId;
      _activeUserSig = userSigInfo.userSig;
      _activeUserSigFetchedAt = DateTime.now();

      // ✅ Restore cached contact names (already done before observer registration
      // above, but keep this as a safety net for warm-start scenarios).
      unawaited(ParticipantNameRegistry.loadFromCache());

      // Set self info is best-effort — TUICallKit.setSelfInfo has a known null
      // check bug (TUICallKitImpl line 118) that crashes on empty avatar.
      // Call continues to work even without it.
      unawaited(
        _setSelfInfoWithRetryDebug(
          dependencies: dependencies,
          nickname: nickname,
          avatar: avatar,
        ),
      );

      // Preload contact names for incoming call display resolution.
      unawaited(_preloadContactNames(dependencies));

      // Disabled: using custom Flutter UI instead of TUICallKit native UI.
      // try {
      //   await TUICallKit.instance.enableFloatWindow(true);
      // } catch (error, stackTrace) {
      //   dependencies.logger.error(
      //     'enableFloatWindow threw',
      //     error: error,
      //     stackTrace: stackTrace,
      //   );
      // }

      // try {
      //   TUICallKit.instance.enableIncomingBanner(true);
      // } catch (error, stackTrace) {
      //   dependencies.logger.error(
      //     'enableIncomingBanner threw',
      //     error: error,
      //     stackTrace: stackTrace,
      //   );
      // }

      unawaited(
        _notifyPushRegistrationInBackground(
          dependencies: dependencies,
          sdkAppId: userSigInfo.sdkAppId,
          userId: currentUserId,
          epoch: epoch,
        ),
      );

      return TUICallSessionState.success(
        userId: currentUserId,
        nickname: nickname,
      );
    } on TimeoutException catch (error) {
      _activeUserId = null;
      _activeSdkAppId = null;
      _activeUserSig = null;
      _activeUserSigFetchedAt = null;
      return TUICallSessionState.failure('音视频登录超时: ${error.message}');
    } catch (error) {
      _activeUserId = null;
      _activeSdkAppId = null;
      _activeUserSig = null;
      _activeUserSigFetchedAt = null;
      return TUICallSessionState.failure('音视频初始化失败: $error');
    }
  }

  Future<void> logoutSilently({AppDependencies? dependencies}) async {
    // Dispose call observer (removes TUICallObserver and IM listener)
    disposeCallObserver();

    // Uninitialize TUICallEngine so native SDK goes offline
    // and stops receiving incoming call notifications.
    try {
      await rtc.TUICallEngine.instance.unInit().timeout(const Duration(seconds: 5));
      debugPrint('[TRTC-DEBUG][Logout] TUICallEngine.unInit success');
    } catch (e) {
      debugPrint('[TRTC-DEBUG][Logout] TUICallEngine.unInit failed: $e');
    }

    clearLocalSessionState();
    await Future<void>.value();
  }

  Future<T> _enqueueSessionTransition<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _sessionTransitionQueue = _sessionTransitionQueue.catchError((_) {}).then((
      _,
    ) async {
      try {
        final value = await action();
        completer.complete(value);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  bool _isWithinReuseWindow(DateTime? fetchedAt) {
    if (fetchedAt == null) {
      return false;
    }
    return DateTime.now().difference(fetchedAt) <= _activeSigReuseWindow;
  }

  /// Quick check if session is already warm (cached signature is valid and recent).
  /// Use this to skip loading overlays when the session is already initialized.
  bool get isSessionWarm {
    return _activeUserId != null &&
        _activeUserId!.isNotEmpty &&
        (_activeUserSig?.isNotEmpty ?? false) &&
        (_activeSdkAppId ?? 0) > 0 &&
        _isWithinReuseWindow(_activeUserSigFetchedAt);
  }

  /// Current active user ID from TRTC session.
  /// Returns empty string if not logged in.
  String get activeUserId => _activeUserId ?? '';

  bool _isEpochStale(int epoch) => epoch != _sessionEpoch;

  Future<void> _notifyPushRegistrationInBackground({
    required AppDependencies dependencies,
    required int sdkAppId,
    required String userId,
    required int epoch,
  }) async {
    if (sdkAppId <= 0) {
      return;
    }
    if (_isEpochStale(epoch)) {
      return;
    }
    try {
      await dependencies.pushService
          .notifyIMLoggedIn(sdkAppId, userId: userId)
          .timeout(const Duration(seconds: 12));
      if (_isEpochStale(epoch)) {
        return;
      }
    } catch (error, stackTrace) {
      dependencies.logger.error(
        'notifyIMLoggedIn after TUICall login failed (non-blocking)',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool> _setSelfInfoWithRetryDebug({
    required AppDependencies dependencies,
    required String nickname,
    required String avatar,
  }) async {
    const maxAttempts = 5;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        debugPrint('[TRTC-DEBUG][Warmup] setSelfInfo attempt $attempt/$maxAttempts');
        final selfInfoResult = await rtc.TUICallEngine.instance.setSelfInfo(
          nickname,
          avatar,
        );
        debugPrint('[TRTC-DEBUG][Warmup] setSelfInfo result: code=${selfInfoResult.code} msg=${selfInfoResult.message}');
        if (selfInfoResult.code == rtc.TUIError.success) {
          debugPrint('[TRTC-DEBUG][Warmup] setSelfInfo SUCCESS');
          return true;
        }
        dependencies.logger.error(
          'set TUICall self info failed: '
          'attempt=$attempt/$maxAttempts, '
          'code=${selfInfoResult.code}, '
          'message=${selfInfoResult.message}',
        );
      } catch (error, stackTrace) {
        dependencies.logger.error(
          'set TUICall self info threw: '
          'attempt=$attempt/$maxAttempts',
          error: error,
          stackTrace: stackTrace,
        );
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    return false;
  }

  Future<String?> _tryGetUserIdFromAuth({
    required AppDependencies dependencies,
  }) async {
    try {
      final token = await dependencies.authLocalStore.getAccessToken();
      dependencies.logger.debug(
        '[PUSH-DEBUG] _tryGetUserIdFromAuth: token=${token != null && token.isNotEmpty ? "present" : "null"}',
      );
      if (token != null && token.isNotEmpty) {
        final info = await dependencies.authService
            .fetchPermissionInfoAndCache();
        final id = _trtcService.extractCurrentUserId(info);
        dependencies.logger.debug(
          '[PUSH-DEBUG] _tryGetUserIdFromAuth: '
          'extractCurrentUserId(info)=${_maskSensitive(id)}',
        );
        if (id != null && id.isNotEmpty) {
          return id;
        }
        final permissionInfo = await dependencies.authService
            .getCachedPermissionInfo();
        final alias = PushService.extractAliasFromPermissionInfo(
          permissionInfo,
        );
        dependencies.logger.debug(
          '[PUSH-DEBUG] _tryGetUserIdFromAuth: '
          'extractAliasFromPermissionInfo=${_maskSensitive(alias)}',
        );
        return alias;
      }
    } catch (e, st) {
      dependencies.logger.error(
        '[PUSH-DEBUG] _tryGetUserIdFromAuth failed',
        error: e,
        stackTrace: st,
      );
    }
    return null;
  }

  String _maskSensitive(String? raw, {int keepPrefix = 2, int keepSuffix = 2}) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) {
      return '--';
    }
    final visibleThreshold = keepPrefix + keepSuffix + 2;
    if (value.length <= visibleThreshold) {
      return '***(${value.length})';
    }
    final prefix = value.substring(0, keepPrefix);
    final suffix = value.substring(value.length - keepSuffix);
    return '$prefix***$suffix(${value.length})';
  }

  /// Resolve caller name for display (used by observer callbacks).
  String _resolveCallerNameForPush(String callerId) {
    final registered = ParticipantNameRegistry.resolve(callerId);
    if (registered.isNotEmpty) return registered;
    try {
      final participants = CallStore.shared.state.allParticipants.value;
      for (final p in participants) {
        if (p.id == callerId) {
          final name = p.remark.isNotEmpty ? p.remark : p.name;
          if (name.isNotEmpty) return name;
        }
      }
    } catch (_) {}
    return callerId;
  }

  /// Send a missed call push notification to the callee when the caller's
  /// call was not answered (timeout or busy). Only called from the caller side.
  Future<void> _sendMissedCallPushNotification({
    required String calleeUserId,
    required String callerId,
    required String callerName,
    required String callId,
    required String mediaType,
  }) async {
    final deps = _observerDependencies;
    if (deps == null) {
      debugPrint('[TRTC-MissedCallPush] skip: no observer dependencies');
      return;
    }
    try {
      final mediaLabel = mediaType == 'video' ? '视频' : '语音';
      final title = '${mediaLabel}邀请';
      final content = '$callerName发来$mediaLabel通话请求，请查看';
      final ext = jsonEncode(<String, dynamic>{
        'page': 'incoming_call',
        'callId': callId,
        'callerId': callerId,
        'callerName': callerName,
        'mediaType': mediaType,
      });
      final androidInfo = jsonEncode(<String, dynamic>{
        // Huawei
        'HuaweiImportance': 'HIGH',
        'HuaweiCategory': 'VOIP',
        // Honor
        'HonorImportance': 'HIGH',
        'HonorCategory': 'VOIP',
        // Xiaomi
        'XiaomiCategory': 'VOIP',
        // OPPO
        'OppoCategory': 'VOIP',
        // Vivo
        'VivoCategory': 'VOIP',
        // Google FCM
        'GooglePriority': 'HIGH',
      });

      debugPrint(
        '[TRTC-MissedCallPush] sending to callee=$calleeUserId '
        'title=$title mediaType=$mediaType',
      );

      final response = await deps.apiClient.postJson(
        '/admin-api/api/trtc/sendToUserNotify',
        queryParameters: <String, dynamic>{
          'userIdList': calleeUserId,
          'title': title,
          'content': content,
          'ext': ext,
          'androidInfo': androidInfo,
        },
      );

      final code = _asInt(response['code']) ?? -1;
      if (code == 0) {
        debugPrint('[TRTC-MissedCallPush] sent successfully');
      } else {
        debugPrint('[TRTC-MissedCallPush] server returned code=$code');
      }
    } catch (e) {
      debugPrint('[TRTC-MissedCallPush] failed: $e');
    }
  }

  /// Check online status for given user IDs via IM SDK.
  /// Returns a map of userId -> statusType (0=unknown, 1=online, 2=offline, 3=unlogged).
  /// Returns empty map on failure (caller should treat as "possibly online").
  Future<Map<String, int>> checkUsersOnlineStatus(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return const <String, int>{};
    try {
      final result = await TencentImSDKPlugin.v2TIMManager
          .getUserStatus(userIDList: userIds)
          .timeout(const Duration(seconds: 3));
      if (result.code != 0) {
        debugPrint('[TRTC-OnlineStatus] getUserStatus failed: code=${result.code}');
        return const <String, int>{};
      }
      final statusList = result.data ?? [];
      final map = <String, int>{};
      for (final s in statusList) {
        map[s.userID ?? ''] = s.statusType ?? 0;
      }
      debugPrint(
        '[TRTC-OnlineStatus] ${map.length}/${userIds.length} users checked: '
        '${map.entries.map((e) => '${e.key}=${e.value}').join(', ')}',
      );
      return map;
    } catch (e) {
      debugPrint('[TRTC-OnlineStatus] getUserStatus error: $e');
      return const <String, int>{};
    }
  }

  /// Send an offline push notification immediately when all targets are offline.
  /// Used as a fast path before attempting TRTC call.
  /// Send an offline push notification for a call invite.
  /// If callId is empty, reads from CallSessionManager (populated by SDK observer).
  /// Falls back to a generated UUID if still unavailable.
  Future<void> sendOfflineCallPushNotification({
    required List<String> calleeUserIds,
    required String callerId,
    required String callerName,
    required String mediaType, // 'video' or 'audio'
    String callId = '',
  }) async {
    final deps = _observerDependencies;
    if (deps == null) {
      debugPrint('[TRTC-OfflinePush] skip: no observer dependencies');
      return;
    }
    if (calleeUserIds.isEmpty) return;

    // Resolve callId: parameter > CallSessionManager > generated UUID
    var resolvedCallId = callId;
    if (resolvedCallId.isEmpty) {
      resolvedCallId = CallSessionManager.instance.current.callId;
    }
    if (resolvedCallId.isEmpty) {
      resolvedCallId = _generateUuid();
      debugPrint('[TRTC-OfflinePush] generated fallback callId=$resolvedCallId');
    }

    try {
      final mediaLabel = mediaType == 'video' ? '视频' : '语音';
      final title = '${mediaLabel}邀请';
      final content = '$callerName发来$mediaLabel通话请求，请查看';
      final ext = jsonEncode(<String, dynamic>{
        'page': 'incoming_call',
        'callId': resolvedCallId,
        'callerId': callerId,
        'callerName': callerName,
        'mediaType': mediaType,
      });
      final androidInfo = jsonEncode(<String, dynamic>{
        // Huawei
        'HuaweiImportance': 'HIGH',
        'HuaweiCategory': 'VOIP',
        // Honor
        'HonorImportance': 'HIGH',
        'HonorCategory': 'VOIP',
        // Xiaomi
        'XiaomiCategory': 'VOIP',
        // OPPO
        'OppoCategory': 'VOIP',
        // Vivo
        'VivoCategory': 'VOIP',
        // Google FCM
        'GooglePriority': 'HIGH',
      });

      final userIdStr = calleeUserIds.join(',');
      debugPrint(
        '[TRTC-OfflinePush] sending to ${calleeUserIds.length} users: $userIdStr '
        'title=$title mediaType=$mediaType',
      );

      final response = await deps.apiClient.postJson(
        '/admin-api/api/trtc/sendToUserNotify',
        queryParameters: <String, dynamic>{
          'userIdList': userIdStr,
          'title': title,
          'content': content,
          'ext': ext,
          'androidInfo': androidInfo,
        },
      );

      final code = _asInt(response['code']) ?? -1;
      if (code == 0) {
        debugPrint('[TRTC-OfflinePush] sent successfully to $userIdStr');
      } else {
        debugPrint('[TRTC-OfflinePush] server returned code=$code');
      }
    } catch (e) {
      debugPrint('[TRTC-OfflinePush] failed: $e');
    }
  }

  String? _extractNickname(Map<String, dynamic>? sessionInfo) {
    if (sessionInfo == null || sessionInfo.isEmpty) {
      return null;
    }
    final permissionInfo = _asMap(sessionInfo['permissionInfo']) ?? sessionInfo;
    final permissionData = _asMap(permissionInfo['data']) ?? permissionInfo;
    final profileInfo = _asMap(sessionInfo['profileInfo']);
    final profileData = _asMap(profileInfo?['data']) ?? profileInfo;

    return _pickFirstText(<Object?>[
      _asMap(permissionData['user'])?['nickname'],
      _asMap(permissionData['user'])?['name'],
      _asMap(permissionData['user'])?['realName'],
      permissionData['nickname'],
      permissionData['name'],
      permissionData['realName'],
      _asMap(profileData?['user'])?['nickname'],
      _asMap(profileData?['user'])?['name'],
      profileData?['nickname'],
      profileData?['name'],
      profileData?['realName'],
    ]);
  }

  String? _extractAvatar(Map<String, dynamic>? sessionInfo) {
    if (sessionInfo == null || sessionInfo.isEmpty) {
      return null;
    }
    final permissionInfo = _asMap(sessionInfo['permissionInfo']) ?? sessionInfo;
    final permissionData = _asMap(permissionInfo['data']) ?? permissionInfo;
    final profileInfo = _asMap(sessionInfo['profileInfo']);
    final profileData = _asMap(profileInfo?['data']) ?? profileInfo;
    return _pickFirstText(<Object?>[
      _asMap(permissionData['user'])?['avatar'],
      _asMap(permissionData['user'])?['avatarUrl'],
      _asMap(permissionData['user'])?['avatarURL'],
      permissionData['avatar'],
      permissionData['avatarUrl'],
      permissionData['avatarURL'],
      _asMap(profileData?['user'])?['avatar'],
      _asMap(profileData?['user'])?['avatarUrl'],
      _asMap(profileData?['user'])?['avatarURL'],
      profileData?['avatar'],
      profileData?['avatarUrl'],
      profileData?['avatarURL'],
    ]);
  }

  String? _pickFirstText(List<Object?> candidates) {
    for (final candidate in candidates) {
      final text = _asText(candidate);
      if (text != null) {
        return text;
      }
    }
    return null;
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, data) => MapEntry(key.toString(), data));
    }
    return null;
  }

  String? _asText(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }

  static String _generateUuid() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    return '${_hex(bytes, 0, 4)}-${_hex(bytes, 4, 2)}-${_hex(bytes, 6, 2)}-${_hex(bytes, 8, 2)}-${_hex(bytes, 10, 6)}';
  }

  static String _hex(List<int> bytes, int offset, int count) {
    final buf = StringBuffer();
    for (var i = 0; i < count; i++) {
      buf.write('${bytes[offset + i].toRadixString(16).padLeft(2, '0')}');
    }
    return buf.toString();
  }
}

class TUICallSessionState {
  const TUICallSessionState._({
    required this.success,
    required this.message,
    this.userId,
    this.nickname,
  });

  const TUICallSessionState.success({
    required String userId,
    required String nickname,
  }) : this._(success: true, message: '', userId: userId, nickname: nickname);

  const TUICallSessionState.failure(String message)
    : this._(success: false, message: message);

  final bool success;
  final String message;
  final String? userId;
  final String? nickname;
}
