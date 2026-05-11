import 'dart:async';

import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/core/widgets/app_empty_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_baidu_mapapi_base/flutter_baidu_mapapi_base.dart';
import 'package:flutter_baidu_mapapi_map/flutter_baidu_mapapi_map.dart';
import 'package:provider/provider.dart';

class KeyPointPage extends StatefulWidget {
  const KeyPointPage({super.key});

  @override
  State<KeyPointPage> createState() => _KeyPointPageState();
}

class _KeyPointPageState extends State<KeyPointPage> {
  static final BMFCoordinate _fallbackCenter = BMFCoordinate(41.8159, 123.4298);
  static const EdgeInsets _mapInsets = EdgeInsets.fromLTRB(36, 108, 36, 372);
  static const double _selectedSiteZoom = 16.8;
  static const String _markerAssetPath = 'assets/images/marker.png';

  static const String _statusActive = '\u5728\u7528';
  static const String _statusReserve = '\u50A8\u5907';

  static final Map<_KeyPointCategory, List<_KeyPointSite>> _dataByCategory =
      <_KeyPointCategory, List<_KeyPointSite>>{
        _KeyPointCategory.shelter: <_KeyPointSite>[
          _KeyPointSite(
            index: 1,
            name: '\u5E02\u4F53\u80B2\u4E2D\u5FC3\u907F\u96BE\u573A',
            area: 95108,
            capacity: 63000,
            status: _statusActive,
            latitude: 41.81548,
            longitude: 123.43002,
          ),
          _KeyPointSite(
            index: 2,
            name: '\u5317\u9675\u516C\u56ED\u5E7F\u573A',
            area: 6000,
            capacity: 4000,
            status: _statusActive,
            latitude: 41.81678,
            longitude: 123.42695,
          ),
          _KeyPointSite(
            index: 3,
            name: '\u548C\u5E73\u6587\u5316\u5BAB\u907F\u96BE\u70B9',
            area: 6500,
            capacity: 4300,
            status: _statusReserve,
            latitude: 41.81835,
            longitude: 123.43286,
          ),
          _KeyPointSite(
            index: 4,
            name: '120\u5E7F\u573A\u907F\u96BE\u70B9',
            area: 10000,
            capacity: 6666,
            status: _statusActive,
            latitude: 41.81364,
            longitude: 123.43391,
          ),
          _KeyPointSite(
            index: 5,
            name: '\u5357\u5E93\u5317\u5DF7\u907F\u96BE\u70B9',
            area: 30000,
            capacity: 20000,
            status: _statusReserve,
            latitude: 41.81255,
            longitude: 123.42682,
          ),
          _KeyPointSite(
            index: 6,
            name: '\u5317\u7AD9\u4E1C\u5E7F\u573A\u907F\u96BE\u70B9',
            area: 100000,
            capacity: 66000,
            status: _statusActive,
            latitude: 41.82044,
            longitude: 123.43151,
          ),
        ],
        _KeyPointCategory.supplies: <_KeyPointSite>[
          _KeyPointSite(
            index: 1,
            name: '\u5E94\u6025\u7269\u8D44\u4ED3\u5E93A',
            area: 2200,
            capacity: 3200,
            status: _statusReserve,
            latitude: 41.81318,
            longitude: 123.42898,
          ),
          _KeyPointSite(
            index: 2,
            name: '\u5E94\u6025\u7269\u8D44\u4ED3\u5E93B',
            area: 1800,
            capacity: 2600,
            status: _statusActive,
            latitude: 41.81711,
            longitude: 123.43578,
          ),
          _KeyPointSite(
            index: 3,
            name: '\u751F\u6D3B\u7269\u8D44\u50A8\u5907\u70B9',
            area: 1500,
            capacity: 2000,
            status: _statusReserve,
            latitude: 41.81928,
            longitude: 123.42611,
          ),
          _KeyPointSite(
            index: 4,
            name: '\u673A\u68B0\u7269\u8D44\u50A8\u5907\u70B9',
            area: 1300,
            capacity: 1800,
            status: _statusActive,
            latitude: 41.81184,
            longitude: 123.43345,
          ),
        ],
        _KeyPointCategory.community: <_KeyPointSite>[
          _KeyPointSite(
            index: 1,
            name: '\u5317\u90E8\u793E\u533A\u5DE5\u4F5C\u7AD9',
            area: 12000,
            capacity: 8000,
            status: _statusReserve,
            latitude: 41.81878,
            longitude: 123.42453,
          ),
          _KeyPointSite(
            index: 2,
            name: '\u4E1C\u5317\u793E\u533A\u5DE5\u4F5C\u7AD9',
            area: 13200,
            capacity: 8600,
            status: _statusReserve,
            latitude: 41.81502,
            longitude: 123.43728,
          ),
          _KeyPointSite(
            index: 3,
            name: '\u5E73\u5B89\u5FD7\u613F\u670D\u52A1\u7AD9',
            area: 10800,
            capacity: 6900,
            status: _statusActive,
            latitude: 41.81028,
            longitude: 123.42916,
          ),
        ],
        _KeyPointCategory.keyArea: <_KeyPointSite>[
          _KeyPointSite(
            index: 1,
            name: '\u5E73\u5B89\u6CB3\u9053\u91CD\u70B9\u533A\u57DF',
            area: 56000,
            capacity: 32000,
            status: _statusReserve,
            latitude: 41.81799,
            longitude: 123.43069,
          ),
          _KeyPointSite(
            index: 2,
            name: '\u5317\u7AD9\u5317\u5E7F\u573A\u91CD\u70B9\u533A\u57DF',
            area: 42000,
            capacity: 25000,
            status: _statusReserve,
            latitude: 41.81422,
            longitude: 123.43242,
          ),
          _KeyPointSite(
            index: 3,
            name: '\u751F\u6001\u6EE8\u6CB3\u5E26\u91CD\u70B9\u533A\u57DF',
            area: 48000,
            capacity: 29000,
            status: _statusActive,
            latitude: 41.82131,
            longitude: 123.42852,
          ),
        ],
      };

