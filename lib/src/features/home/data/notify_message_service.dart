import 'dart:convert';

import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/network/api_client.dart';

class NotifyMessageService {
  const NotifyMessageService();

  Future<NotifyMessagePageResult> loadMyPage(
    ApiClient apiClient, {
    required int pageNo,
    int pageSize = 20,
    bool? readStatus,
  }) async {
    final response = await apiClient.getJson(
      AppConstants.notifyMessageMyPagePath,
      queryParameters: <String, dynamic>{
        'pageNo': pageNo,
        'pageSize': pageSize,
        if (readStatus != null) 'readStatus': readStatus.toString(),
      },
    );
    final data = _expectSuccessAndData(
      response,
      fallbackMessage: '\u6D88\u606F\u5217\u8868\u52A0\u8F7D\u5931\u8D25',
    );
    final map = _asMap(data);
    final total = _asInt(map?['total']) ?? 0;
    final list = _asMapList(map?['list']);
    final items = list.map(NotifyMessageItem.fromMap).toList(growable: false);
    return NotifyMessagePageResult(total: total, list: items);
  }

  Future<void> markRead(ApiClient apiClient, List<int> ids) async {
    final normalizedIds = ids.where((id) => id > 0).toList(growable: false);
    if (normalizedIds.isEmpty) {
      return;
    }

    // New OpenAPI example uses comma-separated ids; fallback to list style
    // for servers that parse repeated query params.
    var needFallback = false;
    try {
      final response = await apiClient.putJson(
        AppConstants.notifyMessageUpdateReadPath,
        queryParameters: <String, dynamic>{'ids': normalizedIds.join(',')},
      );
      _expectSuccessAndData(
        response,
        fallbackMessage: '\u6807\u8BB0\u5DF2\u8BFB\u5931\u8D25',
      );
    } on AppException {
      needFallback = true;
    }

    if (!needFallback) {
      return;
    }

    final response = await apiClient.putJson(
      AppConstants.notifyMessageUpdateReadPath,
      queryParameters: <String, dynamic>{'ids': normalizedIds},
    );
    _expectSuccessAndData(
      response,
      fallbackMessage: '\u6807\u8BB0\u5DF2\u8BFB\u5931\u8D25',
    );
  }

  Future<void> markAllRead(ApiClient apiClient) async {
    final response = await apiClient.putJson(
      AppConstants.notifyMessageUpdateAllReadPath,
    );
    _expectSuccessAndData(
      response,
      fallbackMessage: '\u5168\u90E8\u5DF2\u8BFB\u5931\u8D25',
    );
  }

  Future<NotifyMessageItem> getDetail(ApiClient apiClient, int id) async {
    if (id <= 0) {
      throw AppException('\u6D88\u606F\u53C2\u6570\u9519\u8BEF');
    }
    final response = await apiClient.getJson(
      AppConstants.notifyMessageGetPath,
      queryParameters: <String, dynamic>{'id': id},
    );
    final data = _expectSuccessAndData(
      response,
      fallbackMessage: '\u6D88\u606F\u8BE6\u60C5\u52A0\u8F7D\u5931\u8D25',
    );
    final map = _asMap(data);
    if (map == null || map.isEmpty) {
      throw AppException('\u6D88\u606F\u8BE6\u60C5\u4E0D\u5B58\u5728');
    }
    return NotifyMessageItem.fromMap(map);
  }

  Object? _expectSuccessAndData(
    Map<String, dynamic> response, {
    required String fallbackMessage,
  }) {
    final code = _asInt(response['code']) ?? 0;
    if (code != 0) {
      throw AppException(_asText(response['msg']) ?? fallbackMessage);
    }
    return response['data'];
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

  List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    return value
        .whereType<Map>()
        .map((item) => item.map((key, data) => MapEntry(key.toString(), data)))
        .toList(growable: false);
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

  String? _asText(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }
}

class NotifyMessagePageResult {
  const NotifyMessagePageResult({required this.total, required this.list});

  final int total;
  final List<NotifyMessageItem> list;
}

class NotifyMessageItem {
  const NotifyMessageItem({
    required this.id,
    required this.title,
    required this.content,
    required this.readStatus,
    required this.createTime,
    required this.messageTypeKey,
    required this.messageTypeLabel,
    this.templateCode,
    this.templateType,
    this.senderName,
    this.eventId,
    this.riskId,
  });

