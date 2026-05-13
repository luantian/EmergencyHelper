import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/network/api_client.dart';
import 'package:go_router/go_router.dart';
import 'package:emergency_helper/src/core/routing/app_router.dart';
import 'package:emergency_helper/src/core/routing/pending_push_route_store.dart';
import 'package:emergency_helper/src/core/routing/route_paths.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/features/event/data/event_center.dart';
import 'package:emergency_helper/src/features/push/data/push_service.dart';
import 'package:emergency_helper/src/features/risk/data/risk_center.dart';
import 'package:emergency_helper/src/features/trtc/data/call_phase.dart';
import 'package:emergency_helper/src/features/trtc/data/custom_call_navigator.dart';
import 'package:emergency_helper/src/features/trtc/data/tuicall_session_service.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class EmergencyHelperApp extends StatefulWidget {
  const EmergencyHelperApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  /// Static accessor for SplashPage to await full app initialization
  /// (push init + pending push handling). Set in initState.
  static Future<void> Function()? appReady;

  @override
  State<EmergencyHelperApp> createState() => _EmergencyHelperAppState();
}

class _EmergencyHelperAppState extends State<EmergencyHelperApp> {
  late final _router = AppRouter.buildRouter();
  late final StreamSubscription<ApiAuthExpiredEvent> _authExpiredSubscription;
  late final StreamSubscription<PushOpenPayload> _pushOpenSubscription;
  late final StreamSubscription<PushIncomingEvent> _pushIncomingSubscription;

  Timer? _pushBannerTimer;
  _InAppPushBannerData? _pushBannerData;
  bool _isHandlingAuthExpired = false;
  bool _isNavigatingFromPush = false;
  final Completer<void> _initCompleter = Completer<void>();

  // Dedup key for push open events — prevents duplicate navigation when both
  // the Flutter plugin callback and the native retry loop fire for the same tap.
  String? _lastHandledPushKey;
  DateTime? _lastHandledPushTime;
  Timer? _navigatingFromPushResetTimer;

  @override
  void initState() {
    super.initState();
    EmergencyHelperApp.appReady = () => _initCompleter.future;
    _authExpiredSubscription = widget.dependencies.apiClient.authExpiredStream
        .listen((event) {
          unawaited(_handleAuthExpired(event));
        });
    _pushOpenSubscription = widget.dependencies.pushService.openPayloadStream
        .listen((payload) {
          unawaited(_handlePushOpen(payload));
        });
    _pushIncomingSubscription = widget
        .dependencies
        .pushService
        .incomingEventStream
        .listen((event) {
          unawaited(_handleIncomingPush(event));
        });
    TUICallSessionService.instance
        .addCallNotificationListener(_onCallNotification);
    // initCallObserver moved to after TUICallKit.login success
    unawaited(_initializeDependencies());
  }

  @override
  void dispose() {
    TUICallSessionService.instance.disposeCallObserver();
    TUICallSessionService.instance
        .removeCallNotificationListener(_onCallNotification);
    _authExpiredSubscription.cancel();
    _pushOpenSubscription.cancel();
    _pushIncomingSubscription.cancel();
    _pushBannerTimer?.cancel();
    _navigatingFromPushResetTimer?.cancel();
    widget.dependencies.dispose();
    super.dispose();
  }

