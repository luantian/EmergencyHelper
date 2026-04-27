import 'dart:async';

import 'package:dio/dio.dart';
import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/logging/app_logger.dart';

class ApiAuthExpiredEvent {
  const ApiAuthExpiredEvent({
    required this.path,
    required this.triggeredAt,
    this.httpStatusCode,
    this.businessCode,
    this.message,
  });

  final String path;
  final DateTime triggeredAt;
  final int? httpStatusCode;
  final int? businessCode;
  final String? message;
}

class ApiClient {
  ApiClient({
    required AppLogger logger,
    Future<String?> Function()? tokenProvider,
  }) : _logger = logger,
       _tokenProvider = tokenProvider,
       _dio = Dio(
         BaseOptions(
           baseUrl: AppConstants.apiBaseUrl,
           connectTimeout: const Duration(seconds: 8),
           receiveTimeout: const Duration(seconds: 8),
           sendTimeout: const Duration(seconds: 8),
           contentType: Headers.jsonContentType,
           responseType: ResponseType.json,
         ),
       );

  static const String _authExpiredMessage =
      '\u767B\u5F55\u72B6\u6001\u5DF2\u5931\u6548\uFF0C\u8BF7\u91CD\u65B0\u767B\u5F55';
  static const String _authExpiredCancelReason = 'AUTH_EXPIRED_FORCE_LOGOUT';

  final Dio _dio;
  final AppLogger _logger;
  final Future<String?> Function()? _tokenProvider;
  final StreamController<ApiAuthExpiredEvent> _authExpiredController =
      StreamController<ApiAuthExpiredEvent>.broadcast();
  final Set<CancelToken> _activeCancelTokens = <CancelToken>{};

  Future<bool> Function()? _authStateValidator;
  bool _authExpiredHandled = false;

  Stream<ApiAuthExpiredEvent> get authExpiredStream =>
      _authExpiredController.stream;

  void cancelAllPendingRequests({String reason = 'MANUAL_CANCEL'}) {
    for (final token in _activeCancelTokens.toList(growable: false)) {
      if (!token.isCancelled) {
        token.cancel(reason);
      }
    }
    _activeCancelTokens.clear();
  }

  void setAuthStateValidator(Future<bool> Function() validator) {
    _authStateValidator = validator;
  }

