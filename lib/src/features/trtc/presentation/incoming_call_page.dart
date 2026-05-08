import 'package:atomic_x_core/atomicxcore.dart';
import 'package:emergency_helper/src/features/trtc/data/tuicall_session_service.dart';
import 'package:flutter/material.dart';

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
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _sessionService.addCallNotificationListener(_onCallNotification);
  }

  @override
  void dispose() {
    _sessionService.removeCallNotificationListener(_onCallNotification);
    _pulseController.dispose();
    super.dispose();
  }

  void _onCallNotification(String message) {
    if (message.contains('其他设备接听') || message.contains('其他设备拒绝')) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _handleAccept() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    _sessionService.markLocalUserAnswered();
    try {
      await CallStore.shared.accept();
    } catch (e) {
      debugPrint('[IncomingCall] accept failed: $e');
    }
    // onCallBegin observer will navigate to InCallPage automatically
  }

  Future<void> _handleReject() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await CallStore.shared.reject();
    } catch (e) {
      debugPrint('[IncomingCall] reject failed: $e');
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
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
}
