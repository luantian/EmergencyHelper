import 'package:emergency_helper/src/features/auth/data/auth_service.dart';

enum AppOrgScope {
  community,
  street,
  industryDepartment,
  emergencyBureau,
  unknown,
}

class AppFeaturePermission {
  AppFeaturePermission({
    required this.scope,
    required this.scopeName,
    required Set<String> permissions,
    required Set<String> roles,
  }) : permissions = Set<String>.unmodifiable(permissions),
       roles = Set<String>.unmodifiable(roles);

  const AppFeaturePermission.unknown()
    : scope = AppOrgScope.unknown,
      scopeName = 'unknown',
      permissions = const <String>{},
      roles = const <String>{};

  final AppOrgScope scope;
  final String scopeName;
  final Set<String> permissions;
  final Set<String> roles;

  bool get isEmergencyBureau => scope == AppOrgScope.emergencyBureau;
  bool get isCommunity => scope == AppOrgScope.community;

  bool get canMessageReceive {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['notify', 'message'],
          <String>['notify', 'read'],
          <String>['message', 'list'],
          <String>['message', 'read'],
          <String>['notify-message', 'my-page'],
        ]) ||
        _hasDomainAdminPermission('notify') ||
        _hasDomainAdminPermission('message');
  }

  bool get canCommandIssue {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['command', 'issue'],
          <String>['command', 'send'],
          <String>['dispatch', 'issue'],
        ]) ||
        _hasDomainAdminPermission('command');
  }

  bool get canEventReport {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['event', 'report'],
          <String>['event', 'create'],
          <String>['event', 'add'],
          <String>['event', 'submit'],
        ]) ||
        _hasDomainAdminPermission('event');
  }

  bool get canEventQuery {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['event', 'list'],
          <String>['event', 'page'],
          <String>['event', 'query'],
          <String>['event', 'detail'],
          <String>['event', 'get'],
        ]) ||
        _hasDomainAdminPermission('event');
  }

  bool get canEventTransfer {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['event', 'transfer'],
          <String>['event', 'dispatch'],
          <String>['event', 'assign'],
        ]) ||
        _hasDomainAdminPermission('event');
  }

  bool get canEventFeedback {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['event', 'feedback'],
          <String>['event', 'reply'],
        ]) ||
        _hasDomainAdminPermission('event');
  }

  bool get canEventClose {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['event', 'close'],
          <String>['event', 'finish'],
          <String>['event', 'complete'],
        ]) ||
        _hasDomainAdminPermission('event');
  }

  bool get canRiskReport {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['risk', 'report'],
          <String>['risk', 'create'],
          <String>['risk', 'add'],
          <String>['risk', 'submit'],
        ]) ||
        _hasDomainAdminPermission('risk');
  }

  bool get canRiskQuery {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['risk', 'list'],
          <String>['risk', 'page'],
          <String>['risk', 'query'],
          <String>['risk', 'detail'],
          <String>['risk', 'get'],
        ]) ||
        _hasDomainAdminPermission('risk');
  }

  bool get canRiskTransfer {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['risk', 'transfer'],
          <String>['risk', 'dispatch'],
          <String>['risk', 'assign'],
        ]) ||
        _hasDomainAdminPermission('risk');
  }

  bool get canRiskFeedback {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['risk', 'feedback'],
          <String>['risk', 'reply'],
        ]) ||
        _hasDomainAdminPermission('risk');
  }

  bool get canRiskClose {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['risk', 'close'],
          <String>['risk', 'finish'],
          <String>['risk', 'complete'],
        ]) ||
        _hasDomainAdminPermission('risk');
  }

  bool get canContactsQuery {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['dept', 'list'],
          <String>['dept', 'simple-list'],
          <String>['user', 'list'],
          <String>['user', 'simple-list'],
          <String>['contact', 'list'],
          <String>['contact', 'query'],
        ]) ||
        _hasDomainAdminPermission('dept') ||
        _hasDomainAdminPermission('user') ||
        _hasDomainAdminPermission('contact');
  }

  bool get canContactsCall {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['contact', 'call'],
          <String>['phone', 'call'],
          <String>['tel', 'call'],
          <String>['user', 'get'],
        ]) ||
        _hasDomainAdminPermission('contact') ||
        _hasDomainAdminPermission('user');
  }

  bool get canKeyPointQuery {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['emergency', 'place'],
          <String>['place', 'list'],
          <String>['place', 'page'],
          <String>['place', 'query'],
          <String>['point', 'list'],
          <String>['point', 'query'],
        ]) ||
        _hasDomainAdminPermission('place') ||
        _hasDomainAdminPermission('point');
  }

  bool get canRtcConnect {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['rtc', 'call'],
          <String>['trtc', 'call'],
          <String>['video', 'call'],
        ]) ||
        _hasDomainAdminPermission('rtc');
  }

  bool get canDataVisualization {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['event', 'statistics'],
          <String>['data', 'visualization'],
          <String>['dashboard', 'view'],
          <String>['report', 'export'],
        ]) ||
        _hasDomainAdminPermission('dashboard') ||
        _hasDomainAdminPermission('report');
  }

  bool get canReportExport {
    return _hasAnyPermissionMatch(const <List<String>>[
          <String>['report', 'export'],
          <String>['event', 'export'],
          <String>['statistics', 'export'],
        ]) ||
        _hasDomainAdminPermission('report');
  }

  bool _hasDomainAdminPermission(String domainToken) {
    final domain = domainToken.toLowerCase();
    for (final code in permissions) {
      final normalized = _normalizePermissionCode(code);
      if (normalized.isEmpty) {
        continue;
      }
      if (normalized == '*') {
        return true;
      }
      final hasDomain = normalized.contains(domain);
      if (!hasDomain) {
        continue;
      }
      if (normalized.endsWith(':*') ||
          normalized.contains(':all') ||
          normalized.contains(':manage') ||
          normalized.contains(':admin')) {
        return true;
      }
    }
    return false;
  }

  bool _hasAnyPermissionMatch(List<List<String>> requiredFragments) {
    if (requiredFragments.isEmpty || permissions.isEmpty) {
      return false;
    }
    for (final code in permissions) {
      final normalized = _normalizePermissionCode(code);
      if (normalized.isEmpty) {
        continue;
      }
      if (normalized == '*') {
        return true;
      }
      for (final fragments in requiredFragments) {
        final matched = fragments.every(
          (fragment) => normalized.contains(fragment.toLowerCase()),
        );
        if (matched) {
          return true;
        }
      }
    }
    return false;
  }

  static AppFeaturePermission fromSessionInfo(Map<String, dynamic>? info) {
    if (info == null || info.isEmpty) {
      return const AppFeaturePermission.unknown();
    }

    final permissionInfo = _asMap(info['permissionInfo']) ?? info;
    final permissionData = _asMap(permissionInfo['data']) ?? permissionInfo;
    final permissionUser = _asMap(permissionData['user']) ?? permissionData;
    final permissionDept = _asMap(permissionUser['dept']);

    final roleCodes = _extractStringSet(<Object?>[
      permissionData['roles'],
      permissionUser['roles'],
    ]);
    final permissionCodes = _extractStringSet(<Object?>[
      permissionData['permissions'],
      permissionUser['permissions'],
    ]);

    final deptType =
        _asText(permissionUser['deptType']) ??
        _asText(permissionDept?['type']) ??
        _asText(permissionUser['orgType']) ??
        _asText(permissionData['deptType']) ??
        _asText(permissionData['orgType']);
    final deptName = _asText(permissionUser['deptName']);
    final orgName = _asText(permissionUser['orgName']);
    final scopeHints = <String>[
      ...roleCodes,
      ...<String?>[deptType, deptName, orgName].whereType<String>(),
    ];
    final scope = _detectScope(scopeHints);

    return AppFeaturePermission(
      scope: scope,
      scopeName: _scopeName(scope),
      permissions: permissionCodes,
      roles: roleCodes,
    );
  }

  static AppOrgScope _detectScope(List<String> hints) {
    final normalized = hints.map(_normalizeRoleHint).where((v) => v.isNotEmpty);

    var hasEmergency = false;
    var hasStreet = false;
    var hasCommunity = false;
    var hasIndustry = false;
    for (final value in normalized) {
      if (value.contains('emergency') ||
          value.contains('yingji') ||
          value.contains('bureau')) {
        hasEmergency = true;
      }
      if (value.contains('street') || value.contains('jiedao')) {
        hasStreet = true;
      }
      if (value.contains('community') || value.contains('shequ')) {
        hasCommunity = true;
      }
      if (value.contains('industry') ||
          value.contains('hangye') ||
          value.contains('department')) {
        hasIndustry = true;
      }
    }

    if (hasEmergency) {
      return AppOrgScope.emergencyBureau;
    }
    if (hasCommunity) {
      return AppOrgScope.community;
    }
    if (hasStreet) {
      return AppOrgScope.street;
    }
    if (hasIndustry) {
      return AppOrgScope.industryDepartment;
    }
    return AppOrgScope.unknown;
  }

  static String _scopeName(AppOrgScope scope) {
    switch (scope) {
      case AppOrgScope.community:
        return 'community';
      case AppOrgScope.street:
        return 'street';
      case AppOrgScope.industryDepartment:
        return 'industryDepartment';
      case AppOrgScope.emergencyBureau:
        return 'emergencyBureau';
      case AppOrgScope.unknown:
        return 'unknown';
    }
  }

  static Set<String> _extractStringSet(List<Object?> sources) {
    final result = <String>{};
    for (final source in sources) {
      if (source is! List) {
        continue;
      }
      for (final item in source) {
        if (item is Map) {
          final name =
              _asText(item['code']) ??
              _asText(item['name']) ??
              _asText(item['roleCode']) ??
              _asText(item['roleName']) ??
              _asText(item['permission']);
          if (name != null) {
            result.add(_normalizePermissionCode(name));
          }
          continue;
        }
        final text = _asText(item);
        if (text != null) {
          result.add(_normalizePermissionCode(text));
        }
      }
    }
    result.removeWhere((value) => value.trim().isEmpty);
    return result;
  }

  static String _normalizePermissionCode(String raw) {
    return raw.trim().toLowerCase();
  }

  static String _normalizeRoleHint(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('_', '')
        .replaceAll('-', '');
  }

  static String? _asText(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, data) => MapEntry(key.toString(), data));
    }
    return null;
  }
}

