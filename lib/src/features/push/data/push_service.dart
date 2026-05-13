import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/logging/app_logger.dart';
import 'package:emergency_helper/src/core/routing/route_paths.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_push/common/tim_push_listener.dart';
import 'package:tencent_cloud_chat_push/common/tim_push_message.dart';
import 'package:tencent_cloud_chat_push/tencent_cloud_chat_push.dart';
import 'package:tencent_cloud_chat_push/tencent_cloud_chat_push_platform_interface.dart';

class PushService {
  PushService({required AppLogger logger}) : _logger = logger;

  final AppLogger _logger;
  final TencentCloudChatPush _chatPush = TencentCloudChatPush();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<PushOpenPayload> _openPayloadController =
      StreamController<PushOpenPayload>.broadcast();
  final StreamController<PushIncomingEvent> _incomingEventController =
      StreamController<PushIncomingEvent>.broadcast();
  TIMPushListener? _pushListener;
  bool _pushListenerRegistered = false;
  bool _localNotificationInitialized = false;

  bool _initialized = false;
  bool _available = false;
  bool _registrationIdConfirmed = false;
  String? _registrationId;
  String? _boundAlias;
  String? _queuedAlias;
  String? _lastAliasBindCode;
  String? _lastAliasBindMessage;
  DateTime? _lastAliasBindTime;
  String? _lastRegisterPushCode;
  String? _lastRegisterPushMessage;
  DateTime? _lastRegisterPushTime;
  int? _lastRegisterPushSdkAppId;
  String? _lastSetRegistrationIdCode;
  String? _lastSetRegistrationIdMessage;
  DateTime? _lastSetRegistrationIdTime;
  String? _lastSetRegistrationIdValue;
  PushOpenPayload? _pendingOpenPayload;
  Future<void>? _ongoingNotifyImLoginTask;
  int? _ongoingNotifyImLoginSdkAppId;
  DateTime? _lastNotifyImLoginAt;
  int? _lastNotifyImLoginSdkAppId;
  int _lifecycleEpoch = 0;
  static const Duration _notifyImLoginDedupWindow = Duration(seconds: 8);
  static const Duration _registerPushTimeout = Duration(seconds: 10);
  static const Duration _getRegistrationIdTimeout = Duration(seconds: 5);
  static const Duration _unregisterPushTimeout = Duration(seconds: 5);
  static const String _localNotificationChannelId =
      'emergency_helper_push_channel';
  static const String _localNotificationChannelName =
      '\u6d88\u606f\u901a\u77e5';
  static const String _localNotificationChannelDescription =
      '\u7528\u4e8e\u5c55\u793a\u63a8\u9001\u6d88\u606f\u63d0\u9192';
  static const List<Duration> _aliasBindRetryBackoffs = <Duration>[
    Duration.zero,
    Duration(seconds: 2),
    Duration(seconds: 5),
  ];

  Stream<PushOpenPayload> get openPayloadStream =>
      _openPayloadController.stream;
  Stream<PushIncomingEvent> get incomingEventStream =>
      _incomingEventController.stream;

  String? get registrationId => _registrationId;
  String? get boundAlias => _boundAlias;
  String? get queuedAlias => _queuedAlias;
  bool get isInitialized => _initialized;
  String? get lastAliasBindCode => _lastAliasBindCode;
  String? get lastAliasBindMessage => _lastAliasBindMessage;
  DateTime? get lastAliasBindTime => _lastAliasBindTime;
  String? get lastRegisterPushCode => _lastRegisterPushCode;
  String? get lastRegisterPushMessage => _lastRegisterPushMessage;
  DateTime? get lastRegisterPushTime => _lastRegisterPushTime;
  int? get lastRegisterPushSdkAppId => _lastRegisterPushSdkAppId;
  String? get lastSetRegistrationIdCode => _lastSetRegistrationIdCode;
  String? get lastSetRegistrationIdMessage => _lastSetRegistrationIdMessage;
  DateTime? get lastSetRegistrationIdTime => _lastSetRegistrationIdTime;
  String? get lastSetRegistrationIdValue => _lastSetRegistrationIdValue;

  bool get isAvailable => _available;

  Future<String?> refreshRegistrationId() async {
    // Don't override a confirmed RegistrationID. The native SDK's
    // getRegistrationID() may return a short value (e.g., IM userId)
    // before vendor push tokens arrive 鈥?we don't want to lose the real one.
    if (_registrationIdConfirmed && _registrationId != null) {
      _available = true;
      await _retryQueuedAliasIfNeeded();
      return _registrationId;
    }
    final fetched = (await _getRegistrationIdSafe())?.trim();
    if (fetched != null && fetched.isNotEmpty) {
      final keepCurrentConfirmedLongToken =
          (_registrationIdConfirmed &&
              (_registrationId ?? '').trim().isNotEmpty &&
              _looksLikeVendorToken(_registrationId!.trim())) &&
          !_looksLikeVendorToken(fetched);
      if (!keepCurrentConfirmedLongToken) {
        _registrationId = fetched;
        _registrationIdConfirmed = _looksLikeVendorToken(fetched);
      }
      _available = true;
      await _retryQueuedAliasIfNeeded();
    }
    return _registrationId;
  }

  Future<void> syncBadgeCount(int unreadCount) async {
    // Badge is managed by the app UI; TIMPush does not expose a badge API.
    _logger.info('sync badge count: $unreadCount');
  }

