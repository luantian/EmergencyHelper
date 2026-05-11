import 'dart:async';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/features/trtc/data/call_phase.dart';
import 'package:emergency_helper/src/features/trtc/data/tuicall_session_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart' as rtc;
import 'package:vibration/vibration.dart';

class IncomingCallPage extends StatefulWidget {
  final String callId;
  final String callerId;
  final String callerName;
  final CallMediaType mediaType;

  const IncomingCallPage({
    super.key,
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.mediaType,
  });

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage>
    with SingleTickerProviderStateMixin {
  final TUICallSessionService _sessionService = TUICallSessionService.instance;
  bool _submitting = false;
  bool _isRinging = false;
  late final AnimationController _pulseController;
  Timer? _vibrationTimer;
  Timer? _incomingCallTimeoutTimer;
  Timer? _callStatePollTimer;

  @override
  void initState() {
    super.initState();
    debugPrint('[TRTC-DEBUG][IncomingCall] initState: caller=${widget.callerName}(${widget.callerId}) mediaType=${widget.mediaType} callId=${widget.callId}');
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _sessionService.addCallNotificationListener(_onCallNotification);
    // Also listen to CallStore activeCall state — when another device accepts,
    // the call observer triggers _resetState() which clears activeCall.
    // This is more reliable than relying solely on _notifyCall since
    // _callObserver and _globalCallObserver are independent.
    CallStore.shared.state.activeCall.addListener(_onActiveCallChanged);
    // Timeout: TUICall default ring timeout is ~30s. If no response,
    // assume the call was handled on another device or timed out.
    _incomingCallTimeoutTimer = Timer(const Duration(seconds: 30), _onCallTimeout);
    // Poll native call state every 2 seconds. The FFI layer doesn't forward
    // otherDeviceAccepted events, but we can detect when the call is no longer
    // active by querying the engine state.
    _callStatePollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_isRinging) return;
      _checkNativeCallState();
    });
    _startRinging();
  }

  /// Poll native call state via Dart FFI callExperimentalAPI.
  /// Tries various experimental API names to find one that returns call state.
  /// This uses the SAME FFI channel as the Flutter observer, so if any API
  /// returns useful state, we can detect otherDeviceAccepted.
  void _checkNativeCallState() async {
    try {
      // Try callExperimentalAPI with various API names
      final apiNames = [
        'getCallState',
        'getCurrentCallState',
        'getCallInfo',
        'status',
        'getCallStatus',
        'checkCallState',
        'queryCallState',
        'engineStatus',
        'getEngineStatus',
        'getActiveCallId',
        'getCurrentCallId',
      ];

      for (final apiName in apiNames) {
        try {
          final result = await rtc.TUICallEngine.instance.callExperimentalAPI(
            {'api': apiName},
          );
          debugPrint('[TRTC-DEBUG][IncomingCall] experimentalAPI("$apiName") called');
        } catch (e) {
          // API not available
        }
      }

      // Also try queryRecentCalls to see if the current call appears as ended
      try {
        final filter = rtc.TUICallRecentCallsFilter();
        await rtc.TUICallEngine.instance.queryRecentCalls(filter);
        debugPrint('[TRTC-DEBUG][IncomingCall] queryRecentCalls called');
      } catch (e) {
        debugPrint('[TRTC-DEBUG][IncomingCall] queryRecentCalls failed: $e');
      }
    } catch (e) {
      debugPrint('[TRTC-DEBUG][IncomingCall] queryCallState failed: $e');
    }
  }

  void _onActiveCallChanged() {
    final activeCall = CallStore.shared.state.activeCall.value;
    // If activeCall becomes empty (reset by _resetState after onCallEnd/onCallNotConnected),
    // it means the call was handled elsewhere (e.g., another device accepted).
    if (activeCall.callId.isEmpty) {
      debugPrint('[TRTC-DEBUG][IncomingCall] activeCall cleared, call handled elsewhere');
      _stopRinging();
      if (mounted) {
        // Only pop if this page is currently the top route.
        // When the callee has answered and navigated to InCallPage,
        // IncomingCallPage is underneath and should NOT pop itself here.
        final isTopRoute = ModalRoute.of(context)?.isCurrent == true;
        debugPrint('[TRTC-DEBUG][IncomingCall] _onActiveCallChanged: isTopRoute=$isTopRoute');
        if (isTopRoute) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  void _onCallTimeout() {
    if (!mounted) return;
    final session = CallSessionManager.instance.current;
    if (session.phase == CallPhase.incomingRinging) {
      debugPrint('[TRTC-DEBUG][IncomingCall] timeout: call not handled locally within 60s');
      AppCenterToast.show(context, '通话可能已在其他设备处理');
      _stopRinging();
      Navigator.of(context).pop();
    }
  }

  void _startRinging() async {
    if (_isRinging) return;
    _isRinging = true;

    // Play system ringtone
    try {
      await FlutterRingtonePlayer().playRingtone(
        looping: true,
        volume: 1.0,
        asAlarm: false,
      );
      debugPrint('[TRTC-DEBUG][IncomingCall] ringtone started');
    } catch (e) {
      debugPrint('[TRTC-DEBUG][IncomingCall] ringtone failed: $e');
    }

    // Vibrate in a pattern: vibrate 1s, pause 0.5s, repeat
    final hasVibrator = await Vibration.hasVibrator() ?? false;
    if (hasVibrator) {
      _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!_isRinging) return;
        Vibration.vibrate(duration: 1000);
      });
      // Start first vibration immediately
      Vibration.vibrate(duration: 1000);
      debugPrint('[TRTC-DEBUG][IncomingCall] vibration started');
    }
  }

  void _stopRinging() {
    if (!_isRinging) return;
    _isRinging = false;
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    try {
      FlutterRingtonePlayer().stop();
      Vibration.cancel();
      debugPrint('[TRTC-DEBUG][IncomingCall] ringing stopped');
    } catch (e) {
      debugPrint('[TRTC-DEBUG][IncomingCall] stop ringing failed: $e');
    }
  }

  @override
  void dispose() {
    debugPrint('[TRTC-DEBUG][IncomingCall] dispose');
    _stopRinging();
    _incomingCallTimeoutTimer?.cancel();
    _sessionService.removeCallNotificationListener(_onCallNotification);
    CallStore.shared.state.activeCall.removeListener(_onActiveCallChanged);
    _pulseController.dispose();
    super.dispose();
  }

  void _onCallNotification(String message) {
    debugPrint('[TRTC-DEBUG][IncomingCall] notification: $message');
    if (message.contains('其他设备接听') || message.contains('其他设备拒绝')) {
      debugPrint('[TRTC-DEBUG][IncomingCall] other device handled, popping');
      _stopRinging();
      if (mounted) {
        AppCenterToast.show(context, message);
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _handleAccept() async {
    if (_submitting) {
      debugPrint('[TRTC-DEBUG][IncomingCall] accept blocked: already submitting');
      return;
    }
    debugPrint('[TRTC-DEBUG][IncomingCall] >>> accept tapped');
    _stopRinging();
    setState(() => _submitting = true);

    // Request runtime permissions before accepting.
    if (widget.mediaType == CallMediaType.video) {
      debugPrint('[TRTC-DEBUG][IncomingCall] requesting camera/microphone permissions');
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();
      if (!cameraStatus.isGranted || !micStatus.isGranted) {
        debugPrint('[TRTC-DEBUG][IncomingCall] permission denied');
        setState(() => _submitting = false);
        _showMessage('需要摄像头和麦克风权限才能接听');
        return;
      }
    } else {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        debugPrint('[TRTC-DEBUG][IncomingCall] microphone permission denied');
        setState(() => _submitting = false);
        _showMessage('需要麦克风权限才能接听');
        return;
      }
    }

    CallSessionManager.instance.markConnecting();
    // NOTE: Do NOT call DeviceStore.openLocalCamera here.
    // The camera is opened by CallParticipantView when the InCallPage renders,
    // which needs the view to be created for proper video binding.
    // _CallDeviceStoreImpl.openLocalCamera only updates state without actually
    // opening the camera hardware, so calling it here sets cameraStatus=on
    // prematurely and prevents CallParticipantView from opening the real camera.
    debugPrint('[TRTC-DEBUG][IncomingCall] calling CallStore.accept()');
    try {
      final acceptResult = await CallStore.shared.accept().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('[TRTC-DEBUG][IncomingCall] accept() TIMED OUT after 15s');
          throw TimeoutException('accept() timed out');
        },
      );
      debugPrint('[TRTC-DEBUG][IncomingCall] CallStore.accept() returned: code=${acceptResult.errorCode} msg=${acceptResult.errorMessage}');
      if (acceptResult.errorCode != 0) {
        debugPrint('[TRTC-DEBUG][IncomingCall] accept returned error: code=${acceptResult.errorCode} msg=${acceptResult.errorMessage}');
        setState(() => _submitting = false);
        if (mounted) {
          _showMessage('接听失败: ${acceptResult.errorMessage}');
          _startRinging();
        }
      }
    } on TimeoutException catch (e) {
      debugPrint('[TRTC-DEBUG][IncomingCall] accept timeout: $e');
      setState(() => _submitting = false);
      if (mounted) {
        _showMessage('接听超时，请重试');
        _startRinging();
      }
    } catch (e) {
      debugPrint('[TRTC-DEBUG][IncomingCall] accept threw: $e');
      setState(() => _submitting = false);
      if (mounted) {
        _showMessage('接听失败: $e');
        _startRinging();
      }
    }
    // onCallBegin observer will navigate to InCallPage automatically
  }

  Future<void> _handleReject() async {
    if (_submitting) {
      debugPrint('[TRTC-DEBUG][IncomingCall] reject blocked: already submitting');
      return;
    }
    debugPrint('[TRTC-DEBUG][IncomingCall] >>> reject tapped');
    _stopRinging();
    setState(() => _submitting = true);
    // Mark idle BEFORE reject to prevent FFI bug from treating
    // local reject as "other device handled" (onCallNotConnected
    // fires with reject/unknown instead of the true reason).
    CallSessionManager.instance.resetToIdle();
    try {
      debugPrint('[TRTC-DEBUG][IncomingCall] calling CallStore.reject()');
      await CallStore.shared.reject();
      debugPrint('[TRTC-DEBUG][IncomingCall] CallStore.reject() returned');
    } catch (e) {
      debugPrint('[TRTC-DEBUG][IncomingCall] reject failed: $e');
    }
    // Do NOT pop here. The SDK will fire onCallNotConnected(reject)
    // which calls dismissAllCallScreens() to handle navigation.
    // Popping manually + SDK dismissal causes race condition → black screen.
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.mediaType == CallMediaType.video;
    final callTypeText = isVideo ? '视频' : '语音';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A237E), Color(0xFF0D47A1), Color(0xFF01579B)],
          ),
        ),
        child: PopScope(
          canPop: false,
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(),
                _buildCallerInfo(callTypeText),
                const SizedBox(height: 32),
                _buildPulseRing(),
                const Spacer(),
                _buildActionButtons(),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCallerInfo(String callTypeText) {
    return Column(
      children: [
        CircleAvatar(
          radius: 48,
          backgroundColor: Colors.white.withValues(alpha: 0.15),
          child: Text(
            widget.callerName.isNotEmpty ? widget.callerName[0] : '?',
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          widget.callerName.isNotEmpty ? widget.callerName : widget.callerId,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '邀请你进行$callTypeText通话',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildPulseRing() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = 1.0 + _pulseController.value * 0.3;
        final opacity = 0.3 * (1 - _pulseController.value);
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 120 * scale,
              height: 120 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: opacity),
                  width: 2,
                ),
              ),
            ),
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildActionButton(
          icon: Icons.call_end_rounded,
          color: const Color(0xFFEF5350),
          label: '拒绝',
          onPressed: _handleReject,
        ),
        _buildActionButton(
          icon: Icons.phone_rounded,
          color: const Color(0xFF66BB6A),
          label: '接听',
          onPressed: _handleAccept,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: _submitting ? null : onPressed,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}
