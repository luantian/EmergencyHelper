import 'dart:async';
import 'dart:math';

import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/features/push/data/push_service.dart';
import 'package:emergency_helper/src/features/trtc/data/custom_call_navigator.dart';
import 'package:emergency_helper/src/features/trtc/data/trtc_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart' as rtc;
import 'package:tencent_calls_uikit/tencent_calls_uikit.dart';

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

  /// Track active incoming call IDs on this device.
  final Set<String> _incomingCallIds = {};

  /// Whether the local user answered the current incoming call.
  bool _localUserAnsweredIncoming = false;

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

  /// Mark a call as incoming on this device. Call when incoming call UI shows.
  void markIncomingCall(String callId) {
    _incomingCallIds.add(callId);
    debugPrint('[TRTC-Session] markIncomingCall callId=$callId, 当前集合=$_incomingCallIds');
  }

  /// Mark that the local user answered the current incoming call.
  void markLocalUserAnswered() {
    _localUserAnsweredIncoming = true;
    debugPrint('[TRTC-Session] markLocalUserAnswered');
  }

  /// Check if the call ended due to another device handling it (FFI bug workaround).
  /// Returns true if this was an incoming call on this device that was NOT answered locally.
  bool _isOtherDeviceHandled(String callId) {
    final wasIncoming = _incomingCallIds.remove(callId);
    final answeredLocally = _localUserAnsweredIncoming;
    _localUserAnsweredIncoming = false;
    debugPrint('[TRTC-Workaround] callId=$callId wasIncoming=$wasIncoming answeredLocally=$answeredLocally');
    return wasIncoming && !answeredLocally;
  }

  /// Stop everything and notify — await native cleanup before showing toast.
  Future<void> _stopAndNotify(String message) async {
    await _stopIncomingCall();
    CustomCallNavigator.instance.dismissAllCallScreens();
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

  /// Initialize global call observer. Should be called once after login.
  void initCallObserver() {
    if (_globalCallObserver != null) {
      disposeCallObserver();
    }
    _globalCallObserver = rtc.TUICallObserver(
      onCallReceived: (callId, callerId, calleeIdList, mediaType, info) {
        debugPrint(
          '[TRTC-GlobalObserver] 📞 onCallReceived callId=$callId '
          'callerId=$callerId mediaType=$mediaType',
        );
        markIncomingCall(callId);
        // Navigate to custom incoming call UI.
        CustomCallNavigator.instance.navigateToIncomingCall(
          callId: callId,
          callerId: callerId,
          callerName: _resolveCallerName(callerId),
          mediaType: _mediaTypeToString(mediaType),
        );
      },
      onCallNotConnected: (callId, mediaType, reason, userId, info) {
        debugPrint(
          '[TRTC-GlobalObserver] 🔔 onCallNotConnected callId=$callId '
          'reason=$reason(${reason.index}) userId=$userId',
        );
        switch (reason) {
          case rtc.CallEndReason.otherDeviceAccepted:
            _incomingCallIds.remove(callId);
            _localUserAnsweredIncoming = false;
            _notifyCall('通话已在其他设备接听');
            break;
          case rtc.CallEndReason.hangup:
            // 可能是正常挂断，也可能是 FFI bug 映射
            final wasIncoming = _incomingCallIds.remove(callId);
            if (wasIncoming && !_localUserAnsweredIncoming) {
              debugPrint('[TRTC-Workaround] hangup on incoming call → other device handled');
              _localUserAnsweredIncoming = false;
              CustomCallNavigator.instance.dismissAllCallScreens();
              unawaited(_stopAndNotify('通话已在其他设备接听'));
            } else {
              _localUserAnsweredIncoming = false;
            }
            break;
          case rtc.CallEndReason.reject:
          case rtc.CallEndReason.unknown:
            // ⚠️ rtc_room_engine 4.0.1 FFI bug:
            // otherDeviceAccepted(7) 被映射为 unknown(0) 或 reject(2)
            if (_isOtherDeviceHandled(callId)) {
              // 手动挂断来电以停止 SDK 的响铃 UI（FFI bug 导致 SDK 无法自动关闭）
              CustomCallNavigator.instance.dismissAllCallScreens();
              unawaited(_stopAndNotify('通话已在其他设备接听'));
            } else {
              if (reason == rtc.CallEndReason.unknown) {
                debugPrint('[TRTC] 真实 unknown，忽略');
              } else {
                _notifyCall('通话被拒绝');
              }
            }
            break;
          case rtc.CallEndReason.otherDeviceReject:
            _incomingCallIds.remove(callId);
            _localUserAnsweredIncoming = false;
            _notifyCall('通话已在其他设备拒绝');
            break;
          case rtc.CallEndReason.canceled:
            _incomingCallIds.remove(callId);
            _localUserAnsweredIncoming = false;
            _notifyCall('对方已取消通话');
            break;
          case rtc.CallEndReason.noResponse:
            _incomingCallIds.remove(callId);
            _localUserAnsweredIncoming = false;
            _notifyCall('对方无应答');
            break;
          case rtc.CallEndReason.lineBusy:
            _incomingCallIds.remove(callId);
            _localUserAnsweredIncoming = false;
            _notifyCall('对方正忙');
            break;
          default:
            _incomingCallIds.remove(callId);
            _localUserAnsweredIncoming = false;
            debugPrint('[TRTC-GlobalObserver] 未处理的 reason: ${reason.index}');
        }
      },
      onCallBegin: (callId, mediaType, info) {
        _incomingCallIds.remove(callId);
        _localUserAnsweredIncoming = false;
        debugPrint(
          '[TRTC-GlobalObserver] 🟢 onCallBegin callId=$callId '
          'mediaType=$mediaType',
        );
        // Transition to in-call UI.
        CustomCallNavigator.instance.navigateToInCall(
          callId: callId,
          mediaType: _mediaTypeToString(mediaType),
        );
      },
      onCallEnd: (callId, mediaType, reason, userId, totalTime, info) {
        debugPrint(
          '[TRTC-GlobalObserver] 🔴 onCallEnd callId=$callId '
          'reason=$reason(${reason.index}) userId=$userId totalTime=${totalTime}s',
        );
        switch (reason) {
          case rtc.CallEndReason.otherDeviceAccepted:
            _incomingCallIds.remove(callId);
            _localUserAnsweredIncoming = false;
            CustomCallNavigator.instance.dismissAllCallScreens();
            _notifyCall('通话已在其他设备接听');
            break;
          case rtc.CallEndReason.lineBusy:
          case rtc.CallEndReason.otherDeviceReject:
            _incomingCallIds.remove(callId);
            _localUserAnsweredIncoming = false;
            CustomCallNavigator.instance.dismissAllCallScreens();
            _notifyCall('对方正忙');
            break;
          default:
            _incomingCallIds.remove(callId);
            _localUserAnsweredIncoming = false;
            CustomCallNavigator.instance.dismissAllCallScreens();
            break;
        }
      },
    );
    rtc.TUICallEngine.instance.addObserver(_globalCallObserver!);
    debugPrint('[TRTC-GlobalObserver] ✅ registered after login');
  }

  void disposeCallObserver() {
    final observer = _globalCallObserver;
    if (observer != null) {
      rtc.TUICallEngine.instance.removeObserver(observer);
      _globalCallObserver = null;
      debugPrint('[TRTC-GlobalObserver] disposed');
    }
  }

  /// The sdkAppId of the currently active IM session, or null if not logged in.
  int? get activeSdkAppId => _activeSdkAppId;

  String _mediaTypeToString(dynamic mediaType) {
    final str = mediaType.toString().toLowerCase();
    return str.contains('video') ? 'video' : 'audio';
  }

  String _resolveCallerName(String callerId) {
    // Try to resolve from known names map, fallback to callerId.
    return callerId;
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
  }

  Future<void> warmupSessionAndPushInBackground({
    required AppDependencies dependencies,
    int roomIdHint = 0,
    String? userIdHint,
  }) async {
    final running = _ongoingWarmupTask;
    if (running != null) {
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
    final epoch = _sessionEpoch;
    String? currentUserId;

    // Try 1: userIdHint provided directly
    if (userIdHint != null && userIdHint.isNotEmpty) {
      currentUserId = userIdHint.trim();
      dependencies.logger.debug(
        '[PUSH-DEBUG] using userIdHint=${_maskSensitive(currentUserId)}',
      );
    }

    // Try 2: extract from permission info
    if (currentUserId == null || currentUserId.isEmpty) {
      Map<String, dynamic>? sessionInfo = await dependencies.authService
          .getCachedPermissionInfo();
      sessionInfo ??= await dependencies.authService
          .fetchPermissionInfoAndCache();
      currentUserId = _trtcService.extractCurrentUserId(sessionInfo)?.trim();
      dependencies.logger.debug(
        '[PUSH-DEBUG] extractCurrentUserId result='
        '${_maskSensitive(currentUserId)}',
      );
    }

    // Try 3: fallback to auth-based extraction
    if (currentUserId == null || currentUserId.isEmpty) {
      dependencies.logger.debug(
        '[PUSH-DEBUG] falling back to _tryGetUserIdFromAuth',
      );
      currentUserId = await _tryGetUserIdFromAuth(dependencies: dependencies);
      dependencies.logger.debug(
        '[PUSH-DEBUG] fallbackUserId=${_maskSensitive(currentUserId)}',
      );
    }

    if (currentUserId == null || currentUserId.isEmpty) {
      return const TUICallSessionState.failure('未获取到当前登录用户ID');
    }

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

    // Avoid re-entering the IM login path for the same in-memory user session.
    // Repeated logout->login for the same account may trigger SDK internal
    // send-port lock contention on some devices.
    if (!forceRefreshSig && _activeUserId == currentUserId) {
      return TUICallSessionState.success(
        userId: currentUserId,
        nickname: nickname,
      );
    }

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

      final callKitLoginResult = await TUICallKit.instance
          .login(userSigInfo.sdkAppId, userSigInfo.userId, userSigInfo.userSig)
          .timeout(const Duration(seconds: 15));
      if (_isEpochStale(epoch)) {
        return const TUICallSessionState.failure('SESSION_CANCELLED');
      }

      final callKitReady =
          callKitLoginResult.isSuccess ||
          _looksAlreadyLoggedIn(
            callKitLoginResult.errorCode,
            callKitLoginResult.errorMessage,
          );
      if (!callKitReady) {
        return TUICallSessionState.failure(
          '音视频登录失败: ${callKitLoginResult.errorMessage ?? "未知错误"}',
        );
      }

      // Do not mirror-login via the extra native channel here.
      // TUICallKit login already establishes IM session; duplicate native login
      // increases contention risk in `libdart_native_imsdk` on some devices.

      _activeUserId = currentUserId;
      _activeSdkAppId = userSigInfo.sdkAppId;
      _activeUserSig = userSigInfo.userSig;
      _activeUserSigFetchedAt = DateTime.now();

      // ✅ Register observer AFTER login success — native layer must be ready
      try {
        initCallObserver();
      } catch (error, stackTrace) {
        dependencies.logger.error(
          'initCallObserver threw',
          error: error,
          stackTrace: stackTrace,
        );
      }

      final selfInfoReady = await _setSelfInfoWithRetry(
        dependencies: dependencies,
        nickname: nickname,
        avatar: avatar,
      );
      if (!selfInfoReady) {
        return const TUICallSessionState.failure('音视频用户资料初始化失败，请稍后重试');
      }

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
    // IMPORTANT:
    // Do not call TUICallKit.logout() during app logout/login transitions.
    // Native IM SDK logout can contend with concurrent login/warmup and cause
    // UI-thread stalls (ANR) on some devices.
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

  Future<bool> _setSelfInfoWithRetry({
    required AppDependencies dependencies,
    required String nickname,
    required String avatar,
  }) async {
    const maxAttempts = 5;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final selfInfoResult = await TUICallKit.instance.setSelfInfo(
          nickname,
          avatar,
        );
        if (selfInfoResult.isSuccess) {
          return true;
        }
        dependencies.logger.error(
          'set TUICall self info failed: '
          'attempt=$attempt/$maxAttempts, '
          'code=${selfInfoResult.errorCode}, '
          'message=${selfInfoResult.errorMessage}',
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

  bool _looksAlreadyLoggedIn(int? code, String? message) {
    final normalized = (message ?? '').toLowerCase();
    final byCode = code == 6013 || code == 6208 || code == 6206;
    final byText =
        normalized.contains('already login') ||
        normalized.contains('already logged') ||
        normalized.contains('has login') ||
        normalized.contains('repeated login');
    return byCode || byText;
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
