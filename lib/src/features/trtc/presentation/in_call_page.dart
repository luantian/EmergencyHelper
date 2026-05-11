import 'dart:async';
import 'dart:convert';

import 'package:atomic_x_core/api/call/call_store.dart';
import 'package:atomic_x_core/api/device/device_store.dart';
import 'package:atomic_x_core/api/device/base_beauty_store.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:atomic_x_core/impl/view/call/float/call_float_cell_view.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/features/event/presentation/event_transfer_picker_page.dart';
import 'package:emergency_helper/src/features/trtc/data/custom_call_navigator.dart';
import 'package:emergency_helper/src/features/trtc/data/participant_name_registry.dart';
import 'package:emergency_helper/src/features/trtc/data/tuicall_session_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart' as rtc;

/// In-call screen with video/audio display and controls.
class InCallPage extends StatefulWidget {
  final String callId;
  final CallMediaType mediaType;
  /// The caller's user ID, used to resolve selfInfo when CallStore hasn't
  /// been populated yet (caller side after calls() succeeds).
  final String selfUserId;

  /// Whether this is the caller side (should play ringtone while waiting).
  /// False for callee side (already answered, no ringtone needed).
  final bool isCallerSide;

  const InCallPage({
    super.key,
    required this.callId,
    required this.mediaType,
    this.selfUserId = '',
    this.isCallerSide = true,
  });

  @override
  State<InCallPage> createState() => _InCallPageState();
}

class _InCallPageState extends State<InCallPage> {
  final _callDuration = ValueNotifier<int>(0);
  Timer? _durationTimer;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isFrontCamera = true;
  bool _isSpeakerOn = true;
  bool _isInviting = false;
  bool _isRinging = false;
  // Which participant's video is in the PiP small window.
  // true = self, false = remote (first remote participant).
  bool _isSelfInPip = true;

  // PiP drag state
  double _smallViewTop = 128.0;
  double _smallViewRight = 20.0;
  bool _isOnlyShowVideoView = false;
  StreamSubscription<dynamic>? _nativeCallEventSub;

  static const double _minSmallViewTop = 100.0;
  static const double _maxSmallViewTopOffset = 216.0;
  static const double _maxSmallViewRightOffset = 110.0;
  static const double _smallViewScale = 0.25;

  @override
  void initState() {
    super.initState();
    debugPrint('[TRTC-DEBUG][InCall] initState: callId=${widget.callId} mediaType=${widget.mediaType} isCallerSide=${widget.isCallerSide}');

    // Safety net: if CallStore state wasn't populated by the caller
    // (e.g., navigated directly via URL), populate it from widget.selfUserId.
    final effectiveSelfUserId = widget.selfUserId.isNotEmpty
        ? widget.selfUserId
        : TUICallSessionService.instance.activeUserId;
    if (effectiveSelfUserId.isNotEmpty) {
      final currentSelfId = CallStore.shared.state.selfInfo.value.id;
      if (currentSelfId.isEmpty) {
        debugPrint('[TRTC-DEBUG][InCall] selfInfo.id is empty (currentSelfId="$currentSelfId"), '
            'populating via populateCallerState with effectiveSelfUserId=$effectiveSelfUserId');
        CallStore.shared.populateCallerState(effectiveSelfUserId, '', [], widget.mediaType);
      }
    }

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Set DeviceStore focus to call mode so all device control methods
    // (mic, camera, speaker, etc.) route to _CallDeviceStoreImpl instead
    // of the default _NoneDeviceStoreImpl (which has empty implementations).
    debugPrint('[TRTC-DEBUG][InCall] setting DeviceStore focus to call');
    DeviceStore.shared.setFocus(DeviceFocusOwner.call);

    _startDurationTimer();
    // Initialize devices without awaiting — build will react to state changes.
    unawaited(_initDeviceStates());
    TUICallSessionService.instance.addCallNotificationListener(_onCallNotification);

    // Start ringtone while waiting for callee to answer (caller side only).
    if (widget.isCallerSide) {
      _startRinging();
    }

    // Listen for participant changes to reset invite button state when someone joins.
    CallStore.shared.state.allParticipants.addListener(_onParticipantsChanged);

    // Register callback for onCallBegin navigation redirect.
    // When the caller is already on InCallPage and onCallBegin fires,
    // CustomCallNavigator will invoke this (no-op with Visibility-based layout).
    CustomCallNavigator.instance.onCallBeginForInCallPage = () {
      _stopRinging();
    };

    // Native EventChannel listener for multi-device call sync.
    _nativeCallEventSub = const EventChannel(
      'com.tianyanzhiyun/trtc_call_events',
    ).receiveBroadcastStream().listen(_onNativeCallEvent);
  }