  _KeyPointCategory _category = _KeyPointCategory.shelter;
  _KeyPointSite? _selectedSite;
  BMFMapController? _mapController;
  final List<String> _markerIds = <String>[];
  bool _loadingRemote = false;
  String? _loadError;
  late Map<_KeyPointCategory, List<_KeyPointSite>> _sitesByCategory;
  bool _didApplyInitialCategory = false;
  Uint8List? _markerIconData;

  List<_KeyPointSite> get _currentSites =>
      _sitesByCategory[_category] ?? const <_KeyPointSite>[];

  @override
  void initState() {
    super.initState();
    _sitesByCategory = _cloneSiteMap(_dataByCategory);
    unawaited(_prepareMarkerIcon());
    Future<void>.microtask(_loadSitesFromApi);
  }

  @override
  void dispose() {
    final controller = _mapController;
    if (controller != null) {
      unawaited(controller.cleanAllMarkers());
    }
    _markerIds.clear();
    _mapController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sites = _currentSites;

    return Scaffold(
      key: const Key('key-point-root'),
      appBar: AppBar(
        title: const Text('\u91CD\u70B9\u70B9\u4F4D'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        actions: <Widget>[
          IconButton(
            tooltip: '刷新点位',
            onPressed: _loadingRemote ? null : _loadSitesFromApi,
            icon: _loadingRemote
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF2F3F5),
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: BMFMapWidget(
              onBMFMapCreated: _onMapCreated,
              mapOptions: BMFMapOptions(
                center: _initialCenterForMap(),
                zoomLevel: 15,
                showMapScaleBar: false,
                showZoomControl: true,
              ),
            ),
          ),
          const Positioned(
            left: 2,
            bottom: 2,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.white),
                child: SizedBox(width: 88, height: 22),
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 132,
            child: _MapTools(
              onToggleTap: () {
                _showMessage(
                  '\u56FE\u5C42\u5207\u6362\u529F\u80FD\u6682\u672A\u5F00\u653E',
                );
              },
              onSearchTap: _showSearchPanel,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _PointListPanel(
              sites: sites,
              selectedSiteKey: _selectedSite?.markerKey,
              onSiteTap: _onSiteTapped,
            ),
          ),
          if (_loadingRemote)
            const Positioned(
              left: 8,
              right: 8,
              top: 12,
              child: _LoadBanner(
                icon: Icons.hourglass_top_rounded,
                text: '正在加载重点点位...',
                backgroundColor: Color(0xFFEAF4FF),
                borderColor: Color(0xFFBFD9F7),
                textColor: Color(0xFF1F5E9D),
              ),
            ),
          if ((_loadError ?? '').trim().isNotEmpty)
            Positioned(
              left: 8,
              right: 8,
              top: _loadingRemote ? 52 : 12,
              child: _LoadBanner(
                icon: Icons.info_outline_rounded,
                text: _loadError!,
                backgroundColor: const Color(0xFFFFF6E8),
                borderColor: const Color(0xFFF3CD8D),
                textColor: const Color(0xFF8A5A14),
                actionText: '重试',
                onActionTap: _loadSitesFromApi,
              ),
            ),
        ],
      ),
      bottomNavigationBar: _CategoryBottomBar(
        current: _category,
        onChanged: (next) {
          if (next == _category) {
            return;
          }
          setState(() {
            _category = next;
            _selectedSite = null;
          });
          unawaited(_refreshMarkers(animate: true));
        },
      ),
    );
  }