  Future<void> clearBadgeAndNotifications() async {
    // App UI handles badge clearing; TIMPush handles internal notification state.
    try {
      await _localNotifications.cancelAll();
    } catch (_) {}
    _logger.info('clear push badge');
  }

  PushDebugSnapshot getDebugSnapshot({String? userId}) {
    return PushDebugSnapshot(
      initialized: _initialized,
      available: _available,
      userId: userId,
      registrationId: _registrationId,
      boundAlias: _boundAlias,
      queuedAlias: _queuedAlias,
      lastAliasBindCode: _lastAliasBindCode,
      lastAliasBindMessage: _lastAliasBindMessage,
      lastAliasBindTime: _lastAliasBindTime,
      lastRegisterPushCode: _lastRegisterPushCode,
      lastRegisterPushMessage: _lastRegisterPushMessage,
      lastRegisterPushTime: _lastRegisterPushTime,
      lastRegisterPushSdkAppId: _lastRegisterPushSdkAppId,
      lastSetRegistrationIdCode: _lastSetRegistrationIdCode,
      lastSetRegistrationIdMessage: _lastSetRegistrationIdMessage,
      lastSetRegistrationIdTime: _lastSetRegistrationIdTime,
      lastSetRegistrationIdValue: _lastSetRegistrationIdValue,
      production: false,
      channel: 'tim-push',
      appKey: 'N/A (uses timpush-configs.json)',
    );
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    if (!Platform.isAndroid && !Platform.isIOS) {
      _logger.info('push init skipped: unsupported platform');
      return;
    }

    try {
      // Only register the notification click callback here 鈥?do NOT call
      // registerPush() yet, because the IM SDK isn't logged in and
      // registerPush would fail with "not logined" (errcode 800001).
      // The actual push registration (registerPush) will happen after
      // IM login via notifyIMLoggedIn().
      final clickResult = await TencentCloudChatPushPlatform.instance
          .registerOnNotificationClickedEvent(
            onNotificationClicked: _onNotificationClicked,
          );
      _logger.info('push click callback registered, code=${clickResult.code}');
      final wakeResult = await TencentCloudChatPushPlatform.instance
          .registerOnAppWakeUpEvent(onAppWakeUpEvent: _onAppWakeUpEvent);
      _logger.info(
        'push app-wake callback registered, code=${wakeResult.code}',
      );
      await _ensurePushListenerRegistered();
      await _ensureLocalNotificationInitialized();

      // Check for cold-start push notification ext data from Intent extras.
      await _checkColdStartPushExt();

      // Don't call getRegistrationID here 鈥?before IM login it may return
      // the IM userId instead of the real vendor push token.
      _logger.info('push initialized (awaiting IM login for registration)');
    } on MissingPluginException catch (error, stackTrace) {
      _recordAliasBindResult(
        code: 'INIT_PLUGIN_MISSING',
        message: error.message ?? error.toString(),
      );
      _logger.error(
        'push init failed: missing plugin',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      _recordAliasBindResult(code: 'INIT_FAILED', message: error.toString());
      _logger.error('push init failed', error: error, stackTrace: stackTrace);
    }
  }

  /// Call this after the IM SDK (TUICallKit) has successfully logged in.
  /// This registers push with the correct sdkAppId so the native TIMPush SDK
  /// can properly report the vendor channel token to the Tencent IM server.
  Future<void> notifyIMLoggedIn(
    int sdkAppId, {
    String? userId,
    bool force = false,
  }) async {
    final epoch = _lifecycleEpoch;
    final running = _ongoingNotifyImLoginTask;
    if (!force &&
        running != null &&
        _ongoingNotifyImLoginSdkAppId == sdkAppId) {
      await running;
      return;
    }
    if (!force &&
        _available &&
        _lastNotifyImLoginSdkAppId == sdkAppId &&
        _lastNotifyImLoginAt != null &&
        DateTime.now().difference(_lastNotifyImLoginAt!) <
            _notifyImLoginDedupWindow) {
      _logger.debug(
        '[PUSH-DEBUG] notifyIMLoggedIn deduped for sdkAppId=$sdkAppId',
      );
      return;
    }
    final task = _notifyIMLoggedInInternal(
      sdkAppId,
      epoch: epoch,
      force: force,
    );
    _ongoingNotifyImLoginTask = task;
    _ongoingNotifyImLoginSdkAppId = sdkAppId;
    try {
      await task;
      _lastNotifyImLoginSdkAppId = sdkAppId;
      _lastNotifyImLoginAt = DateTime.now();
    } finally {
      if (identical(_ongoingNotifyImLoginTask, task)) {
        _ongoingNotifyImLoginTask = null;
        _ongoingNotifyImLoginSdkAppId = null;
      }
    }
  }

  Future<void> _notifyIMLoggedInInternal(
    int sdkAppId, {
    required int epoch,
    required bool force,
  }) async {
    _logger.debug(
      '[PUSH-DEBUG] notifyIMLoggedIn called with sdkAppId=$sdkAppId',
    );
    if (_isEpochStale(epoch)) {
      return;
    }
    if (!_initialized) {
      _recordRegisterPushResult(
        code: 'NOT_INITIALIZED',
        message: 'push not yet initialized',
        sdkAppId: sdkAppId,
      );
      _logger.error('notifyIMLoggedIn: push not yet initialized');
      return;
    }
    if (sdkAppId <= 0) {
      _recordRegisterPushResult(
        code: 'INVALID_SDKAPPID',
        message: 'invalid sdkAppId: $sdkAppId',
        sdkAppId: sdkAppId,
      );
      _logger.error('notifyIMLoggedIn: invalid sdkAppId=$sdkAppId');
      return;
    }
    try {
      _recordSetRegistrationIdResult(
        code: 'SKIP',
        message: 'setRegistrationID disabled; use SDK-generated RegistrationID',
        value: '',
      );
      final result = await _chatPush
          .registerPush(
            sdkAppId: sdkAppId,
            appKey: _resolvedTimPushAppKey,
            onNotificationClicked: _onNotificationClicked,
          )
          .timeout(_registerPushTimeout);
      if (_isEpochStale(epoch)) {
        return;
      }
      await _ensurePushListenerRegistered();
      _logger.debug(
        'push re-registered after IM login, sdkAppId=$sdkAppId, '
        'code=${result.code}, dataLength=${result.data?.length ?? 0}',
      );
      final registerMessage = (result.errorMessage ?? '').trim().isNotEmpty
          ? result.errorMessage!.trim()
          : (result.code == 0 ? 'registerPush success' : 'registerPush failed');
      _recordRegisterPushResult(
        code: result.code.toString(),
        message: force ? '[force] $registerMessage' : registerMessage,
        sdkAppId: sdkAppId,
      );
      if (result.code == 0) {
        _available = true;
      }

      // Capture the RegistrationID directly from registerPush response.
      // The response data IS the RegistrationID on success.
      if (result.code == 0 && result.data != null && result.data!.isNotEmpty) {
        _registrationId = result.data!.trim();
        _available = true;
        _registrationIdConfirmed = _looksLikeVendorToken(_registrationId!);
        _logger.debug(
          '[PUSH-DEBUG] notifyIMLoggedIn captured registrationId='
          '${_maskSensitive(_registrationId)}',
        );
      }

      // TIMPush SDK only auto-registers Huawei+FCM vendor channels.
      // On Honor devices (without HMS), we need to manually register
      // the Honor push channel after the IM login completes.
      if (await _isHonorDevice()) {
        await _registerHonorPush(epoch: epoch);
      }

      // Vendor push tokens (Huawei/Honor) are obtained asynchronously.
      // Wait and retry until we get a valid RegistrationID.
      await _pollRegistrationId(epoch: epoch);

      // If an alias was queued while push was unavailable, retry binding now.
      await _retryQueuedAliasIfNeeded();
    } catch (error, stackTrace) {
      _recordRegisterPushResult(
        code: 'EXCEPTION',
        message: error.toString(),
        sdkAppId: sdkAppId,
      );
      _logger.error(
        'push re-register after IM login failed',
        error: error,
        stackTrace: stackTrace,
      );
      // Still try Honor push and polling even if main registration failed.
      if (await _isHonorDevice()) {
        await _registerHonorPush(epoch: epoch);
      }
      await _pollRegistrationId(epoch: epoch);

      // Retry queued alias even on partial recovery.
      await _retryQueuedAliasIfNeeded();
    }
  }

  /// Poll for a valid RegistrationID after vendor channels are registered.
  /// Vendor tokens (Huawei/Honor) arrive asynchronously, so we need to wait.
  /// A real vendor token is typically a long base64-like string (20+ chars),
  /// whereas a userId is usually short (1-10 chars).
  Future<void> _pollRegistrationId({required int epoch}) async {
    const maxRetries = 15;
    const retryDelay = Duration(seconds: 2);
    final originalRegId = (_registrationId ?? '').trim();
    final originalLooksLikeVendor =
        originalRegId.isNotEmpty && _looksLikeVendorToken(originalRegId);
    String? latestFallbackRegId = originalRegId.isNotEmpty
        ? originalRegId
        : null;
    for (var i = 0; i < maxRetries; i++) {
      if (_isEpochStale(epoch)) {
        return;
      }
      final regId = (await _getRegistrationIdSafe())?.trim();
      _logger.debug(
        '[PUSH-DEBUG] pollRegistrationId attempt ${i + 1}/$maxRetries: '
        'fetched=${_maskSensitive(regId)}, '
        'current=${_maskSensitive(_registrationId)}',
      );
      if (regId != null && regId.isNotEmpty && _looksLikeVendorToken(regId)) {
        _registrationId = regId;
        _available = true;
        _registrationIdConfirmed = true;
        _logger.info(
          'RegistrationID obtained after ${i + 1} polls: '
          '${_maskSensitive(regId)}',
        );
        return;
      }
      if ((latestFallbackRegId == null || latestFallbackRegId.isEmpty) &&
          regId != null &&
          regId.isNotEmpty) {
        latestFallbackRegId = regId;
      }
      if (i < maxRetries - 1) {
        await Future.delayed(retryDelay);
      }
    }
    if (_isEpochStale(epoch)) {
      return;
    }
    // If polling didn't yield a vendor token, keep whatever we had before
    // (which might be from the registerPush response).
    if (latestFallbackRegId != null && latestFallbackRegId.isNotEmpty) {
      final shouldKeepOriginalVendor =
          originalLooksLikeVendor &&
          !_looksLikeVendorToken(latestFallbackRegId);
      final resolvedRegId = shouldKeepOriginalVendor
          ? originalRegId
          : latestFallbackRegId;
      _registrationId = resolvedRegId;
      _available = true;
      _registrationIdConfirmed = _looksLikeVendorToken(resolvedRegId);
      _logger.info(
        'Polling did not yield a vendor token, using fallback registrationId: '
        '${_maskSensitive(resolvedRegId)}',
      );
    } else {
      _logger.info(
        'Failed to obtain RegistrationID after $maxRetries polls. '
        'Vendor push channel may not be fully registered.',
      );
    }
    _logger.debug(
      '[PUSH-DEBUG] pollRegistrationId: final registrationId='
      '${_maskSensitive(_registrationId)}',
    );
  }

  /// Check if a token looks like a real vendor push token.
  /// Vendor tokens are typically long base64-like strings (20+ chars),
  /// whereas userId values are usually short numeric or alphanumeric strings.
  bool _looksLikeVendorToken(String token) {
    // A real vendor token should be at least 20 characters long
    // and contain characters typical of base64 encoding.
    return token.length >= 20;
  }

  bool _isEpochStale(int epoch) => epoch != _lifecycleEpoch;

  String _maskSensitive(String? raw, {int keepPrefix = 3, int keepSuffix = 3}) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) {
      return '--';
    }
    final visibleThreshold = keepPrefix + keepSuffix + 2;
    if (value.length <= visibleThreshold) {
      return '***(${value.length})';
    }
    final prefix = value.substring(0, keepPrefix);
    final suffix = value.substring(value.length - keepSuffix);
    return '$prefix***$suffix(${value.length})';
  }

  /// Retry binding the queued alias once push becomes available again.
  Future<void> _retryQueuedAliasIfNeeded() async {
    final queued = _queuedAlias;
    if (queued == null || queued.trim().isEmpty || !_available) {
      return;
    }
    _logger.info(
      'retrying queued alias after IM login: ${_maskSensitive(queued)}',
    );
    await bindAlias(queued);
  }

  /// Check if the device brand is Honor (鐙珛鍝佺墝).
  /// After 2020, Honor separated from Huawei and uses a different push channel.
  /// TIMPush SDK auto-registers Huawei push, but Honor needs manual trigger.
  static Future<bool> _isHonorDevice() async {
    if (!Platform.isAndroid) return false;
    try {
      const channel = MethodChannel('com.tianyanzhiyun/device_brand');
      final brand = await channel.invokeMethod<String>('getDeviceBrand');
      return brand?.toLowerCase() == 'honor';
    } catch (_) {
      return false;
    }
  }

  /// Manually trigger Honor push registration via native method channel.
  /// TIMPush SDK skips Honor channel entirely on Honor devices (uses
  /// Huawei鈫扚CM fallback instead), so we need this manual step.
  Future<void> _registerHonorPush({required int epoch}) async {
    if (_isEpochStale(epoch)) {
      return;
    }
    try {
      const channel = MethodChannel('com.tianyanzhiyun/push_honor');
      await channel.invokeMethod('registerHonorPush');
      _logger.info('Honor push registration triggered');
      // Give Honor push SDK time to register and get token, then refresh.
      await Future.delayed(const Duration(seconds: 2));
      if (_isEpochStale(epoch)) {
        return;
      }
      _registrationId = await _getRegistrationIdSafe();
      _logger.info(
        'After Honor push registration, registrationId='
        '${_maskSensitive(_registrationId)}',
      );
    } catch (error, stackTrace) {
      _logger.error(
        'register Honor push failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _onNotificationClicked({
    required String ext,
    String? userID,
    String? groupID,
  }) {
    _logger.info(
      '[PUSH-DIAG] _onNotificationClicked: ext=$ext, userID=$userID, groupID=$groupID',
    );
    Map<String, dynamic> payload;
    try {
      if (ext.isNotEmpty) {
        payload = jsonDecode(ext) as Map<String, dynamic>;
      } else {
        payload = {'userID': userID, 'groupID': groupID};
      }
    } catch (_) {
      payload = {'ext': ext, 'userID': userID, 'groupID': groupID};
    }
    _logger.info(
      '[PUSH-DIAG] decoded payload keys=${payload.keys.toList()}',
    );
    payload.forEach((key, value) {
      _logger.info('[PUSH-DIAG] payload[$key] = $value');
    });
    final openPayload = PushOpenPayload.fromEvent(payload);
    _logger.info(
      '[PUSH-DIAG] PushOpenPayload: routePath=${openPayload.routePath}, eventId=${openPayload.eventId}, page=${openPayload.page}, type=${openPayload.type}',
    );
    if (_openPayloadController.hasListener) {
      _pendingOpenPayload = null;
      _openPayloadController.add(openPayload);
    } else {
      _pendingOpenPayload = openPayload;
    }
    _logger.info(
      'push opened via notification click: '
      'route=${openPayload.routePath}',
    );
  }

  void _onAppWakeUpEvent() {
    _logger.info('push app-wake event received');
  }

  /// Check for cold-start push notification ext data that was extracted
  /// from the launch Intent. TIMPush SDK doesn't fire callbacks on cold-start,
  /// so we read the ext data via a MethodChannel.
  Future<void> _checkColdStartPushExt() async {
    try {
      const channel = MethodChannel('com.tianyanzhiyun/cold_start_push');
      final ext = await channel.invokeMethod<String>('getColdStartPushExt');
      if (ext == null || ext.isEmpty) {
        _logger.info('cold-start: no push ext found in Intent');
        return;
      }
      _logger.info('[PUSH-DIAG] cold-start: found push ext in Intent: $ext');

      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(ext) as Map<String, dynamic>;
      } catch (_) {
        payload = {'ext': ext};
      }
      _logger.info(
        '[PUSH-DIAG] cold-start decoded payload keys=${payload.keys.toList()}',
      );

      final openPayload = PushOpenPayload.fromEvent(payload);
      _logger.info(
        '[PUSH-DIAG] cold-start PushOpenPayload: routePath=${openPayload.routePath}, eventId=${openPayload.eventId}, page=${openPayload.page}',
      );

      if (_openPayloadController.hasListener) {
        _pendingOpenPayload = null;
        _openPayloadController.add(openPayload);
      } else {
        _pendingOpenPayload = openPayload;
      }
    } on MissingPluginException {
      _logger.info('cold-start: MethodChannel not available, skipping');
    } catch (error, stackTrace) {
      _logger.error(
        'cold-start: failed to check push ext',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _ensurePushListenerRegistered() async {
    if (_pushListenerRegistered) {
      return;
    }
    try {
      final listener = TIMPushListener(
        onRecvPushMessage: _onRecvPushMessage,
        onRevokePushMessage: _onRevokePushMessage,
      );
      await _chatPush.addPushListener(listener: listener);
      _pushListener = listener;
      _pushListenerRegistered = true;
      _logger.info('TIM push listener registered');
    } catch (error, stackTrace) {
      _logger.error(
        'register TIM push listener failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _onRecvPushMessage(TimPushMessage message) {
    final payload = <String, dynamic>{};
    final title = _asText(message.title);
    final desc = _asText(message.desc);
    final ext = _asText(message.ext);
    final messageId = _asText(message.messageID);
    if (title != null) {
      payload['title'] = title;
    }
    if (desc != null) {
      payload['desc'] = desc;
      payload['content'] = desc;
      payload['message'] = desc;
    }
    if (ext != null) {
      payload['ext'] = ext;
    }
    if (messageId != null) {
      payload['messageID'] = messageId;
    }
    if (payload.isEmpty) {
      return;
    }
    unawaited(
      _showLocalSystemNotification(payload: payload, title: title, body: desc),
    );
    _emitIncomingEvent(PushIncomingEventSource.message, payload);
  }

  void _onRevokePushMessage(String messageId) {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) {
      return;
    }
    _emitIncomingEvent(PushIncomingEventSource.notification, <String, dynamic>{
      'messageID': normalizedMessageId,
      'revoke': true,
    });
  }

  void _emitIncomingEvent(
    PushIncomingEventSource source,
    Map<String, dynamic> payload,
  ) {
    if (_incomingEventController.isClosed) {
      return;
    }
    _incomingEventController.add(
      PushIncomingEvent(
        source: source,
        payload: Map<String, dynamic>.from(payload),
        receivedAt: DateTime.now(),
      ),
    );
  }

  Future<void> bindAliasFromPermissionInfo(
    Map<String, dynamic>? permissionInfo,
  ) async {
    final alias = extractAliasFromPermissionInfo(permissionInfo);
    if (alias == null || alias.isEmpty) {
      return;
    }
    await bindAlias(alias);
  }

  Future<void> bindAlias(String alias) async {
    final normalizedAlias = alias.trim();
    if (normalizedAlias.isEmpty) {
      return;
    }
    if (!_available) {
      final currentRegId = await _getRegistrationIdSafe();
      if (currentRegId != null && currentRegId.trim().isNotEmpty) {
        _registrationId = currentRegId.trim();
        _available = true;
      }
    }
    if (!_available) {
      _queuedAlias = normalizedAlias;
      _recordAliasBindResult(
        code: 'PENDING',
        message: 'Push not ready, alias queued: $normalizedAlias',
      );
      return;
    }
    if (_boundAlias == normalizedAlias) {
      _recordAliasBindResult(
        code: 'SKIP',
        message: 'Alias already bound: $normalizedAlias',
      );
      return;
    }
    final outcome = await _bindAliasWithRetry(normalizedAlias);
    if (outcome.success) {
      _boundAlias = normalizedAlias;
      _queuedAlias = null;
      _recordAliasBindResult(code: outcome.code, message: outcome.message);
      _logger.info('push alias bound: ${_maskSensitive(normalizedAlias)}');
      return;
    }
    _queuedAlias = normalizedAlias;
    _recordAliasBindResult(code: outcome.code, message: outcome.message);
    _logger.error(
      'bind push alias failed: alias=${_maskSensitive(normalizedAlias)}, '
      'code=${outcome.code}, message=${outcome.message}',
    );
  }

  Future<void> unregisterPush({
    Duration timeout = _unregisterPushTimeout,
  }) async {
    _lifecycleEpoch++;
    _clearLocalPushRuntimeState();
    try {
      final result = await _chatPush.unRegisterPush().timeout(timeout);
      final code = result.code.toString();
      final message = (result.errorMessage ?? '').trim().isNotEmpty
          ? result.errorMessage!.trim()
          : (result.code == 0
                ? 'unRegisterPush success'
                : 'unRegisterPush failed');
      _recordAliasBindResult(code: 'UNREGISTER_$code', message: message);
      if (result.code == 0) {
        _logger.info('push unregistered successfully');
      } else {
        _logger.error(
          'push unregister returned non-zero code: '
          'code=$code, message=$message',
        );
      }
    } on TimeoutException catch (error, stackTrace) {
      _recordAliasBindResult(
        code: 'UNREGISTER_TIMEOUT',
        message: error.message ?? 'unRegisterPush timeout',
      );
      _logger.error(
        'push unregister timeout',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      _recordAliasBindResult(
        code: 'UNREGISTER_EXCEPTION',
        message: error.toString(),
      );
      _logger.error(
        'push unregister failed',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _clearLocalPushRuntimeState();
    }
  }

  Future<void> unbindAlias() async {
    _lifecycleEpoch++;
    _clearLocalPushRuntimeState();
    _recordAliasBindResult(code: 'UNBIND', message: 'Alias unbound');
    _logger.info('push alias unbound (local state cleared)');
  }

  void _clearLocalPushRuntimeState() {
    _queuedAlias = null;
    _boundAlias = null;
    _available = false;
    _registrationId = null;
    _registrationIdConfirmed = false;
    _ongoingNotifyImLoginTask = null;
    _ongoingNotifyImLoginSdkAppId = null;
    _lastNotifyImLoginAt = null;
    _lastNotifyImLoginSdkAppId = null;
  }

  void _recordAliasBindResult({required String code, required String message}) {
    _lastAliasBindCode = code;
    _lastAliasBindMessage = message;
    _lastAliasBindTime = DateTime.now();
  }

  void _recordRegisterPushResult({
    required String code,
    required String message,
    required int sdkAppId,
  }) {
    _lastRegisterPushCode = code;
    _lastRegisterPushMessage = message;
    _lastRegisterPushSdkAppId = sdkAppId;
    _lastRegisterPushTime = DateTime.now();
  }

  void _recordSetRegistrationIdResult({
    required String code,
    required String message,
    required String value,
  }) {
    _lastSetRegistrationIdCode = code;
    _lastSetRegistrationIdMessage = message;
    _lastSetRegistrationIdValue = value;
    _lastSetRegistrationIdTime = DateTime.now();
  }

  PushOpenPayload? consumePendingOpenPayload() {
    final payload = _pendingOpenPayload;
    _pendingOpenPayload = null;
    return payload;
  }

  static String? extractAliasFromPermissionInfo(Map<String, dynamic>? info) {
    if (info == null || info.isEmpty) {
      return null;
    }

    final permissionInfo = _asMap(info['permissionInfo']) ?? info;
    final permissionData = _asMap(permissionInfo['data']) ?? permissionInfo;
    final profileInfo =
        _asMap(info['profileInfo']) ?? _asMap(permissionInfo['profileInfo']);
    final profileData = _asMap(profileInfo?['data']) ?? profileInfo;

    final candidates = <Map<String, dynamic>?>[
      _asMap(permissionData['user']),
      _asMap(permissionInfo['user']),
      _asMap(info['user']),
      _asMap(profileData?['user']),
      profileData,
      permissionData,
      permissionInfo,
      info,
    ];

    for (final candidate in candidates) {
      if (candidate == null || candidate.isEmpty) {
        continue;
      }
      final userId =
          _asText(candidate['id']) ??
          _asText(candidate['userId']) ??
          _asText(candidate['uid']);
      if (userId == null || userId.trim().isEmpty) {
        continue;
      }
      return userId.trim();
    }
    return null;
  }

  Future<_AliasBindOutcome> _bindAliasWithRetry(String alias) async {
    _AliasBindOutcome? lastOutcome;
    final totalAttempts = _aliasBindRetryBackoffs.length;
    for (var index = 0; index < totalAttempts; index++) {
      final attempt = index + 1;
      final backoff = _aliasBindRetryBackoffs[index];
      if (backoff > Duration.zero) {
        await Future<void>.delayed(backoff);
      }
      if ((_registrationId ?? '').trim().isEmpty) {
        _registrationId = await _getRegistrationIdSafe();
      }
      final outcome = await _bindAliasOnce(alias);
      if (outcome.success) {
        if (attempt > 1) {
          _logger.info(
            'push alias bind recovered on retry '
            '$attempt/$totalAttempts: $alias',
          );
        }
        return outcome;
      }
      lastOutcome = outcome;
      _logger.error(
        'push alias bind attempt failed ($attempt/$totalAttempts): '
        'alias=$alias, code=${outcome.code}, message=${outcome.message}',
      );
    }
    return lastOutcome ??
        const _AliasBindOutcome(
          success: false,
          code: 'BIND_FAILED',
          message: 'Alias bind failed',
        );
  }

  Future<_AliasBindOutcome> _bindAliasOnce(String alias) async {
    // TIMPush manages device registration automatically upon login to IM SDK.
    // "Binding alias" here is a no-op since TIMPush uses the IM SDK's user
    // identity 鈥?the user is already identified via TUICallKit login.
    return const _AliasBindOutcome(
      success: true,
      code: '0',
      message: 'Alias already managed by TIMPush',
    );
  }

  Future<void> _ensureLocalNotificationInitialized() async {
    if (_localNotificationInitialized) {
      return;
    }
    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const settings = InitializationSettings(android: androidSettings);
      await _localNotifications.initialize(
        settings,
        onDidReceiveNotificationResponse: (response) {
          _onLocalNotificationTapped(response.payload);
        },
      );
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _localNotificationChannelId,
          _localNotificationChannelName,
          description: _localNotificationChannelDescription,
          importance: Importance.max,
        ),
      );
      _localNotificationInitialized = true;
    } catch (error, stackTrace) {
      _logger.error(
        'initialize local notifications failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _showLocalSystemNotification({
    required Map<String, dynamic> payload,
    required String? title,
    required String? body,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    await _ensureLocalNotificationInitialized();
    if (!_localNotificationInitialized) {
      return;
    }

    final resolvedTitle = (title ?? '').trim().isEmpty
        ? '\u65b0\u6d88\u606f'
        : title!.trim();
    final resolvedBody = (body ?? '').trim().isEmpty
        ? '\u6536\u5230\u4e00\u6761\u63a8\u9001\u6d88\u606f'
        : body!.trim();
    const androidDetails = AndroidNotificationDetails(
      _localNotificationChannelId,
      _localNotificationChannelName,
      channelDescription: _localNotificationChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
    );
    const details = NotificationDetails(android: androidDetails);
    final messageId = _asText(payload['messageID']);
    final notificationId = (messageId ?? DateTime.now().toIso8601String())
        .hashCode
        .abs();

    try {
      await _localNotifications.show(
        notificationId,
        resolvedTitle,
        resolvedBody,
        details,
        payload: _buildLocalNotificationPayload(payload),
      );
    } catch (error, stackTrace) {
      _logger.error(
        'show local system notification failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _onLocalNotificationTapped(String? rawPayload) {
    final payloadText = (rawPayload ?? '').trim();
    if (payloadText.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(payloadText);
      if (decoded is! Map) {
        return;
      }
      final event = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final openPayload = PushOpenPayload.fromEvent(event);
      if (_openPayloadController.hasListener) {
        _pendingOpenPayload = null;
        _openPayloadController.add(openPayload);
      } else {
        _pendingOpenPayload = openPayload;
      }
    } catch (error, stackTrace) {
      _logger.error(
        'parse local notification payload failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  String _buildLocalNotificationPayload(Map<String, dynamic> payload) {
    try {
      return jsonEncode(payload);
    } catch (_) {
      return '{}';
    }
  }

  Future<String?> _getRegistrationIdSafe() async {
    try {
      final result = await TencentCloudChatPush().getRegistrationID().timeout(
        _getRegistrationIdTimeout,
      );
      if (result.code == 0 && result.data != null && result.data!.isNotEmpty) {
        return result.data!.trim();
      }
      return null;
    } catch (error, stackTrace) {
      _logger.error(
        'get registration id failed',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  String? get _resolvedTimPushAppKey {
    final value = AppConstants.timPushAppKey.trim();
    if (value.isEmpty) {
      return null;
    }
    return value;
  }

  void dispose() {
    _lifecycleEpoch++;
    final listener = _pushListener;
    if (listener != null) {
      unawaited(_chatPush.removePushListener(listener: listener));
    }
    _pushListener = null;
    _pushListenerRegistered = false;
    _openPayloadController.close();
    _incomingEventController.close();
  }
}

enum PushIncomingEventSource { notification, message }

class _AliasBindOutcome {
  const _AliasBindOutcome({
    required this.success,
    required this.code,
    required this.message,
  });

  final bool success;
  final String code;
  final String message;
}

class PushIncomingEvent {
  const PushIncomingEvent({
    required this.source,
    required this.payload,
    required this.receivedAt,
  });

  final PushIncomingEventSource source;
  final Map<String, dynamic> payload;
  final DateTime receivedAt;
}

class PushOpenPayload {
  const PushOpenPayload({
    required this.routePath,
    this.eventId,
    this.page,
    this.type,
    required this.raw,
  });

  final String routePath;
  final String? eventId;
  final String? page;
  final String? type;
  final Map<String, dynamic> raw;

  factory PushOpenPayload.fromEvent(Map<String, dynamic> event) {
    final merged = _extractMergedPayload(event);
    final rawRoute = _asText(merged['route']) ?? _asText(event['route']);
    final eventId =
        _asText(merged['eventId']) ??
        _asText(merged['event_id']) ??
        _asText(merged['bizId']) ??
        _asText(merged['biz_id']);
    final page =
        _asText(merged['page']) ??
        _asText(merged['targetPage']) ??
        _asText(merged['target']) ??
        _asText(merged['scene']);
    final type = _asText(merged['type']) ?? _asText(merged['bizType']);

    return PushOpenPayload(
      routePath: _resolveRoute(
        rawRoute: rawRoute,
        eventId: eventId,
        page: page,
        type: type,
      ),
      eventId: eventId,
      page: page,
      type: type,
      raw: event,
    );
  }

  static String _resolveRoute({
    required String? rawRoute,
    required String? eventId,
    required String? page,
    required String? type,
  }) {
    final cleanedRoute = rawRoute?.trim();
    if (cleanedRoute != null && cleanedRoute.isNotEmpty) {
      final normalized = cleanedRoute.startsWith('/')
          ? cleanedRoute
          : '/$cleanedRoute';
      return _normalizeLegacyTrtcRoute(
        normalized,
        eventId: eventId,
      );
    }

    final pageKey = _normalizePageKey(page ?? type ?? '');
    switch (pageKey) {
      case 'event_notification':
      case 'event_notify':
      case 'event_create':
      case 'event_close':
      case 'event_transfer':
      case 'event_feedback':
        if (eventId != null && eventId.isNotEmpty) {
          return RoutePaths.eventDetailById(eventId);
        }
        return RoutePaths.eventList;
      case 'weather_warning':
      case 'weather_alert':
      case 'weather_warn':
        return RoutePaths.weatherWarningList;
      case 'event_detail':
      case 'eventinfo':
      case 'detail':
      case 'info':
        if (eventId != null && eventId.isNotEmpty) {
          return RoutePaths.eventDetailById(eventId);
        }
        return RoutePaths.eventList;
      case 'feedback':
        if (eventId != null && eventId.isNotEmpty) {
          return RoutePaths.eventFeedbackById(eventId);
        }
        return RoutePaths.eventList;
      case 'event_timeline':
      case 'event_dynamic':
      case 'timeline':
      case 'dynamic':
        if (eventId != null && eventId.isNotEmpty) {
          return RoutePaths.eventTimelineById(eventId);
        }
        return RoutePaths.eventList;
      case 'event_list':
      case 'list':
        return RoutePaths.eventList;
      case 'trtc_call':
      case 'rtc_call':
      case 'video_call':
      case 'call_invite':
      case 'trtc_invite':
      case 'invite_call':
      case 'incoming_call':
      case 'call_received':
      case 'call_incoming':
        // TRTC call routes are handled by SDK observer (onCallReceived),
        // never navigated directly via GoRouter.
        if (eventId != null && eventId.isNotEmpty) {
          return RoutePaths.eventDetailById(eventId);
        }
        return RoutePaths.home;
      case 'home':
        return RoutePaths.home;
      default:
        if (eventId != null && eventId.isNotEmpty) {
          return RoutePaths.eventDetailById(eventId);
        }
        return RoutePaths.home;
    }
  }

  static String _normalizePageKey(String value) {
    return value.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '');
  }

  static String _normalizeLegacyTrtcRoute(
    String route, {
    required String? eventId,
  }) {
    final normalized = route.trim();
    // Normalize legacy event-notification route
    if (normalized == '/event-notification' ||
        normalized == '/event-notify') {
      if (eventId != null && eventId.isNotEmpty) {
        return RoutePaths.eventDetailById(eventId);
      }
      return RoutePaths.eventList;
    }
    // Normalize legacy weather-warning route
    if (normalized == '/weather-warning' ||
        normalized == '/weather-alert') {
      return RoutePaths.weatherWarningList;
    }
    return normalized;
  }
}

class PushDebugSnapshot {
  const PushDebugSnapshot({
    required this.initialized,
    required this.available,
    required this.userId,
    required this.registrationId,
    required this.boundAlias,
    required this.queuedAlias,
    required this.lastAliasBindCode,
    required this.lastAliasBindMessage,
    required this.lastAliasBindTime,
    required this.lastRegisterPushCode,
    required this.lastRegisterPushMessage,
    required this.lastRegisterPushTime,
    required this.lastRegisterPushSdkAppId,
    required this.lastSetRegistrationIdCode,
    required this.lastSetRegistrationIdMessage,
    required this.lastSetRegistrationIdTime,
    required this.lastSetRegistrationIdValue,
    required this.production,
    required this.channel,
    required this.appKey,
  });

  final bool initialized;
  final bool available;
  final String? userId;
  final String? registrationId;
  final String? boundAlias;
  final String? queuedAlias;
  final String? lastAliasBindCode;
  final String? lastAliasBindMessage;
  final DateTime? lastAliasBindTime;
  final String? lastRegisterPushCode;
  final String? lastRegisterPushMessage;
  final DateTime? lastRegisterPushTime;
  final int? lastRegisterPushSdkAppId;
  final String? lastSetRegistrationIdCode;
  final String? lastSetRegistrationIdMessage;
  final DateTime? lastSetRegistrationIdTime;
  final String? lastSetRegistrationIdValue;
  final bool production;
  final String channel;
  final String appKey;
}

Map<String, dynamic> _extractMergedPayload(Map<String, dynamic> event) {
  final merged = <String, dynamic>{};

  // Start with top-level event fields (push ext top-level keys).
  for (final entry in event.entries) {
    merged[entry.key] = entry.value;
  }

  void mergeMap(Object? value, {bool overwrite = true}) {
    final map = _asMap(value);
    if (map == null || map.isEmpty) {
      return;
    }
    if (overwrite) {
      merged.addAll(map);
      return;
    }
    for (final entry in map.entries) {
      merged.putIfAbsent(entry.key, () => entry.value);
    }
  }

  mergeMap(event['extras']);
  mergeMap(event['extra']);
  mergeMap(event['data']);
  // TIMPush ext field
  final ext = _asText(event['ext']);
  if (ext != null && ext.isNotEmpty) {
    try {
      final decoded = jsonDecode(ext);
      if (decoded is Map) {
        merged.addAll(decoded.map((k, v) => MapEntry(k.toString(), v)));
      }
    } catch (_) {}
  }

  // Tencent push templateParams carry eventId/page inside a nested map
  mergeMap(event['templateParams'], overwrite: false);

  // Some call invites carry business fields in nested json strings
  // like userData/user_data instead of top-level ext keys.
  const nestedKeys = <String>[
    'userData',
    'user_data',
    'payload',
    'data',
    'extra',
    'extras',
    'customData',
    'custom_data',
    'extension',
    'extensionInfo',
  ];
  for (var i = 0; i < 2; i++) {
    for (final key in nestedKeys) {
      mergeMap(merged[key], overwrite: false);
    }
  }

  // Fallback: some SDK callbacks may expose userData beside ext.
  mergeMap(event['userData'], overwrite: false);
  mergeMap(event['user_data'], overwrite: false);

  return merged;
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
  return value.toString().trim().isEmpty ? null : value.toString().trim();
}
