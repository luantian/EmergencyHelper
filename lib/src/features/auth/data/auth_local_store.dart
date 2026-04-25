import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthLocalStore {
  static const String _tokenKey = 'auth_access_token';
  static const String _refreshTokenKey = 'auth_refresh_token';
  static const String _expiresTimeKey = 'auth_access_expires_time_ms';
  static const String _permissionInfoKey = 'auth_permission_info_json';
  static const String _rememberAccountKey = 'auth_remember_account';
  static const String _legacyRememberPasswordKey = 'auth_remember_password';
  static const String _rememberedUsernameKey = 'auth_remembered_username';
  static const String _rememberedPasswordKey = 'auth_remembered_password';
  static final Map<String, String> _memoryStore = <String, String>{};
  static final Map<String, int> _memoryIntStore = <String, int>{};
  static final Map<String, bool> _memoryBoolStore = <String, bool>{};

  Future<void> saveSession({
    required String accessToken,
    required Map<String, dynamic> permissionInfo,
    String? refreshToken,
    int? expiresTimeMs,
  }) async {
    final prefs = await _getPrefs();
    final permissionJson = jsonEncode(permissionInfo);
    if (prefs != null) {
      await prefs.setString(_tokenKey, accessToken);
      if (refreshToken != null) {
        await prefs.setString(_refreshTokenKey, refreshToken);
      }
      if (expiresTimeMs != null) {
        await prefs.setInt(_expiresTimeKey, expiresTimeMs);
      }
      await prefs.setString(_permissionInfoKey, permissionJson);
      return;
    }
    _memoryStore[_tokenKey] = accessToken;
    if (refreshToken != null) {
      _memoryStore[_refreshTokenKey] = refreshToken;
    }
    if (expiresTimeMs != null) {
      _memoryIntStore[_expiresTimeKey] = expiresTimeMs;
    }
    _memoryStore[_permissionInfoKey] = permissionJson;
  }

  Future<String?> getAccessToken() async {
    final prefs = await _getPrefs();
    if (prefs != null) {
      return prefs.getString(_tokenKey);
    }
    return _memoryStore[_tokenKey];
  }

  Future<Map<String, dynamic>?> getPermissionInfo() async {
    final prefs = await _getPrefs();
    final value =
        prefs?.getString(_permissionInfoKey) ??
        _memoryStore[_permissionInfoKey];
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, data) => MapEntry(key.toString(), data));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getRefreshToken() async {
    final prefs = await _getPrefs();
    if (prefs != null) {
      return prefs.getString(_refreshTokenKey);
    }
    return _memoryStore[_refreshTokenKey];
  }

  Future<int?> getAccessTokenExpiresTimeMs() async {
    final prefs = await _getPrefs();
    if (prefs != null) {
      return prefs.getInt(_expiresTimeKey);
    }
    return _memoryIntStore[_expiresTimeKey];
  }

  Future<void> clear() async {
    final prefs = await _getPrefs();
    if (prefs != null) {
      await prefs.remove(_tokenKey);
      await prefs.remove(_refreshTokenKey);
      await prefs.remove(_expiresTimeKey);
      await prefs.remove(_permissionInfoKey);
    }
    _memoryStore.remove(_tokenKey);
    _memoryStore.remove(_refreshTokenKey);
    _memoryIntStore.remove(_expiresTimeKey);
    _memoryStore.remove(_permissionInfoKey);
  }

  Future<void> saveRememberedCredential({
    required bool rememberAccount,
    required String username,
  }) async {
    final normalizedUsername = username.trim();
    final prefs = await _getPrefs();
    if (prefs != null) {
      await prefs.setBool(_rememberAccountKey, rememberAccount);
      await prefs.remove(_legacyRememberPasswordKey);
      if (rememberAccount && normalizedUsername.isNotEmpty) {
        await prefs.setString(_rememberedUsernameKey, normalizedUsername);
      } else {
        await prefs.remove(_rememberedUsernameKey);
      }
      // Password is no longer persisted locally for security.
      await prefs.remove(_rememberedPasswordKey);
      return;
    }

    _memoryBoolStore[_rememberAccountKey] = rememberAccount;
    _memoryBoolStore.remove(_legacyRememberPasswordKey);
    if (rememberAccount && normalizedUsername.isNotEmpty) {
      _memoryStore[_rememberedUsernameKey] = normalizedUsername;
    } else {
      _memoryStore.remove(_rememberedUsernameKey);
    }
    _memoryStore.remove(_rememberedPasswordKey);
  }

  Future<RememberedCredential> getRememberedCredential() async {
    final prefs = await _getPrefs();
    if (prefs != null) {
      final rememberAccount =
          prefs.getBool(_rememberAccountKey) ??
          (prefs.getBool(_legacyRememberPasswordKey) ?? false);
      final username = prefs.getString(_rememberedUsernameKey) ?? '';
      await prefs.remove(_rememberedPasswordKey);
      return RememberedCredential(
        rememberAccount: rememberAccount,
        username: rememberAccount ? username : '',
      );
    }
    final rememberAccount =
        _memoryBoolStore[_rememberAccountKey] ??
        (_memoryBoolStore[_legacyRememberPasswordKey] ?? false);
    final username = _memoryStore[_rememberedUsernameKey] ?? '';
    return RememberedCredential(
      rememberAccount: rememberAccount,
      username: rememberAccount ? username : '',
    );
  }

  Future<SharedPreferences?> _getPrefs() async {
    try {
      return await SharedPreferences.getInstance();
    } on MissingPluginException {
      return null;
    }
  }
}

class RememberedCredential {
  const RememberedCredential({
    required this.rememberAccount,
    required this.username,
  });

  final bool rememberAccount;
  final String username;

  @Deprecated('Password is no longer persisted.')
  String get password => '';

  @Deprecated('Use rememberAccount instead.')
  bool get rememberPassword => rememberAccount;
}
