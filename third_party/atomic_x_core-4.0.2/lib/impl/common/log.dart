import 'dart:convert';

import 'package:tencent_rtc_sdk/trtc_cloud.dart';

class Log {
  static const String _api = "TuikitLog";
  static const String _logKeyApi = "api";
  static const String _logKeyParams = "params";
  static const String _logKeyParamsLevel = "level";
  static const String _logKeyParamsMessage = "message";
  static const String _logKeyParamsFile = "file";
  static const String _logKeyParamsModule = "module";
  static const String _logKeyParamsLine = "line";
  
  static const String _moduleAtomicXCoreCommon = "AtomicXCore-Common";
  static const String _moduleAtomicXCoreCall = "AtomicXCore-Call";
  static const String _moduleAtomicXCoreChat = "AtomicXCore-Chat";
  static const String _moduleAtomicXCoreLive = "AtomicXCore-Live";
  static const String _moduleAtomicXCoreRoom = "AtomicXCore-Room";
  
  static const int _logLevelInfo = 0;
  static const int _logLevelWarning = 1;
  static const int _logLevelError = 2;

  final String _moduleName;
  final String _fileName;

  Log._(this._moduleName, this._fileName);

  static Log getCommonLog(String fileName) {
    return Log._(_moduleAtomicXCoreCommon, fileName);
  }

  static Log getCallLog(String fileName) {
    return Log._(_moduleAtomicXCoreCall, fileName);
  }

  static Log getChatLog(String fileName) {
    return Log._(_moduleAtomicXCoreChat, fileName);
  }

  static Log getLiveLog(String fileName) {
    return Log._(_moduleAtomicXCoreLive, fileName);
  }

  static Log getRoomLog(String fileName) {
    return Log._(_moduleAtomicXCoreRoom, fileName);
  }

  void info(String message) {
    _log(_moduleName, _fileName, _logLevelInfo, message);
  }

  void warn(String message) {
    _log(_moduleName, _fileName, _logLevelWarning, message);
  }

  void error(String message) {
    _log(_moduleName, _fileName, _logLevelError, message);
  }

  static void _log(String module, String file, int level, String message) {
  final Map<String, dynamic> jsonObject = {
      _logKeyApi : _api,
      _logKeyParams: {_logKeyParamsModule: module, _logKeyParamsLevel: level, _logKeyParamsMessage: message, _logKeyParamsFile: file, _logKeyParamsLine: 0}
    };
    final jsonString = jsonEncode(jsonObject);
    TRTCCloud.sharedInstance().then((trtcCloud) => trtcCloud.callExperimentalAPI(jsonString));
  }
}
