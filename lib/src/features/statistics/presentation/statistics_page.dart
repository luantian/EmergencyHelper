import 'dart:math' as math;

import 'package:emergency_helper/src/core/widgets/app_empty_view.dart';
import 'package:emergency_helper/src/core/data/form_option_service.dart';
import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/features/statistics/data/event_statistics_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum StatisticsTabKind { event, derivedRisk }

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key, this.initialTab = StatisticsTabKind.event});

  final StatisticsTabKind initialTab;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  static const EventStatisticsService _eventService = EventStatisticsService();
  static final FormOptionService _formOptionService =
      FormOptionService.instance;

  static const List<FormOption> _eventLevelOptions = <FormOption>[
    FormOption(value: '', label: '全部级别'),
    FormOption(value: '0', label: '一般以上（IV级）'),
    FormOption(value: '1', label: '较大（III级）'),
    FormOption(value: '2', label: '重大（II级）'),
    FormOption(value: '3', label: '特别重大（I级）'),
  ];

  static const List<FormOption> _riskLevelOptions = <FormOption>[
    FormOption(value: '', label: '全部等级'),
    FormOption(value: '0', label: '低风险'),
    FormOption(value: '1', label: '中风险'),
    FormOption(value: '2', label: '高风险'),
  ];

  static const List<Color> _seriesColors = <Color>[
    Color(0xFF2E6FD8),
    Color(0xFF2FBA9A),
    Color(0xFFEFB33A),
    Color(0xFFF08045),
    Color(0xFF8C6CE9),
    Color(0xFF4E8FD9),
    Color(0xFF57A45A),
    Color(0xFFEA5A7F),
  ];

  late StatisticsTabKind _currentTab;
  StatisticsPeriod _period = StatisticsPeriod.thisWeek;
  List<FormOption> _streetOptions = const <FormOption>[
    FormOption(value: '', label: '全部街道'),
  ];
  String _selectedStreetId = '';
  String _selectedEventLevel = '';
  String _selectedRiskLevel = '';
  bool _loadingStreetOptions = true;

  late Future<EventStatisticsBundle> _statisticsFuture;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
    _statisticsFuture = _loadStatistics();
    _loadStreetOptions();
  }

  Future<void> _loadStreetOptions() async {
    final dependencies = context.read<AppDependencies>();
    try {
      final loaded = await _formOptionService.loadDeptOptions(
        dependencies.apiClient,
        type: 'street',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _streetOptions = <FormOption>[
          const FormOption(value: '', label: '全部街道'),
          ...loaded,
        ];
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _streetOptions = const <FormOption>[
          FormOption(value: '', label: '全部街道'),
        ];
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingStreetOptions = false;
        });
      }
    }
  }

  Future<EventStatisticsBundle> _loadStatistics() async {
    if (_currentTab == StatisticsTabKind.derivedRisk) {
      return _buildDerivedRiskMockData(
        level: _selectedRiskLevel,
        period: _period,
        streetId: _selectedStreetId,
      );
    }
    final dependencies = context.read<AppDependencies>();
    return _eventService.fetchEventStatistics(
      dependencies.apiClient,
      deptId: _selectedStreetId.isEmpty ? null : _selectedStreetId,
      level: _selectedEventLevel.isEmpty ? null : _selectedEventLevel,
      period: _period,
    );
  }

  Future<void> _reloadStatistics() async {
    setState(() {
      _statisticsFuture = _loadStatistics();
    });
    await _statisticsFuture;
  }

  @override
  Widget build(BuildContext context) {
    final levelOptions = _currentTab == StatisticsTabKind.event
        ? _eventLevelOptions
        : _riskLevelOptions;
    final selectedLevel = _currentTab == StatisticsTabKind.event
        ? _selectedEventLevel
        : _selectedRiskLevel;

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据统计'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF3F6FB),
      body: RefreshIndicator(
        onRefresh: _reloadStatistics,
        child: FutureBuilder<EventStatisticsBundle>(
          future: _statisticsFuture,
          builder: (context, snapshot) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
              children: <Widget>[
                _buildTopRow(),
                const SizedBox(height: 10),
                _FilterPanel(
                  levelLabel: _currentTab == StatisticsTabKind.event
                      ? '事件级别'
                      : '风险等级',
                  streetSelector: _buildDropdown(
                    value: _selectedStreetId,
                    items: _streetOptions,
                    loading: _loadingStreetOptions,
                    onChanged: (value) {
                      setState(() {
                        _selectedStreetId = value;
                      });
                      _reloadStatistics();
                    },
                  ),
                  levelSelector: _buildDropdown(
                    value: selectedLevel,
                    items: levelOptions,
                    onChanged: (value) {
                      setState(() {
                        if (_currentTab == StatisticsTabKind.event) {
                          _selectedEventLevel = value;
                        } else {
                          _selectedRiskLevel = value;
                        }
                      });
                      _reloadStatistics();
                    },
                  ),
                ),
                if (_currentTab == StatisticsTabKind.derivedRisk) ...<Widget>[
                  const SizedBox(height: 8),
                  const _NoticeBanner(text: '衍生风险统计接口暂未提供，当前展示演示数据样式。'),
                ],
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const _LoadingBlock()
                else if (snapshot.hasError)
                  _ErrorBlock(
                    message: snapshot.error.toString(),
                    onRetry: _reloadStatistics,
                  )
                else
                  _StatisticsContent(
                    tabKind: _currentTab,
                    bundle:
                        snapshot.data ??
                        const EventStatisticsBundle(
                          overview: StatisticsOverview(
                            totalCount: 0,
                            pendingCount: 0,
                            closedCount: 0,
                            previousTotalCount: 0,
                          ),
                          distribution: <StatisticsTypeCount>[],
                          trend: StatisticsTrendData(
                            dateList: <String>[],
                            series: <StatisticsTrendSeries>[],
                          ),
                        ),
                    palette: _seriesColors,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopRow() {
    return Row(
      children: <Widget>[
        Expanded(
          child: _TabSwitcher(
            currentTab: _currentTab,
            onTap: (next) {
              if (_currentTab == next) {
                return;
              }
              setState(() {
                _currentTab = next;
                _statisticsFuture = _loadStatistics();
              });
            },
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 108,
          child: _buildDropdown(
            value: _period == StatisticsPeriod.thisWeek ? 'week' : 'month',
            items: const <FormOption>[
              FormOption(value: 'week', label: '本周'),
              FormOption(value: 'month', label: '本月'),
            ],
            onChanged: (value) {
              setState(() {
                _period = value == 'month'
                    ? StatisticsPeriod.thisMonth
                    : StatisticsPeriod.thisWeek;
              });
              _reloadStatistics();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<FormOption> items,
    required ValueChanged<String> onChanged,
    bool loading = false,
  }) {
    if (loading) {
      return Container(
        height: 40,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD6E1EF)),
        ),
        child: const Text(
          '加载中...',
          style: TextStyle(
            color: Color(0xFF8DA0B7),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final validValues = items.map((item) => item.value).toSet();
    final selected = validValues.contains(value) ? value : items.first.value;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD6E1EF)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          style: const TextStyle(
            color: Color(0xFF1E2A39),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          dropdownColor: Colors.white,
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item.value,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: (next) {
            if (next == null) {
              return;
            }
            onChanged(next);
          },
        ),
      ),
    );
  }

  EventStatisticsBundle _buildDerivedRiskMockData({
    required String level,
    required StatisticsPeriod period,
    required String streetId,
  }) {
    final base = switch (level) {
      '0' => 0.74,
      '1' => 1.0,
      '2' => 1.28,
      _ => 1.0,
    };
    final streetOffset = (streetId.isEmpty ? 0 : streetId.hashCode.abs()) % 6;
    final periodBoost = period == StatisticsPeriod.thisMonth ? 1.2 : 1.0;

    int scale(int value) =>
        math.max(0, (value * base * periodBoost).round() + streetOffset);

    final distribution = <StatisticsTypeCount>[
      StatisticsTypeCount(typeName: '城市运行', count: scale(26)),
      StatisticsTypeCount(typeName: '消防安全', count: scale(36)),
      StatisticsTypeCount(typeName: '道路交通', count: scale(16)),
      StatisticsTypeCount(typeName: '城市建设', count: scale(42)),
    ];

    final total = distribution.fold<int>(0, (sum, item) => sum + item.count);
    final pending = scale(23);
    final closed = math.max(0, total - pending);

    final trend = StatisticsTrendData(
      dateList: const <String>[
        '3/23',
        '3/24',
        '3/25',
        '3/26',
        '3/27',
        '3/28',
        '3/29',
      ],
      series: <StatisticsTrendSeries>[
        StatisticsTrendSeries(
          typeName: '城市运行',
          dailyCounts: <int>[
            scale(10),
            scale(14),
            scale(23),
            scale(10),
            scale(13),
            scale(21),
            scale(15),
          ],
        ),
        StatisticsTrendSeries(
          typeName: '消防安全',
          dailyCounts: <int>[
            scale(13),
            scale(15),
            scale(32),
            scale(14),
            scale(20),
            scale(19),
            scale(21),
          ],
        ),
        StatisticsTrendSeries(
          typeName: '道路交通',
          dailyCounts: <int>[
            scale(20),
            scale(23),
            scale(21),
            scale(18),
            scale(16),
            scale(19),
            scale(19),
          ],
        ),
        StatisticsTrendSeries(
          typeName: '城市建设',
          dailyCounts: <int>[
            scale(17),
            scale(17),
            scale(13),
            scale(21),
            scale(19),
            scale(6),
            scale(23),
          ],
        ),
      ],
    );

    return EventStatisticsBundle(
      overview: StatisticsOverview(
        totalCount: total,
        pendingCount: pending,
        closedCount: closed,
        previousTotalCount: math.max(0, total - scale(7)),
      ),
      distribution: distribution,
      trend: trend,
    );
  }
}

class _TabSwitcher extends StatelessWidget {
  const _TabSwitcher({required this.currentTab, required this.onTap});

  final StatisticsTabKind currentTab;
  final ValueChanged<StatisticsTabKind> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD6E0EE)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _SwitchButton(
              label: '突发事件',
              selected: currentTab == StatisticsTabKind.event,
              onTap: () => onTap(StatisticsTabKind.event),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _SwitchButton(
              label: '衍生风险',
              selected: currentTab == StatisticsTabKind.derivedRisk,
              onTap: () => onTap(StatisticsTabKind.derivedRisk),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchButton extends StatelessWidget {
  const _SwitchButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: selected ? const Color(0xFF0E64CC) : Colors.transparent,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF4E6178),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.levelLabel,
    required this.streetSelector,
    required this.levelSelector,
  });

  final String levelLabel;
  final Widget streetSelector;
  final Widget levelSelector;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6E0EE)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1005273F),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          _FilterRow(label: '所属街道', child: streetSelector),
          const SizedBox(height: 8),
          _FilterRow(label: levelLabel, child: levelSelector),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF3A4D63),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7EA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF5D7A3)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFC88120),
            size: 16,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF8D6122),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6E0EE)),
      ),
      child: const CircularProgressIndicator(),
    );
  }
}

