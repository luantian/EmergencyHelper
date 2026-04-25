import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/network/api_client.dart';

class WorkbenchStatisticsService {
  const WorkbenchStatisticsService();

  Future<WorkbenchStatistics> fetchStatistics(ApiClient apiClient) async {
    final response = await apiClient.getJson(AppConstants.eventReportStatisticsPath);
    final data = _expectSuccessAndData(response);
    final root = _asMap(data) ?? const <String, dynamic>{};
    final map = _asMap(root['data']) ?? root;

    final todayNewEventCount = _pickInt(map, const [
      'newEventCount',
      'todayNewEventCount',
      'todayNewEvent',
      'todayEventCount',
      'todayCount',
      'todayAddCount',
      'eventTodayCount',
      'eventNewCount',
    ]);
    final pendingEventCount = _pickInt(map, const [
      'processingEventCount',
      'pendingEventCount',
      'waitHandleEventCount',
      'toHandleEventCount',
      'waitResponseEventCount',
      'eventPendingCount',
    ]);
    final pendingRiskCount = _pickInt(map, const [
      'pendingRiskCount',
      'waitHandleRiskCount',
      'toHandleRiskCount',
      'waitResponseRiskCount',
      'riskPendingCount',
    ]);

    return WorkbenchStatistics(
      todayNewEventCount: todayNewEventCount ?? 0,
      pendingEventCount: pendingEventCount ?? 0,
      pendingRiskCount: pendingRiskCount ?? 0,
    );
  }

  Object? _expectSuccessAndData(Map<String, dynamic> response) {
    final code = _asInt(response['code']) ?? 0;
    if (code != 0) {
      throw AppException(_asText(response['msg']) ?? '获取工作台统计失败');
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

  int? _pickInt(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = _asInt(map[key]);
      if (value != null) {
        return value;
      }
    }
    return null;
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

class WorkbenchStatistics {
  const WorkbenchStatistics({
    required this.todayNewEventCount,
    required this.pendingEventCount,
    required this.pendingRiskCount,
  });

  final int todayNewEventCount;
  final int pendingEventCount;
  final int pendingRiskCount;
}
