import 'dart:async';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:atomic_x_core/impl/view/call/float/call_float_cell_view.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/features/trtc/data/tuicall_session_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// In-call screen with video/audio display and controls.
class InCallPage extends StatefulWidget {
  final String callId;
  final CallMediaType mediaType;

  const InCallPage({
    super.key,
    required this.callId,
    required this.mediaType,
  });

  @override
  State<InCallPage> createState() => _InCallPageState();
}

class _InCallPageState extends State<InCallPage> with TickerProviderStateMixin {
  final _callDuration = ValueNotifier<int>(0);
  Timer? _durationTimer;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  String? _remoteUserId;
  late final AnimationController _switchAnimationController;

  // PiP state (following CallFloatView pattern)
  double _smallViewTop = 128.0;
  double _smallViewRight = 20.0;
  bool _isLocalInMainView = false;
  final _isOnlyShowVideoView = ValueNotifier<bool>(false);

  static const double _minSmallViewTop = 100.0;
  static const double _maxSmallViewTopOffset = 216.0;
  static const double _maxSmallViewRightOffset = 110.0;
  static const double _smallViewScale = 0.25;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _switchAnimationController = AnimationController(
      duration: const Duration(milliseconds: 60),
      vsync: this,
    );
    _resolveRemoteUserId();
    _startDurationTimer();
    _initDeviceStates();
    TUICallSessionService.instance.addCallNotificationListener(_onCallNotification);
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _callDuration.dispose();
    _isOnlyShowVideoView.dispose();
    _switchAnimationController.dispose();
    TUICallSessionService.instance.removeCallNotificationListener(_onCallNotification);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  void _onCallNotification(String message) {
    if (message.contains('其他设备接听') || message.contains('其他设备拒绝')) {
      _handleHangup();
    }
  }

  void _initDeviceStates() {
    _isMuted = DeviceStore.shared.state.microphoneStatus.value == DeviceStatus.off;
    _isCameraOff = DeviceStore.shared.state.cameraStatus.value == DeviceStatus.off;
    _isSpeakerOn = DeviceStore.shared.state.currentAudioRoute.value == AudioRoute.speakerphone;
  }

  void _resolveRemoteUserId() {
    final selfId = CallStore.shared.state.selfInfo.value.id;
    final activeCall = CallStore.shared.state.activeCall.value;
    final isSelfInvoker = activeCall.inviterId == selfId;
    final inviteeIds = activeCall.inviteeIds;
    _remoteUserId = isSelfInvoker
        ? (inviteeIds.isNotEmpty ? inviteeIds.first : activeCall.inviterId)
        : activeCall.inviterId;
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
    final isFront = DeviceStore.shared.state.isFrontCamera.value;
    DeviceStore.shared.switchCamera(!isFront);
  }

