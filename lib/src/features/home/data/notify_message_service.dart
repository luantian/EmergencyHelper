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
    this.templateCode,
    this.templateType,
    this.senderName,
  });

  factory NotifyMessageItem.fromMap(Map<String, dynamic> map) {
    final id = _asInt(map['id']) ?? 0;
    final sender = _asText(map['templateNickname']);
    final content =
        _asText(map['templateContent']) ?? _asText(map['content']) ?? '--';
    final templateCode = _asText(map['templateCode']);
    final title =
        sender ??
        _asText(map['title']) ??
        templateCode ??
        '\u7CFB\u7EDF\u6D88\u606F';
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

    return NotifyMessageItem(
      id: id,
      title: title,
      content: content,
      readStatus: readStatus,
      createTime: fallbackTime,
      templateCode: templateCode,
      templateType: templateType,
      senderName: sender,
    );
  }

  final int id;
  final String title;
  final String content;
  final bool readStatus;
  final DateTime? createTime;
  final String? templateCode;
  final int? templateType;
  final String? senderName;

  NotifyMessageItem copyWith({bool? readStatus}) {
    return NotifyMessageItem(
      id: id,
      title: title,
      content: content,
      readStatus: readStatus ?? this.readStatus,
      createTime: createTime,
      templateCode: templateCode,
      templateType: templateType,
      senderName: senderName,
    );
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
