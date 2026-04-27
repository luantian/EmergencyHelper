import 'package:dio/dio.dart';
import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/logging/app_logger.dart';
import 'package:emergency_helper/src/core/network/api_client.dart';
import 'package:emergency_helper/src/features/auth/data/auth_local_store.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  AuthService({
    required ApiClient apiClient,
    required AuthLocalStore localStore,
    required AppLogger logger,
  }) : _apiClient = apiClient,
       _localStore = localStore,
       _logger = logger;

  final ApiClient _apiClient;
  final AuthLocalStore _localStore;
  final AppLogger _logger;
  static const Duration _tokenExpirySkew = Duration(seconds: 30);
  Future<bool>? _ongoingRefreshTask;

  Future<AuthLoginResult> login({
    required String tenantId,
    required String username,
    required String password,
  }) async {
    final loginResponse = await _apiClient.postJson(
      AppConstants.authLoginPath,
      data: <String, dynamic>{
        'tenantId': tenantId,
        'username': username,
        'password': password,
      },
      withAuthorization: false,
    );

    return _buildAndSaveSessionFromTokenResponse(loginResponse);
  }

  Future<bool> ensureValidAccessToken({bool validateWithServer = false}) async {
    final accessToken = await _localStore.getAccessToken();
    if (accessToken == null || accessToken.trim().isEmpty) {
      return false;
    }

    final expiresTimeMs = await _localStore.getAccessTokenExpiresTimeMs();
    if (_isTokenExpired(expiresTimeMs)) {
      final refreshToken = await _localStore.getRefreshToken();
      if (refreshToken == null || refreshToken.trim().isEmpty) {
        await _localStore.clear();
        return false;
      }

      final ongoingTask = _ongoingRefreshTask;
      if (ongoingTask != null) {
        final refreshResult = await ongoingTask;
        if (!refreshResult) {
          return false;
        }
      } else {
        final refreshTask = _refreshAccessToken(refreshToken.trim());
        _ongoingRefreshTask = refreshTask;
        try {
          final refreshResult = await refreshTask;
          if (!refreshResult) {
            return false;
          }
        } finally {
          if (identical(_ongoingRefreshTask, refreshTask)) {
            _ongoingRefreshTask = null;
          }
        }
      }
    }

    if (!validateWithServer) {
      return true;
    }
    final latestToken = await _localStore.getAccessToken();
    if (latestToken == null || latestToken.trim().isEmpty) {
      return false;
    }

    final acceptedByServer = await _isAccessTokenAcceptedByServer(
      latestToken.trim(),
    );
    if (!acceptedByServer) {
      await _localStore.clear();
      return false;
    }
    return true;
  }

  Future<void> logout({bool clearLocalSession = true}) async {
    final token = await _localStore.getAccessToken();
    if (token != null && token.trim().isNotEmpty) {
      try {
        await _apiClient.postJson(
          AppConstants.authLogoutPath,
          headers: <String, String>{'authorization': token},
        );
      } catch (error, stackTrace) {
        _logger.error(
          'logout request failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    if (clearLocalSession) {
      await _localStore.clear();
      _apiClient.resetAuthExpiredState();
    }
  }

  Future<Map<String, dynamic>?> getCachedPermissionInfo() {
    return _localStore.getPermissionInfo();
  }

  Future<String?> getCachedToken() {
    return _localStore.getAccessToken();
  }

  Future<Map<String, dynamic>?> fetchPermissionInfoAndCache() async {
    final token = await _localStore.getAccessToken();
    if (token == null || token.trim().isEmpty) {
      return null;
    }

    try {
      final permissionResponse = await _apiClient.getJson(
        AppConstants.authPermissionInfoPath,
        headers: <String, String>{'authorization': token},
      );
      final current =
          await _localStore.getPermissionInfo() ?? <String, dynamic>{};
      final merged = <String, dynamic>{
        ...permissionResponse,
        'permissionInfo': permissionResponse,
        if (current['profileInfo'] != null) 'profileInfo': current['profileInfo'],
      };
      await _localStore.saveSession(accessToken: token, permissionInfo: merged);
      return merged;
    } catch (error, stackTrace) {
      _logger.error(
        'fetch permission info failed',
        error: error,
        stackTrace: stackTrace,
      );
      return _localStore.getPermissionInfo();
    }
  }

  Future<Map<String, dynamic>?> fetchUserProfileAndCache() async {
    final token = await _localStore.getAccessToken();
    if (token == null || token.trim().isEmpty) {
      return null;
    }

    try {
      final profileResponse = await _apiClient.getJson(
        AppConstants.authUserProfilePath,
        headers: <String, String>{'authorization': token},
      );
      final current =
          await _localStore.getPermissionInfo() ?? <String, dynamic>{};
      final merged = <String, dynamic>{
        ...current,
        'permissionInfo': _asMap(current['permissionInfo']) ?? current,
        'profileInfo': profileResponse,
      };
      await _localStore.saveSession(accessToken: token, permissionInfo: merged);
      return profileResponse;
    } catch (error, stackTrace) {
      _logger.error(
        'fetch user profile failed',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> updateProfilePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final oldText = oldPassword.trim();
    final newText = newPassword.trim();
    if (oldText.isEmpty || newText.isEmpty) {
      throw AppException('\u8BF7\u8F93\u5165\u5B8C\u6574\u7684\u5BC6\u7801\u4FE1\u606F');
    }

    final response = await _apiClient.putJson(
      AppConstants.authUserProfileUpdatePasswordPath,
      data: <String, dynamic>{
        'oldPassword': oldText,
        'newPassword': newText,
      },
    );
    final code = _asInt(response['code']);
    if (code == null || code == 0) {
      return;
    }
    final message =
        (response['msg'] ?? response['message'])?.toString().trim() ?? '';
    if (message.isNotEmpty) {
      throw AppException(message);
    }
    throw AppException('\u4FEE\u6539\u5BC6\u7801\u5931\u8D25\uFF0C\u8BF7\u7A0D\u540E\u91CD\u8BD5');
  }

  Future<AuthLoginResult> _refreshByRefreshToken(String refreshToken) async {
    final refreshResponse = await _apiClient.postJson(
      AppConstants.authRefreshTokenPath,
      queryParameters: <String, dynamic>{'refreshToken': refreshToken},
      withAuthorization: false,
    );
    return _buildAndSaveSessionFromTokenResponse(
      refreshResponse,
      fallbackRefreshToken: refreshToken,
    );
  }

  Future<bool> _refreshAccessToken(String refreshToken) async {
    try {
      await _refreshByRefreshToken(refreshToken);
      return true;
    } on AppException catch (error, stackTrace) {
      _logger.error(
        'refresh token failed',
        error: error,
        stackTrace: stackTrace,
      );
      await _localStore.clear();
      return false;
    } catch (error, stackTrace) {
      _logger.error(
        'refresh token unexpected error',
        error: error,
        stackTrace: stackTrace,
      );
      await _localStore.clear();
      return false;
    }
  }

  Future<bool> _isAccessTokenAcceptedByServer(String accessToken) async {
    try {
      final response = await _apiClient.getJson(
        AppConstants.authPermissionInfoPath,
        headers: <String, String>{'authorization': accessToken},
        withAuthorization: false,
      );
      if (_isUnauthorizedResponse(response)) {
        return false;
      }
      return true;
    } on AppException catch (error, stackTrace) {
      if (_isUnauthorizedAppException(error)) {
        return false;
      }
      _logger.error(
        'validate token by server failed',
        error: error,
        stackTrace: stackTrace,
      );
      // Keep local session when validation request is unavailable.
      return true;
    } catch (error, stackTrace) {
      _logger.error(
        'validate token by server unexpected error',
        error: error,
        stackTrace: stackTrace,
      );
      return true;
    }
  }

  bool _isUnauthorizedResponse(Map<String, dynamic> response) {
    final code = _asInt(response['code']);
    if (code == 401) {
      return true;
    }
    final message = (response['msg'] ?? response['message'])?.toString() ?? '';
    if (code != null && code != 0 && message.contains('\u672A\u767B\u5F55')) {
      return true;
    }
    return false;
  }

  bool _isUnauthorizedAppException(AppException error) {
    final cause = error.cause;
    if (cause is DioException) {
      final statusCode = cause.response?.statusCode;
      if (statusCode == 401) {
        return true;
      }
      final responseData = cause.response?.data;
      if (responseData is Map<String, dynamic>) {
        return _isUnauthorizedResponse(responseData);
      }
      if (responseData is Map) {
        return _isUnauthorizedResponse(
          responseData.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    }
    if (error.message.contains('\u672A\u767B\u5F55') ||
        error.message.toLowerCase().contains('unauthorized')) {
      return true;
    }
    return false;
  }

  Future<AuthLoginResult> _buildAndSaveSessionFromTokenResponse(
    Map<String, dynamic> tokenResponse, {
    String? fallbackRefreshToken,
  }) async {
    final tokenPayload = _extractTokenPayload(
      tokenResponse,
      fallbackRefreshToken: fallbackRefreshToken,
    );
    if (tokenPayload == null || tokenPayload.accessToken.trim().isEmpty) {
      throw AppException('\u767B\u5F55\u5931\u8D25\uFF1A\u670D\u52A1\u7AEF\u672A\u8FD4\u56DE accessToken');
    }

    final permissionResponse = await _apiClient.getJson(
      AppConstants.authPermissionInfoPath,
      headers: <String, String>{'authorization': tokenPayload.accessToken},
    );

    Map<String, dynamic>? profileResponse;
    try {
      profileResponse = await _apiClient.getJson(
        AppConstants.authUserProfilePath,
        headers: <String, String>{'authorization': tokenPayload.accessToken},
      );
    } catch (error, stackTrace) {
      _logger.error(
        'get user profile failed',
        error: error,
        stackTrace: stackTrace,
      );
    }

    final sessionInfo = <String, dynamic>{
      ...permissionResponse,
      'permissionInfo': permissionResponse,
      ...?profileResponse == null
          ? null
          : <String, dynamic>{'profileInfo': profileResponse},
    };

    await _localStore.saveSession(
      accessToken: tokenPayload.accessToken,
      refreshToken: tokenPayload.refreshToken,
      expiresTimeMs: tokenPayload.expiresTimeMs,
      permissionInfo: sessionInfo,
    );
    _apiClient.resetAuthExpiredState();

    _debugLogToken(
      'login_or_refresh_success',
      tokenPayload.accessToken,
      expiresTimeMs: tokenPayload.expiresTimeMs,
    );

    return AuthLoginResult(
      accessToken: tokenPayload.accessToken,
      refreshToken: tokenPayload.refreshToken,
      expiresTimeMs: tokenPayload.expiresTimeMs,
      permissionInfo: sessionInfo,
    );
  }

  _AuthTokenPayload? _extractTokenPayload(
    Map<String, dynamic> response, {
    String? fallbackRefreshToken,
  }) {
    final accessToken = _extractString(
      response,
      directKey: 'accessToken',
      nestedKey: 'accessToken',
    );
    if (accessToken == null || accessToken.trim().isEmpty) {
      return null;
    }
    final refreshToken =
        _extractString(
          response,
          directKey: 'refreshToken',
          nestedKey: 'refreshToken',
        ) ??
        fallbackRefreshToken;
    final expiresTimeMs =
        _extractEpochMs(
          response,
          directKey: 'expiresTime',
          nestedKey: 'expiresTime',
        ) ??
        _extractEpochMs(
          response,
          directKey: 'expiresIn',
          nestedKey: 'expiresIn',
        );
    return _AuthTokenPayload(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresTimeMs: expiresTimeMs,
    );
  }

  bool _isTokenExpired(int? expiresTimeMs) {
    if (expiresTimeMs == null || expiresTimeMs <= 0) {
      // Legacy sessions may only have accessToken without expiry metadata.
      // Treat them as expired so startup must refresh or go back to login.
      return true;
    }
    final nowWithSkew =
        DateTime.now().millisecondsSinceEpoch + _tokenExpirySkew.inMilliseconds;
    return nowWithSkew >= expiresTimeMs;
  }

  String? _extractString(
    Map<String, dynamic> response, {
    required String directKey,
    required String nestedKey,
  }) {
    final direct = response[directKey];
    if (direct is String && direct.trim().isNotEmpty) {
      return direct.trim();
    }
    final data = _asMap(response['data']);
    if (data == null) {
      return null;
    }
    final nested = data[nestedKey];
    if (nested is String && nested.trim().isNotEmpty) {
      return nested.trim();
    }
    return null;
  }

  int? _extractEpochMs(
    Map<String, dynamic> response, {
    required String directKey,
    required String nestedKey,
  }) {
    final direct = _asInt(response[directKey]);
    if (direct != null) {
      return _normalizeEpochMs(direct);
    }
    final data = _asMap(response['data']);
    if (data == null) {
      return null;
    }
    final nested = _asInt(data[nestedKey]);
    if (nested == null) {
      return null;
    }
    return _normalizeEpochMs(nested);
  }

  int _normalizeEpochMs(int value) {
    if (value <= 0) {
      return value;
    }
    // Small values are treated as duration-seconds (e.g. expiresIn = 7200).
    if (value < 315360000) {
      return DateTime.now().millisecondsSinceEpoch + value * 1000;
    }
    // Unix epoch-seconds to milliseconds.
    if (value < 100000000000) {
      return value * 1000;
    }
    return value;
  }

  int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, data) => MapEntry(key.toString(), data));
    }
    return null;
  }

  void _debugLogToken(
    String scene,
    String token, {
    int? expiresTimeMs,
  }) {
    if (!kDebugMode) {
      return;
    }
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final expireText = expiresTimeMs == null || expiresTimeMs <= 0
        ? 'unknown'
        : DateTime.fromMillisecondsSinceEpoch(expiresTimeMs).toIso8601String();
    _logger.info(
      '[DEBUG_TOKEN][$scene] accessToken=$trimmed, expiresTime=$expireText',
    );
  }
}

class AuthLoginResult {
  AuthLoginResult({
    required this.accessToken,
    required this.permissionInfo,
    this.refreshToken,
    this.expiresTimeMs,
  });

  final String accessToken;
  final String? refreshToken;
  final int? expiresTimeMs;
  final Map<String, dynamic> permissionInfo;
}

class _AuthTokenPayload {
  const _AuthTokenPayload({
    required this.accessToken,
    this.refreshToken,
    this.expiresTimeMs,
  });

  final String accessToken;
  final String? refreshToken;
  final int? expiresTimeMs;
}
