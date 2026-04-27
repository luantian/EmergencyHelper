import 'dart:async';

import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class AppCenterToast {
  AppCenterToast._();

  static OverlayEntry? _activeEntry;
  static Timer? _activeTimer;

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    final text = message.trim();
    if (text.isEmpty) {
      return;
    }

    OverlayState? overlay;
    try {
      overlay = Overlay.of(context, rootOverlay: true);
    } catch (_) {
      overlay = null;
    }
    if (overlay == null) {
      return;
    }

    dismiss();

    final entry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xE7222C38),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                border: Border.all(color: const Color(0x26FFFFFF)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x4D000000),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.32,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _activeEntry = entry;
    overlay.insert(entry);
    _activeTimer = Timer(duration, dismiss);
  }

  static void dismiss() {
    _activeTimer?.cancel();
    _activeTimer = null;
    _activeEntry?.remove();
    _activeEntry = null;
  }
}
