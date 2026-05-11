import 'dart:async';

import 'package:emergency_helper/src/core/auth/app_feature_permission.dart';
import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/routing/route_paths.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/features/home/data/workbench_statistics_service.dart';
import 'package:emergency_helper/src/features/weather/data/event_weather_warning_service.dart';
import 'package:emergency_helper/src/features/weather/data/free_weather_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// UI preview switch: show all workbench entries regardless of backend permission.
const bool _previewShowAllWorkbenchActions = true;

class WorkbenchTabPage extends StatefulWidget {
  const WorkbenchTabPage({super.key});

  @override
  State<WorkbenchTabPage> createState() => _WorkbenchTabPageState();
}

class _WorkbenchTabPageState extends State<WorkbenchTabPage> {
  late Future<AppFeaturePermission> _permissionFuture;
  int _refreshNonce = 0;

  @override
  void initState() {
    super.initState();
    _permissionFuture = _resolvePermission();
  }

  Future<AppFeaturePermission> _resolvePermission() {
    final dependencies = context.read<AppDependencies>();
    return AppFeaturePermissionResolver.instance.resolve(
      dependencies.authService,
    );
  }

  Future<void> _refreshWorkbench() async {
    setState(() {
      _refreshNonce++;
      _permissionFuture = _resolvePermission();
    });
    await _permissionFuture;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppFeaturePermission>(
      future: _permissionFuture,
      builder: (context, snapshot) {
        final permission = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
            title: const Text('\u5DE5\u4F5C\u53F0'),
          ),
          body: RefreshIndicator(
            onRefresh: _refreshWorkbench,
            child: ListView(
              key: const Key('workbench-root'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppTheme.pagePadding,
              children: <Widget>[
                KeyedSubtree(
                  key: ValueKey<String>('weather-$_refreshNonce'),
                  child: const _WeatherSummaryTile(),
                ),
                const SizedBox(height: 8),
                KeyedSubtree(
                  key: ValueKey<String>('warning-$_refreshNonce'),
                  child: const _WarningCard(),
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '\u7EDF\u8BA1\u6700\u8FD130\u5929\u6570\u636E',
                    style: TextStyle(
                      color: Color(0xFF9AA3AE),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                KeyedSubtree(
                  key: ValueKey<String>('summary-$_refreshNonce'),
                  child: const _SummaryPanel(),
                ),
                const SizedBox(height: 12),
                _ActionGrid(permission: permission),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WeatherSummaryTile extends StatefulWidget {
  const _WeatherSummaryTile();

  @override
  State<_WeatherSummaryTile> createState() => _WeatherSummaryTileState();
}

class _WeatherSummaryTileState extends State<_WeatherSummaryTile> {
  late final FreeWeatherService _service;
  late Future<WeatherSnapshot> _future;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _service = FreeWeatherService();
    _future = _service.fetchShenyangForecast();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _reloadWeather(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _reloadWeather() {
    if (!mounted) {
      return;
    }
    setState(() {
      _future = _service.fetchShenyangForecast();
    });
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(RoutePaths.weatherInfo),
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        key: const Key('open-weather-info-button'),
        decoration: BoxDecoration(
          color: AppTheme.surfaceWhite,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: const Color(0xFFDCE3EC)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: FutureBuilder<WeatherSnapshot>(
          future: _future,
          builder: (context, snapshot) {
            final bannerData = snapshot.hasData
                ? _WeatherBannerData.fromSnapshot(snapshot.data!)
                : const _WeatherBannerData.fallback();

            return Row(
              children: <Widget>[
                Text(
                  bannerData.currentTempText,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _AutoMarqueeText(items: bannerData.items)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WeatherBannerData {
  const _WeatherBannerData({
    required this.currentTempText,
    required this.items,
  });

  const _WeatherBannerData.fallback()
    : currentTempText = '--\u00B0C',
      items = const <_WeatherMarqueeItem>[
        _WeatherMarqueeItem(
          iconAsset: 'assets/images/weather/weather_cloudy.png',
          text:
              '\u5929\u6C14\u6570\u636E\u52A0\u8F7D\u4E2D\uFF0C\u8BF7\u7A0D\u5019  \u00B7  '
              '\u5982\u672A\u66F4\u65B0\u53EF\u70B9\u51FB\u8FDB\u5165\u5929\u6C14\u8BE6\u60C5\u9875\u91CD\u8BD5',
        ),
      ];

  factory _WeatherBannerData.fromSnapshot(WeatherSnapshot snapshot) {
    final today = snapshot.daily.isNotEmpty ? snapshot.daily.first : null;
    final iconAsset = _weatherIconAssetByCode(snapshot.currentWeatherCode);
    final weatherLabel = _weatherLabelByCode(snapshot.currentWeatherCode);
    final currentText = '${snapshot.currentTemp.round()}\u00B0C';
    final minTemp = today?.minTemp.round() ?? snapshot.currentTemp.round();
    final maxTemp = today?.maxTemp.round() ?? snapshot.currentTemp.round();
    final text =
        '${snapshot.cityName}$weatherLabel  \u4ECA\u5929 $minTemp~$maxTemp\u00B0C  \u00B7  '
        '\u6E7F\u5EA6 ${snapshot.currentHumidity}%  \u00B7  '
        '\u98CE\u901F ${snapshot.currentWindSpeed.toStringAsFixed(1)}km/h';

    return _WeatherBannerData(
      currentTempText: currentText,
      items: <_WeatherMarqueeItem>[
        _WeatherMarqueeItem(iconAsset: iconAsset, text: text),
      ],
    );
  }

  final String currentTempText;
  final List<_WeatherMarqueeItem> items;
}

String _weatherIconAssetByCode(int code) {
  if (code >= 400 && code < 500) {
    return 'assets/images/weather/weather_snowy.png';
  }
  if (code >= 300 && code < 400) {
    return 'assets/images/weather/weather_rainy.png';
  }
  if (code == 100 || code == 150) {
    return 'assets/images/weather/weather_sunny.png';
  }
  return 'assets/images/weather/weather_cloudy.png';
}

String _weatherLabelByCode(int code) {
  if (code >= 400 && code < 500) {
    return '\u96EA\u5929';
  }
  if (code >= 300 && code < 400) {
    return '\u96E8\u5929';
  }
  if (code == 100 || code == 150) {
    return '\u6674\u5929';
  }
  return '\u9634\u5929';
}

class _AutoMarqueeText extends StatefulWidget {
  const _AutoMarqueeText({required this.items});

  final List<_WeatherMarqueeItem> items;

  @override
  State<_AutoMarqueeText> createState() => _AutoMarqueeTextState();
}

class _AutoMarqueeTextState extends State<_AutoMarqueeText> {
  static const Duration _tickInterval = Duration(milliseconds: 16);
  static const double _pixelsPerTick = 0.55;

  final ScrollController _scrollController = ScrollController();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startTicker();
    });
  }

  @override
  void didUpdateWidget(covariant _AutoMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameItems(oldWidget.items, widget.items)) {
      _restartLoop();
    }
  }

  @override
  void dispose() {
    _stopTicker();
    _scrollController.dispose();
    super.dispose();
  }

  void _restartLoop() {
    _stopTicker();
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startTicker();
    });
  }

  void _startTicker() {
    if (_ticker != null) {
      return;
    }
    _ticker = Timer.periodic(_tickInterval, (_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final max = _scrollController.position.maxScrollExtent;
      if (max <= 1) {
        return;
      }
      final next = _scrollController.position.pixels + _pixelsPerTick;
      if (next >= max) {
        _scrollController.jumpTo(0);
      } else {
        _scrollController.jumpTo(next);
      }
    });
  }

  void _stopTicker() {
    if (_ticker == null) {
      return;
    }
    _ticker!.cancel();
    _ticker = null;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          children: <Widget>[
            _buildTape(),
            const SizedBox(width: 42),
            _buildTape(),
          ],
        ),
      ),
    );
  }

  Widget _buildTape() {
    const textStyle = TextStyle(
      color: Color(0xFF6B747D),
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );

    return Row(
      children: <Widget>[
        for (var i = 0; i < widget.items.length; i++) ...<Widget>[
          Image.asset(
            widget.items[i].iconAsset,
            width: 18,
            height: 18,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 5),
          Text(widget.items[i].text, style: textStyle),
          if (i != widget.items.length - 1) ...<Widget>[
            const SizedBox(width: 12),
            const Text(
              '\u00B7',
              style: TextStyle(
                color: Color(0xFF9AA3AE),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
          ],
        ],
      ],
    );
  }

  bool _sameItems(List<_WeatherMarqueeItem> a, List<_WeatherMarqueeItem> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i].iconAsset != b[i].iconAsset || a[i].text != b[i].text) {
        return false;
      }
    }
    return true;
  }
}

class _WeatherMarqueeItem {
  const _WeatherMarqueeItem({required this.iconAsset, required this.text});

  final String iconAsset;
  final String text;
}

class _WarningCard extends StatefulWidget {
  const _WarningCard();

  @override
  State<_WarningCard> createState() => _WarningCardState();
}

class _WarningCardState extends State<_WarningCard> {
  late final EventWeatherWarningService _service;
  late Future<_WeatherWarningData> _future;
  Timer? _refreshTimer;
  _WeatherWarningData? _cachedData;

  @override
  void initState() {
    super.initState();
    _service = EventWeatherWarningService();
    _future = _loadWarningData();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _reloadWeatherWarning(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _reloadWeatherWarning() {
    if (!mounted) {
      return;
    }
    setState(() {
      _future = _loadWarningData();
    });
  }

  Future<_WeatherWarningData> _loadWarningData() async {
    try {
      final dependencies = context.read<AppDependencies>();
      final list = await _service.fetchWarningList(dependencies.apiClient);
      final first = list.isNotEmpty ? list.first : null;
      if (first == null) {
        return _WeatherWarningData(
          iconLabel: '预警',
          iconAsset: 'assets/images/weather/weather_cloudy.png',
          title: '暂无气象预警信息',
          timeText: '--',
          cardColor: const Color(0xFFE1F1E2),
          iconColor: const Color(0xFF62B46B),
        );
      }
      return _weatherWarningFromBackend(first);
    } catch (_) {
      // Return cached data on error to avoid showing loading/error UI
      if (_cachedData != null) {
        return _cachedData!;
      }
      return _WeatherWarningData(
        iconLabel: '预警',
        iconAsset: 'assets/images/weather/weather_cloudy.png',
        title: '暂无气象预警信息',
        timeText: '--',
        cardColor: const Color(0xFFE1F1E2),
        iconColor: const Color(0xFF62B46B),
      );
    }
  }

  _WeatherWarningData _weatherWarningFromBackend(
    EventWeatherWarningItem item,
  ) {
    final title = item.title.trim().isNotEmpty
        ? item.title.trim()
        : '气象预警信息';
    final warningColor = _backendWarningColor(item.level);
    return _WeatherWarningData(
      iconLabel: _warningIconLabel(item.typeName),
      iconAsset: 'assets/images/weather/weather_cloudy.png',
      title: title,
      timeText: item.publishTime != null
          ? _formatWarningTime(item.publishTime!)
          : '--',
      cardColor: _backendWarningCardColor(item.level),
      iconColor: warningColor,
    );
  }

  Color _backendWarningColor(String level) {
    final raw = level.trim().toLowerCase();
    // Support numeric levels: 1=red, 2=orange, 3=yellow, 4=blue
    if (raw == '1' || raw.contains('red') || raw.contains('红')) return const Color(0xFFE55B5B);
    if (raw == '2' || raw.contains('orange') || raw.contains('橙')) return const Color(0xFFE49A2D);
    if (raw == '3' || raw.contains('yellow') || raw.contains('黄')) return const Color(0xFFF6B434);
    if (raw == '4' || raw.contains('blue') || raw.contains('蓝')) return const Color(0xFF4B81CD);
    return const Color(0xFF7E8DA2);
  }

  Color _backendWarningCardColor(String level) {
    final raw = level.trim().toLowerCase();
    // Support numeric levels: 1=red, 2=orange, 3=yellow, 4=blue
    if (raw == '1' || raw.contains('red') || raw.contains('红')) return const Color(0xFFF8D8D8);
    if (raw == '2' || raw.contains('orange') || raw.contains('橙')) return const Color(0xFFFBE2C1);
    if (raw == '3' || raw.contains('yellow') || raw.contains('黄')) return const Color(0xFFEEC0C0);
    if (raw == '4' || raw.contains('blue') || raw.contains('蓝')) return const Color(0xFFDCEAFD);
    return const Color(0xFFE7EDF4);
  }

  String _warningIconLabel(String typeName) {
    final type = typeName.trim();
    if (type.isEmpty) return '预警';
    if (type.length <= 2) return type;
    return type.substring(0, 2);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_WeatherWarningData>(
      future: _future,
      builder: (context, snapshot) {
        _WeatherWarningData warningData;
        if (snapshot.hasData) {
          warningData = snapshot.data!;
          _cachedData = warningData;
        } else if (_cachedData != null) {
          warningData = _cachedData!;
        } else {
          // Initial state: show fallback without loading indicator
          warningData = _WeatherWarningData(
            iconLabel: '预警',
            iconAsset: 'assets/images/weather/weather_cloudy.png',
            title: '暂无气象预警信息',
            timeText: '--',
            cardColor: const Color(0xFFE1F1E2),
            iconColor: const Color(0xFF62B46B),
          );
        }

        return GestureDetector(
          onTap: () => context.push(RoutePaths.weatherWarningList),
          child: Container(
          decoration: BoxDecoration(
            color: warningData.cardColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: const Color(0x14FFFFFF)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: <Widget>[
              _WarningIcon(
                label: warningData.iconLabel,
                backgroundColor: warningData.iconColor,
                iconAsset: warningData.iconAsset,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      warningData.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      warningData.timeText,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        );
      },
    );
  }
}

class _WarningIcon extends StatelessWidget {
  const _WarningIcon({
    required this.label,
    required this.backgroundColor,
    this.iconAsset,
  });

  final String label;
  final Color backgroundColor;
  final String? iconAsset;

  @override
  Widget build(BuildContext context) {
    final normalizedIconAsset = iconAsset?.trim();
    final hasAsset =
        normalizedIconAsset != null && normalizedIconAsset.isNotEmpty;
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: hasAsset
            ? backgroundColor.withValues(alpha: 0.18)
            : backgroundColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      alignment: Alignment.center,
      child: hasAsset
          ? ColorFiltered(
              colorFilter: ColorFilter.mode(backgroundColor, BlendMode.srcIn),
              child: Image.asset(
                normalizedIconAsset,
                width: 28,
                height: 28,
                fit: BoxFit.contain,
              ),
            )
          : Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

class _WeatherWarningData {
  const _WeatherWarningData({
    required this.iconLabel,
    this.iconAsset,
    required this.title,
    required this.timeText,
    required this.cardColor,
    required this.iconColor,
  });

  factory _WeatherWarningData.loading() {
    return _WeatherWarningData(
      iconLabel: '天气',
      iconAsset: 'assets/images/weather/weather_cloudy.png',
      title: '气象信息加载中',
      timeText: '--',
      cardColor: const Color(0xFFF2F4F7),
      iconColor: const Color(0xFF9AA3AE),
    );
  }

  factory _WeatherWarningData.error() {
    return _WeatherWarningData(
      iconLabel: '提示',
      iconAsset: 'assets/images/weather/weather_cloudy.png',
      title: '暂无气象预警数据',
      timeText: '--',
      cardColor: const Color(0xFFF2F4F7),
      iconColor: const Color(0xFF9AA3AE),
    );
  }

  final String iconLabel;
  final String? iconAsset;
  final String title;
  final String timeText;
  final Color cardColor;
  final Color iconColor;
}

String _formatWarningTime(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)}';
}

class _SummaryPanel extends StatefulWidget {
  const _SummaryPanel();

  @override
  State<_SummaryPanel> createState() => _SummaryPanelState();
}

class _SummaryPanelState extends State<_SummaryPanel> {
  static const WorkbenchStatisticsService _service =
      WorkbenchStatisticsService();
  late Future<WorkbenchStatistics> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadStatistics();
  }

  Future<WorkbenchStatistics> _loadStatistics() async {
    final dependencies = context.read<AppDependencies>();
    return _service.fetchStatistics(dependencies.apiClient);
  }

  void _retry() {
    setState(() {
      _future = _loadStatistics();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WorkbenchStatistics>(
      future: _future,
      builder: (context, snapshot) {
        final isError = snapshot.hasError;
        final data = snapshot.data;
        final errorMessage = snapshot.error is AppException
            ? (snapshot.error as AppException).message
            : null;

        final todayValue = data?.todayNewEventCount.toString() ?? '--';
        final pendingEventValue = data?.pendingEventCount.toString() ?? '--';
        final closedEventValue = data?.closedEventCount.toString() ?? '--';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD9DEE5)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _SummaryItem(
                      title: todayValue,
                      subtitle: '\u4ECA\u65E5\u65B0\u589E\u4E8B\u4EF6',
                      onTap: () => context.push(RoutePaths.eventList),
                    ),
                  ),
                  const _SummaryDivider(),
                  Expanded(
                    child: _SummaryItem(
                      title: pendingEventValue,
                      subtitle: '\u5904\u7406\u4E2D\u4E8B\u4EF6',
                      onTap: () => context.push(
                        RoutePaths.statisticsByTab(tab: 'event'),
                      ),
                    ),
                  ),
                  const _SummaryDivider(),
                  Expanded(
                    child: _SummaryItem(
                      title: closedEventValue,
                      subtitle: '\u5DF2\u529E\u7ED3\u4E8B\u4EF6',
                      onTap: () => context.push(
                        RoutePaths.statisticsByTab(tab: 'derived-risk'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isError)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        '\u7EDF\u8BA1\u6570\u636E\u52A0\u8F7D\u5931\u8D25',
                        style: TextStyle(
                          color: Color(0xFFB06B36),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (errorMessage != null && errorMessage.trim().isNotEmpty)
                      Expanded(
                        child: Text(
                          errorMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Color(0xFFB06B36),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    TextButton(
                      onPressed: _retry,
                      child: const Text('\u91CD\u8BD5'),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.primaryBlue,
                  fontSize: 40,
                  fontWeight: FontWeight.w500,
                  height: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF66707A), fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 74, color: const Color(0xFFE3E7ED));
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.permission});

  final AppFeaturePermission? permission;

  static const List<_ActionItem> _items = <_ActionItem>[
    _ActionItem(
      type: _ActionType.eventReport,
      label: '\u4E8B\u4EF6\u4E0A\u62A5',
    ),
    _ActionItem(type: _ActionType.eventInfo, label: '\u4E8B\u4EF6\u4FE1\u606F'),
    _ActionItem(
      type: _ActionType.riskReport,
      label: '\u98CE\u9669\u4E0A\u62A5',
    ),
    _ActionItem(
      type: _ActionType.derivedRisk,
      label: '\u884D\u751F\u98CE\u9669',
    ),
    _ActionItem(type: _ActionType.keyPoint, label: '\u91CD\u70B9\u70B9\u4F4D'),
  ];

  @override
  Widget build(BuildContext context) {
    final visibleItems = _previewShowAllWorkbenchActions
        ? _items
        : permission == null
        ? _items
        : _items
              .where((item) => _isAllowed(permission!, item.type))
              .toList(growable: false);
    if (visibleItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD9DEE5)),
        ),
        child: const Text(
          '\u6682\u65E0\u53EF\u8BBF\u95EE\u529F\u80FD',
          style: TextStyle(
            color: Color(0xFF7D8792),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const maxColumns = 4;
        const crossAxisSpacing = 8.0;
        const mainAxisSpacing = 10.0;
        final itemWidth =
            (constraints.maxWidth - (maxColumns - 1) * crossAxisSpacing) /
            maxColumns;

        return Wrap(
          spacing: crossAxisSpacing,
          runSpacing: mainAxisSpacing,
          children: visibleItems
              .map(
                (item) => SizedBox(
                  width: itemWidth,
                  height: 82,
                  child: _ActionCard(
                    item: item,
                    enabled:
                        _previewShowAllWorkbenchActions || permission != null,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  bool _isAllowed(AppFeaturePermission permission, _ActionType type) {
    switch (type) {
      case _ActionType.eventReport:
        return permission.canEventReport;
      case _ActionType.eventInfo:
        return permission.canEventQuery ||
            permission.canEventReport ||
            permission.canEventTransfer ||
            permission.canEventFeedback ||
            permission.canEventClose;
      case _ActionType.riskReport:
        return permission.canRiskReport;
      case _ActionType.derivedRisk:
        return permission.canRiskQuery ||
            permission.canRiskReport ||
            permission.canRiskTransfer ||
            permission.canRiskFeedback ||
            permission.canRiskClose;
      case _ActionType.keyPoint:
        return permission.canKeyPointQuery || permission.canDataVisualization;
    }
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.item, required this.enabled});

  final _ActionItem item;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: _keyByType(item.type),
      borderRadius: BorderRadius.circular(6),
      onTap: enabled ? () => _handleTap(context) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Opacity(
            opacity: enabled ? 1 : 0.45,
            child: _ActionIcon(type: item.type),
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: enabled
                  ? const Color(0xFF636D78)
                  : const Color(0xFF9CA5B0),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Key _keyByType(_ActionType type) {
    switch (type) {
      case _ActionType.eventReport:
        return const Key('open-event-report-button');
      case _ActionType.eventInfo:
        return const Key('open-event-list-button');
      case _ActionType.riskReport:
        return const Key('open-risk-report-button');
      case _ActionType.derivedRisk:
        return const Key('open-risk-list-button');
      case _ActionType.keyPoint:
        return const Key('open-key-point-button');
    }
  }

  void _handleTap(BuildContext context) {
    if (item.type == _ActionType.eventReport) {
      context.push(RoutePaths.eventReport);
      return;
    }
    if (item.type == _ActionType.eventInfo) {
      context.push(RoutePaths.eventList);
      return;
    }
    if (item.type == _ActionType.riskReport) {
      context.push(RoutePaths.riskReport);
      return;
    }
    if (item.type == _ActionType.derivedRisk) {
      context.push(RoutePaths.riskList);
      return;
    }
    if (item.type == _ActionType.keyPoint) {
      context.push(RoutePaths.keyPoint);
      return;
    }
    AppCenterToast.show(context, '\u6A21\u5757\u5F85\u63A5\u5165');
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.type});

  final _ActionType type;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: SvgPicture.asset(
        _assetByType(type),
        width: 44,
        height: 44,
        fit: BoxFit.contain,
      ),
    );
  }

  String _assetByType(_ActionType type) {
    switch (type) {
      case _ActionType.eventReport:
        return 'assets/images/icon11.svg';
      case _ActionType.eventInfo:
        return 'assets/images/icon22.svg';
      case _ActionType.riskReport:
        return 'assets/images/icon33.svg';
      case _ActionType.derivedRisk:
        return 'assets/images/icon44.svg';
      case _ActionType.keyPoint:
        return 'assets/images/icon55.svg';
    }
  }
}

class _ActionItem {
  const _ActionItem({required this.type, required this.label});

  final _ActionType type;
  final String label;
}

enum _ActionType { eventReport, eventInfo, riskReport, derivedRisk, keyPoint }
