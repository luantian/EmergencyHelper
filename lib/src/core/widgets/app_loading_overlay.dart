import 'package:flutter/material.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';

class AppLoadingOverlay extends StatelessWidget {
  const AppLoadingOverlay({
    required this.child,
    required this.loading,
    this.message = '\u52A0\u8F7D\u4E2D...',
    this.barrierColor = const Color(0x5E0F1724),
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
                  constraints: const BoxConstraints(minWidth: 152),
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceWhite,
                    borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                    border: Border.all(color: const Color(0x14000000)),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x2E000000),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.8,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                      if (message.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 11),
                        Text(
                          message,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
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
