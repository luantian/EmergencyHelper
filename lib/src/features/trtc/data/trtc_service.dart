import 'dart:convert';

import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/logging/app_logger.dart';
import 'package:emergency_helper/src/core/network/api_client.dart';

class TrtcService {
  const TrtcService();

  Future<TrtcUserSigInfo> getUserSig(
    ApiClient apiClient, {
    required String userId,
    required int roomId,
    AppLogger? logger,
  }) async {
    final requestQuery = <String, dynamic>{'userId': userId, 'roomId': roomId};
    Object? lastError;

    Future<TrtcUserSigInfo> fetchByMethod(String method) async {
      final normalizedMethod = method.toUpperCase();
      _logTrtcApi(
        logger,
        stage: 'request',
        method: normalizedMethod,
        path: AppConstants.trtcUserSigPath,
        queryParameters: requestQuery,
      );
      final response = normalizedMethod == 'POST'
          ? await apiClient.postJson(
              AppConstants.trtcUserSigPath,
              queryParameters: requestQuery,
            )
          : await apiClient.getJson(
              AppConstants.trtcUserSigPath,
              queryParameters: requestQuery,
            );
      _logTrtcApi(
        logger,
        stage: 'response',
        method: normalizedMethod,
        path: AppConstants.trtcUserSigPath,
        queryParameters: requestQuery,
        response: response,
      );
      final data = _expectSuccessAndData(
        response,
        fallbackMessage: '获取 TRTC 用户签名失败',
        endpoint: AppConstants.trtcUserSigPath,
      );
      final parsed = _parseUserSigInfoFromResponseData(data);
      if (parsed == null) {
        throw AppException('TRTC 用户签名数据为空');
      }
      return TrtcUserSigInfo(
        sdkAppId: parsed.sdkAppId,
        userId: _isUsableUserId(parsed.userId) ? parsed.userId : userId,
        userSig: parsed.userSig,
        roomId: parsed.roomId > 0 ? parsed.roomId : roomId,
      );
    }

    try {
      return await fetchByMethod('GET');
    } catch (error) {
      lastError = error;
    }

    try {
      return await fetchByMethod('POST');
    } catch (error) {
      lastError = error;
    }

    if (lastError is AppException) {
      throw lastError;
    }
    throw AppException('获取 TRTC 用户签名失败');
  }

