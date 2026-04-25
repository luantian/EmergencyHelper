import 'dart:async';
import 'dart:io';

import 'package:emergency_helper/src/app.dart';
import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:flutter/material.dart';
import 'package:flutter_baidu_mapapi_base/flutter_baidu_mapapi_base.dart';
import 'package:flutter_baidu_mapapi_map/flutter_baidu_mapapi_map.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sw = Stopwatch()..start();
  BMFMapSDK.setAgreePrivacy(true);
  debugPrint('[main] setAgreePrivacy done in ${sw.elapsedMilliseconds}ms');

  if (Platform.isAndroid) {
    BMFMapSDK.setCoordType(BMF_COORD_TYPE.BD09LL);
    debugPrint('[main] setCoordType done in ${sw.elapsedMilliseconds}ms');
    unawaited(
      BMFAndroidVersion.initAndroidVersion()
          .timeout(const Duration(seconds: 3))
          .then((_) => debugPrint('[main] initAndroidVersion done'))
          .catchError((e) => debugPrint('[main] initAndroidVersion failed: $e')),
    );
  }

  debugPrint('[main] total init before runApp: ${sw.elapsedMilliseconds}ms');
  final dependencies = AppDependencies.create();
  runApp(EmergencyHelperApp(dependencies: dependencies));
}