  @override
  void dispose() {
    debugPrint('[TRTC-DEBUG][InCall] dispose: resetting DeviceStore focus');
    _nativeCallEventSub?.cancel();
    DeviceStore.shared.reset();
    DeviceStore.shared.setFocus(DeviceFocusOwner.none);
    CustomCallNavigator.instance.onCallBeginForInCallPage = null;
    CallStore.shared.state.allParticipants.removeListener(_onParticipantsChanged);
    _durationTimer?.cancel();
    _callDuration.dispose();
    TUICallSessionService.instance.removeCallNotificationListener(_onCallNotification);
    _stopRinging();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  void _onCallNotification(String message) {
    if (message.contains('其他设备接听') || message.contains('其他设备拒绝') || message.contains('对方已挂断')) {
      _stopRinging();
      AppCenterToast.show(context, message);
      _handleHangup();
    }
  }

  /// Handle native call events from EventChannel (bypasses FFI bug).
  void _onNativeCallEvent(dynamic event) {
    if (event is! Map) return;
    final eventName = event['event'] as String? ?? '';
    final data = (event['data'] as Map?)?.cast<String, String>() ?? {};
    final reasonStr = data['reason'] ?? '';
    final reason = int.tryParse(reasonStr) ?? -1;
    final reasonName = data['reasonName'] ?? '';
    debugPrint('[TRTC-DEBUG][InCall] ⚡ native event: $eventName reason=$reason($reasonName)');

    if (eventName == 'onCallNotConnected' || eventName == 'onCallEnd') {
      String? toastMsg;
      if (reason == 7 || reasonName == 'otherDeviceAccepted') {
        toastMsg = '通话已在其他设备接听';
      } else if (reason == 8 || reasonName == 'otherDeviceReject') {
        toastMsg = '通话已在其他设备拒绝';
      } else if (reason == 1 || reasonName == 'hangup') {
        toastMsg = '对方已挂断通话';
      }
      if (toastMsg != null) {
        _stopRinging();
        AppCenterToast.show(context, toastMsg);
        _handleHangup();
      }
    }
  }

  void _onParticipantsChanged() {
    // Reset invite button when a new participant joins — more reliable than
    // waiting for inviteUser() Future to resolve.
    if (_isInviting) {
      setState(() => _isInviting = false);
    }
  }

  Future<void> _initDeviceStates() async {
    // Initialize microphone: open it by default for all calls.
    final micStatus = DeviceStore.shared.state.microphoneStatus.value;
    debugPrint('[TRTC-DEBUG][InCall] _initDeviceStates: micStatus=$micStatus');
    if (micStatus == DeviceStatus.off) {
      debugPrint('[TRTC-DEBUG][InCall] opening microphone');
      final result = await DeviceStore.shared.openLocalMicrophone();
      debugPrint('[TRTC-DEBUG][InCall] openMic result: code=${result.errorCode} msg=${result.errorMessage}');
    }
    _isMuted = DeviceStore.shared.state.microphoneStatus.value == DeviceStatus.off;
    debugPrint('[TRTC-DEBUG][InCall] after init: isMuted=$_isMuted, micStatus=${DeviceStore.shared.state.microphoneStatus.value}');

    // For video calls: camera is already opened by CallParticipantView
    // (local view). Just update the UI state.
    if (widget.mediaType == CallMediaType.video) {
      final cameraStatus = DeviceStore.shared.state.cameraStatus.value;
      debugPrint('[TRTC-DEBUG][InCall] _initDeviceStates: cameraStatus=$cameraStatus');
      _isCameraOff = cameraStatus == DeviceStatus.off;
      _isFrontCamera = DeviceStore.shared.state.isFrontCamera.value;

      // Enable default beauty effect using TRTC built-in beauty.
      // Range is 0-9. Moderate values for a natural look.
      try {
        final beautyStore = BaseBeautyStore.shared;
        beautyStore.setSmoothLevel(5.0);
        beautyStore.setWhitenessLevel(3.0);
        beautyStore.setRuddyLevel(2.0);
        debugPrint('[TRTC-DEBUG][InCall] beauty enabled: smooth=5, whiteness=3, ruddy=2');
      } catch (e) {
        debugPrint('[TRTC-DEBUG][InCall] failed to enable beauty: $e');
      }
    } else {
      _isCameraOff = true;
    }

    // Audio route: prefer speakerphone by default.
    debugPrint('[TRTC-DEBUG][InCall] setting audio route to speakerphone');
    DeviceStore.shared.setAudioRoute(AudioRoute.speakerphone);
    _isSpeakerOn = true;
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final duration = CallStore.shared.state.activeCall.value.duration;
      if (duration != _callDuration.value) {
        _callDuration.value = duration;
      }
    });
  }

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final mm = d.inMinutes.toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<void> _toggleMute() async {
    setState(() => _isMuted = !_isMuted);
    if (_isMuted) {
      DeviceStore.shared.closeLocalMicrophone();
    } else {
      await DeviceStore.shared.openLocalMicrophone();
    }
  }

  Future<void> _toggleCamera() async {
    if (widget.mediaType != CallMediaType.video) return;
    setState(() => _isCameraOff = !_isCameraOff);
    if (_isCameraOff) {
      DeviceStore.shared.closeLocalCamera();
    } else {
      final isFront = DeviceStore.shared.state.isFrontCamera.value;
      setState(() => _isFrontCamera = isFront);
      await DeviceStore.shared.openLocalCamera(isFront);
    }
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    DeviceStore.shared.setAudioRoute(
      _isSpeakerOn ? AudioRoute.speakerphone : AudioRoute.earpiece,
    );
  }

  void _switchCamera() {
    if (widget.mediaType != CallMediaType.video) return;
    setState(() => _isFrontCamera = !_isFrontCamera);
    DeviceStore.shared.switchCamera(_isFrontCamera);
  }

  void _startRinging() async {
    if (_isRinging) return;
    _isRinging = true;
    try {
      await FlutterRingtonePlayer().playRingtone(
        looping: true,
        volume: 1.0,
        asAlarm: false,
      );
      debugPrint('[TRTC-DEBUG][InCall] ringtone started');
    } catch (e) {
      debugPrint('[TRTC-DEBUG][InCall] ringtone failed: $e');
    }
  }

  void _stopRinging() {
    if (!_isRinging) return;
    _isRinging = false;
    try {
      FlutterRingtonePlayer().stop();
      debugPrint('[TRTC-DEBUG][InCall] ringing stopped');
    } catch (e) {
      debugPrint('[TRTC-DEBUG][InCall] stop ringing failed: $e');
    }
  }

  Future<void> _handleHangup() async {
    try {
      await CallStore.shared.hangup();
    } catch (e) {
      debugPrint('[InCall] hangup failed: $e');
      // Even if hangup fails, dismiss the UI.
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
    // Do NOT pop here. The SDK fires onCallEnd which calls
    // dismissAllCallScreens() to handle navigation.
    // Popping here + observer dismissal causes race condition.
  }

  Future<void> _handleInvite() async {
    if (_isInviting) return;
    setState(() => _isInviting = true);

    // Collect current participant IDs to exclude from picker.
    final currentIds = <int>{};
    final selfId = CallStore.shared.state.selfInfo.value.id;
    if (selfId.isNotEmpty) {
      final parsedSelf = int.tryParse(selfId);
      if (parsedSelf != null) currentIds.add(parsedSelf);
    }
    final participants = CallStore.shared.state.allParticipants.value;
    for (final p in participants) {
      final parsed = int.tryParse(p.id);
      if (parsed != null) currentIds.add(parsed);
    }

    final selection = await Navigator.of(context).push<EventTransferSelection>(
      MaterialPageRoute<EventTransferSelection>(
        builder: (_) => EventTransferPickerPage(
          eventId: 'trtc_invite',
          checkPermission: false,
          titleText: '邀请成员加入通话',
          confirmButtonText: '确认邀请',
          emptySelectionHint: '请至少选择一位成员',
          initialSelectedUserIds: currentIds.toList(),
          showContentField: false,
        ),
      ),
    );

    if (!mounted || selection == null || selection.userIds.isEmpty) {
      if (mounted) setState(() => _isInviting = false);
      return;
    }

    final targetIds = selection.userIds
        .map((id) => id.toString())
        .where((id) => id.isNotEmpty && !currentIds.contains(int.tryParse(id)))
        .toList(growable: false);

    if (targetIds.isEmpty) {
      if (mounted) {
        setState(() => _isInviting = false);
        AppCenterToast.show(context, '所选成员已在通话中');
      }
      return;
    }

    try {
      final callUserData = <String, dynamic>{
        'source': 'emergency_helper',
        'page': 'trtc_call',
        'type': 'call_invite',
        'invitedBy': selfId,
        'sentAt': DateTime.now().toIso8601String(),
      };
      final rtcCallParams = rtc.TUICallParams()
        ..userData = jsonEncode(callUserData);

      debugPrint('[InCall] inviting users: $targetIds');
      final result = await rtc.TUICallEngine.instance.inviteUser(
        targetIds,
        rtcCallParams,
      );

      if (!mounted) return;
      if (result.code == rtc.TUIError.success) {
        AppCenterToast.show(context, '已发送邀请');
      } else {
        AppCenterToast.show(
          context,
          '邀请发送失败: ${result.message ?? "未知错误"}',
        );
      }
    } catch (error) {
      debugPrint('[InCall] inviteUser failed: $error');
      if (mounted) {
        AppCenterToast.show(context, '邀请失败: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isInviting = false);
      }
    }
  }

  Color _networkQualityColor(NetworkQuality quality) {
    switch (quality) {
      case NetworkQuality.excellent:
      case NetworkQuality.good:
        return Colors.green;
      case NetworkQuality.poor:
        return Colors.orange;
      case NetworkQuality.bad:
      case NetworkQuality.veryBad:
      case NetworkQuality.down:
        return Colors.red;
      case NetworkQuality.unknown:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.mediaType == CallMediaType.video;

    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: Background - dynamic participant grid for video calls
            if (isVideo) _buildVideoBackground()
            else _buildAudioBackground(),

            // Layer 2: Small video PiP (video calls only)
            if (isVideo) _buildSmallVideoWidget(),

            // Layer 3: Top bar
            _buildTopBar(),

            // Layer 4: Bottom controls
            _buildBottomControls(isVideo: isVideo),
          ],
        ),
      ),
    );
  }

  /// Build a dynamic video layout for video calls.
  /// 1-on-1 (self + 1 remote): full screen remote with PiP self view.
  /// 3+ participants: grid of square tiles, auto-sized for any count.
  Widget _buildVideoBackground() {
    return ValueListenableBuilder(
      valueListenable: CallStore.shared.state.selfInfo,
      builder: (context, selfInfo, _) {
        if (selfInfo.status == CallParticipantStatus.none && selfInfo.id.isEmpty) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<List<CallParticipantInfo>>(
          valueListenable: CallStore.shared.state.allParticipants,
          builder: (context, allParticipants, _) {
            final selfId = selfInfo.id;

            // Collect unique remote participants.
            final remotes = <CallParticipantInfo>[];
            for (final p in allParticipants) {
              if (p.id.isNotEmpty && p.id != selfId) remotes.add(p);
            }

            final total = remotes.length + (selfId.isNotEmpty ? 1 : 0);

            // 1-on-1: full screen + PiP, swapable by tapping PiP.
            if (total <= 2) {
              if (_isSelfInPip) {
                // Default: remote full screen, self in PiP.
                if (remotes.isNotEmpty) {
                  return _buildStreamView(remotes.first.id);
                }
                if (selfId.isNotEmpty) {
                  return _buildStreamView(selfId);
                }
              } else {
                // Swapped: self full screen, remote in PiP.
                if (selfId.isNotEmpty) {
                  return _buildStreamView(selfId);
                }
                if (remotes.isNotEmpty) {
                  return _buildStreamView(remotes.first.id);
                }
              }
              return const SizedBox.shrink();
            }

            // 3+: grid layout.
            final participants = <CallParticipantInfo>[];
            if (selfId.isNotEmpty) {
              participants.add(selfInfo);
            }
            participants.addAll(remotes);
            return _buildGridView(participants);
          },
        );
      },
    );
  }

  /// Grid view for 3+ participants: square tiles, auto-sized, centered.
  Widget _buildGridView(List<CallParticipantInfo> participants) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = participants.length;
        final cols = count <= 4 ? 2 : (count <= 9 ? 3 : 4);
        final rows = (count + cols - 1) ~/ cols;
        final availableW = constraints.maxWidth;
        final availableH = constraints.maxHeight;
        // Tile size is the largest square that fits cols×rows within the available space.
        final tileSize = (availableW / cols).floorToDouble()
            .clamp(0.0, availableH / rows);
        final totalW = tileSize * cols;
        final totalH = tileSize * rows;

        final gridChildren = <Widget>[];
        for (var i = 0; i < participants.length; i++) {
          final col = i % cols;
          final row = i ~/ cols;
          gridChildren.add(Positioned(
            left: col * tileSize,
            top: row * tileSize,
            child: SizedBox(
              width: tileSize,
              height: tileSize,
              child: _buildStreamView(participants[i].id),
            ),
          ));
        }

        return Center(
          child: SizedBox(
            width: totalW,
            height: totalH,
            child: Stack(
              children: gridChildren,
            ),
          ),
        );
      },
    );
  }

  Widget _buildStreamView(String userId) {
    return CallFloatCellView(
      userId: userId,
      key: ValueKey('stream_$userId'),
      isInMainView: true,
    );
  }

  Widget _buildAudioBackground() {
    return Container(
      color: const Color(0xFFF2F2F2),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ValueListenableBuilder(
              valueListenable: CallStore.shared.state.allParticipants,
              builder: (context, participants, _) {
                final selfId = CallStore.shared.state.selfInfo.value.id;
                final remote = participants.where((p) => p.id != selfId).firstOrNull;
                return _buildAvatarForParticipant(remote);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallVideoWidget() {
    return ValueListenableBuilder(
      valueListenable: CallStore.shared.state.allParticipants,
      builder: (context, allParticipants, _) {
        final selfId = CallStore.shared.state.selfInfo.value.id;
        if (selfId.isEmpty) return const SizedBox.shrink();
        // Count unique remote participants with valid IDs.
        var remoteCount = 0;
        for (final p in allParticipants) {
          if (p.id.isNotEmpty && p.id != selfId) remoteCount++;
        }
        // Only show PiP for 1-on-1.
        if (remoteCount > 1) return const SizedBox.shrink();

        // Determine which userId goes in PiP based on _isSelfInPip.
        final pipUserId = _isSelfInPip ? selfId : allParticipants.where((p) => p.id.isNotEmpty && p.id != selfId).firstOrNull?.id ?? selfId;
        return _buildPiP(pipUserId);
      },
    );
  }

  Widget _buildPiP(String userId) {
    if (_isOnlyShowVideoView) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final windowWidth = screenWidth * _smallViewScale;
    final windowHeight = windowWidth / 9 * 16;

    return Positioned(
      top: _smallViewTop,
      right: _smallViewRight,
      child: Stack(
        children: [
          SizedBox(
            width: windowWidth,
            child: Container(
              width: windowWidth,
              height: windowHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 0,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CallFloatCellView(
                  userId: userId,
                  key: ValueKey('pip_$userId'),
                  isInMainView: true,
                ),
              ),
            ),
          ),
          // Drag handler + tap to swap
          Positioned.fill(
            child: GestureDetector(
              onTap: _togglePipPosition,
              onPanUpdate: _refreshViewPosition,
            ),
          ),
        ],
      ),
    );
  }

  void _refreshViewPosition(DragUpdateDetails e) {
    setState(() {
      _smallViewRight -= e.delta.dx;
      _smallViewTop += e.delta.dy;
      if (_smallViewTop < _minSmallViewTop) {
        _smallViewTop = _minSmallViewTop;
      }
      if (_smallViewTop >
          MediaQuery.of(context).size.height - _maxSmallViewTopOffset) {
        _smallViewTop =
            MediaQuery.of(context).size.height - _maxSmallViewTopOffset;
      }
      if (_smallViewRight < 0) _smallViewRight = 0;
      if (_smallViewRight >
          MediaQuery.of(context).size.width - _maxSmallViewRightOffset) {
        _smallViewRight =
            MediaQuery.of(context).size.width - _maxSmallViewRightOffset;
      }
    });
  }

  void _togglePipPosition() {
    setState(() => _isSelfInPip = !_isSelfInPip);
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ValueListenableBuilder(
        valueListenable: _callDuration,
        builder: (context, duration, _) {
          return SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatDuration(duration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  ValueListenableBuilder(
                    valueListenable: CallStore.shared.state.networkQualities,
                    builder: (context, qualities, _) {
                      final selfId = CallStore.shared.state.selfInfo.value.id;
                      final quality = qualities[selfId];
                      if (quality == null) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.signal_cellular_alt_rounded,
                              size: 14,
                              color: _networkQualityColor(quality),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _qualityLabel(quality),
                              style: TextStyle(
                                color: _networkQualityColor(quality),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomControls({required bool isVideo}) {
    if (_isOnlyShowVideoView) return const SizedBox.shrink();
    return Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.6),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlBtn(
                    icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: _isMuted ? '已静音' : '静音',
                    isActive: _isMuted,
                    onPressed: _toggleMute,
                  ),
                  if (isVideo)
                    _buildControlBtn(
                      icon: _isCameraOff
                          ? Icons.videocam_off_rounded
                          : Icons.videocam_rounded,
                      label: _isCameraOff ? '已关闭' : '摄像头',
                      isActive: _isCameraOff,
                      onPressed: _toggleCamera,
                    ),
                  _buildControlBtn(
                    icon: _isSpeakerOn
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    label: _isSpeakerOn ? '扬声器' : '听筒',
                    isActive: !_isSpeakerOn,
                    onPressed: _toggleSpeaker,
                  ),
                  if (isVideo)
                    _buildControlBtn(
                      icon: _isFrontCamera
                          ? Icons.flip_camera_ios_rounded
                          : Icons.flip_camera_android_rounded,
                      label: _isFrontCamera ? '前置' : '后置',
                      onPressed: _switchCamera,
                    ),
                  _buildInviteBtn(),
                  _buildHangupBtn(),
                ],
              ),
            ),
          ),
        );
  }

  Widget _buildControlBtn({
    required IconData icon,
    required String label,
    bool isActive = false,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.15),
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.redAccent : Colors.white,
              size: 24,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildInviteBtn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _isInviting ? null : _handleInvite,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF4A90D9),
            ),
            child: _isInviting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.person_add_alt_1_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _isInviting ? '邀请中' : '邀请',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildHangupBtn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _handleHangup,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFEF5350),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEF5350).withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.call_end_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '挂断',
          style: TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildAvatarForParticipant(CallParticipantInfo? info) {
    final displayName = _getDisplayName(info);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 56,
          backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
          child: Text(
            displayName.isNotEmpty ? displayName[0] : '?',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryBlue,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          displayName,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF333333),
          ),
        ),
      ],
    );
  }

  String _getDisplayName(CallParticipantInfo? info) {
    if (info == null) return '未知用户';
    if (info.remark.isNotEmpty) return info.remark;
    if (info.name.isNotEmpty) return info.name;
    final registered = ParticipantNameRegistry.resolve(info.id);
    if (registered.isNotEmpty) return registered;
    return info.id;
  }

  String _qualityLabel(NetworkQuality quality) {
    switch (quality) {
      case NetworkQuality.excellent:
        return '极好';
      case NetworkQuality.good:
        return '良好';
      case NetworkQuality.poor:
        return '一般';
      case NetworkQuality.bad:
        return '较差';
      case NetworkQuality.veryBad:
        return '很差';
      case NetworkQuality.down:
        return '断开';
      case NetworkQuality.unknown:
        return '未知';
    }
  }
}