  void resetAuthExpiredState() {
    _authExpiredHandled = false;
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool withAuthorization = true,
  }) {
    return _executeJsonRequest(
      methodLabel: 'GET',
      path: path,
      headers: headers,
      withAuthorization: withAuthorization,
      send: (options, cancelToken) {
        return _dio.get<Map<String, dynamic>>(
          path,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
        );
      },
    );
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool withAuthorization = true,
  }) {
    return _executeJsonRequest(
      methodLabel: 'POST',
      path: path,
      headers: headers,
      withAuthorization: withAuthorization,
      send: (options, cancelToken) {
        return _dio.post<Map<String, dynamic>>(
          path,
          data: data ?? const <String, dynamic>{},
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
        );
      },
    );
  }

  Future<Map<String, dynamic>> postFormData(
    String path, {
    required FormData data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool withAuthorization = true,
  }) {
    return _executeJsonRequest(
      methodLabel: 'POST_FORM',
      path: path,
      headers: headers,
      withAuthorization: withAuthorization,
      optionsTransformer: (baseOptions) {
        return baseOptions.copyWith(
          contentType: Headers.multipartFormDataContentType,
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(seconds: 90),
        );
      },
      send: (options, cancelToken) {
        return _dio.post<Map<String, dynamic>>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
        );
      },
    );
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool withAuthorization = true,
  }) {
    return _executeJsonRequest(
      methodLabel: 'PUT',
      path: path,
      headers: headers,
      withAuthorization: withAuthorization,
      send: (options, cancelToken) {
        return _dio.put<Map<String, dynamic>>(
          path,
          data: data ?? const <String, dynamic>{},
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
        );
      },
    );
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool withAuthorization = true,
  }) {
    return _executeJsonRequest(
      methodLabel: 'DELETE',
      path: path,
      headers: headers,
      withAuthorization: withAuthorization,
      send: (options, cancelToken) {
        return _dio.delete<Map<String, dynamic>>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
        );
      },
    );
  }

  Future<Map<String, dynamic>> _executeJsonRequest({
    required String methodLabel,
    required String path,
    required Future<Response<Map<String, dynamic>>> Function(
      Options options,
      CancelToken cancelToken,
    )
    send,
    Map<String, String>? headers,
    required bool withAuthorization,
    Options Function(Options options)? optionsTransformer,
  }) async {
    final cancelToken = CancelToken();
    _activeCancelTokens.add(cancelToken);
    try {
      final baseOptions = await _buildOptions(
        path,
        headers,
        withAuthorization: withAuthorization,
      );
      final options = optionsTransformer == null
          ? baseOptions
          : optionsTransformer(baseOptions);
      final response = await send(options, cancelToken);
      final payload = response.data ?? <String, dynamic>{};
      if (_shouldTriggerAuthExpiredFromBody(
        payload,
        withAuthorization: withAuthorization,
      )) {
        _triggerAuthExpired(
          path: path,
          httpStatusCode: response.statusCode,
          businessCode: _asInt(payload['code']),
          message: _extractMessageFromData(payload),
        );
        throw AppException(_authExpiredMessage);
      }
      return payload;
    } on DioException catch (error, stackTrace) {
      if (_isAuthExpiredCancellation(error)) {
        throw AppException(_authExpiredMessage, cause: error);
      }
      if (_shouldTriggerAuthExpiredFromDioException(
        error,
        withAuthorization: withAuthorization,
      )) {
        _triggerAuthExpired(
          path: path,
          httpStatusCode: error.response?.statusCode,
          businessCode: _extractCodeFromData(error.response?.data),
          message: _extractMessageFromData(error.response?.data),
        );
        throw AppException(_authExpiredMessage, cause: error);
      }
      _logger.error(
        '$methodLabel $path failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_buildErrorMessage(error), cause: error);
    } on AppException catch (error) {
      if (withAuthorization && _isAuthExpiredMessage(error.message)) {
        _triggerAuthExpired(path: path, message: error.message);
      }
      rethrow;
    } catch (error, stackTrace) {
      _logger.error(
        '$methodLabel $path unexpected failure',
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException('\u8BF7\u6C42\u5904\u7406\u5931\u8D25\uFF1A$error');
    } finally {
      _activeCancelTokens.remove(cancelToken);
    }
  }

  Future<Options> _buildOptions(
    String path,
    Map<String, String>? headers, {
    required bool withAuthorization,
  }) async {
    final mergedHeaders = <String, String>{};
    if (headers != null && headers.isNotEmpty) {
      mergedHeaders.addAll(headers);
    }

    final hasAuthorizationHeader =
        mergedHeaders['authorization']?.trim().isNotEmpty ?? false;
    if (withAuthorization &&
        !hasAuthorizationHeader &&
        _authStateValidator != null) {
      final isValid = await _authStateValidator!();
      if (!isValid) {
        _triggerAuthExpired(path: path, message: _authExpiredMessage);
        throw AppException(_authExpiredMessage);
      }
    }

    if (withAuthorization &&
        !hasAuthorizationHeader &&
        _tokenProvider != null) {
      final token = await _tokenProvider();
      if (token != null && token.trim().isNotEmpty) {
        mergedHeaders['authorization'] = token.trim();
      }
    }

    if (mergedHeaders.isEmpty) {
      return Options();
    }
    return Options(headers: mergedHeaders);
  }

  bool _shouldTriggerAuthExpiredFromBody(
    Map<String, dynamic> payload, {
    required bool withAuthorization,
  }) {
    if (!withAuthorization) {
      return false;
    }
    return _isUnauthorizedBusinessResponse(payload);
  }

  bool _shouldTriggerAuthExpiredFromDioException(
    DioException error, {
    required bool withAuthorization,
  }) {
    if (!withAuthorization) {
      return false;
    }
    if (error.response?.statusCode == 401) {
      return true;
    }
    final data = _toJsonMap(error.response?.data);
    if (data != null && _isUnauthorizedBusinessResponse(data)) {
      return true;
    }
    return false;
  }

  bool _isUnauthorizedBusinessResponse(Map<String, dynamic> payload) {
    final code = _asInt(payload['code']);
    if (code == 401) {
      return true;
    }
    if (code == null || code == 0) {
      return false;
    }
    final message = _extractMessageFromData(payload);
    if (message == null || message.trim().isEmpty) {
      return false;
    }
    return _isAuthExpiredMessage(message);
  }

  bool _isAuthExpiredCancellation(DioException error) {
    if (error.type != DioExceptionType.cancel) {
      return false;
    }
    final reasonText =
        '${error.message ?? ''} ${error.error ?? ''}'.toLowerCase();
    return reasonText.contains(_authExpiredCancelReason.toLowerCase());
  }

  void _triggerAuthExpired({
    required String path,
    int? httpStatusCode,
    int? businessCode,
    String? message,
  }) {
    if (_authExpiredHandled) {
      return;
    }
    _authExpiredHandled = true;
    for (final token in _activeCancelTokens.toList(growable: false)) {
      if (!token.isCancelled) {
        token.cancel(_authExpiredCancelReason);
      }
    }
    final event = ApiAuthExpiredEvent(
      path: path,
      triggeredAt: DateTime.now(),
      httpStatusCode: httpStatusCode,
      businessCode: businessCode,
      message: message,
    );
    _logger.info(
      'auth expired detected: path=$path, '
      'httpStatusCode=${httpStatusCode ?? "-"}, '
      'businessCode=${businessCode ?? "-"}, '
      'message=${message ?? "-"}',
    );
    if (!_authExpiredController.isClosed) {
      _authExpiredController.add(event);
    }
  }

  bool _isAuthExpiredMessage(String text) {
    final raw = text.trim();
    if (raw.isEmpty) {
      return false;
    }
    if (raw.contains('\u672A\u767B\u5F55') ||
        raw.contains('\u767B\u5F55\u72B6\u6001\u5DF2\u5931\u6548') ||
        raw.contains('\u767B\u5F55\u5DF2\u8FC7\u671F') ||
        raw.contains('token\u5DF2\u5931\u6548') ||
        raw.contains('token\u8FC7\u671F')) {
      return true;
    }
    final normalized = raw.toLowerCase();
    return normalized.contains('unauthorized') ||
        normalized.contains('jwt expired') ||
        normalized.contains('token expired') ||
        normalized.contains('invalid token') ||
        normalized.contains('access token expired');
  }

  String _buildErrorMessage(DioException error) {
    if (_isAuthExpiredCancellation(error)) {
      return _authExpiredMessage;
    }
    final message = _extractMessageFromData(error.response?.data);
    if (message != null && message.trim().isNotEmpty) {
      return message;
    }
    final statusCode = error.response?.statusCode;
    if (statusCode != null) {
      return '\u7F51\u7EDC\u8BF7\u6C42\u5931\u8D25\uFF08HTTP $statusCode\uFF09';
    }
    if (error.type == DioExceptionType.cancel) {
      return '\u8BF7\u6C42\u5DF2\u53D6\u6D88';
    }
    return '\u7F51\u7EDC\u8BF7\u6C42\u5931\u8D25\uFF0C\u8BF7\u7A0D\u540E\u91CD\u8BD5';
  }

  int? _extractCodeFromData(Object? data) {
    final map = _toJsonMap(data);
    if (map == null) {
      return null;
    }
    return _asInt(map['code']);
  }

  String? _extractMessageFromData(Object? data) {
    final map = _toJsonMap(data);
    if (map == null) {
      return null;
    }
    final candidates = <Object?>[
      map['msg'],
      map['message'],
      map['errorMsg'],
      map['errorMessage'],
    ];
    for (final candidate in candidates) {
      if (candidate is String) {
        final text = candidate.trim();
        if (text.isNotEmpty) {
          return text;
        }
      }
    }
    return null;
  }

  Map<String, dynamic>? _toJsonMap(Object? value) {
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

  void dispose() {
    for (final token in _activeCancelTokens.toList(growable: false)) {
      if (!token.isCancelled) {
        token.cancel('API_CLIENT_DISPOSED');
      }
    }
    _activeCancelTokens.clear();
    _authExpiredController.close();
    _dio.close(force: true);
  }
}