  BMFCoordinate _initialCenterForMap() {
    final sites = _currentSites;
    if (sites.isEmpty) {
      return _fallbackCenter;
    }
    final first = sites.first;
    return BMFCoordinate(first.latitude, first.longitude);
  }

  void _onMapCreated(BMFMapController controller) {
    _mapController = controller;
    var mapLoaded = false;
    controller.setMapDidLoadCallback(
      callback: () {
        mapLoaded = true;
        unawaited(_refreshMarkers(animate: false));
      },
    );
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (!mounted || _mapController != controller || mapLoaded) {
        return;
      }
      unawaited(_refreshMarkers(animate: false));
    });
  }

  Future<void> _prepareMarkerIcon() async {
    try {
      final bytes = await rootBundle.load(_markerAssetPath);
      _markerIconData = bytes.buffer.asUint8List();
      if (!mounted) {
        return;
      }
      if (_mapController != null) {
        await _refreshMarkers(animate: false);
      }
    } catch (_) {
      _markerIconData = null;
    }
  }

  Map<_KeyPointCategory, List<_KeyPointSite>> _cloneSiteMap(
    Map<_KeyPointCategory, List<_KeyPointSite>> source,
  ) {
    return <_KeyPointCategory, List<_KeyPointSite>>{
      for (final entry in source.entries)
        entry.key: List<_KeyPointSite>.from(entry.value),
    };
  }

  Future<void> _loadSitesFromApi() async {
    if (_loadingRemote) {
      return;
    }
    if (mounted) {
      setState(() {
        _loadingRemote = true;
      });
    }
    final dependencies = context.read<AppDependencies>();
    final apiClient = dependencies.apiClient;
    final logger = dependencies.logger;
    try {
      logger.info(
        '[KeyPoint] request ${AppConstants.emergencyPlacePagePath}'
        ' params={pageNo:-1}',
      );
      final response = await apiClient.getJson(
        AppConstants.emergencyPlacePagePath,
        queryParameters: const <String, dynamic>{'pageNo': -1},
      );
      final code = _asInt(response['code']) ?? -1;
      final message = _asText(response['msg']) ?? '--';
      logger.info(
        '[KeyPoint] response code=$code msg=$message '
        'data=${_describeDataShape(response['data'])}',
      );
      if (code != 0) {
        throw AppException(_asText(response['msg']) ?? '重点点位接口调用失败');
      }
      final rows = _extractRows(response['data']);
      logger.info('[KeyPoint] extracted rows=${rows.length}');
      if (rows.isNotEmpty) {
        logger.info('[KeyPoint] first row keys=${rows.first.keys.join(",")}');
      }
      if (rows.isEmpty) {
        throw AppException('重点点位接口返回空数据');
      }
      final nextSites = _buildSitesByCategory(rows);
      logger.info(
        '[KeyPoint] mapped categories '
        'shelter=${nextSites[_KeyPointCategory.shelter]?.length ?? 0}, '
        'supplies=${nextSites[_KeyPointCategory.supplies]?.length ?? 0}, '
        'community=${nextSites[_KeyPointCategory.community]?.length ?? 0}, '
        'keyArea=${nextSites[_KeyPointCategory.keyArea]?.length ?? 0}',
      );
      final hasAny = nextSites.values.any((sites) => sites.isNotEmpty);
      if (!hasAny) {
        throw AppException('重点点位接口返回数据缺少有效坐标');
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _sitesByCategory = nextSites;
        final firstTab = _KeyPointCategory.values.first;
        if (!_didApplyInitialCategory) {
          if ((nextSites[firstTab] ?? const <_KeyPointSite>[]).isNotEmpty) {
            _category = firstTab;
          } else {
            _category = _firstCategoryWithData(nextSites) ?? firstTab;
          }
          _didApplyInitialCategory = true;
        } else if ((_sitesByCategory[_category] ?? const <_KeyPointSite>[])
            .isEmpty) {
          _category = _firstCategoryWithData(nextSites) ?? _category;
        }
        final selected = _selectedSite;
        if (selected != null &&
            !_currentSites.any(
              (item) => item.markerKey == selected.markerKey,
            )) {
          _selectedSite = null;
        }
        _loadError = null;
      });
      await _refreshMarkers(animate: false);
    } on AppException catch (error) {
      logger.error('[KeyPoint] load api failed: ${error.message}');
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = '${error.message}（已回退本地点位）';
      });
      await _refreshMarkers(animate: false);
    } catch (_) {
      logger.error('[KeyPoint] load api failed: unknown error');
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = '重点点位加载失败（已回退本地点位）';
      });
      await _refreshMarkers(animate: false);
    } finally {
      if (mounted) {
        setState(() {
          _loadingRemote = false;
        });
      }
    }
  }

  String _describeDataShape(Object? data) {
    if (data == null) {
      return 'null';
    }
    if (data is List) {
      return 'List(len=${data.length})';
    }
    final map = _asMap(data);
    if (map != null) {
      final keys = map.keys.take(12).join(',');
      return 'Map(keys=$keys)';
    }
    return data.runtimeType.toString();
  }

  List<Map<String, dynamic>> _extractRows(Object? data) {
    final directRows = _asMapList(data);
    if (directRows.isNotEmpty) {
      return directRows;
    }
    final map = _asMap(data);
    if (map == null || map.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    for (final key in <String>['list', 'rows', 'items', 'records', 'data']) {
      final rows = _asMapList(map[key]);
      if (rows.isNotEmpty) {
        return rows;
      }
      final nested = _asMap(map[key]);
      if (nested != null) {
        for (final nestedKey in <String>[
          'list',
          'rows',
          'items',
          'records',
          'data',
        ]) {
          final nestedRows = _asMapList(nested[nestedKey]);
          if (nestedRows.isNotEmpty) {
            return nestedRows;
          }
        }
      }
    }
    return const <Map<String, dynamic>>[];
  }

  Map<_KeyPointCategory, List<_KeyPointSite>> _buildSitesByCategory(
    List<Map<String, dynamic>> rows,
  ) {
    final buckets = <_KeyPointCategory, List<_KeyPointSite>>{
      for (final category in _KeyPointCategory.values)
        category: <_KeyPointSite>[],
    };
    final counters = <_KeyPointCategory, int>{
      for (final category in _KeyPointCategory.values) category: 0,
    };

    for (final row in rows) {
      final coordinate = _extractCoordinate(row);
      final latitude = coordinate.$1;
      final longitude = coordinate.$2;
      if (latitude == null || longitude == null) {
        continue;
      }
      final name =
          _pickFirstText(<Object?>[
            row['placeName'],
            row['name'],
            row['title'],
            row['pointName'],
            row['siteName'],
            row['pointTitle'],
            row['addressName'],
            row['locationName'],
          ]) ??
          '未命名点位';
      final area =
          _asInt(
            _pickFirstNonNull(<Object?>[
              row['area'],
              row['areaSize'],
              row['coverArea'],
              row['coveredArea'],
              row['siteArea'],
            ]),
          ) ??
          0;
      final capacity =
          _asInt(
            _pickFirstNonNull(<Object?>[
              row['capacity'],
              row['personCount'],
              row['peopleCount'],
              row['maxCapacity'],
              row['maxPeople'],
            ]),
          ) ??
          0;
      final rawStatus =
          _pickFirstText(<Object?>[
            row['statusName'],
            row['status'],
            row['state'],
            row['enableStatus'],
            row['usingStatus'],
          ]) ??
          '';
      final status = _normalizeStatus(rawStatus);
      final category = _resolveCategory(row, name: name, status: rawStatus);
      counters[category] = (counters[category] ?? 0) + 1;
      buckets[category]!.add(
        _KeyPointSite(
          index: counters[category]!,
          name: name,
          area: area,
          capacity: capacity,
          status: status,
          latitude: latitude,
          longitude: longitude,
        ),
      );
    }

    return <_KeyPointCategory, List<_KeyPointSite>>{
      for (final entry in buckets.entries)
        entry.key: List<_KeyPointSite>.unmodifiable(entry.value),
    };
  }

  _KeyPointCategory? _firstCategoryWithData(
    Map<_KeyPointCategory, List<_KeyPointSite>> source,
  ) {
    for (final category in _KeyPointCategory.values) {
      final sites = source[category] ?? const <_KeyPointSite>[];
      if (sites.isNotEmpty) {
        return category;
      }
    }
    return null;
  }

  _KeyPointCategory _resolveCategory(
    Map<String, dynamic> row, {
    required String name,
    required String status,
  }) {
    final raw = _pickFirstText(<Object?>[
      row['placeTypeName'],
      row['placeType'],
      row['typeName'],
      row['type'],
      row['categoryName'],
      row['category'],
      row['pointType'],
      row['siteType'],
      row['kind'],
      name,
      status,
    ]);
    final normalized = (raw ?? '').trim().toLowerCase();
    if (normalized.isEmpty) {
      return _KeyPointCategory.keyArea;
    }
    if (normalized.contains('避难') ||
        normalized.contains('庇护') ||
        normalized.contains('shelter')) {
      return _KeyPointCategory.shelter;
    }
    if (normalized.contains('物资') ||
        normalized.contains('仓') ||
        normalized.contains('supply') ||
        normalized.contains('material') ||
        normalized.contains('inventory')) {
      return _KeyPointCategory.supplies;
    }
    if (normalized.contains('社区') ||
        normalized.contains('志愿') ||
        normalized.contains('community') ||
        normalized.contains('team')) {
      return _KeyPointCategory.community;
    }
    if (normalized.contains('重点') ||
        normalized.contains('区域') ||
        normalized.contains('area')) {
      return _KeyPointCategory.keyArea;
    }

    final numericType = _asInt(
      _pickFirstNonNull(<Object?>[
        row['placeType'],
        row['type'],
        row['category'],
        row['siteType'],
        row['pointType'],
      ]),
    );
    switch (numericType) {
      case 1:
        return _KeyPointCategory.shelter;
      case 2:
        return _KeyPointCategory.supplies;
      case 3:
        return _KeyPointCategory.community;
      case 4:
        return _KeyPointCategory.keyArea;
      default:
        return _KeyPointCategory.keyArea;
    }
  }

  String _normalizeStatus(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return _statusReserve;
    }
    if (normalized.contains('在用') ||
        normalized.contains('启用') ||
        normalized.contains('正常') ||
        normalized.toLowerCase() == 'active') {
      return _statusActive;
    }
    return normalized;
  }

  (double?, double?) _extractCoordinate(Map<String, dynamic> row) {
    final latitude = _asDouble(
      _pickFirstNonNull(<Object?>[
        row['latitude'],
        row['lat'],
        row['y'],
        row['bdLat'],
        row['gcjLat'],
        row['wgsLat'],
      ]),
    );
    final longitude = _asDouble(
      _pickFirstNonNull(<Object?>[
        row['longitude'],
        row['lng'],
        row['lon'],
        row['x'],
        row['bdLng'],
        row['gcjLng'],
        row['wgsLng'],
      ]),
    );
    final normalizedDirect = _normalizeCoordinatePair(latitude, longitude);
    if (normalizedDirect.$1 != null && normalizedDirect.$2 != null) {
      return normalizedDirect;
    }

    for (final key in <String>[
      'point',
      'location',
      'coordinate',
      'coords',
      'position',
    ]) {
      final value = row[key];
      final mapValue = _asMap(value);
      if (mapValue != null) {
        final nested = _extractCoordinate(mapValue);
        if (nested.$1 != null && nested.$2 != null) {
          return nested;
        }
      }
      final text = _asText(value);
      if (text != null) {
        final fromText = _extractCoordinateFromText(text);
        if (fromText.$1 != null && fromText.$2 != null) {
          return fromText;
        }
      }
    }
    return (null, null);
  }

  (double?, double?) _extractCoordinateFromText(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) {
      return (null, null);
    }
    final parts = cleaned.split(RegExp(r'[,，\s]+'));
    if (parts.length < 2) {
      return (null, null);
    }
    final first = _asDouble(parts[0]);
    final second = _asDouble(parts[1]);
    if (first == null || second == null) {
      return (null, null);
    }
    return _normalizeCoordinatePair(first, second);
  }

  (double?, double?) _normalizeCoordinatePair(
    double? latitude,
    double? longitude,
  ) {
    if (latitude == null || longitude == null) {
      return (null, null);
    }
    var lat = latitude;
    var lng = longitude;
    if (lat.abs() > 90 && lng.abs() <= 90) {
      final swapped = lat;
      lat = lng;
      lng = swapped;
    }
    if (lat.abs() > 90 || lng.abs() > 180) {
      return (null, null);
    }
    return (lat, lng);
  }

  Object? _pickFirstNonNull(List<Object?> values) {
    for (final value in values) {
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  String? _pickFirstText(List<Object?> values) {
    for (final value in values) {
      final text = _asText(value);
      if (text != null) {
        return text;
      }
    }
    return null;
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
      final normalized = value.trim().replaceAll(',', '');
      return int.tryParse(normalized);
    }
    return null;
  }

  double? _asDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final normalized = value.trim().replaceAll(',', '');
      return double.tryParse(normalized);
    }
    return null;
  }

  Future<void> _refreshMarkers({required bool animate}) async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }

    final currentSites = _currentSites;
    final selectedSite = _selectedSite;
    final selectedSiteKey = selectedSite?.markerKey;
    var addedMarkerCount = 0;

    await controller.cleanAllMarkers();
    _markerIds.clear();

    for (final site in currentSites) {
      final isSelected = selectedSiteKey == site.markerKey;
      final iconData = _markerIconData;
      final marker = iconData != null
          ? BMFMarker.iconData(
              position: BMFCoordinate(site.latitude, site.longitude),
              iconData: iconData,
              title: site.name,
              canShowCallout: true,
              draggable: false,
              selected: isSelected,
              displayPriority: isSelected
                  ? BMFMarkerDisplayPriority.High
                  : BMFMarkerDisplayPriority.Low,
              scaleX: isSelected ? 1.45 : 1.0,
              scaleY: isSelected ? 1.45 : 1.0,
              alpha: isSelected ? 1.0 : 0.86,
              zIndex: isSelected ? 5 : 0,
            )
          : BMFMarker.icon(
              icon: 'assets/images/marker.png',
              position: BMFCoordinate(site.latitude, site.longitude),
              title: site.name,
              canShowCallout: true,
              draggable: false,
              selected: isSelected,
              displayPriority: isSelected
                  ? BMFMarkerDisplayPriority.High
                  : BMFMarkerDisplayPriority.Low,
              scaleX: isSelected ? 1.45 : 1.0,
              scaleY: isSelected ? 1.45 : 1.0,
              alpha: isSelected ? 1.0 : 0.86,
              zIndex: isSelected ? 5 : 0,
            );
      var success = await controller.addMarker(marker);
      if (!success) {
        final fallbackMarker = BMFMarker.icon(
          icon: 'assets/images/marker.png',
          position: BMFCoordinate(site.latitude, site.longitude),
          title: site.name,
          canShowCallout: true,
          draggable: false,
          selected: isSelected,
          displayPriority: isSelected
              ? BMFMarkerDisplayPriority.High
              : BMFMarkerDisplayPriority.Low,
          scaleX: isSelected ? 1.45 : 1.0,
          scaleY: isSelected ? 1.45 : 1.0,
          alpha: isSelected ? 1.0 : 0.86,
          zIndex: isSelected ? 5 : 0,
        );
        success = await controller.addMarker(fallbackMarker);
        if (success) {
          _markerIds.add(fallbackMarker.id);
          addedMarkerCount += 1;
        }
      } else {
        _markerIds.add(marker.id);
        addedMarkerCount += 1;
      }
    }

    try {
      await controller.mapRefresh(refreshDelay: 120);
    } catch (_) {}

    if (addedMarkerCount == 0 && currentSites.isNotEmpty) {
      _showMessage('点位已加载，但地图标记未渲染，请下拉刷新重试');
    }

    if (currentSites.isEmpty) {
      return;
    }

    if (selectedSite != null) {
      final focusBounds = _buildSingleSiteBounds(selectedSite);
      try {
        await controller.setVisibleMapRectWithPadding(
          visibleMapBounds: focusBounds,
          insets: _mapInsets,
          animated: animate,
        );
      } catch (_) {
        await controller.setNewLatLngZoom(
          coordinate: BMFCoordinate(
            selectedSite.latitude,
            selectedSite.longitude,
          ),
          zoom: _selectedSiteZoom,
          animateDurationMs: animate ? 360 : null,
        );
      }
      return;
    }

    if (currentSites.length == 1) {
      await controller.setCenterCoordinate(
        BMFCoordinate(
          currentSites.first.latitude,
          currentSites.first.longitude,
        ),
        animate,
        animateDurationMs: animate ? 360 : null,
      );
      return;
    }

    final bounds = _buildBounds(currentSites);
    try {
      await controller.setVisibleMapRectWithPadding(
        visibleMapBounds: bounds,
        insets: _mapInsets,
        animated: animate,
      );
    } catch (_) {
      final fallbackSite = currentSites.first;
      await controller.setNewLatLngZoom(
        coordinate: BMFCoordinate(
          fallbackSite.latitude,
          fallbackSite.longitude,
        ),
        zoom: 15,
        animateDurationMs: animate ? 360 : null,
      );
    }
  }

  BMFCoordinateBounds _buildSingleSiteBounds(_KeyPointSite site) {
    const radius = 0.0018;
    return BMFCoordinateBounds(
      northeast: BMFCoordinate(site.latitude + radius, site.longitude + radius),
      southwest: BMFCoordinate(site.latitude - radius, site.longitude - radius),
    );
  }

  BMFCoordinateBounds _buildBounds(List<_KeyPointSite> sites) {
    var minLat = sites.first.latitude;
    var maxLat = sites.first.latitude;
    var minLng = sites.first.longitude;
    var maxLng = sites.first.longitude;
    for (final site in sites.skip(1)) {
      if (site.latitude < minLat) {
        minLat = site.latitude;
      }
      if (site.latitude > maxLat) {
        maxLat = site.latitude;
      }
      if (site.longitude < minLng) {
        minLng = site.longitude;
      }
      if (site.longitude > maxLng) {
        maxLng = site.longitude;
      }
    }
    return BMFCoordinateBounds(
      northeast: BMFCoordinate(maxLat, maxLng),
      southwest: BMFCoordinate(minLat, minLng),
    );
  }

  Future<void> _onSiteTapped(_KeyPointSite site) async {
    setState(() {
      _selectedSite = site;
    });
    await _refreshMarkers(animate: true);
  }

  Future<void> _showSearchPanel() async {
    final selected = await showModalBottomSheet<_KeyPointSite>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _currentSites.length,
            itemBuilder: (context, index) {
              final site = _currentSites[index];
              return ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(site.name),
                subtitle: Text('\u5BB9\u91CF: ${site.capacity} \u4EBA'),
                onTap: () => Navigator.of(context).pop(site),
              );
            },
          ),
        );
      },
    );

    if (selected == null) {
      return;
    }
    await _onSiteTapped(selected);
    _showMessage('\u5DF2\u5B9A\u4F4D\u5230 ${selected.name}');
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    AppCenterToast.show(context, message);
  }
}

