import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/network/api_client.dart';

class FormOption {
  const FormOption({required this.value, required this.label});

  final String value;
  final String label;
}

class FormOptionService {
  FormOptionService._();

  static final FormOptionService instance = FormOptionService._();

  List<Map<String, dynamic>>? _dictRowsCache;

  Future<List<FormOption>> loadDictOptions(
    ApiClient apiClient, {
    required String dictType,
  }) async {
    if (dictType.trim().isEmpty) {
      return const <FormOption>[];
    }

    final rows = await _loadDictRows(apiClient);
    final normalizedType = dictType.trim();
    final options = <FormOption>[];
    final seenValues = <String>{};

    for (final row in rows) {
      final currentType = _asText(row['dictType']);
      if (currentType != normalizedType) {
        continue;
      }
      final value = _asText(row['value']);
      final label = _asText(row['label']);
      if (value == null || label == null || seenValues.contains(value)) {
        continue;
      }
      seenValues.add(value);
      options.add(FormOption(value: value, label: label));
    }

    return options;
  }

  Future<List<FormOption>> loadDeptOptions(
    ApiClient apiClient, {
    String type = 'street',
  }) async {
    final rows = _flattenDeptRows(await _loadStreetRows(apiClient, type: type));
    final options = <FormOption>[];
    final seenValues = <String>{};

    for (final row in rows) {
      final id =
          _asText(row['id']) ??
          _asText(row['deptId']) ??
          _asText(row['value']);
      final name =
          _asText(row['name']) ??
          _asText(row['deptName']) ??
          _asText(row['fullName']) ??
          _asText(row['label']) ??
          _asText(row['title']);
      if (id == null || name == null || seenValues.contains(id)) {
        continue;
      }
      seenValues.add(id);
      options.add(FormOption(value: id, label: name));
    }

    return options;
  }

  Future<List<FormOption>> loadEventNameOptions(ApiClient apiClient) async {
    final combined = <String, FormOption>{};
    for (final status in <int>[0, 1, 2]) {
      final response = await apiClient.getJson(
        '/admin-api/api/event/report/page',
        queryParameters: <String, dynamic>{
          'pageNo': 1,
          'pageSize': 200,
          'status': status,
        },
      );
      final code = _asInt(response['code']) ?? 0;
      if (code != 0) {
        throw AppException(_asText(response['msg']) ?? '加载关联事件失败');
      }
      final data = _asMap(response['data']);
      final list = _asMapList(data?['list']);
      for (final row in list) {
        final id = _asText(row['id']);
        final name = _asText(row['name']);
        if (id == null || name == null || combined.containsKey(id)) {
          continue;
        }
        combined[id] = FormOption(value: id, label: name);
      }
    }

    return combined.values.toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _loadStreetRows(
    ApiClient apiClient, {
    required String type,
  }) async {
    final normalizedType = type.trim().isEmpty ? 'street' : type.trim();
    final candidateTypes = <String>[
      normalizedType,
      'street',
      'jd',
      '1',
      '2',
      '3',
      '4',
    ];

    final queries = <Map<String, dynamic>>[];
    final seenQueries = <String>{};
    for (final candidate in candidateTypes) {
      final trimmed = candidate.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      for (final key in <String>['type', 'deptType']) {
        final signature = '$key=$trimmed';
        if (!seenQueries.add(signature)) {
          continue;
        }
        queries.add(<String, dynamic>{key: trimmed});
      }
    }

    AppException? lastError;

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
          final code = _asInt(response['code']) ?? 0;
          if (code == 0) {
            final rows = _asDeptRowsFromData(response['data']);
            if (rows.isNotEmpty) {
              return rows;
            }
            continue;
          }
          lastError = AppException(_asText(response['msg']) ?? '加载街道列表失败');
        } on AppException catch (error) {
          lastError = error;
        }
      }
    }

    try {
      final response = await apiClient.getJson(AppConstants.deptSimpleListPath);
      final code = _asInt(response['code']) ?? 0;
      if (code == 0) {
        final rows = _asDeptRowsFromData(response['data']);
        if (rows.isNotEmpty) {
          return rows;
        }
        return const <Map<String, dynamic>>[];
      }
      lastError = AppException(_asText(response['msg']) ?? '加载街道列表失败');
    } on AppException catch (error) {
      lastError = error;
    }

    throw lastError;
  }

  List<Map<String, dynamic>> _asDeptRowsFromData(Object? data) {
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

  Future<List<Map<String, dynamic>>> _loadDictRows(ApiClient apiClient) async {
    final cached = _dictRowsCache;
    if (cached != null) {
      return cached;
    }

    final response = await apiClient.getJson(
      AppConstants.dictDataSimpleListPath,
    );
    final code = _asInt(response['code']) ?? 0;
    if (code != 0) {
      throw AppException(_asText(response['msg']) ?? '加载字典数据失败');
    }
    final rows = _asMapList(response['data']);
    _dictRowsCache = rows;
    return rows;
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
    if (value is List) {
      return value
          .whereType<Map>()
          .map(
            (item) => item.map((key, data) => MapEntry(key.toString(), data)),
          )
          .toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
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
}
