import 'dart:async';

import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/routing/route_paths.dart';
import 'package:emergency_helper/src/core/widgets/app_loading_overlay.dart';
import 'package:emergency_helper/src/features/event/data/event_center.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class EventListPage extends StatefulWidget {
  const EventListPage({super.key});

  @override
  State<EventListPage> createState() => _EventListPageState();
}

class _EventListPageState extends State<EventListPage> {
  static const int _pageSize = 20;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  EventProcessStatus _status = EventProcessStatus.processing;
  Timer? _searchDebounceTimer;
  int _currentPage = 1;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadingMore = false;
  String? _loadError;
  String? _loadMoreError;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    Future<void>.microtask(_refreshEvents);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('event-list-root'),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '\u8FD4\u56DE',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              context.pop();
              return;
            }
            context.go(RoutePaths.home);
          },
        ),
        title: const Text('\u4E8B\u4EF6\u4FE1\u606F'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        actions: <Widget>[
          IconButton(
            onPressed: _loading || _loadingMore ? null : _refreshEvents,
            icon: const Icon(Icons.refresh),
            tooltip: '\u5237\u65B0',
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF2F3F5),
      body: AppLoadingOverlay(
        loading: _loading,
        message: '\u52A0\u8F7D\u4E2D...',
        child: Column(
          children: <Widget>[
            _StatusTabs(
              status: _status,
              onChanged: (next) {
                setState(() {
                  _status = next;
                });
                _refreshEvents();
              },
            ),
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF6E8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF2C67A)),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFFC6781B),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _loadError!,
                          style: const TextStyle(
                            color: Color(0xFF8A5A14),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _refreshEvents,
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('\u91CD\u8BD5'),
                      ),
                    ],
                  ),
                ),
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
                    onTap: () {
                      _searchController.clear();
                    },
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
                animation: EventCenter.instance,
                builder: (context, _) {
                  final events = EventCenter.instance.queryEvents(
                    status: _status,
                    keyword: _searchController.text,
                  );

                  if (events.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _refreshEvents,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const <Widget>[
                          SizedBox(height: 140),
                          Center(
                            child: Text(
                              '\u6682\u65E0\u4E8B\u4EF6',
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
                    onRefresh: _refreshEvents,
                    child: ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: events.length + 1,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemBuilder: (context, index) {
                        if (index == events.length) {
                          return _buildListFooter();
                        }
                        final event = events[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _EventCard(
                            event: event,
                            onTap: () {
                              context.push(
                                RoutePaths.eventDetailById(event.id),
                              );
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
      ),
    );
  }

  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(
      const Duration(milliseconds: 400),
      _refreshEvents,
    );
    setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _loading ||
        _loadingMore ||
        !_hasMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels + 180 >= position.maxScrollExtent) {
      _loadMoreEvents();
    }
  }

  Future<void> _refreshEvents() {
    return _loadEvents(pageNo: 1, append: false);
  }

  Future<void> _loadMoreEvents() {
    if (_loading || _loadingMore || !_hasMore) {
      return Future<void>.value();
    }
    return _loadEvents(pageNo: _currentPage + 1, append: true);
  }

  Future<void> _loadEvents({required int pageNo, required bool append}) async {
    if (!mounted) {
      return;
    }

    if (append) {
      setState(() {
        _loadingMore = true;
        _loadMoreError = null;
      });
    } else {
      setState(() {
        _loading = true;
        _loadError = null;
        _loadMoreError = null;
      });
    }

    String? loadError;
    for (var attempt = 0; attempt < (append ? 1 : 2); attempt += 1) {
      try {
        final dependencies = context.read<AppDependencies>();
        EventCenter.instance.bindApiClient(dependencies.apiClient);
        final result = await EventCenter.instance.loadEvents(
          status: _status,
          keyword: _searchController.text.trim(),
          pageNo: pageNo,
          pageSize: _pageSize,
          append: append,
        );
        if (mounted) {
          setState(() {
            _currentPage = pageNo;
            _hasMore = result.hasMore;
          });
        }
        loadError = null;
        break;
      } on AppException catch (error) {
        loadError = error.message;
        final canRetry = !append && attempt == 0 && _shouldAutoRetry(loadError);
        if (canRetry) {
          await Future<void>.delayed(const Duration(milliseconds: 320));
          continue;
        }
        break;
      } catch (_) {
        loadError =
            '\u52A0\u8F7D\u4E8B\u4EF6\u5217\u8868\u5931\u8D25\uFF0C\u8BF7\u7A0D\u540E\u91CD\u8BD5';
        if (!append && attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 320));
          continue;
        }
        break;
      }
    }
    if (!mounted) {
      return;
    }
    if (append) {
      setState(() {
        _loadingMore = false;
        _loadMoreError = loadError;
      });
    } else {
      setState(() {
        _loading = false;
        _loadError = loadError;
      });
    }
  }

  Widget _buildListFooter() {
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
    if (_loadMoreError != null && _loadMoreError!.trim().isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: TextButton(
            onPressed: _loadMoreEvents,
            child: const Text(
              '\u52A0\u8F7D\u66F4\u591A\u5931\u8D25\uFF0C\u70B9\u51FB\u91CD\u8BD5',
            ),
          ),
        ),
      );
    }
    if (!_hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(
            '\u6CA1\u6709\u66F4\u591A\u4E8B\u4EF6\u4E86',
            style: TextStyle(color: Color(0xFF8D97A4), fontSize: 12),
          ),
        ),
      );
    }
    return const SizedBox(height: 8);
  }

  bool _shouldAutoRetry(String? message) {
    final text = message?.toLowerCase() ?? '';
    if (text.isEmpty) {
      return true;
    }
    return text.contains('\u7CFB\u7EDF\u5F02\u5E38') ||
        text.contains('\u8BF7\u6C42\u5904\u7406\u5931\u8D25') ||
        text.contains('\u7F51\u7EDC\u8BF7\u6C42\u5931\u8D25') ||
        text.contains('http 5') ||
        text.contains('\u7A0D\u540E\u91CD\u8BD5');
  }
}