class _LoadBanner extends StatelessWidget {
  const _LoadBanner({
    required this.icon,
    required this.text,
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
    this.actionText,
    this.onActionTap,
  });

  final IconData icon;
  final String text;
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;
  final String? actionText;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: textColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if ((actionText ?? '').trim().isNotEmpty && onActionTap != null)
            TextButton(
              onPressed: onActionTap,
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionText!),
            ),
        ],
      ),
    );
  }
}

class _PointListPanel extends StatelessWidget {
  const _PointListPanel({
    required this.sites,
    required this.selectedSiteKey,
    required this.onSiteTap,
  });

  final List<_KeyPointSite> sites;
  final String? selectedSiteKey;
  final ValueChanged<_KeyPointSite> onSiteTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 312,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: 0.98),
            const Color(0xFFF5FAFF).withValues(alpha: 0.98),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border.all(color: const Color(0xFFCBD6E4)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x220F2A47),
            offset: Offset(0, -1),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.format_list_bulleted_rounded,
                  size: 18,
                  color: Color(0xFF226EBD),
                ),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    '\u70B9\u4F4D\u5217\u8868',
                    style: TextStyle(
                      color: Color(0xFF1F2B3A),
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '\u5171 ${sites.length} \u9879',
                  style: const TextStyle(
                    color: Color(0xFF5D6F84),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFD8E1EC)),
          Expanded(
            child: sites.isEmpty
                ? const AppEmptyView(
                    icon: Icons.location_on_outlined,
                    message: '\u6682\u65E0\u70B9\u4F4D\u6570\u636E',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                    itemCount: sites.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final site = sites[index];
                      final selected = selectedSiteKey == site.markerKey;
                      return _PointListItem(
                        site: site,
                        selected: selected,
                        onTap: () => onSiteTap(site),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PointListItem extends StatelessWidget {
  const _PointListItem({
    required this.site,
    required this.selected,
    required this.onTap,
  });

  final _KeyPointSite site;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = site.status == _KeyPointPageState._statusActive;
    final statusColor = active
        ? const Color(0xFF249F53)
        : const Color(0xFF5A6D85);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFECF5FF) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF2D8CE8)
                  : const Color(0xFFD7E1ED),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF2D8CE8)
                            : const Color(0xFFECF2FA),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(
                        '${site.index}',
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : const Color(0xFF48607C),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        site.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF1C2735),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.11),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        site.status,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _PointMeta(
                        label: '\u9762\u79EF',
                        value: '${site.area}\u33A1',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PointMeta(
                        label: '\u5BB9\u7EB3',
                        value: '${site.capacity}\u4EBA',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PointMeta extends StatelessWidget {
  const _PointMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          '$label: ',
          style: const TextStyle(
            color: Color(0xFF6A7B91),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF2A394B),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _MapTools extends StatelessWidget {
  const _MapTools({required this.onToggleTap, required this.onSearchTap});

  final VoidCallback onToggleTap;
  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFBCC4D0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _MapToolButton(
            icon: Icons.layers_outlined,
            label: '\u56FE\u5C42',
            onTap: onToggleTap,
          ),
          const Divider(height: 1),
          _MapToolButton(
            icon: Icons.search_outlined,
            label: '\u641C\u7D22',
            onTap: onSearchTap,
          ),
        ],
      ),
    );
  }
}