class AppFeaturePermissionResolver {
  AppFeaturePermissionResolver._();

  static final AppFeaturePermissionResolver instance =
      AppFeaturePermissionResolver._();
  static const Duration _cacheTtl = Duration(seconds: 45);

  AppFeaturePermission? _cached;
  int? _cachedAtMs;
  Future<AppFeaturePermission>? _ongoingTask;

  Future<AppFeaturePermission> resolve(
    AuthService authService, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _cached;
      final cachedAtMs = _cachedAtMs;
      if (cached != null &&
          cachedAtMs != null &&
          DateTime.now().millisecondsSinceEpoch - cachedAtMs <
              _cacheTtl.inMilliseconds) {
        return cached;
      }
      final ongoingTask = _ongoingTask;
      if (ongoingTask != null) {
        return ongoingTask;
      }
    }

    final task = _load(authService, forceRefresh: forceRefresh);
    _ongoingTask = task;
    try {
      final permission = await task;
      _cached = permission;
      _cachedAtMs = DateTime.now().millisecondsSinceEpoch;
      return permission;
    } finally {
      if (identical(_ongoingTask, task)) {
        _ongoingTask = null;
      }
    }
  }

  void clearCache() {
    _cached = null;
    _cachedAtMs = null;
    _ongoingTask = null;
  }

  Future<AppFeaturePermission> _load(
    AuthService authService, {
    required bool forceRefresh,
  }) async {
    Map<String, dynamic>? info;
    if (forceRefresh) {
      info = await authService.fetchPermissionInfoAndCache();
    } else {
      info = await authService.getCachedPermissionInfo();
      if (info == null || info.isEmpty) {
        info = await authService.fetchPermissionInfoAndCache();
      } else {
        final latest = await authService.fetchPermissionInfoAndCache();
        if (latest != null && latest.isNotEmpty) {
          info = latest;
        }
      }
    }

    return AppFeaturePermission.fromSessionInfo(info);
  }
}
