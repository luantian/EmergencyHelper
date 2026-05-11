import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/network/api_client.dart';

class EventStatisticsService {
  const EventStatisticsService();

  static const String _reportNumPath =
      '/admin-api/event/report/statistics/reportNum';
  static const String _typePath = '/admin-api/event/report/statistics/type';
  static const String _trendPath = '/admin-api/event/report/statistics/trend';

  Future<EventStatisticsBundle> fetchEventStatistics(
    ApiClient apiClient, {
    required String? deptId,
    required String? level,
    required StatisticsPeriod period,
  }) async {
    final range = _buildTimeRange(period);
    final previousRange = _buildPreviousTimeRange(period, range);
    final baseQuery = <String, dynamic>{
      if (deptId != null && deptId.trim().isNotEmpty) 'deptId': deptId.trim(),
      if (level != null && level.trim().isNotEmpty) 'level': level.trim(),
    };

    final reportResponses = await Future.wait<Map<String, dynamic>>(
      <Future<Map<String, dynamic>>>[
      apiClient.postJson(
        _reportNumPath,
        queryParameters: <String, dynamic>{
          ...baseQuery,
          'createTimeStart': _formatDateTime(range.start),
          'createTimeEnd': _formatDateTime(range.end),
        },
      ),
      apiClient.postJson(
        _reportNumPath,
        queryParameters: <String, dynamic>{
          ...baseQuery,
          'createTimeStart': _formatDateTime(previousRange.start),
          'createTimeEnd': _formatDateTime(previousRange.end),
        },
      ),
      ],
    );
    final reportNumData = _unwrapData(reportResponses[0]);
    final previousReportNumData = _unwrapData(reportResponses[1]);
    final overview = StatisticsOverview(
      totalCount: _asInt(reportNumData['totalCount']) ?? 0,
      pendingCount: _asInt(reportNumData['pendingCount']) ?? 0,
      closedCount: _asInt(reportNumData['closedCount']) ?? 0,
      previousTotalCount: _asInt(previousReportNumData['totalCount']) ?? 0,
    );

    final typeResponse = await apiClient.postJson(
      _typePath,
      queryParameters: <String, dynamic>{
        ...baseQuery,
        'createTimeStart': _formatDateTime(range.start),
        'createTimeEnd': _formatDateTime(range.end),
      },
    );
    final typeData = _unwrapData(typeResponse);
    final distribution = _asMapList(typeData['typeList'])
        .map((item) {
          return StatisticsTypeCount(
            typeName: _asText(item['typeName']) ?? '其他',
            count: _asInt(item['count']) ?? 0,
          );
        })
        .where((item) => item.count > 0)
        .toList(growable: false);

    final trendResponse = await apiClient.postJson(
      _trendPath,
      queryParameters: baseQuery,
    );
    final trendData = _unwrapData(trendResponse);
    final dateList = _asList(trendData['dateList'])
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final trendSeries = _asMapList(trendData['typeList'])
        .map((item) {
          return StatisticsTrendSeries(
            typeName: _asText(item['typeName']) ?? '其他',
            dailyCounts: _asList(
              item['dailyCounts'],
            ).map((value) => _asInt(value) ?? 0).toList(growable: false),
          );
        })
        .toList(growable: false);

    return EventStatisticsBundle(
      overview: overview,
      distribution: distribution,
      trend: StatisticsTrendData(dateList: dateList, series: trendSeries),
    );
  }

  Map<String, dynamic> _unwrapData(Map<String, dynamic> response) {
    final code = _asInt(response['code']) ?? -1;
    if (code != 0) {
      throw AppException(_asText(response['msg']) ?? '统计接口返回失败');
    }
    final rawData = response['data'];
    final map = _asMap(rawData);
    if (map == null) {
      return const <String, dynamic>{};
    }
    if (map['data'] is Map || map['data'] is Map<String, dynamic>) {
      return _asMap(map['data']) ?? map;
    }
    return map;
  }

  _TimeRange _buildTimeRange(StatisticsPeriod period) {
    final now = DateTime.now();
    switch (period) {
      case StatisticsPeriod.thisWeek:
        final weekday = now.weekday;
        final startDate = now.subtract(Duration(days: weekday - 1));
        final start = DateTime(
          startDate.year,
          startDate.month,
          startDate.day,
          0,
          0,
          0,
        );
        final endDate = start.add(const Duration(days: 6));
        final end = DateTime(
          endDate.year,
          endDate.month,
          endDate.day,
          23,
          59,
          59,
        );
        return _TimeRange(start: start, end: end);
      case StatisticsPeriod.thisMonth:
        final start = DateTime(now.year, now.month, 1, 0, 0, 0);
        final nextMonthStart = DateTime(now.year, now.month + 1, 1);
        final end = nextMonthStart.subtract(const Duration(seconds: 1));
        return _TimeRange(start: start, end: end);
    }
  }

  _TimeRange _buildPreviousTimeRange(
    StatisticsPeriod period,
    _TimeRange currentRange,
  ) {
    switch (period) {
      case StatisticsPeriod.thisWeek:
        return _TimeRange(
          start: currentRange.start.subtract(const Duration(days: 7)),
          end: currentRange.end.subtract(const Duration(days: 7)),
        );
      case StatisticsPeriod.thisMonth:
        final previousEnd = currentRange.start.subtract(
          const Duration(seconds: 1),
        );
        final previousStart = DateTime(
          previousEnd.year,
          previousEnd.month,
          1,
          0,
          0,
          0,
        );
        return _TimeRange(start: previousStart, end: previousEnd);
    }
  }

  String _formatDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
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

  List<dynamic> _asList(Object? value) {
    if (value is List) {
      return value;
    }
    return const <dynamic>[];
  }

  List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    return value
        .whereType<Object?>()
        .map((item) => _asMap(item))
        .whereType<Map<String, dynamic>>()
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

enum StatisticsPeriod { thisWeek, thisMonth }

class EventStatisticsBundle {
  const EventStatisticsBundle({
    required this.overview,
    required this.distribution,
    required this.trend,
  });

  final StatisticsOverview overview;
  final List<StatisticsTypeCount> distribution;
  final StatisticsTrendData trend;
}

class StatisticsOverview {
  const StatisticsOverview({
    required this.totalCount,
    required this.pendingCount,
    required this.closedCount,
    required this.previousTotalCount,
  });

  final int totalCount;
  final int pendingCount;
  final int closedCount;
  final int previousTotalCount;

  double get closedRate {
    if (totalCount <= 0) {
      return 0;
    }
    return (closedCount / totalCount) * 100;
  }

  double get totalChangeRate {
    if (previousTotalCount <= 0) {
      return totalCount <= 0 ? 0 : 100;
    }
    return ((totalCount - previousTotalCount) / previousTotalCount) * 100;
  }

  int get totalChangePercentRounded => totalChangeRate.abs().round();

  bool get totalIncreased => totalCount > previousTotalCount;

  bool get totalDecreased => totalCount < previousTotalCount;
}

class StatisticsTypeCount {
  const StatisticsTypeCount({required this.typeName, required this.count});

  final String typeName;
  final int count;
}

class StatisticsTrendData {
  const StatisticsTrendData({required this.dateList, required this.series});

  final List<String> dateList;
  final List<StatisticsTrendSeries> series;
}

class StatisticsTrendSeries {
  const StatisticsTrendSeries({
    required this.typeName,
    required this.dailyCounts,
  });

  final String typeName;
  final List<int> dailyCounts;
}

class _TimeRange {
  const _TimeRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}
