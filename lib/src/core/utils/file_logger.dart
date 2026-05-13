import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// File-based logger that mirrors `debugPrint` output to a persistent file.
///
/// Usage: call [init] early in `main()`. After that, all calls to
/// [debugPrint] (or [log]) will be appended to the log file.
///
/// The previous log file is renamed to `.bak` so that even if the app
/// crashes on launch the prior session's log is still available.
///
/// Logs are written to the app's cache directory. Pull via:
///   adb shell run-as com.tianyanzhiyun.emergency_helper cat cache/_trtc_last_run.log
class FileLogger {
  FileLogger._();

  static IOSink? _sink;
  static String? _logPath;

  /// Initialize the logger. Clears/rotates the file and returns its path.
  static Future<String> init() async {
    // Platform-specific cache directory.
    String cacheDir;
    if (Platform.isAndroid) {
      cacheDir = '/data/data/com.tianyanzhiyun.emergency_helper/cache';
    } else {
      cacheDir = Directory.systemTemp.path;
    }

    final file = File('$cacheDir/_trtc_last_run.log');
    final oldFile = File('$cacheDir/_trtc_last_run.log.bak');

    // Rotate: previous -> .bak (so we can still recover a crashed run's log)
    if (file.existsSync()) {
      if (oldFile.existsSync()) oldFile.deleteSync();
      file.renameSync(oldFile.path);
    }

    _sink = file.openWrite(mode: FileMode.write);
    _logPath = file.path;

    // Mirror the very first line so the user knows logging started.
    final header = '=== Log session started at ${DateTime.now().toIso8601String()} ===';
    _sink?.write('$header\n');
    await _sink?.flush();

    // Override Flutter's debugPrint to also write to file.
    debugPrint = _debugPrintToFile;

    return file.path;
  }

  static void _debugPrintToFile(String? message, {int? wrapWidth}) {
    if (message == null || message.isEmpty) return;
    _sink?.write('$message\n');
    print(message);
  }

  /// Explicit log call (also goes through debugPrint override).
  static void log(String message) {
    debugPrint(message);
  }

  /// Flush and close the file (call on app exit if possible).
  static Future<void> dispose() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }

  /// Current log file path, null if not initialized.
  static String? get logPath => _logPath;
}
