import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:rtc_room_engine/api/room/tui_room_engine.dart';

class LiveDataReporter {
  static const int dataReportComponentLiveRoom = 21;
  static const int dataReportComponentVoiceRoom = 22;
  static const int dataReporterComponentCoreWidget = 26;
  static int dataReportComponent = dataReporterComponentCoreWidget;
  static const int dataReportFramework = 7;
  static const int dataReportLanguageFlutter = 9;

  static void reportComponent() {
    try {
      Map<String, dynamic> params = {
        'framework': dataReportFramework,
        'component': dataReportComponent,
        'language': dataReportLanguageFlutter,
      };

      Map<String, dynamic> jsonObject = {
        'api': 'setFramework',
        'params': params,
      };

      String jsonString = jsonEncode(jsonObject);
      TUIRoomEngine.sharedInstance().invokeExperimentalAPI(jsonString);
    } catch (e) {
      debugPrint('Error reporting component');
    }
  }
}