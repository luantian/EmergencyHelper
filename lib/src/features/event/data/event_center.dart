import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/network/api_client.dart';
import 'package:flutter/foundation.dart';

enum EventProcessStatus { processing, finished }

extension EventProcessStatusX on EventProcessStatus {
  String get label {
    switch (this) {
      case EventProcessStatus.processing:
        return '\u5904\u7406\u4E2D';
      case EventProcessStatus.finished:
        return '\u5DF2\u529E\u7ED3';
    }
  }

  int get apiCode {
    return apiCodes.first;
  }

  List<int> get apiCodes {
    switch (this) {
      case EventProcessStatus.processing:
        return const <int>[0, 1];
      case EventProcessStatus.finished:
        return const <int>[2];
    }
  }
}

class EventAttachmentPayload {
  const EventAttachmentPayload({
    this.id,
    required this.name,
    required this.path,
    this.type,
  });

  final int? id;
  final String name;
  final String path;
  final String? type;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      'name': name,
      'path': path,
      if (type != null && type!.trim().isNotEmpty) 'type': type,
    };
  }
}

class EventTimelineItem {
  EventTimelineItem({
    required this.time,
    required this.stage,
    this.content,
    this.operatorName,
    this.receiverNames,
    this.attachments = const <EventAttachmentPayload>[],
    this.attachmentName,
    this.attachmentPath,
    this.attachmentType,
  });

  final DateTime time;
  final String stage;
  final String? content;
  final String? operatorName;
  final String? receiverNames;
  final List<EventAttachmentPayload> attachments;
  final String? attachmentName;
  final String? attachmentPath;
  final String? attachmentType;
}

class EventRecord {
  EventRecord({
    required this.id,
    required this.name,
    required this.description,
    required this.status,
    required this.level,
    required this.type,
    required this.department,
    required this.reportTime,
    required this.location,
    required this.street,
    required this.timeline,
    this.attachments = const <EventAttachmentPayload>[],
    this.attachmentName,
  });

  final String id;
  final String name;
  final String description;
  EventProcessStatus status;
  final String level;
  final String type;
  final String department;
  final DateTime reportTime;
  final String location;
  final String street;
  final List<EventTimelineItem> timeline;
  final List<EventAttachmentPayload> attachments;
  String? attachmentName;
}

class EventPageLoadResult {
  const EventPageLoadResult({
    required this.pageNo,
    required this.pageSize,
    required this.receivedCount,
    required this.acceptedCount,
    required this.hasMore,
  });

  final int pageNo;
  final int pageSize;
  final int receivedCount;
  final int acceptedCount;
  final bool hasMore;
}

class EventCenter extends ChangeNotifier {
  EventCenter._();

  static final EventCenter instance = EventCenter._();

  ApiClient? _apiClient;
  final Map<EventProcessStatus, List<EventRecord>> _statusCache =
      <EventProcessStatus, List<EventRecord>>{
        EventProcessStatus.processing: <EventRecord>[],
        EventProcessStatus.finished: <EventRecord>[],
      };
  final Map<String, EventRecord> _eventById = <String, EventRecord>{};
  final Map<int, String> _deptNameByIdCache = <int, String>{};
  final Map<String, String> _eventTypeNameByValueCache = <String, String>{};
  String? _lastErrorMessage;

  String? get lastErrorMessage => _lastErrorMessage;

  void bindApiClient(ApiClient apiClient) {
    _apiClient = apiClient;
  }

  void resetSessionCache({bool notify = true}) {
    _statusCache[EventProcessStatus.processing] = <EventRecord>[];
    _statusCache[EventProcessStatus.finished] = <EventRecord>[];
    _eventById.clear();
    _deptNameByIdCache.clear();
    _eventTypeNameByValueCache.clear();
    _lastErrorMessage = null;
    if (notify) {
      notifyListeners();
    }
  }

  List<EventRecord> queryEvents({
    required EventProcessStatus status,
    String keyword = '',
  }) {
    final source = _statusCache[status] ?? const <EventRecord>[];
    final normalizedKeyword = keyword.trim();

    final result = source.where((event) {
      if (normalizedKeyword.isEmpty) {
        return true;
      }
      return event.name.contains(normalizedKeyword) ||
          event.description.contains(normalizedKeyword) ||
          event.location.contains(normalizedKeyword);
    }).toList();

    result.sort((a, b) => b.reportTime.compareTo(a.reportTime));
    return List<EventRecord>.unmodifiable(result);
  }

  EventRecord? eventById(String eventId) {
    return _eventById[eventId];
  }

  Future<EventPageLoadResult> loadEvents({
    required EventProcessStatus status,
    String keyword = '',
    int pageNo = 1,
    int pageSize = 50,
    bool append = false,
  }) async {
    final apiClient = _ensureApiClient();
    await _ensureEventTypeCacheLoaded(apiClient);
    await _ensureStreetDeptCacheLoaded(apiClient);
    final mappedById = <String, EventRecord>{};
    var receivedCount = 0;
    var hasMore = false;

    for (final statusCode in status.apiCodes) {
      final response = await apiClient.getJson(
        '/admin-api/api/event/report/page',
        queryParameters: <String, dynamic>{
          'pageNo': pageNo,
          'pageSize': pageSize,
          'status': statusCode,
          if (keyword.trim().isNotEmpty) 'name': keyword.trim(),
        },
      );
      final data = _expectSuccessAndGetData(
        response,
        defaultErrorMessage:
            '\u52A0\u8F7D\u4E8B\u4EF6\u5217\u8868\u5931\u8D25\uFF0C\u8BF7\u7A0D\u540E\u91CD\u8BD5',
      );
      final dataMap = _asMap(data);
      final list = _asMapList(dataMap?['list']);
      receivedCount += list.length;
      if (pageSize > 0 && list.length >= pageSize) {
        hasMore = true;
      }
      for (final item in list) {
        final event = _eventFromMap(item);
        if (event.status != status || event.id.trim().isEmpty) {
          continue;
        }
        mappedById[event.id] = event;
      }
    }
    final mapped = mappedById.values.toList()
      ..sort((a, b) => b.reportTime.compareTo(a.reportTime));

    final merged = append
        ? _mergeEventList(_statusCache[status] ?? const <EventRecord>[], mapped)
        : mapped;

    _statusCache[status] = merged;
    for (final event in merged) {
      _eventById[event.id] = event;
    }
    _lastErrorMessage = null;
    notifyListeners();
    return EventPageLoadResult(
      pageNo: pageNo,
      pageSize: pageSize,
      receivedCount: receivedCount,
      acceptedCount: mapped.length,
      hasMore: hasMore,
    );
  }

