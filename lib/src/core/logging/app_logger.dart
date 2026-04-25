import 'package:flutter/foundation.dart';

class AppLogger {
  void debug(String message) {
    if (!kDebugMode) {
      return;
    }
    _print('DEBUG', message);
  }

  void info(String message) => _print('INFO', message);

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    _print('ERROR', message);
    if (error != null) {
      _print('ERROR', 'cause: $error');
    }
    if (stackTrace != null) {
      _print('ERROR', stackTrace.toString());
    }
  }

  void _print(String level, String message) {
    final timestamp = DateTime.now().toIso8601String();
    debugPrint('[$timestamp][$level] $message');
  }
}