  void _onCallNotification(String message) {
    debugPrint('[App] call notification: $message');
    AppCenterToast.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [Provider<AppDependencies>.value(value: widget.dependencies)],
      child: MaterialApp.router(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('en', 'US'),
        ],
        routerConfig: _router,
        builder: (context, child) {
          return Stack(
            children: <Widget>[
              child ?? const SizedBox.shrink(),
              if (_pushBannerData != null)
                _InAppTopPushBanner(
                  data: _pushBannerData!,
                  onTap: () => _onTapPushBanner(_pushBannerData!),
                  onClose: _dismissTopPushBanner,
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handlePushOpen(PushOpenPayload payload) async {
    debugPrint('[App] _handlePushOpen: START routePath=${payload.routePath}');
    _dismissTopPushBanner();

    // Dedup: same call notification within 3s → skip duplicate event.
    // Uses callId if available, otherwise composite key (callerId+page+mediaType).
    final rawCallId = (payload.raw['callId'] as String?) ?? '';
    final dedupKey = rawCallId.isNotEmpty
        ? 'call:$rawCallId'
        : 'caller:${payload.raw['callerId'] ?? ''}'
            '|page:${payload.raw['page'] ?? ''}'
            '|media:${payload.raw['mediaType'] ?? ''}';
    final now = DateTime.now();
    debugPrint('[App] _handlePushOpen: dedupKey=$dedupKey lastKey=$_lastHandledPushKey');
    if (dedupKey.isNotEmpty &&
        dedupKey == _lastHandledPushKey &&
        _lastHandledPushTime != null &&
        now.difference(_lastHandledPushTime!) < const Duration(seconds: 3)) {
      debugPrint('[App] _handlePushOpen: duplicate push skipped, key=$dedupKey');
      return;
    }
    _lastHandledPushKey = dedupKey;
    _lastHandledPushTime = now;

    if (_isNavigatingFromPush) {
      debugPrint('[App] _handlePushOpen: already navigating from push, skipping');
      return;
    }
    debugPrint('[App] _handlePushOpen: calling _navigateByRoutePath');
    await _navigateByRoutePath(payload.routePath, payload);
  }

  Future<void> _navigateByRoutePath(String routePath, [PushOpenPayload? payload]) async {
    debugPrint('[App] _navigateByRoutePath called: routePath=$routePath');
    if (_isNavigatingFromPush) {
      debugPrint('[App] _navigateByRoutePath: already navigating from push, skipping');
      return;
    }
    _isNavigatingFromPush = true;
    final normalizedPath = routePath.trim().toLowerCase();

    // Call-invite routes (/trtc-call-new, /trtc-call) should never be
    // navigated to directly 鈥?they use join() which bypasses the SDK call
    // state machine. Let the SDK observer re-deliver onCallReceived instead,
    // which triggers IncomingCallPage 鈫?accept() path.
    if (normalizedPath.startsWith('/trtc-call')) {
      _isNavigatingFromPush = false;
      debugPrint('[App] skipping navigation to call route $routePath; SDK will handle onCallReceived');
      return;
    }

    // When the resolved target is /home from an incoming call push notification,
    // we need to restore the incoming call UI ourselves — the push was sent by
    // our backend API (not the TRTC SDK), so the SDK observer will NOT re-fire
    // onCallReceived when the app cold-starts from this notification.
    if (normalizedPath == RoutePaths.home) {
      debugPrint('[App] target is /home, going directly via go(home)');
      _router.go(RoutePaths.home);

      // Do NOT open IncomingCallPage here from push payload. The push only
      // wakes the app — TRTC warmup (IM login + TUICallEngine init + observer
      // registration) must complete first. The SDK will fire onCallReceived
      // when the call is still active, which triggers navigateToIncomingCall.
      // If the call has ended, onCallNotConnected fires and we stay on Home.

      // Delay guard reset with a timer so a near-duplicate event (e.g. native
      // retry loop firing ~200ms later) hits the guard while still true.
      _navigatingFromPushResetTimer?.cancel();
      _navigatingFromPushResetTimer = Timer(
        const Duration(milliseconds: 500),
        () => _isNavigatingFromPush = false,
      );
      return;
    }

    // Store the push target route. SplashPage._bootstrapSession will
    // consume() it and navigate after auth is validated, ensuring a single
    // go(Home) 鈫?push(target) path instead of competing with this handler.
    PendingPushRouteStore.instance.set(routePath);
    debugPrint('[App] PendingPushRouteStore set to $routePath');

    final token = await widget.dependencies.authLocalStore.getAccessToken();
    if (!mounted) {
      _isNavigatingFromPush = false;
      debugPrint('[App] _navigateByRoutePath: not mounted after token check');
      return;
    }
    if (token == null || token.trim().isEmpty) {
      _isNavigatingFromPush = false;
      debugPrint('[App] _navigateByRoutePath: no token, going to login');
      _router.go(RoutePaths.login);
      return;
    }

    // Warm-start: user is already on a page (e.g. Home). Navigate via
    // go(home) 鈫?push(target) so back returns to home.
    // Cold-start: SplashPage._bootstrapSession will detect the pending
    // route and skip navigation 鈥?let this handler do the work.
    debugPrint('[App] _navigateByRoutePath: going to home, will push target=$routePath');
    _router.go(RoutePaths.home);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[App] _navigateByRoutePath: postFrameCallback firing, pushing $routePath');
      _isNavigatingFromPush = false;
      if (!mounted) {
        debugPrint('[App] _navigateByRoutePath: not mounted in postFrameCallback');
        return;
      }
      // Use the root navigator context, not this widget's context. The
      // widget tree may have changed (e.g., splash 鈫?home transition)
      // since go(home) was called, and a stale context causes push to fail.
      final rootContext = AppRouter.navigatorKey.currentContext;
      if (rootContext == null) {
        debugPrint('[App] _navigateByRoutePath: root navigator context not available');
        return;
      }
      rootContext.push(routePath);
    });
  }

  Future<void> _handleAuthExpired(ApiAuthExpiredEvent event) async {
    if (!mounted || _isHandlingAuthExpired) {
      return;
    }
    _isHandlingAuthExpired = true;
    _dismissTopPushBanner();
    try {
      final tokenSnapshot = await widget.dependencies.authLocalStore
          .getAccessToken();
      if (tokenSnapshot == null || tokenSnapshot.trim().isEmpty) {
        widget.dependencies.logger.info(
          'auth expired ignored without local token: path=${event.path}',
        );
        widget.dependencies.apiClient.resetAuthExpiredState();
        return;
      }

      final stillAuthorized = await widget.dependencies.authService
          .ensureValidAccessToken(validateWithServer: true)
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (stillAuthorized) {
        widget.dependencies.logger.info(
          'stale auth expired ignored: path=${event.path}',
        );
        widget.dependencies.apiClient.resetAuthExpiredState();
        return;
      }

      widget.dependencies.logger.info(
        'global auth expired: path=${event.path}, '
        'http=${event.httpStatusCode ?? "-"}, '
        'biz=${event.businessCode ?? "-"}, '
        'message=${event.message ?? "-"}',
      );
      widget.dependencies.apiClient.cancelAllPendingRequests(
        reason: 'AUTH_EXPIRED_FORCE_LOGOUT',
      );
      TUICallSessionService.instance.disposeCallObserver();
      TUICallSessionService.instance.clearLocalSessionState();
      EventCenter.instance.resetSessionCache(notify: false);
      RiskCenter.instance.resetSessionData(notify: false);
      await widget.dependencies.authLocalStore.clear();
      if (!mounted) {
        return;
      }
      _router.go(RoutePaths.login);
      unawaited(_runAuthExpiredCleanupInBackground());
    } catch (error, stackTrace) {
      widget.dependencies.logger.error(
        'handle global auth expired failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _router.go(RoutePaths.login);
      }
    } finally {
      _isHandlingAuthExpired = false;
    }
  }

  Future<void> _runAuthExpiredCleanupInBackground() async {
    await _runWithTimeout(
      widget.dependencies.pushService.unregisterPush(),
      timeout: const Duration(seconds: 3),
    );
    await _runWithTimeout(
      widget.dependencies.pushService.unbindAlias(),
      timeout: const Duration(seconds: 2),
    );
    await _runWithTimeout(
      widget.dependencies.pushService.clearBadgeAndNotifications(),
      timeout: const Duration(seconds: 2),
    );
    await _runWithTimeout(
      TUICallSessionService.instance.logoutSilently(
        dependencies: widget.dependencies,
      ),
      timeout: const Duration(seconds: 4),
    );
  }

  Future<void> _runWithTimeout(
    Future<void> task, {
    required Duration timeout,
  }) async {
    try {
      await task.timeout(timeout);
    } catch (_) {}
  }

  Future<void> _handleIncomingPush(PushIncomingEvent event) async {
    final token = await widget.dependencies.authLocalStore.getAccessToken();
    if (!mounted || token == null || token.trim().isEmpty) {
      return;
    }
    final payload = PushOpenPayload.fromEvent(event.payload);
    final isCallInvite = _isCallInvite(payload, event.payload);
    final data = _InAppPushBannerData(
      title: _resolveIncomingTitle(event.payload, isCallInvite: isCallInvite),
      content: _resolveIncomingContent(
        event.payload,
        isCallInvite: isCallInvite,
      ),
      routePath: payload.routePath,
      isCallInvite: isCallInvite,
      receivedAt: DateTime.now(),
    );
    _showTopPushBanner(data);
  }

  bool _isCallInvite(PushOpenPayload payload, Map<String, dynamic> rawEvent) {
    if (payload.routePath.trim().toLowerCase().startsWith('/trtc-call')) {
      return true;
    }
    final pageKey = _normalizePushKey(payload.page ?? payload.type ?? '');
    if (pageKey.contains('trtc') ||
        pageKey.contains('video_call') ||
        pageKey.contains('rtc_call') ||
        pageKey.contains('call_invite') ||
        pageKey.contains('invite_call')) {
      return true;
    }
    final merged = _extractMergedPushPayload(rawEvent);
    final typeKey = _normalizePushKey(
      _asText(merged['type']) ??
          _asText(merged['bizType']) ??
          _asText(merged['scene']) ??
          '',
    );
    return typeKey.contains('trtc') ||
        typeKey.contains('call') ||
        typeKey.contains('video');
  }

  void _showTopPushBanner(_InAppPushBannerData data) {
    if (!mounted) {
      return;
    }
    _pushBannerTimer?.cancel();
    setState(() {
      _pushBannerData = data;
    });
    final dismissDelay = data.isCallInvite
        ? const Duration(seconds: 15)
        : const Duration(seconds: 5);
    _pushBannerTimer = Timer(dismissDelay, () {
      if (!mounted) {
        return;
      }
      if (_pushBannerData?.receivedAt != data.receivedAt) {
        return;
      }
      _dismissTopPushBanner();
    });
  }

  Future<void> _onTapPushBanner(_InAppPushBannerData data) async {
    _dismissTopPushBanner();
    await _navigateByRoutePath(data.routePath);
  }

  void _dismissTopPushBanner() {
    _pushBannerTimer?.cancel();
    _pushBannerTimer = null;
    if (!mounted || _pushBannerData == null) {
      return;
    }
    setState(() {
      _pushBannerData = null;
    });
  }

  String _resolveIncomingTitle(
    Map<String, dynamic> event, {
    required bool isCallInvite,
  }) {
    final merged = _extractMergedPushPayload(event);
    return _pickFirstText(<Object?>[
          merged['title'],
          merged['notificationTitle'],
          merged['subject'],
          event['title'],
          event['notificationTitle'],
          event['cn.jpush.android.NOTIFICATION_CONTENT_TITLE'],
          event['cn.jpush.android.ALERT'],
          event['alert'],
        ]) ??
        (isCallInvite
            ? '\u89C6\u9891\u901A\u8BDD\u9080\u8BF7'
            : '\u65B0\u6D88\u606F');
  }

  String _resolveIncomingContent(
    Map<String, dynamic> event, {
    required bool isCallInvite,
  }) {
    final merged = _extractMergedPushPayload(event);
    if (isCallInvite) {
      final callType = _resolveCallTypeLabel(event, merged);
      return '\u9080\u8BF7\u4F60\u8FDB\u884C$callType\u901A\u8BDD\uFF0C\u70B9\u51FB\u7ACB\u5373\u63A5\u542C\u3002';
    }
    return _pickFirstText(<Object?>[
          merged['content'],
          merged['message'],
          merged['body'],
          merged['desc'],
          event['content'],
          event['message'],
          event['cn.jpush.android.ALERT'],
          event['alert'],
        ]) ??
        '\u6536\u5230\u4E00\u6761\u65B0\u6D88\u606F';
  }

  String _resolveCallTypeLabel(
    Map<String, dynamic> event,
    Map<String, dynamic> merged,
  ) {
    final raw = _pickFirstText(<Object?>[
      merged['mediaType'],
      merged['media_type'],
      merged['callType'],
      merged['call_type'],
      event['mediaType'],
      event['media_type'],
      event['callType'],
      event['call_type'],
    ]);
    final normalized = _normalizePushKey(raw ?? '');
    if (normalized.contains('audio') || normalized.contains('voice')) {
      return '\u8BED\u97F3';
    }
    if (normalized.contains('video')) {
      return '\u89C6\u9891';
    }
    return '\u89C6\u9891';
  }

  String _normalizePushKey(String value) {
    return value.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '');
  }

  Map<String, dynamic> _extractMergedPushPayload(Map<String, dynamic> event) {
    final merged = <String, dynamic>{};
    merged.addAll(_asMap(event['extras']) ?? const <String, dynamic>{});
    merged.addAll(
      _asMap(event['cn.jpush.android.EXTRA']) ?? const <String, dynamic>{},
    );
    merged.addAll(_asMap(event['extra']) ?? const <String, dynamic>{});
    merged.addAll(_asMap(event['data']) ?? const <String, dynamic>{});
    return merged;
  }

  String? _pickFirstText(List<Object?> candidates) {
    for (final candidate in candidates) {
      final text = _asText(candidate);
      if (text != null) {
        return text;
      }
    }
    return null;
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, data) => MapEntry(key.toString(), data));
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return decoded.map((key, data) => MapEntry(key.toString(), data));
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  String? _asText(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }

  Future<void> _initializeDependencies() async {
    try {
      await _ensureNotificationPermission();
      await widget.dependencies.initialize();
      final pendingPayload = widget.dependencies.pushService
          .consumePendingOpenPayload();
      if (pendingPayload != null) {
        await _handlePushOpen(pendingPayload);
      }
    } finally {
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    }

    // Start TRTC warmup (IM login + TUICallEngine init + observer registration)
    // at App level so it runs regardless of SplashPage lifecycle. This ensures
    // incoming call observer is registered even during cold-start from push.
    unawaited(_warmupTrtcInBackground());
    unawaited(_bindPushAliasInBackground());
  }

  Future<void> _warmupTrtcInBackground() async {
    try {
      final wasFromCallPush = _isFromCallPushColdStart();
      await TUICallSessionService.instance
          .warmupSessionAndPushInBackground(
            dependencies: widget.dependencies,
          )
          .timeout(const Duration(seconds: 30), onTimeout: () {});

      // If cold-started from a call push and no incoming call was received
      // after warmup completed, the call has already ended — show toast.
      if (wasFromCallPush && mounted) {
        final hasActiveCall =
            CallSessionManager.instance.current.phase == CallPhase.incomingRinging;
        if (!hasActiveCall) {
          debugPrint('[App] warmup done, no pending call → call expired');
          CustomCallNavigator.instance.showToast('通话已结束');
        }
      }
    } catch (_) {
      // Non-critical; subsequent protected APIs will re-init if needed.
    }
  }

  bool _isFromCallPushColdStart() {
    final page = PendingPushRouteStore.instance.peek();
    if (page == null) return false;
    final normalized = page.trim().toLowerCase();
    return normalized == RoutePaths.home ||
        normalized.startsWith('/trtc-call') ||
        normalized.contains('incoming_call');
  }

  Future<void> _bindPushAliasInBackground() async {
    try {
      Map<String, dynamic>? permissionInfo = await widget.dependencies.authService
          .getCachedPermissionInfo();
      permissionInfo ??= await widget.dependencies.authService
          .fetchPermissionInfoAndCache();
      await widget.dependencies.pushService.bindAliasFromPermissionInfo(
        permissionInfo,
      );
    } catch (_) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        Map<String, dynamic>? permissionInfo = await widget.dependencies.authService
            .getCachedPermissionInfo();
        permissionInfo ??= await widget.dependencies.authService
            .fetchPermissionInfoAndCache();
        await widget.dependencies.pushService.bindAliasFromPermissionInfo(
          permissionInfo,
        );
      } catch (_) {}
    }
  }

  Future<void> _ensureNotificationPermission() async {
    if (!Platform.isAndroid || _isFlutterTestEnv()) {
      return;
    }
    try {
      final status = await Permission.notification.status;
      if (status.isGranted) {
        return;
      }
      await Permission.notification.request();
    } catch (_) {
      // Keep startup resilient when permission plugin is unavailable.
    }
  }

  bool _isFlutterTestEnv() {
    return Platform.environment.containsKey('FLUTTER_TEST') &&
        Platform.environment['FLUTTER_TEST'] != 'false';
  }
}