  Future<bool> verifyUserSig(
    ApiClient apiClient, {
    required String userId,
    required String userSig,
    AppLogger? logger,
  }) async {
    final requestQuery = <String, dynamic>{
      'userId': userId,
      'userSig': userSig,
      'userSigLength': userSig.length,
    };
    _logTrtcApi(
      logger,
      stage: 'request',
      method: 'POST',
      path: AppConstants.trtcVerifySigPath,
      queryParameters: requestQuery,
    );
    final response = await apiClient.postJson(
      AppConstants.trtcVerifySigPath,
      queryParameters: requestQuery,
    );
    _logTrtcApi(
      logger,
      stage: 'response',
      method: 'POST',
      path: AppConstants.trtcVerifySigPath,
      queryParameters: requestQuery,
      response: response,
    );
    final data = _expectSuccessAndData(
      response,
      fallbackMessage: '校验 TRTC 用户签名失败',
      endpoint: AppConstants.trtcVerifySigPath,
    );
    if (data is bool) {
      return data;
    }
    if (data is num) {
      return data.toInt() != 0;
    }
    if (data is String) {
      final normalized = data.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    final map = _asMap(data);
    if (map != null && map.isNotEmpty) {
      final directCandidates = <Object?>[
        map['valid'],
        map['isValid'],
        map['verifyOk'],
        map['passed'],
        map['result'],
      ];
      for (final candidate in directCandidates) {
        if (candidate is bool) {
          return candidate;
        }
        if (candidate is num) {
          return candidate.toInt() != 0;
        }
        if (candidate is String) {
          final normalized = candidate.trim().toLowerCase();
          if (normalized == 'true' || normalized == '1') {
            return true;
          }
          if (normalized == 'false' || normalized == '0') {
            return false;
          }
        }
      }
    }
    return false;
  }

  Future<List<TrtcCallRecord>> getCallRecords(
    ApiClient apiClient, {
    required int userId,
  }) async {
    final response = await apiClient.getJson(
      AppConstants.trtcCallRecordsPath,
      queryParameters: <String, dynamic>{'userId': userId},
    );
    final data = _expectSuccessAndData(
      response,
      fallbackMessage: '获取 TRTC 通话记录失败',
      endpoint: AppConstants.trtcCallRecordsPath,
    );
    return _asMapList(data).map(TrtcCallRecord.fromMap).toList(growable: false);
  }

  Future<TrtcCallRecordPageResult> getCallRecordPage(
    ApiClient apiClient, {
    required int userId,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final response = await apiClient.getJson(
      AppConstants.trtcCallRecordsPagePath,
      queryParameters: <String, dynamic>{
        'userId': userId,
        'pageNum': pageNum,
        'pageSize': pageSize,
      },
    );
    final data = _expectSuccessAndData(
      response,
      fallbackMessage: '获取 TRTC 通话记录失败',
      endpoint: AppConstants.trtcCallRecordsPagePath,
    );
    final map = _asMap(data);
    if (map == null || map.isEmpty) {
      return const TrtcCallRecordPageResult(total: 0, list: <TrtcCallRecord>[]);
    }
    final total = _asInt(map['total']) ?? 0;
    final list = _asMapList(
      map['list'],
    ).map(TrtcCallRecord.fromMap).toList(growable: false);
    return TrtcCallRecordPageResult(total: total, list: list);
  }

  String? extractCurrentUserId(Map<String, dynamic>? sessionInfo) {
    if (sessionInfo == null || sessionInfo.isEmpty) {
      return null;
    }
    final permissionInfo = _asMap(sessionInfo['permissionInfo']) ?? sessionInfo;
    final permissionData = _asMap(permissionInfo['data']) ?? permissionInfo;
    final profileInfo = _asMap(sessionInfo['profileInfo']);
    final profileData = _asMap(profileInfo?['data']) ?? profileInfo;

    final candidates = <Map<String, dynamic>?>[
      _asMap(permissionData['user']),
      _asMap(permissionInfo['user']),
      _asMap(sessionInfo['user']),
      _asMap(profileData?['user']),
      profileData,
      permissionData,
      permissionInfo,
      sessionInfo,
    ];

    for (final candidate in candidates) {
      if (candidate == null || candidate.isEmpty) {
        continue;
      }
      final userId =
          _asText(candidate['id']) ??
          _asText(candidate['userId']) ??
          _asText(candidate['uid']);
      if (userId != null && userId.isNotEmpty) {
        return userId;
      }
    }
    return null;
  }

  Object? _expectSuccessAndData(
    Map<String, dynamic> response, {
    required String fallbackMessage,
    String? endpoint,
  }) {
    final code = _asInt(response['code']) ?? 0;
    if (code != 0) {
      final message = _asText(response['msg']);
      if (message == null) {
        throw AppException(fallbackMessage);
      }
      final normalized = message.replaceAll(' ', '');
      if (normalized == '系统异常' || normalized == '系统错误') {
        final endpointSuffix = endpoint == null ? '' : '，接口：$endpoint';
        throw AppException('$fallbackMessage（服务端返回“系统异常”$endpointSuffix）');
      }
      throw AppException(message);
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

  TrtcUserSigInfo? _parseUserSigInfoFromResponseData(Object? data) {
    final direct = _asMap(data);
    if (direct == null || direct.isEmpty) {
      return null;
    }

    final candidates = <Map<String, dynamic>>[direct];
    for (final key in <String>[
      'userSigInfo',
      'user_sig_info',
      'result',
      'data',
      'payload',
    ]) {
      final nested = _asMap(direct[key]);
      if (nested != null && nested.isNotEmpty) {
        candidates.add(nested);
      }
    }

    for (final candidate in candidates) {
      final parsed = TrtcUserSigInfo.fromMap(candidate);
      if (parsed.sdkAppId > 0 &&
          parsed.userSig.trim().isNotEmpty &&
          parsed.userId.trim().isNotEmpty) {
        return parsed;
      }
    }
    return null;
  }

  void _logTrtcApi(
    AppLogger? logger, {
    required String stage,
    required String method,
    required String path,
    Map<String, dynamic>? queryParameters,
    Object? body,
    Map<String, dynamic>? response,
  }) {
    if (logger == null) {
      return;
    }
    final payload = <String, dynamic>{
      'stage': stage,
      'method': method,
      'url': '${AppConstants.apiBaseUrl}$path',
      'query': queryParameters,
      'body': body,
      'response': response,
    };
    logger.info('[TRTC_API] ${jsonEncode(payload)}');
  }
}

class TrtcUserSigInfo {
  const TrtcUserSigInfo({
    required this.sdkAppId,
    required this.userId,
    required this.userSig,
    required this.roomId,
  });

  factory TrtcUserSigInfo.fromMap(Map<String, dynamic> map) {
    Object? pick(List<String> keys) {
      for (final key in keys) {
        final value = map[key];
        if (value != null) {
          return value;
        }
      }
      return null;
    }

    return TrtcUserSigInfo(
      sdkAppId:
          _toInt(
            pick(<String>['sdkAppId', 'sdkAppID', 'SDKAppID', 'sdkappid']),
          ) ??
          0,
      userId:
          _toText(
            pick(<String>['userId', 'userID', 'uid', 'user_id', 'userid']),
          ) ??
          '',
      userSig:
          _toText(
            pick(<String>['userSig', 'userSIG', 'user_sig', 'usersig']),
          ) ??
          '',
      roomId: _toInt(pick(<String>['roomId', 'roomID', 'room_id'])) ?? 0,
    );
  }

  final int sdkAppId;
  final String userId;
  final String userSig;
  final int roomId;
}

class TrtcCallRecordPageResult {
  const TrtcCallRecordPageResult({required this.total, required this.list});

  final int total;
  final List<TrtcCallRecord> list;
}

class TrtcCallRecord {
  const TrtcCallRecord({
    required this.id,
    required this.roomId,
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.calleeId,
    required this.calleeName,
    required this.callType,
    required this.mediaType,
    required this.status,
    required this.startTime,
    required this.connectTime,
    required this.endTime,
    required this.duration,
    required this.endReason,
    required this.createTime,
  });

  factory TrtcCallRecord.fromMap(Map<String, dynamic> map) {
    return TrtcCallRecord(
      id: _toInt(map['id']) ?? 0,
      roomId: _toInt(map['roomId']) ?? 0,
      callId: _toText(map['callId']) ?? '',
      callerId: _toInt(map['callerId']) ?? 0,
      callerName: _toText(map['callerName']) ?? '--',
      calleeId: _toInt(map['calleeId']) ?? 0,
      calleeName: _toText(map['calleeName']) ?? '--',
      callType: _toInt(map['callType']) ?? 0,
      mediaType: _toInt(map['mediaType']) ?? 0,
      status: _toInt(map['status']) ?? 0,
      startTime: _toDateTime(map['startTime']),
      connectTime: _toDateTime(map['connectTime']),
      endTime: _toDateTime(map['endTime']),
      duration: _toInt(map['duration']) ?? 0,
      endReason: _toInt(map['endReason']) ?? 0,
      createTime: _toDateTime(map['createTime']),
    );
  }

  final int id;
  final int roomId;
  final String callId;
  final int callerId;
  final String callerName;
  final int calleeId;
  final String calleeName;
  final int callType;
  final int mediaType;
  final int status;
  final DateTime? startTime;
  final DateTime? connectTime;
  final DateTime? endTime;
  final int duration;
  final int endReason;
  final DateTime? createTime;
}

bool _isUsableUserId(String? value) {
  if (value == null || value.isEmpty) {
    return false;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') {
    return false;
  }
  return true;
}

int? _toInt(Object? value) {
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

String? _toText(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  if (text.isEmpty || text == 'null') {
    return null;
  }
  return text;
}

DateTime? _toDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  if (value is num) {
    return _fromEpoch(value.toDouble());
  }

  final text = _toText(value);
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
  return DateTime.tryParse(normalized);
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