  Future<void> _handleHangup() async {
    try {
      await CallStore.shared.hangup();
    } catch (e) {
      debugPrint('[InCall] hangup failed: $e');
    }
    if (mounted) {
      Navigator.of(context).pop();
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
    final remoteId = _remoteUserId;

    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: Background
            if (isVideo) _buildVideoBackground(remoteId)
            else _buildAudioBackground(),

            // Layer 2: Local Video PiP (video calls only)
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

  Widget _buildVideoBackground(String? remoteId) {
    return ValueListenableBuilder(
      valueListenable: CallStore.shared.state.selfInfo,
      builder: (context, selfInfo, _) {
        if (selfInfo.status == CallParticipantStatus.waiting) {
          return const SizedBox.shrink();
        }
        return Stack(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 60),
              child: _isLocalInMainView
                  ? _buildLocalStreamView(key: const ValueKey('main_local'))
                  : _buildRemoteStreamView(
                      remoteId: remoteId,
                      key: const ValueKey('main_remote'),
                    ),
            ),
            // Tap to toggle overlay controls
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  _isOnlyShowVideoView.value = !_isOnlyShowVideoView.value;
                  setState(() {});
                },
              ),
            ),
          ],
        );
      },
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
    return ValueListenableBuilder2<CallParticipantInfo?, bool>(
      first: CallStore.shared.state.selfInfo,
      second: _isOnlyShowVideoView,
      builder: (context, selfInfo, onlyShow, _) {
        if (selfInfo == null ||
            selfInfo.status == CallParticipantStatus.waiting ||
            onlyShow) {
          return const SizedBox.shrink();
        }

        final screenWidth = MediaQuery.of(context).size.width;
        final windowWidth = screenWidth * _smallViewScale;
        final windowHeight = windowWidth / 9 * 16;

        return Positioned(
          top: _smallViewTop,
          right: _smallViewRight,
          child: Stack(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 60),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: SizedBox(
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
                      child: _isLocalInMainView
                          ? _buildRemoteStreamView(
                              remoteId: _remoteUserId,
                              key: const ValueKey('pip_remote'),
                            )
                          : _buildLocalStreamView(
                              key: const ValueKey('pip_local'),
                            ),
                    ),
                  ),
                ),
              ),
              // Drag handler
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => _changeVideoView(),
                  onPanUpdate: _refreshViewPosition,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _changeVideoView() {
    if (_switchAnimationController.isAnimating) return;
    _switchAnimationController.forward().then((_) {
      if (!mounted) return;
      setState(() {
        _isLocalInMainView = !_isLocalInMainView;
      });
      _switchAnimationController.reset();
    });
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
    return ValueListenableBuilder(
      valueListenable: _isOnlyShowVideoView,
      builder: (context, onlyShow, _) {
        if (onlyShow) return const SizedBox.shrink();
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
                    isActive: _isSpeakerOn,
                    onPressed: _toggleSpeaker,
                  ),
                  if (isVideo)
                    _buildControlBtn(
                      icon: Icons.flip_camera_ios_rounded,
                      label: '切换',
                      onPressed: _switchCamera,
                    ),
                  _buildHangupBtn(),
                ],
              ),
            ),
          ),
        );
      },
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

  Widget _buildLocalStreamView({Key? key}) {
    final selfId = CallStore.shared.state.selfInfo.value.id;
    return CallFloatCellView(
      userId: selfId,
      key: key ?? ValueKey('local_$selfId'),
      isInMainView: _isLocalInMainView,
    );
  }

  Widget _buildRemoteStreamView({
    required String? remoteId,
    Key? key,
  }) {
    final selfId = CallStore.shared.state.selfInfo.value.id;
    final activeCall = CallStore.shared.state.activeCall.value;
    final isSelfInvoker = activeCall.inviterId == selfId;
    final inviteeIds = activeCall.inviteeIds;
    final fallbackId = activeCall.inviterId.isNotEmpty
        ? activeCall.inviterId
        : selfId;
    final userId = remoteId ??
        (isSelfInvoker
            ? (inviteeIds.isNotEmpty ? inviteeIds.first : fallbackId)
            : fallbackId);

    return CallFloatCellView(
      userId: userId,
      key: key ?? ValueKey('remote_$userId'),
      isInMainView: !_isLocalInMainView,
    );
  }

  String _getDisplayName(CallParticipantInfo? info) {
    if (info == null) return '未知用户';
    if (info.remark.isNotEmpty) return info.remark;
    if (info.name.isNotEmpty) return info.name;
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

/// Helper to listen to two ValueListenables at once.
class ValueListenableBuilder2<A, B> extends StatelessWidget {
  final ValueListenable<A> first;
  final ValueListenable<B> second;
  final Widget Function(BuildContext, A, B, Widget?) builder;

  const ValueListenableBuilder2({
    super.key,
    required this.first,
    required this.second,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<A>(
      valueListenable: first,
      builder: (context, a, _) {
        return ValueListenableBuilder<B>(
          valueListenable: second,
          builder: (context, b, child) {
            return builder(context, a, b, child);
          },
        );
      },
    );
  }
}
