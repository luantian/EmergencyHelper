import 'package:emergency_helper/src/core/network/api_client.dart';
import 'package:flutter/foundation.dart';

class EventWeatherWarningService {
  Future<List<EventWeatherWarningItem>> fetchWarningList(
    ApiClient apiClient,
  ) async {
    debugPrint('[WeatherWarning] >>> REQUEST START >>>');
    debugPrint('[WeatherWarning] endpoint=/admin-api/eventweather-warning/page');
    debugPrint('[WeatherWarning] params: pageNo=1, pageSize=10');
    final response = await apiClient.getJson(
      '/admin-api/event/weather-warning/page',
      queryParameters: <String, dynamic>{
        'pageNo': 1,
        'pageSize': 10,
      },
    );

    // Dump full raw response for debugging
    debugPrint(
        '[WeatherWarning] <<< FULL RAW RESPONSE <<<');
    debugPrint('[WeatherWarning] response=${response.toString()}');
    debugPrint('[WeatherWarning] >>> END FULL RAW RESPONSE >>>');

    final code = _asInt(response['code']);
    final data = response['data'];

    debugPrint('[WeatherWarning] raw response keys=${response.keys.toList()}');
    debugPrint('[WeatherWarning] code=$code, data type=${data.runtimeType}');
    debugPrint('[WeatherWarning] data=${data.toString().substring(0, data.toString().length > 500 ? 500 : data.toString().length)}');

    if (code != 0) {
      debugPrint('[WeatherWarning] non-zero code, returning empty list');
      return const <EventWeatherWarningItem>[];
    }

    final dataMap = _asMap(data);
    debugPrint('[WeatherWarning] dataMap keys=${dataMap?.keys.toList()}');
    if (dataMap != null) {
      debugPrint('[WeatherWarning] dataMap total=${dataMap['total']}');
      debugPrint('[WeatherWarning] dataMap list=${dataMap['list']?.toString().substring(0, dataMap['list'].toString().length.clamp(0, 500))}');
    }

    final records = _asList(dataMap?['list'] ?? dataMap?['records'] ?? data);
    debugPrint('[WeatherWarning] parsed ${records.length} records');
    for (var i = 0; i < records.length; i++) {
      debugPrint('[WeatherWarning] record[$i]=${records[i].toString().substring(0, records[i].toString().length.clamp(0, 300))}');
    }
    return records
        .map((item) => EventWeatherWarningItem.fromMap(item))
        .toList();
  }

  Map<String, dynamic>? _asMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.cast<String, dynamic>();
    return null;
  }

  int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  List<Map<String, dynamic>> _asList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
  }
}

class EventWeatherWarningItem {
  EventWeatherWarningItem({
    required this.id,
    required this.title,
    required this.content,
    required this.typeName,
    required this.level,
    required this.publishTime,
    this.province = '',
    this.city = '',
    this.org = '',
  });

  factory EventWeatherWarningItem.fromMap(Map<String, dynamic> map) {
    final pubTime = map['pubTime'] ?? map['publishTime'];
    DateTime? parsedTime;
    if (pubTime is int) {
      parsedTime = DateTime.fromMillisecondsSinceEpoch(pubTime);
    } else if (pubTime is num) {
      parsedTime = DateTime.fromMillisecondsSinceEpoch(pubTime.toInt());
    } else if (pubTime is String) {
      parsedTime = DateTime.tryParse(pubTime);
    }
    return EventWeatherWarningItem(
      id: map['id']?.toString() ?? '',
      title: (map['title'] ?? '').toString(),
      content: (map['content'] ?? '').toString(),
      typeName: (map['typeName'] ?? map['levelName'] ?? '').toString(),
      level: (map['level'] ?? '').toString(),
      publishTime: parsedTime,
      province: (map['province'] ?? '').toString(),
      city: (map['city'] ?? '').toString(),
      org: (map['org'] ?? '').toString(),
    );
  }

  final String id;
  final String title;
  final String content;
  final String typeName;
  final String level;
  final DateTime? publishTime;
  final String province;
  final String city;
  final String org;
}
