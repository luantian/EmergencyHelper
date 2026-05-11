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

  /// Number of call pages pushed (IncomingCall + InCall).
  int _callPagesPushed = 0;

  /// When true, suppresses incoming call page auto-push from SDK.
  /// Used during cold-start join to avoid duplicate IncomingCallPage.
  bool suppressIncomingPush = false;

  /// When true, shows "通话已结束" toast after dismissAllCallScreens().
  /// Set by IncomingCallPage cold-start join failure catch block.
  static bool showCallEndedToast = false;

  void navigateToIncomingCall({
    required String callId,
    required String callerId,
    required String callerName,
    required String mediaType,
  }) {
    if (suppressIncomingPush) {
      debugPrint('[TRTC-DEBUG][Navigator] navigateToIncomingCall suppressed (cold-start in progress)');
      return;
    }
    _callPagesPushed++;
    final context = AppRouter.navigatorKey.currentContext;
    debugPrint('[TRTC-DEBUG][Navigator] navigateToIncomingCall callId=$callId caller=$callerName mediaType=$mediaType context=${context != null ? "OK" : "NULL"}');
    if (context == null) return;
    final path = '${RoutePaths.trtcIncomingCall}'
        '?callId=${Uri.encodeComponent(callId)}'
        '&callerId=${Uri.encodeComponent(callerId)}'
        '&callerName=${Uri.encodeComponent(callerName)}'
        '&mediaType=$mediaType';
    debugPrint('[TRTC-DEBUG][Navigator] pushing path: $path');
    GoRouter.of(context).push(path);
  }

  /// Callback set by InCallPage when mounted.
  /// When onCallBegin fires for the caller (already on InCallPage),
  /// this is invoked to re-mount video widgets instead of navigating.
  VoidCallback? onCallBeginForInCallPage;

  void navigateToInCall({
    required String callId,
    required String mediaType,
    String selfUserId = '',
    bool isCallerSide = true,
  }) {
    try {
      final context = AppRouter.navigatorKey.currentContext;
      debugPrint('[TRTC-DEBUG][Navigator] navigateToInCall callId=$callId mediaType=$mediaType selfUserId=$selfUserId isCallerSide=$isCallerSide context=${context != null ? "OK" : "NULL"}');
      if (context == null) {
        debugPrint('[TRTC-DEBUG][Navigator] ABORT: context is null');
        return;
      }

      _callPagesPushed++;
      final navigator = Navigator.of(context);
      final path = '${RoutePaths.trtcInCall}'
          '?callId=${Uri.encodeComponent(callId)}'
          '&mediaType=$mediaType'
          '&selfUserId=${Uri.encodeComponent(selfUserId)}'
          '&isCallerSide=$isCallerSide';

      debugPrint('[TRTC-DEBUG][Navigator] pushing path: $path');
      GoRouter.of(context).push(path);
    } catch (e, st) {
      debugPrint('[TRTC-DEBUG][Navigator] navigateToInCall crashed: $e');
      debugPrint('[TRTC-DEBUG][Navigator] stack: $st');
    }
  }

  void dismissAllCallScreens() {
    final context = AppRouter.navigatorKey.currentContext;
    debugPrint('[TRTC-DEBUG][Navigator] dismissAllCallScreens context=${context != null ? "OK" : "NULL"} pushCount=$_callPagesPushed');
    if (context == null) return;
    final navigator = Navigator.of(context);
    // Pop exactly the number of call pages we pushed.
    debugPrint('[TRTC-DEBUG][Navigator] calling _safePopCallPages from dismissAllCallScreens');
    _safePopCallPages(navigator, _callPagesPushed);
    _callPagesPushed = 0;

    // Show call-ended toast after pages are popped (avoids conflict with pop).
    if (showCallEndedToast) {
      showCallEndedToast = false;
      showToast('通话已结束');
    }
  }

  /// Pop call pages from the top of the stack without over-popping.
  /// Pops exactly [count] pages, or fewer if the stack runs out.
  void _safePopCallPages(NavigatorState navigator, [int count = 2]) {
    int toPop = count;
    while (toPop > 0 && navigator.canPop()) {
      debugPrint('[TRTC-DEBUG][Navigator] _safePopCallPages: popping $toPop more, canPop=true');
      navigator.pop();
      toPop--;
    }
    if (toPop > 0) {
      debugPrint('[TRTC-DEBUG][Navigator] _safePopCallPages: stopped, cannot pop further');
    }
  }

  void showToast(String message) {
    final context = AppRouter.navigatorKey.currentContext;
    if (context == null) return;
    AppCenterToast.show(context, message);
  }
}