  factory NotifyMessageItem.fromMap(Map<String, dynamic> map) {
    final id = _asInt(map['id']) ?? 0;
    final sender = _asText(map['templateNickname']);
    final content =
        _asText(map['templateContent']) ?? _asText(map['content']) ?? '--';
    final templateCode = _asText(map['templateCode']);
    final readStatus = _asBool(map['readStatus']) ?? false;
    final createTime = _asDateTime(
      map['createTime'] ??
          map['sendTime'] ??
          map['send_time'] ??
          map['create_at'] ??
          map['createDate'] ??
          map['create_date'],
    );
    final fallbackTime =
        createTime ?? _parseTimeFromTemplateParams(map['templateParams']);
    final templateType = _asInt(map['templateType']);
    Map<String, dynamic>? templateParams;
    final tpValue = map['templateParams'];
    if (tpValue is Map<String, dynamic>) {
      templateParams = tpValue;
    } else if (tpValue is Map) {
      templateParams = tpValue.map(
        (key, data) => MapEntry(key.toString(), data),
      );
    } else if (tpValue is String) {
      final raw = tpValue.trim();
      if (raw.startsWith('{') && raw.endsWith('}')) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            templateParams = decoded;
          } else if (decoded is Map) {
            templateParams = decoded.map(
              (key, data) => MapEntry(key.toString(), data),
            );
          }
        } catch (_) {}
      }
    }
    final eventId = _asInt(templateParams?['eventId']);
    final riskId = _asInt(templateParams?['riskId']) ??
        _asInt(templateParams?['risk_id']);
    final typeInfo = _resolveMessageType(
      templateType: templateType,
      templateCode: templateCode,
      title: sender ?? _asText(map['title']) ?? templateCode ?? '',
      content: content,
    );
    final title = _resolveTitle(
      typeKey: typeInfo.key,
      typeLabel: typeInfo.label,
      templateParams: templateParams,
      fallback: sender ?? _asText(map['title']) ?? templateCode,
    );

    return NotifyMessageItem(
      id: id,
      title: title,
      content: content,
      readStatus: readStatus,
      createTime: fallbackTime,
      messageTypeKey: typeInfo.key,
      messageTypeLabel: typeInfo.label,
      templateCode: templateCode,
      templateType: templateType,
      senderName: sender,
      eventId: eventId,
      riskId: riskId,
    );
  }

  final int id;
  final String title;
  final String content;
  final bool readStatus;
  final DateTime? createTime;
  final String messageTypeKey;
  final String messageTypeLabel;
  final String? templateCode;
  final int? templateType;
  final String? senderName;
  final int? eventId;
  final int? riskId;

  static String _resolveTitle({
    required String typeKey,
    required String typeLabel,
    required Map<String, dynamic>? templateParams,
    String? fallback,
  }) {
    String? fromParams(List<String> keys) {
      for (final key in keys) {
        final value = templateParams?[key];
        final text = _asText(value);
        if (text != null && text.isNotEmpty) {
          return text;
        }
      }
      return null;
    }

    String? name;
    switch (typeKey) {
      case 'event_report':
      case 'event_dynamic':
        name = fromParams(const <String>['eventName', 'event_name', 'name']);
        break;
      case 'risk_report':
      case 'risk_dynamic':
        name = fromParams(const <String>['riskName', 'risk_name', 'name']);
        break;
      case 'weather_warning':
        name = fromParams(const <String>['title', 'weatherTitle', 'warningTitle']);
        break;
    }
    return name ?? fallback ?? typeLabel;
  }

  NotifyMessageItem copyWith({bool? readStatus}) {
    return NotifyMessageItem(
      id: id,
      title: title,
      content: content,
      readStatus: readStatus ?? this.readStatus,
      createTime: createTime,
      messageTypeKey: messageTypeKey,
      messageTypeLabel: messageTypeLabel,
      templateCode: templateCode,
      templateType: templateType,
      senderName: senderName,
      eventId: eventId,
      riskId: riskId,
    );
  }

  static _NotifyMessageTypeInfo _resolveMessageType({
    required int? templateType,
    required String? templateCode,
    required String title,
    required String content,
  }) {
    final text = '${templateCode ?? ''}|$title|$content'
        .toLowerCase()
        .replaceAll(' ', '');

    final hasWeather = _containsAny(text, const <String>[
      'weather',
      'meteorology',
      '\u6C14\u8C61',
      '\u9884\u8B66',
      'warning',
      'alarm',
      'typhoon',
      'rainstorm',
    ]);
    if (hasWeather) {
      return const _NotifyMessageTypeInfo(
        'weather_warning',
        '\u6C14\u8C61\u9884\u8B66',
      );
    }

    final hasRisk = _containsAny(text, const <String>[
      'risk',
      '\u98CE\u9669',
      '\u884D\u751F',
      '\u6B21\u751F',
    ]);
    final hasEvent = _containsAny(text, const <String>[
      'event',
      'incident',
      '\u4E8B\u4EF6',
    ]);
    final hasDynamic = _containsAny(text, const <String>[
      'dynamic',
      'timeline',
      '\u52A8\u6001',
      '\u53CD\u9988',
      '\u8FDB\u5C55',
      '\u5904\u7F6E',
      '\u529E\u7ED3',
      '\u8BC4\u8BBA',
    ]);
    final hasReport = _containsAny(text, const <String>[
      'report',
      'create',
      '\u4E0A\u62A5',
      '\u65B0\u589E',
      '\u767B\u8BB0',
    ]);
    final hasTransfer = _containsAny(text, const <String>[
      'transfer',
      'assign',
      'dispatch',
      '\u8F6C\u6D3E',
      '\u5206\u6D3E',
      '\u6307\u6D3E',
      '\u7B7E\u6536',
      '\u5F85\u5904\u7406',
    ]);

    if (hasRisk && hasDynamic) {
      return const _NotifyMessageTypeInfo(
        'risk_dynamic',
        '\u98CE\u9669\u52A8\u6001',
      );
    }
    if (hasEvent && hasDynamic) {
      return const _NotifyMessageTypeInfo(
        'event_dynamic',
        '\u4E8B\u4EF6\u52A8\u6001',
      );
    }
    if (hasRisk && (hasReport || hasTransfer)) {
      return const _NotifyMessageTypeInfo(
        'risk_report',
        '\u98CE\u9669\u4E0A\u62A5',
      );
    }
    if (hasEvent && (hasReport || hasTransfer)) {
      return const _NotifyMessageTypeInfo(
        'event_report',
        '\u4E8B\u4EF6\u4E0A\u62A5',
      );
    }

    if (hasRisk) {
      return const _NotifyMessageTypeInfo(
        'risk_report',
        '\u98CE\u9669\u4E0A\u62A5',
      );
    }
    if (hasEvent) {
      return const _NotifyMessageTypeInfo(
        'event_report',
        '\u4E8B\u4EF6\u4E0A\u62A5',
      );
    }

    if (templateType != null && templateType == 1) {
      return const _NotifyMessageTypeInfo('other', '\u5176\u4ED6\u901A\u77E5');
    }

    return const _NotifyMessageTypeInfo('other', '\u5176\u4ED6\u901A\u77E5');
  }

  static bool _containsAny(String source, List<String> keywords) {
    for (final keyword in keywords) {
      if (source.contains(keyword.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  static int? _asInt(Object? value) {
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

  static bool? _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final text = value.trim().toLowerCase();
      if (text == 'true' || text == '1') {
        return true;
      }
      if (text == 'false' || text == '0') {
        return false;
      }
    }
    return null;
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

  static DateTime? _asDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is num) {
      return _fromEpoch(value.toDouble());
    }

    final text = _asText(value);
    if (text == null) {
      return null;
    }

    final numeric = num.tryParse(text);
    if (numeric != null) {
      final fromEpoch = _fromEpoch(numeric.toDouble());
      if (fromEpoch != null) {
        return fromEpoch;
      }
    }

    final parsed = DateTime.tryParse(text);
    if (parsed != null) {
      return parsed;
    }

    final normalized = text.contains(' ') ? text.replaceFirst(' ', 'T') : text;
    final normalizedParsed = DateTime.tryParse(normalized);
    if (normalizedParsed != null) {
      return normalizedParsed;
    }

    final simpleDateTime = RegExp(
      r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?$',
    );
    final match = simpleDateTime.firstMatch(text);
    if (match != null) {
      final year = int.tryParse(match.group(1) ?? '');
      final month = int.tryParse(match.group(2) ?? '');
      final day = int.tryParse(match.group(3) ?? '');
      final hour = int.tryParse(match.group(4) ?? '');
      final minute = int.tryParse(match.group(5) ?? '');
      final second = int.tryParse(match.group(6) ?? '0') ?? 0;
      if (year != null &&
          month != null &&
          day != null &&
          hour != null &&
          minute != null) {
        return DateTime(year, month, day, hour, minute, second);
      }
    }
    return null;
  }

  static DateTime? _parseTimeFromTemplateParams(Object? value) {
    Map<String, dynamic>? map;
    if (value is Map<String, dynamic>) {
      map = value;
    } else if (value is Map) {
      map = value.map((key, data) => MapEntry(key.toString(), data));
    } else if (value is String) {
      final raw = value.trim();
      if (raw.startsWith('{') && raw.endsWith('}')) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            map = decoded;
          } else if (decoded is Map) {
            map = decoded.map((key, data) => MapEntry(key.toString(), data));
          }
        } catch (_) {}
      }
    }
    if (map == null || map.isEmpty) {
      return null;
    }
    for (final key in <String>[
      'createTime',
      'time',
      'timestamp',
      'sendTime',
      'send_time',
      'dateTime',
      'occurTime',
    ]) {
      final parsed = _asDateTime(map[key]);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  static DateTime? _fromEpoch(double raw) {
    if (!raw.isFinite) {
      return null;
    }
    var millis = raw;
    if (millis.abs() < 100000000000) {
      millis *= 1000;
    }
    try {
      return DateTime.fromMillisecondsSinceEpoch(millis.round());
    } catch (_) {
      return null;
    }
  }
}

class _NotifyMessageTypeInfo {
  const _NotifyMessageTypeInfo(this.key, this.label);

  final String key;
  final String label;
}
