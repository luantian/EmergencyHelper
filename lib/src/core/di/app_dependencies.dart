import 'dart:io';

import 'package:emergency_helper/src/core/logging/app_logger.dart';
import 'package:emergency_helper/src/core/network/api_client.dart';
import 'package:emergency_helper/src/features/auth/data/auth_local_store.dart';
import 'package:emergency_helper/src/features/auth/data/auth_service.dart';
import 'package:emergency_helper/src/features/event/data/event_center.dart';
import 'package:emergency_helper/src/features/push/data/push_service.dart';

class AppDependencies {
  AppDependencies._({
    required this.logger,
    required this.apiClient,
    required this.authLocalStore,
    required this.authService,
    required this.pushService,
  });

  final AppLogger logger;
  final ApiClient apiClient;
  final AuthLocalStore authLocalStore;
  final AuthService authService;
  final PushService pushService;
  bool _initialized = false;

  static AppDependencies create() {
    final logger = AppLogger();
    final authLocalStore = AuthLocalStore();
    final apiClient = ApiClient(
      logger: logger,
      tokenProvider: authLocalStore.getAccessToken,
    );
    final authService = AuthService(
      apiClient: apiClient,
      localStore: authLocalStore,
      logger: logger,
    );
    apiClient.setAuthStateValidator(authService.ensureValidAccessToken);
    EventCenter.instance.bindApiClient(apiClient);
    final pushService = PushService(logger: logger);

    return AppDependencies._(
      logger: logger,
      apiClient: apiClient,
      authLocalStore: authLocalStore,
      authService: authService,
      pushService: pushService,
    );
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    if (_isFlutterTestEnv()) {
      return;
    }
    await pushService.initialize();
  }

  void dispose() {
    pushService.dispose();
    apiClient.dispose();
  }

  bool _isFlutterTestEnv() {
    return Platform.environment.containsKey('FLUTTER_TEST') &&
        Platform.environment['FLUTTER_TEST'] != 'false';
  }
}
