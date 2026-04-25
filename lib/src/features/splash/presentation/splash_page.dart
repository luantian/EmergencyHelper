import 'dart:async';

import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/routing/route_paths.dart';
import 'package:emergency_helper/src/features/event/data/event_center.dart';
import 'package:emergency_helper/src/features/push/data/push_service.dart';
import 'package:emergency_helper/src/features/risk/data/risk_center.dart';
import 'package:emergency_helper/src/features/trtc/data/trtc_service.dart';
import 'package:emergency_helper/src/features/trtc/data/tuicall_session_service.dart';
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
      await dependencies.pushService.unbindAlias();
      await dependencies.pushService.clearBadgeAndNotifications();
      await TUICallSessionService.instance.logoutSilently(
        dependencies: dependencies,
      );
      if (!mounted) {
        return;
      }
      context.go(RoutePaths.login);
      return;
    }

    final hasValidToken = await dependencies.authService.ensureValidAccessToken(
      validateWithServer: true,
    );
    if (!mounted) {
      return;
    }
    if (!hasValidToken) {
      EventCenter.instance.resetSessionCache(notify: false);
      RiskCenter.instance.resetSessionData(notify: false);
      await dependencies.pushService.unbindAlias();
      await dependencies.pushService.clearBadgeAndNotifications();
      await TUICallSessionService.instance.logoutSilently(
        dependencies: dependencies,
      );
      if (!mounted) {
        return;
      }
      context.go(RoutePaths.login);
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
    unawaited(_ensureCallSessionInBackground(dependencies));
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

  Future<void> _ensureCallSessionInBackground(
    AppDependencies dependencies,
  ) async {
    try {
      print('[PUSH-DEBUG] splash: _ensureCallSessionInBackground started');
      final result = await TUICallSessionService.instance.ensureLoggedIn(
        dependencies: dependencies,
      );
      print(
        '[PUSH-DEBUG] splash: ensureLoggedIn result=${result.success}, '
        'message=${result.message}, '
        'sdkAppId=${TUICallSessionService.instance.activeSdkAppId}',
      );
      var sdkAppId = TUICallSessionService.instance.activeSdkAppId;
      if (!result.success && sdkAppId == null) {
        // ensureLoggedIn may have failed because IM SDK was already logged in
        // (native "has login" reported as failure in Dart layer).
        // Try to fetch UserSig and retry login to get sdkAppId.
        print('[PUSH-DEBUG] splash: ensureLoggedIn failed, trying to recover');
        try {
          final authService = dependencies.authService;
          var sessionInfo = await authService.getCachedPermissionInfo();
          sessionInfo ??= await authService.fetchPermissionInfoAndCache();
          final userId = PushService.extractAliasFromPermissionInfo(
            sessionInfo,
          );
          if (userId != null && userId.isNotEmpty) {
            final userSigInfo = await TrtcService().getUserSig(
              dependencies.apiClient,
              userId: userId,
              roomId: 100001,
              logger: dependencies.logger,
            );
            if (userSigInfo.sdkAppId > 0) {
              sdkAppId = userSigInfo.sdkAppId;
              print(
                '[PUSH-DEBUG] splash: recovered sdkAppId=$sdkAppId '
                'from UserSig for userId=$userId',
              );
              // Try login again; if "has login" it will be treated as success.
              await TUICallSessionService.instance.ensureLoggedIn(
                dependencies: dependencies,
                forceRefreshSig: true,
                userIdHint: userId,
              );
              sdkAppId =
                  TUICallSessionService.instance.activeSdkAppId ?? sdkAppId;
            }
          }
        } catch (e) {
          print('[PUSH-DEBUG] splash: recovery failed: $e');
        }
      }
      if (sdkAppId != null && sdkAppId > 0) {
        print('[PUSH-DEBUG] splash: calling notifyIMLoggedIn($sdkAppId)');
        await dependencies.pushService.notifyIMLoggedIn(sdkAppId);
        print('[PUSH-DEBUG] splash: notifyIMLoggedIn completed');
      } else {
        print(
          '[PUSH-DEBUG] splash: no sdkAppId available, push not registered',
        );
      }
    } catch (e) {
      print('[PUSH-DEBUG] splash: _ensureCallSessionInBackground error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6E7EB),
      body: const SizedBox.expand(),
    );
  }
}
