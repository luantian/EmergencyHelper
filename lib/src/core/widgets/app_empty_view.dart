import 'package:flutter/material.dart';

/// Unified empty state view for all list pages.
class AppEmptyView extends StatelessWidget {
  const AppEmptyView({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 42, color: const Color(0xFF9AABBF)),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF6F8095),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