class _StatusTabs extends StatelessWidget {
  const _StatusTabs({required this.status, required this.onChanged});

  final EventProcessStatus status;
  final ValueChanged<EventProcessStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget buildItem(EventProcessStatus value) {
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
                  value == EventProcessStatus.processing
                      ? Icons.hourglass_top_rounded
                      : Icons.task_alt_rounded,
                  size: 18,
                  color: selected
                      ? AppTheme.primaryBlue
                      : const Color(0xFF6A7581),
                ),
                const SizedBox(width: 6),
                Text(
                  value.label,
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
            buildItem(EventProcessStatus.processing),
            const SizedBox(width: 4),
            buildItem(EventProcessStatus.finished),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onTap});

  final EventRecord event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusForeground = event.status == EventProcessStatus.processing
        ? const Color(0xFF1F9A3C)
        : const Color(0xFF586579);
    final statusBackground = event.status == EventProcessStatus.processing
        ? const Color(0xFFE8F8EC)
        : const Color(0xFFE9ECF2);
    final levelColor = _levelTagColor(event.level);
    final typeLabel = _normalizeEventType(event.type);

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
                          event.status == EventProcessStatus.processing
                              ? Icons.timelapse_rounded
                              : Icons.check_circle_rounded,
                          size: 11,
                          color: statusForeground,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          event.status.label,
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
                  if (event.level.trim().isNotEmpty && event.level != '--')
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
                        event.level,
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
                event.name,
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
                      event.location,
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
                            event.department,
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
                          _formatTime(event.reportTime),
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

  String? _normalizeEventType(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text == '--' || text.toLowerCase() == 'null') {
      return null;
    }
    return text;
  }

  static String _formatTime(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}