  Future<EventRecord?> loadEventDetail(String eventId) async {
    final normalizedEventId = eventId.trim();
    if (normalizedEventId.isEmpty) {
      throw AppException(
        '\u4E8B\u4EF6ID\u65E0\u6548\uFF0C\u65E0\u6CD5\u52A0\u8F7D\u8BE6\u60C5',
      );
    }
    final apiClient = _ensureApiClient();
    await _ensureEventTypeCacheLoaded(apiClient);
    await _ensureStreetDeptCacheLoaded(apiClient);
    final response = await apiClient.getJson(
      '/admin-api/api/event/report/$normalizedEventId',
    );
    final data = _expectSuccessAndGetData(
      response,
      defaultErrorMessage: '加载事件详情失败',
    );
    final map = _asMap(data);
    if (map == null) {
      final cached = _eventById[normalizedEventId];
      if (cached != null) {
        return cached;
      }
      throw AppException('事件详情数据格式错误');
    }

    final cachedDetail = _eventById[normalizedEventId];
    final detail = _eventFromMap(map);
    final dynamics = await _loadEventOperationListSafely(
      path: '/admin-api/api/event/report/dynamic/list',
      eventId: normalizedEventId,
      defaultErrorMessage: '\u52A0\u8F7D\u4E8B\u4EF6\u52A8\u6001\u5931\u8D25',
    );

    final timeline = _buildTimeline(
      detailMap: map,
      dynamics: dynamics,
      transfers: const <Map<String, dynamic>>[],
      feedbacks: const <Map<String, dynamic>>[],
    );
    final stabilizedTimeline = _stabilizeTimeline(
      current: timeline,
      previous: cachedDetail?.timeline ?? const <EventTimelineItem>[],
    );

    if (stabilizedTimeline.isNotEmpty) {
      detail.timeline
        ..clear()
        ..addAll(stabilizedTimeline);
    }

    _eventById[normalizedEventId] = detail;
    _replaceInStatusCache(detail);
    _lastErrorMessage = null;
    notifyListeners();
    return detail;
  }

  Future<int?> createEvent({
    required String name,
    required String description,
    required int level,
    required int type,
    double? longitude,
    double? latitude,
    String? locationName,
    int? deptId,
    List<EventAttachmentPayload> attachments = const <EventAttachmentPayload>[],
  }) async {
    final apiClient = _ensureApiClient();
    final response = await apiClient.postJson(
      '/admin-api/api/event/report',
      data: <String, dynamic>{
        'name': name,
        'description': description,
        'level': level,
        'type': type,
        'longitude': ?longitude,
        'latitude': ?latitude,
        if (locationName != null && locationName.trim().isNotEmpty)
          'locationName': locationName.trim(),
        'deptId': ?deptId,
        if (attachments.isNotEmpty)
          'attachmentUrls': attachments.map((item) => item.toJson()).toList(),
      },
    );
    final data = _expectSuccessAndGetData(
      response,
      defaultErrorMessage: '创建事件失败',
    );
    final newId = _asInt(data);
    try {
      await loadEvents(status: EventProcessStatus.processing);
      if (newId != null) {
        await loadEventDetail(newId.toString());
      }
    } catch (_) {}
    return newId;
  }