class _StatisticsContent extends StatelessWidget {
  const _StatisticsContent({
    required this.tabKind,
    required this.bundle,
    required this.palette,
  });

  final StatisticsTabKind tabKind;
  final EventStatisticsBundle bundle;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    final totalText = tabKind == StatisticsTabKind.event ? '事件总数' : '风险总数';
    final pendingText = tabKind == StatisticsTabKind.event ? '处理中' : '待处理';
    final closedText = tabKind == StatisticsTabKind.event ? '已办结' : '已整改';
    final totalFooterText = _buildTotalFooterText(bundle.overview);
    final totalFooterColor = _buildTotalFooterColor(bundle.overview);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionTitle(title: '核心指标'),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _MetricCard(
                label: totalText,
                value: bundle.overview.totalCount.toString(),
                color: const Color(0xFF2D6FDA),
                footer: totalFooterText,
                footerColor: totalFooterColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                label: pendingText,
                value: bundle.overview.pendingCount.toString(),
                color: const Color(0xFFF08B3D),
                footer: '需关注',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                label: closedText,
                value: bundle.overview.closedCount.toString(),
                color: const Color(0xFF2AAE84),
                footer: '办结率 ${bundle.overview.closedRate.toStringAsFixed(0)}%',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SectionTitle(
          title: tabKind == StatisticsTabKind.event ? '事件类型分布' : '风险类型分布',
        ),
        const SizedBox(height: 8),
        _PieDistributionCard(
          distribution: bundle.distribution,
          palette: palette,
        ),
        const SizedBox(height: 12),
        const _SectionTitle(title: '近7天趋势'),
        const SizedBox(height: 8),
        _TrendLineCard(trend: bundle.trend, palette: palette),
      ],
    );
  }

  String _buildTotalFooterText(StatisticsOverview overview) {
    if (overview.totalIncreased) {
      return '\u2191 ${overview.totalChangePercentRounded}%';
    }
    if (overview.totalDecreased) {
      return '\u2193 ${overview.totalChangePercentRounded}%';
    }
    return '\u2194 0%';
  }

  Color _buildTotalFooterColor(StatisticsOverview overview) {
    if (overview.totalIncreased) {
      return const Color(0xFFD95858);
    }
    if (overview.totalDecreased) {
      return const Color(0xFF2AAE84);
    }
    return const Color(0xFF6D8096);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF1C2B3B),
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
    this.footer,
    this.footerColor,
  });

  final String label;
  final String value;
  final Color color;
  final String? footer;
  final Color? footerColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD8E2EF)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1005273F),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6A7B8E),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            footer ?? '当前统计',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: footerColor ?? color.withValues(alpha: 0.9),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PieDistributionCard extends StatelessWidget {
  const _PieDistributionCard({
    required this.distribution,
    required this.palette,
  });

  final List<StatisticsTypeCount> distribution;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    if (distribution.isEmpty) {
      return const _ChartShell(
        child: const SizedBox(height: 300, child: AppEmptyView(icon: Icons.insert_chart_outlined_rounded, message: '暂无统计数据')),
      );
    }

    final total = distribution.fold<int>(0, (sum, item) => sum + item.count);
    final sections = List<PieChartSectionData>.generate(distribution.length, (
      i,
    ) {
      final item = distribution[i];
      final color = palette[i % palette.length];
      final percent = total <= 0 ? 0 : (item.count / total) * 100;
      final typeLabel = _compactTypeLabel(item.typeName);
      return PieChartSectionData(
        value: item.count.toDouble(),
        color: color,
        radius: 62,
        title: percent >= 8 ? typeLabel : '',
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
        titlePositionPercentageOffset: 0.64,
      );
    });

    return _ChartShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Center(
            child: SizedBox(
              width: 220,
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  PieChart(
                    PieChartData(
                      sections: sections,
                      sectionsSpace: 2,
                      centerSpaceRadius: 44,
                      startDegreeOffset: -90,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text(
                        '总量',
                        style: TextStyle(
                          color: Color(0xFF6D7F92),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$total',
                        style: const TextStyle(
                          color: Color(0xFF1E2D3E),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildLegend(total: total),
        ],
      ),
    );
  }

  String _compactTypeLabel(String source, {int maxLength = 4}) {
    final trimmed = source.trim();
    if (trimmed.isEmpty || trimmed.length <= maxLength) {
      return trimmed;
    }
    return '${trimmed.substring(0, maxLength)}…';
  }

  Widget _buildLegend({required int total}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final spacing = 14.0;
        final itemWidth = maxWidth >= 520
            ? (maxWidth - spacing * 2) / 3
            : maxWidth >= 360
            ? (maxWidth - spacing) / 2
            : maxWidth;

        return Wrap(
          spacing: spacing,
          runSpacing: 10,
          children: List<Widget>.generate(distribution.length, (index) {
            final item = distribution[index];
            final color = palette[index % palette.length];
            final percent = total <= 0 ? 0 : (item.count / total) * 100;
            return SizedBox(
              width: itemWidth,
              child: Row(
                children: <Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${item.typeName} ${item.count} (${percent.toStringAsFixed(0)}%)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF344659),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}

class _TrendLineCard extends StatelessWidget {
  const _TrendLineCard({required this.trend, required this.palette});

  final StatisticsTrendData trend;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    if (trend.dateList.isEmpty || trend.series.isEmpty) {
      return const _ChartShell(
        child: const SizedBox(height: 320, child: AppEmptyView(icon: Icons.insert_chart_outlined_rounded, message: '暂无统计数据')),
      );
    }

    final seriesData =
        trend.series
            .map((series) {
              final total = series.dailyCounts.fold<int>(
                0,
                (sum, item) => sum + item,
              );
              return _LineSeriesModel(series: series, total: total);
            })
            .toList(growable: false)
          ..sort((a, b) => b.total.compareTo(a.total));

    final visibleSeries = seriesData.take(5).toList(growable: false);

    var maxY = 0;
    for (final model in visibleSeries) {
      for (final value in model.series.dailyCounts) {
        if (value > maxY) {
          maxY = value;
        }
      }
    }
    final safeMaxY = math.max<double>(6, ((maxY / 5).ceil() * 5).toDouble());

    final groupCount = trend.dateList.length;
    final barWidth = _barWidth(visibleSeries.length);
    final groups = List<BarChartGroupData>.generate(groupCount, (x) {
      final rods = List<BarChartRodData>.generate(visibleSeries.length, (
        index,
      ) {
        final counts = visibleSeries[index].series.dailyCounts;
        final y = x < counts.length ? counts[x].toDouble() : 0.0;
        return BarChartRodData(
          toY: y,
          width: barWidth,
          borderRadius: BorderRadius.circular(2),
          color: palette[index % palette.length],
        );
      });

      return BarChartGroupData(x: x, barsSpace: 3, barRods: rods);
    });

    return _ChartShell(
      child: SizedBox(
        height: 340,
        child: Column(
          children: <Widget>[
            Expanded(
              child: BarChart(
                BarChartData(
                  minY: 0,
                  maxY: safeMaxY,
                  alignment: BarChartAlignment.spaceAround,
                  groupsSpace: 12,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: safeMaxY / 5,
                    getDrawingHorizontalLine: (value) =>
                        const FlLine(color: Color(0xFFDCE5F1), strokeWidth: 1),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: const Border(
                      left: BorderSide(color: Color(0xFFC7D4E4), width: 1),
                      bottom: BorderSide(color: Color(0xFFC7D4E4), width: 1),
                      right: BorderSide.none,
                      top: BorderSide.none,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: safeMaxY / 5,
                        reservedSize: 22,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 2,
                          child: Text(
                            value.toInt().toString(),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: Color(0xFF7890A8),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        interval: _xInterval(trend.dateList.length),
                        getTitlesWidget: (value, _) {
                          final index = value.round();
                          if (index < 0 || index >= trend.dateList.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              _shortDate(trend.dateList[index]),
                              style: const TextStyle(
                                color: Color(0xFF5E738A),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: groups,
                  barTouchData: BarTouchData(enabled: false),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: List<Widget>.generate(visibleSeries.length, (index) {
                final color = palette[index % palette.length];
                final name = visibleSeries[index].series.typeName;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Color(0xFF32465C),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );
              }),
            ),
            if (trend.series.length > visibleSeries.length) ...<Widget>[
              const SizedBox(height: 6),
              const Text(
                '已展示数量最高的前5类趋势',
                style: TextStyle(
                  color: Color(0xFF8296AC),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  double _barWidth(int seriesCount) {
    if (seriesCount <= 1) {
      return 14;
    }
    if (seriesCount == 2) {
      return 11;
    }
    if (seriesCount == 3) {
      return 9;
    }
    if (seriesCount == 4) {
      return 8;
    }
    return 7;
  }

  double _xInterval(int count) {
    if (count <= 1) {
      return 1;
    }
    if (count <= 5) {
      return 1;
    }
    if (count <= 8) {
      return 2;
    }
    return (count / 4).floorToDouble();
  }

  String _shortDate(String source) {
    final text = source.trim();
    if (text.isEmpty) {
      return '--';
    }
    if (text.contains('-')) {
      final parts = text.split('-');
      if (parts.length >= 2) {
        return '${parts[parts.length - 2]}/${parts.last}';
      }
    }
    return text;
  }
}

class _LineSeriesModel {
  const _LineSeriesModel({required this.series, required this.total});

  final StatisticsTrendSeries series;
  final int total;
}

class _ChartShell extends StatelessWidget {
  const _ChartShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6E0EE)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1005273F),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7EA),
        border: Border.all(color: const Color(0xFFF3D095)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '统计数据加载失败',
            style: TextStyle(
              color: Color(0xFF925C17),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF9F6B24),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ),
        ],
      ),
    );
  }
}





