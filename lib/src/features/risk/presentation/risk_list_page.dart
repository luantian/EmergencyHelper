import 'package:emergency_helper/src/core/routing/route_paths.dart';
import 'package:emergency_helper/src/features/risk/data/risk_center.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RiskListPage extends StatefulWidget {
  const RiskListPage({super.key});

  @override
  State<RiskListPage> createState() => _RiskListPageState();
}

class _RiskListPageState extends State<RiskListPage> {
  static const int _pageSize = 20;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  RiskProcessStatus _status = RiskProcessStatus.processing;
  int _currentPage = 1;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('risk-list-root'),
      appBar: AppBar(
        title: const Text('\u884D\u751F\u98CE\u9669'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF2F3F5),
      body: Column(
        children: <Widget>[
          _StatusTabs(
            status: _status,
            onChanged: (next) {
              setState(() {
                _status = next;
                _currentPage = 1;
              });
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFD8E1EC)),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x140F2239),
                          offset: Offset(0, 2),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      textAlignVertical: TextAlignVertical.center,
                      style: const TextStyle(fontSize: 14, height: 1.2),
                      decoration: const InputDecoration(
                        hintText: '\u641C\u7D22',
                        hintStyle: TextStyle(
                          color: Color(0xFF7C8794),
                          fontSize: 14,
                          height: 1.2,
                        ),
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        filled: false,
                        fillColor: Colors.transparent,
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: Color(0xFF6B7682),
                        ),
                        prefixIconConstraints: BoxConstraints(
                          minWidth: 36,
                          minHeight: 38,
                        ),
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _searchController.clear,
                  child: const Text(
                    '\u53D6\u6D88',
                    style: TextStyle(
                      color: Color(0xFF4D5968),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: RiskCenter.instance,
              builder: (context, _) {
                final allRisks = RiskCenter.instance.queryRisks(
                  status: _status,
                  keyword: _searchController.text,
                );
                final visibleCount = (_currentPage * _pageSize).clamp(
                  0,
                  allRisks.length,
                );
                final risks = allRisks.take(visibleCount).toList();
                final hasMore = visibleCount < allRisks.length;

                if (allRisks.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refreshRisks,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const <Widget>[
                        SizedBox(height: 140),
                        Center(
                          child: Text(
                            '\u6682\u65E0\u98CE\u9669',
                            style: TextStyle(
                              color: Color(0xFF808995),
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refreshRisks,
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: risks.length + 1,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemBuilder: (context, index) {
                      if (index == risks.length) {
                        return _buildRiskListFooter(hasMore);
                      }
                      final risk = risks[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _RiskCard(
                          risk: risk,
                          onTap: () {
                            context.push(RoutePaths.riskDetailById(risk.id));
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _onSearchChanged() {
    setState(() {
      _currentPage = 1;
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels + 180 >= position.maxScrollExtent) {
      _loadMoreRisks();
    }
  }

  Future<void> _refreshRisks() async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) {
      return;
    }
    setState(() {
      _currentPage = 1;
      _loadingMore = false;
    });
  }

  Future<void> _loadMoreRisks() async {
    final total = RiskCenter.instance.queryRisks(
      status: _status,
      keyword: _searchController.text,
    );
    final visibleCount = _currentPage * _pageSize;
    if (visibleCount >= total.length) {
      return;
    }
    setState(() {
      _loadingMore = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) {
      return;
    }
    setState(() {
      _currentPage += 1;
      _loadingMore = false;
    });
  }

  Widget _buildRiskListFooter(bool hasMore) {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(
            '\u6CA1\u6709\u66F4\u591A\u98CE\u9669\u4E86',
            style: TextStyle(color: Color(0xFF8D97A4), fontSize: 12),
          ),
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}

class _StatusTabs extends StatelessWidget {
  const _StatusTabs({required this.status, required this.onChanged});

  final RiskProcessStatus status;
  final ValueChanged<RiskProcessStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget buildItem(RiskProcessStatus value) {
      final selected = value == status;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFFEFFFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? const Color(0xFFD3E2F6) : Colors.transparent,
              ),
              boxShadow: selected
                  ? const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x140F2239),
                        offset: Offset(0, 1),
                        blurRadius: 4,
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  value == RiskProcessStatus.processing
                      ? Icons.hourglass_top_rounded
                      : Icons.task_alt_rounded,
                  size: 18,
                  color: selected
                      ? AppTheme.primaryBlue
                      : const Color(0xFF6A7581),
                ),
                const SizedBox(width: 6),
                Text(
                  _statusText(value),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? AppTheme.primaryBlue
                        : const Color(0xFF45515D),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFE9F0FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD6E2F1)),
        ),
        child: Row(
          children: <Widget>[
            buildItem(RiskProcessStatus.processing),
            const SizedBox(width: 4),
            buildItem(RiskProcessStatus.finished),
          ],
        ),
      ),
    );
  }

  String _statusText(RiskProcessStatus value) {
    switch (value) {
      case RiskProcessStatus.processing:
        return '\u5904\u7406\u4E2D';
      case RiskProcessStatus.finished:
        return '\u5DF2\u529E\u7ED3';
    }
  }
}

class _RiskCard extends StatelessWidget {
  const _RiskCard({required this.risk, required this.onTap});

  final RiskRecord risk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusForeground = risk.status == RiskProcessStatus.processing
        ? const Color(0xFF1F9A3C)
        : const Color(0xFF586579);
    final statusBackground = risk.status == RiskProcessStatus.processing
        ? const Color(0xFFE8F8EC)
        : const Color(0xFFE9ECF2);
    final levelColor = _levelTagColor(risk.level);
    final typeLabel = _normalizeRiskType(risk.type);
    final riskSummary = risk.description.trim().isEmpty
        ? '--'
        : risk.description.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD5E0EC)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x120F2239),
                offset: Offset(0, 2),
                blurRadius: 8,
              ),
              BoxShadow(
                color: Color(0x0A0F2239),
                offset: Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusBackground,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          risk.status == RiskProcessStatus.processing
                              ? Icons.timelapse_rounded
                              : Icons.check_circle_rounded,
                          size: 11,
                          color: statusForeground,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _statusText(risk.status),
                          style: TextStyle(
                            color: statusForeground,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (typeLabel != null) ...<Widget>[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '\u7C7B\u578B\uFF1A$typeLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF5F6D7E),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (risk.level.trim().isNotEmpty && risk.level != '--')
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: levelColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        risk.level,
                        style: TextStyle(
                          color: levelColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                risk.secondaryRisk,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF111821),
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDCE5F1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Row(
                      children: <Widget>[
                        Icon(
                          Icons.info_outline_rounded,
                          size: 13,
                          color: Color(0xFF708196),
                        ),
                        SizedBox(width: 5),
                        Text(
                          '\u98CE\u9669\u4FE1\u606F',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF677B91),
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      riskSummary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF4E5F73),
                        height: 1.32,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.place_outlined,
                      size: 15,
                      color: Color(0xFF738295),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      risk.location,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF2A3441),
                        height: 1.32,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFE8EDF4)),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.apartment_rounded,
                          size: 13,
                          color: Color(0xFF768394),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            risk.department,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF5D6977),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F7FC),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFD9E4F1)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.schedule_rounded,
                          size: 12,
                          color: Color(0xFF6C7D91),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatTime(risk.reportTime),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF4F627A),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusText(RiskProcessStatus value) {
    switch (value) {
      case RiskProcessStatus.processing:
        return '\u5904\u7406\u4E2D';
      case RiskProcessStatus.finished:
        return '\u5DF2\u529E\u7ED3';
    }
  }

  Color _levelTagColor(String levelText) {
    if (levelText.contains('\u7279\u522B\u91CD\u5927') ||
        levelText.contains('I')) {
      return const Color(0xFFE24D4D);
    }
    if (levelText.contains('\u91CD\u5927') || levelText.contains('II')) {
      return const Color(0xFFE38D33);
    }
    if (levelText.contains('\u8F83\u5927') || levelText.contains('III')) {
      return const Color(0xFFE0B13C);
    }
    return const Color(0xFF3B8F59);
  }

  String? _normalizeRiskType(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text == '--' || text.toLowerCase() == 'null') {
      return null;
    }
    if (RegExp(r'^\d+$').hasMatch(text)) {
      switch (int.tryParse(text)) {
        case 0:
          return '\u57CE\u5E02\u5185\u6D9D';
        case 1:
          return '\u68EE\u6797\u706B\u707E';
        case 2:
          return '\u5730\u8D28\u707E\u5BB3';
        case 3:
          return '\u4EA4\u901A\u4E8B\u6545';
        case 4:
          return '\u5176\u4ED6';
        default:
          return null;
      }
    }
    return text;
  }

  static String _formatTime(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}
