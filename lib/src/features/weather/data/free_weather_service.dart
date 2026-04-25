import 'package:dio/dio.dart';
import 'package:emergency_helper/src/core/constants/app_constants.dart';

class FreeWeatherService {
  FreeWeatherService([Dio? dio])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ),
          );

  final Dio _dio;

  Future<WeatherSnapshot> fetchShenyangForecast() async {
    final key = AppConstants.qWeatherKey.trim();
    if (key.isEmpty) {
      throw Exception(
        '\u672a\u914d\u7f6e\u548c\u98ce\u5929\u6c14 KEY\uff08QWEATHER_KEY\uff09',
      );
    }

    final location = AppConstants.qWeatherDefaultLocation;
    final common = <String, dynamic>{'location': location, 'lang': 'zh'};
    final options = Options(headers: {'X-QW-Api-Key': key});

    final nowRes = await _dio.get<Map<String, dynamic>>(
      '${AppConstants.qWeatherHost}/v7/weather/now',
      queryParameters: common,
      options: options,
    );
    final hourlyRes = await _dio.get<Map<String, dynamic>>(
      '${AppConstants.qWeatherHost}/v7/weather/24h',
      queryParameters: common,
      options: options,
    );
    final dailyRes = await _dio.get<Map<String, dynamic>>(
      '${AppConstants.qWeatherHost}/v7/weather/7d',
      queryParameters: common,
      options: options,
    );

    final nowRoot = nowRes.data ?? <String, dynamic>{};
    final hourlyRoot = hourlyRes.data ?? <String, dynamic>{};
    final dailyRoot = dailyRes.data ?? <String, dynamic>{};

    final nowCode = (nowRoot['code'] ?? '').toString();
    final hourlyCode = (hourlyRoot['code'] ?? '').toString();
    final dailyCode = (dailyRoot['code'] ?? '').toString();
    if (nowCode != '200' || hourlyCode != '200' || dailyCode != '200') {
      throw Exception(
        '\u548c\u98ce\u5929\u6c14\u8fd4\u56de\u5931\u8d25'
        '\uff08now:$nowCode, 24h:$hourlyCode, 7d:$dailyCode\uff09\uff0c'
        '\u8bf7\u68c0\u67e5 QWEATHER_HOST \u4e0e\u51ed\u636e\u6743\u9650',
      );
    }

    final now =
        (nowRoot['now'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final hourlyList = _toMapList(hourlyRoot['hourly']);
    final dailyList = _toMapList(dailyRoot['daily']);

    final hourlyItems = <WeatherHour>[];
    for (final item in hourlyList) {
      final time = DateTime.tryParse((item['fxTime'] ?? '').toString());
      if (time == null) {
        continue;
      }
      hourlyItems.add(
        WeatherHour(
          time: time,
          temperature: _toDouble(item['temp']) ?? 0,
          weatherCode: _toInt(item['icon']) ?? 101,
        ),
      );
    }

    final dailyItems = <WeatherDay>[];
    for (final item in dailyList) {
      final date = DateTime.tryParse((item['fxDate'] ?? '').toString());
      if (date == null) {
        continue;
      }
      dailyItems.add(
        WeatherDay(
          date: date,
          maxTemp: _toDouble(item['tempMax']) ?? 0,
          minTemp: _toDouble(item['tempMin']) ?? 0,
          uvIndex: _toDouble(item['uvIndex']) ?? 0,
          rainProbability: _toInt(item['precip']) ?? 0,
        ),
      );
    }

    return WeatherSnapshot(
      cityName: '\u6c88\u9633',
      currentTemp: _toDouble(now['temp']) ?? 0,
      currentHumidity: _toInt(now['humidity']) ?? 0,
      currentWindSpeed: _toDouble(now['windSpeed']) ?? 0,
      currentWeatherCode: _toInt(now['icon']) ?? 101,
      hourly: hourlyItems,
      daily: dailyItems,
      sunrise: dailyItems.isNotEmpty
          ? _dateWithClock(
              dailyItems.first.date,
              (dailyList.first['sunrise'] ?? '').toString(),
            )
          : null,
      sunset: dailyItems.isNotEmpty
          ? _dateWithClock(
              dailyItems.first.date,
              (dailyList.first['sunset'] ?? '').toString(),
            )
          : null,
    );
  }

  Future<WeatherWarningSnapshot> fetchOfficialWarningNow() async {
    final key = AppConstants.qWeatherKey.trim();
    if (key.isEmpty) {
      throw Exception('QWEATHER_KEY is empty');
    }

    final options = Options(headers: {'X-QW-Api-Key': key});
    final response = await _dio.get<Map<String, dynamic>>(
      '${AppConstants.qWeatherHost}/v7/warning/now',
      queryParameters: <String, dynamic>{
        'location': AppConstants.qWeatherDefaultLocation,
        'lang': 'zh',
      },
      options: options,
    );

    final root = response.data ?? <String, dynamic>{};
    final code = (root['code'] ?? '').toString();
    if (code != '200') {
      throw Exception('QWeather warning API failed: code=$code');
    }

    final warningRaw = _toMapList(root['warning']);
    final warnings = <WeatherWarningItem>[];
    for (final item in warningRaw) {
      warnings.add(
        WeatherWarningItem(
          id: (item['id'] ?? '').toString(),
          sender: (item['sender'] ?? '').toString(),
          title: (item['title'] ?? '').toString(),
          text: (item['text'] ?? '').toString(),
          typeName: (item['typeName'] ?? '').toString(),
          severity: (item['severity'] ?? '').toString(),
          severityColor: (item['severityColor'] ?? '').toString(),
          status: (item['status'] ?? '').toString(),
          pubTime: DateTime.tryParse((item['pubTime'] ?? '').toString()),
          startTime: DateTime.tryParse((item['startTime'] ?? '').toString()),
          endTime: DateTime.tryParse((item['endTime'] ?? '').toString()),
        ),
      );
    }

    return WeatherWarningSnapshot(
      updateTime: DateTime.tryParse((root['updateTime'] ?? '').toString()),
      warnings: warnings,
    );
  }

  DateTime? _dateWithClock(DateTime day, String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  List<Map<String, dynamic>> _toMapList(Object? raw) {
    if (raw is! List) {
      return const <Map<String, dynamic>>[];
    }
    return raw
        .whereType<Map>()
        .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  double? _toDouble(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }

  int? _toInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }
}

class WeatherSnapshot {
  WeatherSnapshot({
    required this.cityName,
    required this.currentTemp,
    required this.currentHumidity,
    required this.currentWindSpeed,
    required this.currentWeatherCode,
    required this.hourly,
    required this.daily,
    required this.sunrise,
    required this.sunset,
  });

  final String cityName;
  final double currentTemp;
  final int currentHumidity;
  final double currentWindSpeed;
  final int currentWeatherCode;
  final List<WeatherHour> hourly;
  final List<WeatherDay> daily;
  final DateTime? sunrise;
  final DateTime? sunset;
}

class WeatherHour {
  WeatherHour({
    required this.time,
    required this.temperature,
    required this.weatherCode,
  });

  final DateTime time;
  final double temperature;
  final int weatherCode;
}

class WeatherDay {
  WeatherDay({
    required this.date,
    required this.maxTemp,
    required this.minTemp,
    required this.uvIndex,
    required this.rainProbability,
  });

  final DateTime date;
  final double maxTemp;
  final double minTemp;
  final double uvIndex;
  final int rainProbability;
}

class WeatherWarningSnapshot {
  WeatherWarningSnapshot({required this.updateTime, required this.warnings});

  final DateTime? updateTime;
  final List<WeatherWarningItem> warnings;
}

class WeatherWarningItem {
  WeatherWarningItem({
    required this.id,
    required this.sender,
    required this.title,
    required this.text,
    required this.typeName,
    required this.severity,
    required this.severityColor,
    required this.status,
    required this.pubTime,
    required this.startTime,
    required this.endTime,
  });

  final String id;
  final String sender;
  final String title;
  final String text;
  final String typeName;
  final String severity;
  final String severityColor;
  final String status;
  final DateTime? pubTime;
  final DateTime? startTime;
  final DateTime? endTime;
}
