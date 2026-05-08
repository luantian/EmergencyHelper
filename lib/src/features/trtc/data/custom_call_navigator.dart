import 'package:emergency_helper/src/core/routing/app_router.dart';
import 'package:emergency_helper/src/core/routing/route_paths.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bridges TUICallSessionService observer callbacks to GoRouter navigation
/// without requiring a BuildContext.
class CustomCallNavigator {
  CustomCallNavigator._();
  static final CustomCallNavigator instance = CustomCallNavigator._();

  void navigateToIncomingCall({
    required String callId,
    required String callerId,
    required String callerName,
    required String mediaType,
  }) {
    final context = AppRouter.navigatorKey.currentContext;
    if (context == null) return;
    final path = '${RoutePaths.trtcIncomingCall}'
        '?callId=${Uri.encodeComponent(callId)}'
        '&callerId=${Uri.encodeComponent(callerId)}'
        '&callerName=${Uri.encodeComponent(callerName)}'
        '&mediaType=$mediaType';
    GoRouter.of(context).push(path);
  }

  void navigateToInCall({
    required String callId,
    required String mediaType,
  }) {
    final context = AppRouter.navigatorKey.currentContext;
    if (context == null) return;
    // Pop incoming call page if present, then push in-call page.
    final navigator = Navigator.of(context);
    navigator.popUntil(
      (route) => route.settings.name != RoutePaths.trtcIncomingCall,
    );
    final path = '${RoutePaths.trtcInCall}'
        '?callId=${Uri.encodeComponent(callId)}'
        '&mediaType=$mediaType';
    GoRouter.of(context).push(path);
  }

  void dismissAllCallScreens() {
    final context = AppRouter.navigatorKey.currentContext;
    if (context == null) return;
    final navigator = Navigator.of(context);
    navigator.popUntil(
      (route) =>
          route.settings.name != RoutePaths.trtcIncomingCall &&
          route.settings.name != RoutePaths.trtcInCall,
    );
  }

  void showToast(String message) {
    final context = AppRouter.navigatorKey.currentContext;
    if (context == null) return;
    AppCenterToast.show(context, message);
  }
}