  Future<void> updateEvent({
    required int id,
    required String name,
    required String description,
    required int level,
    required int type,
    double? longitude,
    double? latitude,
    String? locationName,
    int? deptId,
    List<EventAttachmentPayload> attachments = const <EventAttachmentPayload>[],
  }) async {
    final apiClient = _ensureApiClient();
    final response = await apiClient.putJson(
      '/admin-api/api/event/report',
      data: <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
        'level': level,
        'type': type,
        'longitude': ?longitude,
        'latitude': ?latitude,
        if (locationName != null && locationName.trim().isNotEmpty)
          'locationName': locationName.trim(),
        'deptId': ?deptId,
        if (attachments.isNotEmpty)
          'attachmentUrls': attachments.map((item) => item.toJson()).toList(),
      },
    );
    _expectSuccessAndGetData(response, defaultErrorMessage: '更新事件失败');
    try {
      await loadEvents(status: EventProcessStatus.processing);
      await loadEvents(status: EventProcessStatus.finished);
      await loadEventDetail(id.toString());
    } catch (_) {}
  }

  Future<void> submitFeedback({
    required String eventId,
    required String content,
    List<EventAttachmentPayload> attachments = const <EventAttachmentPayload>[],
  }) async {
    final apiClient = _ensureApiClient();
    final eventIdValue = _asInt(eventId);
    if (eventIdValue == null) {
      throw AppException(
        '\u4E8B\u4EF6 ID \u65E0\u6548\uFF0C\u65E0\u6CD5\u63D0\u4EA4\u53CD\u9988',
      );
    }

    final response = await apiClient.postJson(
      '/admin-api/api/event/report/feedback',
      data: <String, dynamic>{
        'eventId': eventIdValue,
        'content': content,
        if (attachments.isNotEmpty)
          'attachmentUrls': attachments.map((item) => item.toJson()).toList(),
      },
    );
    _expectSuccessAndGetData(response, defaultErrorMessage: '提交反馈失败');
    try {
      await loadEventDetail(eventId);
      await loadEvents(status: EventProcessStatus.processing);
    } catch (_) {}
  }

  Future<void> transfer({
    required String eventId,
    required List<int> userIds,
    required String content,
  }) async {
    final apiClient = _ensureApiClient();
    final eventIdValue = _asInt(eventId);
    if (eventIdValue == null) {
      throw AppException(
        '\u4E8B\u4EF6 ID \u65E0\u6548\uFF0C\u65E0\u6CD5\u8F6C\u6D3E',
      );
    }
    if (userIds.isEmpty) {
      throw AppException('请至少选择一位接收人');
    }

    final response = await apiClient.postJson(
      '/admin-api/api/event/report/transfer',
      data: <String, dynamic>{
        'eventId': eventIdValue,
        'userIds': userIds,
        'content': content,
      },
    );
    _expectSuccessAndGetData(response, defaultErrorMessage: '转派失败');
    try {
      await loadEventDetail(eventId);
      await loadEvents(status: EventProcessStatus.processing);
    } catch (_) {}
  }

  Future<void> finish(
    String eventId, {
    String closeReason = '\u4E8B\u4EF6\u5DF2\u5904\u7406\u5B8C\u6BD5',
  }) async {
    final apiClient = _ensureApiClient();
    final eventIdValue = _asInt(eventId);
    if (eventIdValue == null) {
      throw AppException(
        '\u4E8B\u4EF6 ID \u65E0\u6548\uFF0C\u65E0\u6CD5\u529E\u7ED3',
      );
    }

    final response = await apiClient.postJson(
      '/admin-api/api/event/report/close',
      data: <String, dynamic>{'id': eventIdValue, 'closeReason': closeReason},
    );
    _expectSuccessAndGetData(response, defaultErrorMessage: '办结失败');
    try {
      await loadEvents(status: EventProcessStatus.processing);
      await loadEvents(status: EventProcessStatus.finished);
      await loadEventDetail(eventId);
    } catch (_) {}
  }

  Future<bool> canTransfer(String eventId) {
    return _checkCanOperate(
      '/admin-api/api/event/report/transfer/can',
      eventId,
    );
  }

  Future<bool> canFeedback(String eventId) {
    return _checkCanOperate(
      '/admin-api/api/event/report/feedback/can',
      eventId,
    );
  }

  Future<bool> canClose() async {
    final apiClient = _ensureApiClient();
    try {
      final response = await apiClient.getJson(
        '/admin-api/api/event/report/close/can',
      );
      final data = _expectSuccessAndGetData(
        response,
        defaultErrorMessage: '校验办结权限失败',
      );
      if (data is bool) {
        return data;
      }
      return _asInt(data) == 1;
    } catch (_) {
      return false;
    }
  }

  Future<String?> uploadAttachment(
    File file, {
    String directory = 'event',
  }) async {
    final payload = await uploadAttachmentPayload(file, directory: directory);
    return payload?.path;
  }

  Future<EventAttachmentPayload?> uploadAttachmentPayload(
    File file, {
    String directory = 'event',
  }) async {
    final apiClient = _ensureApiClient();
    final filePath = file.path.trim();
    final name = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'attachment';

    try {
      if (filePath.isEmpty || !(await file.exists())) {
        throw AppException(
          '\u4E0A\u4F20\u9644\u4EF6\u5931\u8D25\uFF1A'
          '\u6587\u4EF6\u4E0D\u5B58\u5728\u6216\u4E0D\u53EF\u8BBF\u95EE',
        );
      }

      Future<Object?> uploadByPath(String path) async {
        final response = await apiClient.postFormData(
          path,
          queryParameters: <String, dynamic>{
            if (directory.trim().isNotEmpty) 'directory': directory.trim(),
          },
          data: FormData.fromMap(<String, dynamic>{
            'file': await MultipartFile.fromFile(filePath, filename: name),
          }),
        );
        return _expectSuccessAndGetData(
          response,
          defaultErrorMessage: '上传附件失败',
        );
      }

      Object? data;
      try {
        data = await uploadByPath('/admin-api/infra/file/upload');
      } on AppException catch (error) {
        final message = error.message.toLowerCase();
        final canFallback =
            message.contains('http 404') ||
            message.contains('http 405') ||
            message.contains('not allowed');
        if (!canFallback) {
          rethrow;
        }
        data = await uploadByPath('/app-api/infra/file/upload');
      }

      final map = _asMap(data);
      if (map != null) {
        final rawPath =
            _asText(map['path']) ??
            _asText(map['url']) ??
            _asText(map['uploadUrl']);
        final path = _normalizeAttachmentPath(rawPath);
        if (path.isNotEmpty) {
          return EventAttachmentPayload(
            id: _asInt(map['id']),
            name: _asText(map['name']) ?? name,
            path: path,
            type: _asText(map['type']),
          );
        }
      }
      final text = _asText(data);
      final normalizedText = _normalizeAttachmentPath(text);
      if (normalizedText.isEmpty) {
        return null;
      }
      return EventAttachmentPayload(name: name, path: normalizedText);
    } on AppException {
      rethrow;
    } catch (error) {
      throw AppException('上传附件失败：$error');
    }
  }

  Future<void> deleteAttachmentById(int? fileId) async {
    if (fileId == null || fileId <= 0) {
      return;
    }
    await deleteAttachmentIds(<int>[fileId]);
  }

  Future<void> deleteAttachmentIds(List<int> fileIds) async {
    final normalizedIds = fileIds
        .where((id) => id > 0)
        .toSet()
        .toList(growable: false);
    if (normalizedIds.isEmpty) {
      return;
    }

    final apiClient = _ensureApiClient();

    Future<void> deleteByPath({
      required String path,
      required Map<String, dynamic> query,
    }) async {
      final response = await apiClient.deleteJson(path, queryParameters: query);
      final data = _expectSuccessAndGetData(
        response,
        defaultErrorMessage: '删除附件失败',
      );
      if (data is bool && !data) {
        throw AppException('删除附件失败');
      }
    }

    try {
      if (normalizedIds.length == 1) {
        await deleteByPath(
          path: '/admin-api/infra/file/delete',
          query: <String, dynamic>{'id': normalizedIds.first},
        );
      } else {
        await deleteByPath(
          path: '/admin-api/infra/file/delete-list',
          query: <String, dynamic>{'ids': normalizedIds},
        );
      }
    } on AppException catch (error) {
      final message = error.message.toLowerCase();
      final canFallback =
          message.contains('http 404') ||
          message.contains('http 405') ||
          message.contains('not allowed');
      if (!canFallback) {
        rethrow;
      }

      if (normalizedIds.length == 1) {
        await deleteByPath(
          path: '/app-api/infra/file/delete',
          query: <String, dynamic>{'id': normalizedIds.first},
        );
      } else {
        await deleteByPath(
          path: '/app-api/infra/file/delete-list',
          query: <String, dynamic>{'ids': normalizedIds},
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadEventOperationListSafely({
    required String path,
    required String eventId,
    required String defaultErrorMessage,
  }) async {
    final eventIdValue = _asInt(eventId);
    if (eventIdValue == null) {
      return const <Map<String, dynamic>>[];
    }
    final apiClient = _ensureApiClient();
    try {
      final response = await apiClient.getJson(
        path,
        queryParameters: <String, dynamic>{'eventId': eventIdValue},
      );
      final data = _expectSuccessAndGetData(
        response,
        defaultErrorMessage: defaultErrorMessage,
      );
      return _asMapList(data);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  List<EventTimelineItem> _buildTimeline({
    required Map<String, dynamic> detailMap,
    required List<Map<String, dynamic>> dynamics,
    required List<Map<String, dynamic>> transfers,
    required List<Map<String, dynamic>> feedbacks,
  }) {
    final timeline = <EventTimelineItem>[];
    final reportAttachments = _attachmentsFromAny(detailMap);
    final reportAttachment = reportAttachments.isEmpty
        ? null
        : reportAttachments.first;
    final dynamicFeedbackKeys = <String>{};
    final dynamicTransferKeys = <String>{};

    final reportTime =
        _parseDateTime(detailMap['reportTime']) ??
        _parseDateTime(detailMap['createTime']) ??
        DateTime.now();
    timeline.add(
      EventTimelineItem(
        time: reportTime,
        stage: '\u5DF2\u4E0A\u62A5',
        content: _asText(detailMap['description']),
        operatorName: _asText(detailMap['reportUserName']),
        attachments: reportAttachments,
        attachmentName: reportAttachment?.name,
        attachmentPath: reportAttachment?.path,
        attachmentType: reportAttachment?.type,
      ),
    );

    for (final item in dynamics) {
      final timelineItem = _timelineFromDynamic(item);
      if (timelineItem != null) {
        timeline.add(timelineItem);
        if (_isFeedbackDynamic(item)) {
          dynamicFeedbackKeys.add(
            _feedbackSignature(
              time: timelineItem.time,
              operatorName: timelineItem.operatorName,
              content: timelineItem.content,
              attachmentPath: timelineItem.attachmentPath,
            ),
          );
        }
        if (_isTransferDynamic(item)) {
          dynamicTransferKeys.add(
            _transferSignature(
              time: timelineItem.time,
              operatorName: timelineItem.operatorName,
              receiverNames: timelineItem.receiverNames,
              content: timelineItem.content,
            ),
          );
        }
      }
    }
    for (final item in feedbacks) {
      final timelineItem = _timelineFromFeedback(item);
      if (timelineItem != null) {
        final signature = _feedbackSignature(
          time: timelineItem.time,
          operatorName: timelineItem.operatorName,
          content: timelineItem.content,
          attachmentPath: timelineItem.attachmentPath,
        );
        if (dynamicFeedbackKeys.contains(signature)) {
          continue;
        }
        timeline.add(timelineItem);
      }
    }
    for (final item in transfers) {
      final timelineItem = _timelineFromTransfer(item);
      if (timelineItem != null) {
        final signature = _transferSignature(
          time: timelineItem.time,
          operatorName: timelineItem.operatorName,
          receiverNames: timelineItem.receiverNames,
          content: timelineItem.content,
        );
        if (dynamicTransferKeys.contains(signature)) {
          continue;
        }
        timeline.add(timelineItem);
      }
    }

    return _deduplicateAndSortTimeline(timeline);
  }

  List<EventTimelineItem> _stabilizeTimeline({
    required List<EventTimelineItem> current,
    required List<EventTimelineItem> previous,
  }) {
    if (current.length > 1 || previous.length <= 1) {
      return current;
    }
    if (current.isEmpty) {
      return previous;
    }
    final merged = <EventTimelineItem>[current.first];
    for (final item in previous) {
      if (_timelineIdentityKey(item) == _timelineIdentityKey(current.first)) {
        continue;
      }
      merged.add(item);
    }
    return _deduplicateAndSortTimeline(merged);
  }

  List<EventTimelineItem> _deduplicateAndSortTimeline(
    List<EventTimelineItem> source,
  ) {
    final uniqueKeys = <String>{};
    final deduplicated = <EventTimelineItem>[];
    for (final item in source) {
      final key = _timelineIdentityKey(item);
      if (uniqueKeys.add(key)) {
        deduplicated.add(item);
      }
    }
    deduplicated.sort((a, b) => b.time.compareTo(a.time));
    return deduplicated;
  }

  String _timelineIdentityKey(EventTimelineItem item) {
    return '${item.stage}|${item.time.toIso8601String()}|${item.operatorName ?? ''}'
        '|${item.receiverNames ?? ''}|${item.content ?? ''}'
        '|${item.attachmentName ?? ''}|${item.attachmentPath ?? ''}'
        '|${item.attachmentType ?? ''}'
        '|${item.attachments.map((a) => '${a.name}|${a.path}|${a.type ?? ''}').join('||')}';
  }

  EventTimelineItem? _timelineFromDynamic(Map<String, dynamic> item) {
    final attachments = _attachmentsFromAny(item);
    final attachment = attachments.isEmpty ? null : attachments.first;
    final stage =
        _asText(item['typeName']) ?? _dynamicTypeLabel(_asInt(item['type']));
    final content = _asText(item['content']);
    final operatorName = _asText(item['operatorName']);
    final receiverNames = _extractReceiverNames(_asText(item['extraInfo']));
    final time = _parseDateTime(item['createTime']) ?? DateTime.now();
    if (stage == '--' &&
        content == null &&
        operatorName == null &&
        receiverNames == null) {
      return null;
    }
    return EventTimelineItem(
      time: time,
      stage: stage,
      content: content,
      operatorName: operatorName,
      receiverNames: receiverNames,
      attachments: attachments,
      attachmentName: attachment?.name,
      attachmentPath: attachment?.path,
      attachmentType: attachment?.type,
    );
  }

  bool _isFeedbackDynamic(Map<String, dynamic> item) {
    final type = _asInt(item['type']);
    if (type == 2) {
      return true;
    }
    final typeName = _asText(item['typeName']) ?? '';
    return typeName.contains('反馈');
  }

  bool _isTransferDynamic(Map<String, dynamic> item) {
    final type = _asInt(item['type']);
    if (type == 1) {
      return true;
    }
    final typeName = _asText(item['typeName']) ?? '';
    return typeName.contains('转派');
  }

  String _feedbackSignature({
    required DateTime time,
    String? operatorName,
    String? content,
    String? attachmentPath,
  }) {
    final bucket = time.millisecondsSinceEpoch ~/ 5000;
    final text = (content ?? '').trim();
    final attachment = (attachmentPath ?? '').trim();
    final operator = (operatorName ?? '').trim();
    final body = text.isNotEmpty ? text : attachment;
    final fallback = body.isNotEmpty ? body : operator;
    return '$bucket|$fallback';
  }

  String _transferSignature({
    required DateTime time,
    String? operatorName,
    String? receiverNames,
    String? content,
  }) {
    final bucket = time.millisecondsSinceEpoch ~/ 5000;
    final operator = (operatorName ?? '').trim();
    final receivers = (receiverNames ?? '').trim();
    final text = (content ?? '').trim();
    final body = receivers.isNotEmpty ? receivers : text;
    return '$bucket|$operator|$body';
  }

  EventTimelineItem? _timelineFromFeedback(Map<String, dynamic> item) {
    final attachments = _attachmentsFromAny(item);
    final attachment = attachments.isEmpty ? null : attachments.first;
    final content = _asText(item['content']);
    final operatorName = _asText(item['userName']);
    final time = _parseDateTime(item['createTime']) ?? DateTime.now();
    if (content == null && operatorName == null) {
      return null;
    }
    return EventTimelineItem(
      time: time,
      stage: '反馈',
      content: content,
      operatorName: operatorName,
      attachments: attachments,
      attachmentName: attachment?.name,
      attachmentPath: attachment?.path,
      attachmentType: attachment?.type,
    );
  }

  EventTimelineItem? _timelineFromTransfer(Map<String, dynamic> item) {
    final receiverNames = _asText(item['userName']);
    final operatorName = _asText(item['assignUserName']);
    final content = _asText(item['handleResult']) ?? _asText(item['content']);
    final time =
        _parseDateTime(item['assignTime']) ??
        _parseDateTime(item['createTime']) ??
        DateTime.now();
    if (receiverNames == null && operatorName == null && content == null) {
      return null;
    }
    return EventTimelineItem(
      time: time,
      stage: '转派',
      content: content,
      operatorName: operatorName,
      receiverNames: receiverNames,
    );
  }

  String _dynamicTypeLabel(int? type) {
    switch (type) {
      case 1:
        return '转派';
      case 2:
        return '反馈';
      case 3:
        return '办结';
      default:
        return '--';
    }
  }

  Future<bool> _checkCanOperate(String path, String eventId) async {
    final apiClient = _ensureApiClient();
    final eventIdValue = _asInt(eventId);
    if (eventIdValue == null) {
      return false;
    }
    try {
      final response = await apiClient.getJson(
        path,
        queryParameters: <String, dynamic>{'eventId': eventIdValue},
      );
      final data = _expectSuccessAndGetData(
        response,
        defaultErrorMessage: '操作校验失败',
      );
      if (data is bool) {
        return data;
      }
      return _asInt(data) == 1;
    } catch (_) {
      return false;
    }
  }

  ApiClient _ensureApiClient() {
    final apiClient = _apiClient;
    if (apiClient == null) {
      throw AppException('事件服务未初始化，请稍后重试');
    }
    return apiClient;
  }

  Object? _expectSuccessAndGetData(
    Map<String, dynamic> response, {
    required String defaultErrorMessage,
  }) {
    final code = _asInt(response['code']) ?? 0;
    if (code != 0) {
      final message = _asText(response['msg']) ?? defaultErrorMessage;
      _lastErrorMessage = message;
      throw AppException(message);
    }
    _lastErrorMessage = null;
    return response['data'];
  }

  void _replaceInStatusCache(EventRecord detail) {
    if (detail.id.trim().isEmpty) {
      return;
    }
    final processingList = List<EventRecord>.from(
      _statusCache[EventProcessStatus.processing] ?? const <EventRecord>[],
    );
    final finishedList = List<EventRecord>.from(
      _statusCache[EventProcessStatus.finished] ?? const <EventRecord>[],
    );

    processingList.removeWhere((item) => item.id == detail.id);
    finishedList.removeWhere((item) => item.id == detail.id);

    if (detail.status == EventProcessStatus.processing) {
      processingList.add(detail);
      processingList.sort((a, b) => b.reportTime.compareTo(a.reportTime));
    } else {
      finishedList.add(detail);
      finishedList.sort((a, b) => b.reportTime.compareTo(a.reportTime));
    }

    _statusCache[EventProcessStatus.processing] = processingList;
    _statusCache[EventProcessStatus.finished] = finishedList;
  }

  List<EventRecord> _mergeEventList(
    List<EventRecord> oldList,
    List<EventRecord> newList,
  ) {
    if (oldList.isEmpty) {
      return List<EventRecord>.from(newList)
        ..sort((a, b) => b.reportTime.compareTo(a.reportTime));
    }
    if (newList.isEmpty) {
      return List<EventRecord>.from(oldList)
        ..sort((a, b) => b.reportTime.compareTo(a.reportTime));
    }

    final mergedById = <String, EventRecord>{};
    for (final item in oldList) {
      mergedById[item.id] = item;
    }
    for (final item in newList) {
      mergedById[item.id] = item;
    }

    final merged = mergedById.values.toList();
    merged.sort((a, b) => b.reportTime.compareTo(a.reportTime));
    return merged;
  }

  EventRecord _eventFromMap(Map<String, dynamic> map) {
    final id = _asText(map['id']) ?? '';
    final statusCode = _asInt(map['status']) ?? 0;
    final status = statusCode == 2
        ? EventProcessStatus.finished
        : EventProcessStatus.processing;
    final reportTime =
        _parseDateTime(map['reportTime']) ??
        _parseDateTime(map['createTime']) ??
        DateTime.now();

    final levelName = _asText(map['levelName']);
    final typeName = _firstNonEmptyText(<String?>[
      _asText(map['typeName']),
      _eventTypeLabelByRawValue(map['type']),
    ]);
    final reportDeptName = _resolveReportDepartmentName(map);
    final streetName = _resolveStreetName(map);
    final locationName = _asText(map['locationName']);
    final attachments = _extractAttachments(map['attachmentUrls']);
    final attachmentName = _firstAttachmentName(map['attachmentUrls']);

    return EventRecord(
      id: id,
      name: _asText(map['name']) ?? '',
      description: _asText(map['description']) ?? '',
      status: status,
      level: levelName ?? _fallbackLevelName(_asInt(map['level'])),
      type: typeName ?? _asText(map['type']) ?? '--',
      department: reportDeptName ?? '--',
      reportTime: reportTime,
      location: locationName ?? '--',
      street: streetName ?? '--',
      timeline: <EventTimelineItem>[
        EventTimelineItem(
          time: reportTime,
          stage: _asText(map['statusName']) ?? _stageFromStatusCode(statusCode),
          content: _asText(map['description']),
          operatorName: _asText(map['reportUserName']),
          attachmentName: attachmentName,
        ),
      ],
      attachments: attachments,
      attachmentName: attachmentName,
    );
  }

  String? _resolveReportDepartmentName(Map<String, dynamic> map) {
    return _firstNonEmptyText(<String?>[
      _departmentNameFromObject(map['reportDeptName']),
      _departmentNameFromObject(map['reportDept']),
      _departmentNameFromObject(map['reportDeptInfo']),
      _departmentNameFromObject(map['reportDeptVO']),
      _departmentNameFromObject(map['reportOrgName']),
      _departmentNameFromObject(map['reportOrg']),
      _departmentNameFromObject(map['reportDepartment']),
      _departmentNameFromObject(map['deptName']),
      _departmentNameFromObject(map['dept']),
      _departmentNameFromObject(map['department']),
      _departmentNameFromObject(map['belongDeptName']),
      _departmentNameFromObject(map['belongDept']),
      _departmentNameFromObject(map['orgName']),
      _departmentNameFromObject(map['org']),
      _departmentNameFromObject(map['tenantName']),
      _departmentNameFromObject(map['tenant']),
    ]);
  }

  String? _resolveStreetName(Map<String, dynamic> map) {
    return _firstNonEmptyText(<String?>[
      _departmentNameFromObject(map['streetName']),
      _departmentNameFromObject(map['street']),
      _departmentNameFromObject(map['streetInfo']),
      _departmentNameFromObject(map['streetVO']),
      _departmentNameFromObject(map['deptName']),
      _departmentNameFromObject(map['dept']),
      _departmentNameByIdFromMap(map),
    ]);
  }

  String? _departmentNameByIdFromMap(Map<String, dynamic> map) {
    if (_deptNameByIdCache.isEmpty) {
      return null;
    }
    final streetMap = _asMap(map['street']);
    final deptMap = _asMap(map['dept']);
    final candidates = <int?>[
      _asInt(map['streetId']),
      _asInt(streetMap?['id']),
      _asInt(streetMap?['deptId']),
      _asInt(map['deptId']),
      _asInt(deptMap?['id']),
      _asInt(deptMap?['deptId']),
    ];
    for (final candidate in candidates) {
      if (candidate == null) {
        continue;
      }
      final name = _deptNameByIdCache[candidate];
      if (name != null && name.trim().isNotEmpty) {
        return name.trim();
      }
    }
    return null;
  }

  String? _departmentNameFromObject(Object? value) {
    if (value == null) {
      return null;
    }
    final map = _asMap(value);
    if (map != null && map.isNotEmpty) {
      return _firstNonEmptyText(<String?>[
        _asText(map['name']),
        _asText(map['deptName']),
        _asText(map['fullName']),
        _asText(map['orgName']),
        _asText(map['tenantName']),
        _departmentNameFromObject(map['dept']),
        _departmentNameFromObject(map['department']),
        _departmentNameFromObject(map['org']),
        _departmentNameFromObject(map['tenant']),
        _departmentNameFromObject(map['street']),
      ]);
    }
    if (value is List) {
      for (final item in value) {
        final text = _departmentNameFromObject(item);
        if (text != null) {
          return text;
        }
      }
      return null;
    }
    if (value is String || value is num || value is bool) {
      return _asText(value);
    }
    return null;
  }

  String? _firstNonEmptyText(List<String?> values) {
    for (final value in values) {
      final text = value?.trim();
      if (text != null && text.isNotEmpty && text != 'null') {
        return text;
      }
    }
    return null;
  }

  String _stageFromStatusCode(int statusCode) {
    switch (statusCode) {
      case 2:
        return '\u5DF2\u529E\u7ED3';
      case 1:
        return '\u5904\u7406\u4E2D';
      default:
        return '\u5DF2\u4E0A\u62A5';
    }
  }

  String _fallbackLevelName(int? code) {
    switch (code) {
      case 0:
        return '\u4E00\u822C\u4EE5\u4E0B IV \u7EA7';
      case 1:
        return '\u8F83\u5927 III \u7EA7';
      case 2:
        return '\u91CD\u5927 II \u7EA7';
      case 3:
        return '\u7279\u522B\u91CD\u5927 I \u7EA7';
      default:
        return '--';
    }
  }

  EventAttachmentPayload? _firstAttachment(Object? value) {
    final attachments = _extractAttachments(value);
    if (attachments.isEmpty) {
      return null;
    }
    for (final item in attachments) {
      if (item.path.trim().isNotEmpty) {
        return item;
      }
    }
    return null;
  }

  List<EventAttachmentPayload> _attachmentsFromAny(
    Map<String, dynamic> source,
  ) {
    final result = <EventAttachmentPayload>[];
    final unique = <String>{};

    void appendAll(List<EventAttachmentPayload> items) {
      for (final item in items) {
        final name = item.name.trim();
        final path = item.path.trim();
        final type = (item.type ?? '').trim();
        final key = '${item.id ?? ''}|$name|$path|$type';
        if (name.isEmpty && path.isEmpty) {
          continue;
        }
        if (unique.add(key)) {
          result.add(
            EventAttachmentPayload(
              id: item.id,
              name: name.isEmpty
                  ? (_extractNameFromPath(path) ?? 'attachment')
                  : name,
              path: path,
              type: type.isEmpty ? null : type,
            ),
          );
        }
      }
    }

    final candidates = <Object?>[
      source['attachmentUrls'],
      source['attachmentUrl'],
      source['attachments'],
      source['attachment'],
      source['fileList'],
      source['files'],
    ];
    for (final candidate in candidates) {
      appendAll(_extractAttachments(candidate));
    }

    if (result.isNotEmpty) {
      return List<EventAttachmentPayload>.unmodifiable(result);
    }

    final direct = _firstAttachmentFromAny(source);
    if (direct != null) {
      return List<EventAttachmentPayload>.unmodifiable(<EventAttachmentPayload>[
        direct,
      ]);
    }
    return const <EventAttachmentPayload>[];
  }

  EventAttachmentPayload? _firstAttachmentFromAny(Map<String, dynamic> source) {
    final candidates = <Object?>[
      source['attachmentUrls'],
      source['attachmentUrl'],
      source['attachments'],
      source['attachment'],
      source['fileList'],
      source['files'],
    ];
    for (final candidate in candidates) {
      final attachment = _firstAttachment(candidate);
      if (attachment != null) {
        return attachment;
      }
    }

    final directPath =
        _asText(source['attachmentPath']) ??
        _asText(source['attachmentUrl']) ??
        _asText(source['filePath']) ??
        _asText(source['fileUrl']) ??
        _asText(source['downloadUrl']) ??
        _asText(source['uploadUrl']) ??
        _asText(source['url']) ??
        _asText(source['path']) ??
        _asText(source['attachmentUrls']);
    final directName =
        _asText(source['attachmentName']) ??
        _asText(source['fileName']) ??
        _extractNameFromPath(directPath);
    final directType =
        _asText(source['attachmentType']) ??
        _asText(source['fileType']) ??
        _asText(source['mimeType']) ??
        _asText(source['type']);
    final safePath = _normalizeAttachmentPath(directPath);
    final safeName = directName?.trim();
    final hasPath = safePath.isNotEmpty;
    if (hasPath) {
      final resolvedName = (safeName != null && safeName.isNotEmpty)
          ? safeName
          : (_extractNameFromPath(safePath) ?? 'attachment');
      return EventAttachmentPayload(
        name: resolvedName,
        path: safePath,
        type: directType?.trim(),
      );
    }

    final extraInfoRaw = _asText(source['extraInfo']);
    if (extraInfoRaw != null && extraInfoRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(extraInfoRaw);
        final map = _asMap(decoded);
        if (map != null) {
          return _firstAttachmentFromAny(map);
        }
      } catch (_) {}
    }
    return null;
  }

  String? _firstAttachmentName(Object? value) {
    final attachments = _extractAttachments(value);
    if (attachments.isEmpty) {
      return null;
    }
    for (final item in attachments) {
      final name = item.name.trim();
      if (name.isNotEmpty) {
        return name;
      }
      final path = item.path.trim();
      if (path.isNotEmpty) {
        final uri = Uri.tryParse(path);
        if (uri != null && uri.pathSegments.isNotEmpty) {
          return uri.pathSegments.last;
        }
        final parts = path.split('/');
        if (parts.isNotEmpty) {
          return parts.last;
        }
      }
    }
    return null;
  }

  List<EventAttachmentPayload> _extractAttachments(Object? value) {
    final source = _asMapList(value);
    if (source.isEmpty) {
      if (value is List) {
        final fromStringList = <EventAttachmentPayload>[];
        for (final item in value) {
          final path = _normalizeAttachmentPath(_asText(item));
          if (path.isEmpty) {
            continue;
          }
          fromStringList.add(
            EventAttachmentPayload(
              name: _extractNameFromPath(path) ?? 'attachment',
              path: path,
            ),
          );
        }
        if (fromStringList.isNotEmpty) {
          return List<EventAttachmentPayload>.unmodifiable(fromStringList);
        }
      }
      final singlePath = _normalizeAttachmentPath(_asText(value));
      if (singlePath.isEmpty) {
        return const <EventAttachmentPayload>[];
      }
      return List<EventAttachmentPayload>.unmodifiable(<EventAttachmentPayload>[
        EventAttachmentPayload(
          name: _extractNameFromPath(singlePath) ?? 'attachment',
          path: singlePath,
        ),
      ]);
    }
    final result = <EventAttachmentPayload>[];
    for (final item in source) {
      final path = _normalizeAttachmentPath(
        _asText(item['path']) ??
            _asText(item['filePath']) ??
            _asText(item['fileUrl']) ??
            _asText(item['attachmentPath']) ??
            _asText(item['attachmentUrl']) ??
            _asText(item['downloadUrl']) ??
            _asText(item['url']) ??
            _asText(item['uploadUrl']),
      );
      if (path.isEmpty) {
        continue;
      }
      final name =
          _asText(item['name']) ?? _extractNameFromPath(path) ?? 'attachment';
      result.add(
        EventAttachmentPayload(
          id: _asInt(item['id']),
          name: name,
          path: path,
          type: _asText(item['type']),
        ),
      );
    }
    return List<EventAttachmentPayload>.unmodifiable(result);
  }

  String _normalizeAttachmentPath(String? rawPath) {
    final text = rawPath?.trim() ?? '';
    if (text.isEmpty || text == 'null') {
      return '';
    }
    final normalized = text.replaceAll('\\', '/');
    final lower = normalized.toLowerCase();
    if (lower.startsWith('/uploadfile/upload/')) {
      return '/uploadFile/${normalized.substring('/uploadFile/upload/'.length)}';
    }
    if (lower.startsWith('uploadfile/upload/')) {
      return 'uploadFile/${normalized.substring('uploadFile/upload/'.length)}';
    }
    return normalized;
  }

  Future<void> _ensureStreetDeptCacheLoaded(ApiClient apiClient) async {
    if (_deptNameByIdCache.isNotEmpty) {
      return;
    }
    try {
      final rows = await _loadStreetDeptRows(apiClient);
      if (rows.isEmpty) {
        return;
      }
      final flattened = _flattenDeptRows(rows);
      for (final row in flattened) {
        final id =
            _asInt(row['id']) ?? _asInt(row['deptId']) ?? _asInt(row['value']);
        final name = _firstNonEmptyText(<String?>[
          _asText(row['name']),
          _asText(row['deptName']),
          _asText(row['fullName']),
          _asText(row['label']),
          _asText(row['title']),
        ]);
        if (id == null || name == null) {
          continue;
        }
        _deptNameByIdCache.putIfAbsent(id, () => name);
      }
    } catch (_) {}
  }

  Future<void> _ensureEventTypeCacheLoaded(ApiClient apiClient) async {
    if (_eventTypeNameByValueCache.isNotEmpty) {
      return;
    }
    try {
      final response = await apiClient.getJson(AppConstants.dictDataSimpleListPath);
      final code = _asInt(response['code']) ?? -1;
      if (code != 0) {
        return;
      }
      final rows = _asMapList(response['data']);
      for (final row in rows) {
        final dictType = _asText(row['dictType']) ?? '';
        if (dictType != 'event_type') {
          continue;
        }
        final value = _asText(row['value']);
        final label = _asText(row['label']);
        if (value == null || label == null) {
          continue;
        }
        _eventTypeNameByValueCache.putIfAbsent(value, () => label);
      }
    } catch (_) {}
  }

  String? _eventTypeLabelByRawValue(Object? rawValue) {
    final value = _asText(rawValue);
    if (value == null) {
      return null;
    }
    final direct = _eventTypeNameByValueCache[value];
    if (direct != null && direct.trim().isNotEmpty) {
      return direct;
    }
    final numeric = _asInt(rawValue);
    if (numeric == null) {
      return null;
    }
    return _eventTypeNameByValueCache[numeric.toString()];
  }

  Future<List<Map<String, dynamic>>> _loadStreetDeptRows(ApiClient apiClient) async {
    final candidateTypes = <String>['street', 'jd', '1', '2', '3', '4'];
    final queries = <Map<String, dynamic>>[];
    final seenQueries = <String>{};
    for (final candidate in candidateTypes) {
      for (final key in <String>['type', 'deptType']) {
        final signature = '$key=$candidate';
        if (!seenQueries.add(signature)) {
          continue;
        }
        queries.add(<String, dynamic>{key: candidate});
      }
    }

    for (final path in <String>[
      AppConstants.deptListByTypePath,
      AppConstants.deptListByTypeCompatPath,
    ]) {
      for (final query in queries) {
        try {
          final response = await apiClient.getJson(
            path,
            queryParameters: query,
          );
          final code = _asInt(response['code']) ?? -1;
          if (code != 0) {
            continue;
          }
          final rows = _deptRowsFromData(response['data']);
          if (rows.isNotEmpty) {
            return rows;
          }
        } catch (_) {}
      }
    }

    try {
      final response = await apiClient.getJson(AppConstants.deptSimpleListPath);
      final code = _asInt(response['code']) ?? -1;
      if (code == 0) {
        return _deptRowsFromData(response['data']);
      }
    } catch (_) {}
    return const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _deptRowsFromData(Object? data) {
    final directRows = _asMapList(data);
    if (directRows.isNotEmpty) {
      return directRows;
    }

    final dataMap = _asMap(data);
    if (dataMap == null || dataMap.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    for (final key in <String>['list', 'rows', 'items', 'records', 'data']) {
      final rows = _asMapList(dataMap[key]);
      if (rows.isNotEmpty) {
        return rows;
      }
    }
    return const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _flattenDeptRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final result = <Map<String, dynamic>>[];
    void walk(Map<String, dynamic> row) {
      result.add(row);
      for (final key in <String>[
        'children',
        'childList',
        'deptList',
        'subDepts',
        'nodes',
      ]) {
        final children = _asMapList(row[key]);
        for (final child in children) {
          walk(child);
        }
      }
    }

    for (final row in rows) {
      walk(row);
    }
    return result;
  }

  String? _extractNameFromPath(String? path) {
    final text = path?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(text);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    final parts = text.split('/');
    if (parts.isEmpty) {
      return null;
    }
    return parts.last.trim().isEmpty ? null : parts.last.trim();
  }

  String? _extractReceiverNames(String? extraInfoRaw) {
    if (extraInfoRaw == null || extraInfoRaw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(extraInfoRaw);
      if (decoded is Map<String, dynamic>) {
        final value = _asText(decoded['receiverNames']);
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }
      if (decoded is Map) {
        final value = _asText(decoded['receiverNames']);
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }
    } catch (_) {}
    return null;
  }

  DateTime? _parseDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is num) {
      return _fromEpoch(value.toDouble());
    }

    final raw = _asText(value);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final numeric = num.tryParse(raw);
    if (numeric != null) {
      final parsed = _fromEpoch(numeric.toDouble());
      if (parsed != null) {
        return parsed;
      }
    }
    return DateTime.tryParse(raw);
  }

  DateTime? _fromEpoch(double raw) {
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

  List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map(
            (item) => item.map((key, data) => MapEntry(key.toString(), data)),
          )
          .toList(growable: false);
    }
    if (value is Map) {
      return <Map<String, dynamic>>[
        value.map((key, data) => MapEntry(key.toString(), data)),
      ];
    }
    if (value is String) {
      final raw = value.trim();
      if (raw.isEmpty) {
        return const <Map<String, dynamic>>[];
      }
      try {
        final decoded = jsonDecode(raw);
        return _asMapList(decoded);
      } catch (_) {
        return const <Map<String, dynamic>>[];
      }
    }
    return const <Map<String, dynamic>>[];
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
