import 'package:flutter/material.dart';

class AppLoadingOverlay extends StatelessWidget {
  const AppLoadingOverlay({
    required this.child,
    required this.loading,
    this.message = '\u52A0\u8F7D\u4E2D...',
    this.barrierColor = const Color(0x66000000),
    super.key,
  });

  final Widget child;
  final bool loading;
  final String message;
  final Color barrierColor;

  @override
  Widget build(BuildContext context) {
    if (!loading) {
      return child;
    }

    return Stack(
      children: <Widget>[
        child,
        Positioned.fill(
          child: AbsorbPointer(
            absorbing: true,
            child: DecoratedBox(
              decoration: BoxDecoration(color: barrierColor),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(minWidth: 136),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.8),
                      ),
                      if (message.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(
                          message,
                          style: const TextStyle(
                            color: Color(0xFF3D4653),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