class _MapToolButton extends StatelessWidget {
  const _MapToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 54,
        height: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 22, color: const Color(0xFF4E5968)),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF4E5968),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBottomBar extends StatelessWidget {
  const _CategoryBottomBar({required this.current, required this.onChanged});

  final _KeyPointCategory current;
  final ValueChanged<_KeyPointCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFD8DEE6))),
      ),
      child: Row(
        children: _KeyPointCategory.values
            .map(
              (category) => Expanded(
                child: _CategoryItem(
                  category: category,
                  selected: category == current,
                  onTap: () => onChanged(category),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _CategoryItem extends StatelessWidget {
  const _CategoryItem({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final _KeyPointCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF2088E8) : const Color(0xFF4D596A);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(category.icon, size: 22, color: color),
          const SizedBox(height: 3),
          Text(
            category.label,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyPointSite {
  const _KeyPointSite({
    required this.index,
    required this.name,
    required this.area,
    required this.capacity,
    required this.status,
    required this.latitude,
    required this.longitude,
  });

  final int index;
  final String name;
  final int area;
  final int capacity;
  final String status;
  final double latitude;
  final double longitude;

  String get markerKey => '$name|$latitude|$longitude';
}

enum _KeyPointCategory { shelter, supplies, community, keyArea }

extension _KeyPointCategoryX on _KeyPointCategory {
  String get label {
    switch (this) {
      case _KeyPointCategory.shelter:
        return '\u907F\u96BE\u573A\u6240';
      case _KeyPointCategory.supplies:
        return '\u6551\u63F4\u7269\u8D44';
      case _KeyPointCategory.community:
        return '\u793E\u533A\u529B\u91CF';
      case _KeyPointCategory.keyArea:
        return '\u91CD\u70B9\u533A\u57DF';
    }
  }

  IconData get icon {
    switch (this) {
      case _KeyPointCategory.shelter:
        return Icons.apartment_outlined;
      case _KeyPointCategory.supplies:
        return Icons.inventory_2_outlined;
      case _KeyPointCategory.community:
        return Icons.people_outline;
      case _KeyPointCategory.keyArea:
        return Icons.place_outlined;
    }
  }
}