class _InAppPushBannerData {
  const _InAppPushBannerData({
    required this.title,
    required this.content,
    required this.routePath,
    required this.isCallInvite,
    required this.receivedAt,
  });

  final String title;
  final String content;
  final String routePath;
  final bool isCallInvite;
  final DateTime receivedAt;
}

class _InAppTopPushBanner extends StatelessWidget {
  const _InAppTopPushBanner({
    required this.data,
    required this.onTap,
    required this.onClose,
  });

  final _InAppPushBannerData data;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 10,
      right: 10,
      top: 8,
      child: SafeArea(
        bottom: false,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                color: data.isCallInvite
                    ? const Color(0xFF0D5CB6)
                    : const Color(0xFF16324A),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x2A0F2239),
                    blurRadius: 14,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        data.isCallInvite
                            ? Icons.video_call_rounded
                            : Icons.notifications_active_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            data.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            data.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFE4ECF8),
                              fontSize: 12.5,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            data.isCallInvite
                                ? '\u70B9\u51FB\u4E00\u952E\u8FDB\u5165\u623F\u95F4'
                                : '\u70B9\u51FB\u67E5\u770B',
                            style: const TextStyle(
                              color: Color(0xFFB9D8FF),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: onClose,
                      constraints: const BoxConstraints(
                        minHeight: 28,
                        minWidth: 28,
                      ),
                      padding: EdgeInsets.zero,
                      splashRadius: 16,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 19,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
