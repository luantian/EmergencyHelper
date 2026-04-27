import 'dart:async';

import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/routing/route_paths.dart';
import 'package:emergency_helper/src/features/event/data/event_center.dart';
import 'package:emergency_helper/src/features/risk/data/risk_center.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_bootstrapSession);
  }

  Future<void> _bootstrapSession() async {
    final dependencies = context.read<AppDependencies>();
    final accessToken = await dependencies.authLocalStore.getAccessToken();
    if (!mounted) {
      return;
    }

    if (accessToken == null || accessToken.trim().isEmpty) {
      EventCenter.instance.resetSessionCache(notify: false);
      RiskCenter.instance.resetSessionData(notify: false);
      if (!mounted) {
        return;
      }
      context.go(RoutePaths.login);
      unawaited(_cleanupLoggedOutStateInBackground(dependencies));
      return;
    }

    final hasValidToken = await dependencies.authService
        .ensureValidAccessToken(validateWithServer: true)
        .timeout(
          const Duration(seconds: 6),
          onTimeout: () {
            dependencies.logger.error(
              '[AUTH] splash token validate timeout, skip blocking startup',
            );
            // Keep startup responsive; subsequent protected APIs still perform
            // auth checks and will redirect to login when token is invalid.
            return true;
          },
        );
    if (!mounted) {
      return;
    }
    if (!hasValidToken) {
      EventCenter.instance.resetSessionCache(notify: false);
      RiskCenter.instance.resetSessionData(notify: false);
      if (!mounted) {
        return;
      }
      context.go(RoutePaths.login);
      unawaited(_cleanupLoggedOutStateInBackground(dependencies));
      return;
    }

    var permissionInfo = await dependencies.authService
        .getCachedPermissionInfo();
    permissionInfo ??= await dependencies.authService
        .fetchPermissionInfoAndCache();
    if (!mounted) {
      return;
    }
    context.go(RoutePaths.home);
    unawaited(
      _bindPushAliasInBackground(
        dependencies: dependencies,
        permissionInfo: permissionInfo,
      ),
    );
  }

  Future<void> _bindPushAliasInBackground({
    required AppDependencies dependencies,
    required Map<String, dynamic>? permissionInfo,
  }) async {
    try {
      await dependencies.pushService.bindAliasFromPermissionInfo(
        permissionInfo,
      );
    } catch (_) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        await dependencies.pushService.bindAliasFromPermissionInfo(
          permissionInfo,
        );
      } catch (_) {}
    }
  }

  Future<void> _cleanupLoggedOutStateInBackground(
    AppDependencies dependencies,
  ) async {
    try {
      await dependencies.pushService.unbindAlias();
      await dependencies.pushService.clearBadgeAndNotifications();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6E7EB),
      body: const SizedBox.expand(),
    );
  }
}
