import 'dart:async';

import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/routing/route_paths.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/core/widgets/app_loading_overlay.dart';
import 'package:emergency_helper/src/features/home/data/notify_message_service.dart';
import 'package:emergency_helper/src/features/home/presentation/message_detail_page.dart';
import 'package:emergency_helper/src/features/push/data/push_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class MessageTabPage extends StatefulWidget {
  const MessageTabPage({
    super.key,
    this.onUnreadChanged,
    this.onUnreadHintChanged,
    this.isActive = false,
    this.unreadCountHint = 0,
  });

  final Future<void> Function()? onUnreadChanged;
  final ValueChanged<int>? onUnreadHintChanged;
  final bool isActive;
  final int unreadCountHint;

  @override
  State<MessageTabPage> createState() => _MessageTabPageState();
}

class _MessageTabPageState extends State<MessageTabPage>
    with AutomaticKeepAliveClientMixin<MessageTabPage> {
  static const int _pageSize = 20;
  static const Duration _activeAutoRefreshInterval = Duration(seconds: 20);
  static const List<Duration> _unreadSyncRetryDelays = <Duration>[
    Duration(milliseconds: 650),
    Duration(milliseconds: 1600),
    Duration(seconds: 3),
  ];

  final NotifyMessageService _service = const NotifyMessageService();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<PushIncomingEvent>? _pushEventSubscription;
  Timer? _activeAutoRefreshTimer;
  Timer? _autoRefreshDebounceTimer;
  Timer? _unreadChangedRetryTimer;
  int _unreadChangedRetryIndex = 0;

  List<NotifyMessageItem> _items = const <NotifyMessageItem>[];
  int _total = 0;
  int _currentPage = 1;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadingMore = false;
  bool _markingAllRead = false;
  String? _loadError;

  bool get _hasUnread => _items.any((item) => !item.readStatus);

  @override
  bool get wantKeepAlive {
    return true;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _subscribePushEvents();
    _syncActiveAutoRefreshTimer(active: widget.isActive);
    Future<void>.microtask(_refreshMessages);
  }

  @override
  void didUpdateWidget(covariant MessageTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      _syncActiveAutoRefreshTimer(active: widget.isActive);
      if (widget.isActive) {
        _scheduleAutoRefresh(const Duration(milliseconds: 250));
      }
    }
    if (widget.isActive && widget.unreadCountHint != oldWidget.unreadCountHint) {
      _scheduleAutoRefresh(const Duration(milliseconds: 200));
    }
  }

  @override
  void dispose() {
    _pushEventSubscription?.cancel();
    _activeAutoRefreshTimer?.cancel();
    _autoRefreshDebounceTimer?.cancel();
    _unreadChangedRetryTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text('\u6D88\u606F'),
        actions: <Widget>[
          TextButton(
            onPressed: _markingAllRead || !_hasUnread ? null : _markAllRead,
            child: Text(
              '\u5168\u90E8\u5DF2\u8BFB',
              style: TextStyle(
                color: _markingAllRead || !_hasUnread
                    ? Colors.white54
                    : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF3F6FA),
      body: AppLoadingOverlay(
        loading: _loading && _items.isEmpty,
        message: '\u52A0\u8F7D\u4E2D...',
        child: Column(
          children: <Widget>[
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
                        onPressed: _refreshMessages,
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
            Expanded(
              child: _items.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _refreshMessages,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const <Widget>[
                          SizedBox(height: 160),
                          _EmptyMessageView(),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _refreshMessages,
                      child: ListView.separated(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                        itemCount: _items.length + 1,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          if (index >= _items.length) {
                            return _buildFooter();
                          }
                          final item = _items[index];
                          return _MessageItemTile(
                            item: item,
                            onTap: () => _onTapMessage(item),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_hasMore) {
      return const SizedBox(height: 6);
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          '\u5DF2\u52A0\u8F7D\u5168\u90E8\u6D88\u606F',
          style: TextStyle(color: Color(0xFF9AA4B2), fontSize: 12),
        ),
      ),
    );
  }

  void _onScroll() {
    if (!_hasMore || _loading || _loadingMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels + 140 < position.maxScrollExtent) {
      return;
    }
    unawaited(_loadMoreMessages());
  }

  void _subscribePushEvents() {
    final dependencies = context.read<AppDependencies>();
    _pushEventSubscription = dependencies.pushService.incomingEventStream
        .listen((event) {
          if (!mounted || !widget.isActive) {
            return;
          }
          if (event.source == PushIncomingEventSource.notification ||
              event.source == PushIncomingEventSource.message) {
            _scheduleAutoRefresh(const Duration(milliseconds: 350));
          }
        });
  }

  void _syncActiveAutoRefreshTimer({required bool active}) {
    _activeAutoRefreshTimer?.cancel();
    if (!active) {
      return;
    }
    _activeAutoRefreshTimer = Timer.periodic(
      _activeAutoRefreshInterval,
      (_) => _scheduleAutoRefresh(const Duration(milliseconds: 120)),
    );
  }

  void _scheduleAutoRefresh(Duration delay) {
    if (!mounted || !widget.isActive) {
      return;
    }
    _autoRefreshDebounceTimer?.cancel();
    _autoRefreshDebounceTimer = Timer(delay, () {
      if (!mounted || !widget.isActive) {
        return;
      }
      if (_loading || _loadingMore || _markingAllRead) {
        return;
      }
      unawaited(_refreshMessages());
    });
  }

  Future<void> _refreshMessages() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
      _loadError = null;
      _currentPage = 1;
      _hasMore = true;
    });

    try {
      final dependencies = context.read<AppDependencies>();
      final page = await _service.loadMyPage(
        dependencies.apiClient,
        pageNo: 1,
        pageSize: _pageSize,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _items = page.list;
        _total = page.total;
        _hasMore = _items.length < _total;
      });
      await _notifyUnreadChanged();
    } on AppException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError =
            '\u6D88\u606F\u5217\u8868\u52A0\u8F7D\u5931\u8D25\uFF0C\u8BF7\u7A0D\u540E\u91CD\u8BD5';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_loading || _loadingMore || !_hasMore) {
      return;
    }
    setState(() {
      _loadingMore = true;
    });

    try {
      final dependencies = context.read<AppDependencies>();
      final nextPage = _currentPage + 1;
      final page = await _service.loadMyPage(
        dependencies.apiClient,
        pageNo: nextPage,
        pageSize: _pageSize,
      );
      if (!mounted) {
        return;
      }
      final merged = <NotifyMessageItem>[..._items, ...page.list];
      setState(() {
        _items = merged;
        _total = page.total;
        _currentPage = nextPage;
        _hasMore = merged.length < _total;
      });
    } catch (_) {
      // keep current list
    } finally {
      if (mounted) {
        setState(() {
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _onTapMessage(NotifyMessageItem item) async {
    if (!mounted) {
      return;
    }
    var current = item;
    for (final candidate in _items) {
      if (candidate.id == item.id) {
        current = candidate;
        break;
      }
    }
    final wasUnread = !current.readStatus;
    if (wasUnread) {
      final nextHint = (widget.unreadCountHint - 1).clamp(0, 9999).toInt();
      _emitUnreadHint(nextHint);
      setState(() {
        _items = _items
            .map(
              (candidate) => candidate.id == current.id
                  ? candidate.copyWith(readStatus: true)
                  : candidate,
            )
            .toList(growable: false);
      });
    }
    await context.push(
      RoutePaths.messageDetailById(item.id),
      extra: MessageDetailRouteExtra(
        initialItem: current,
        onReadChanged: _notifyUnreadChanged,
      ),
    );
    if (!mounted) {
      return;
    }
    await _refreshMessages();
    await _notifyUnreadChanged();
  }

  Future<void> _markAllRead() async {
    if (_markingAllRead || !_hasUnread) {
      return;
    }
    setState(() {
      _markingAllRead = true;
    });

    try {
      final dependencies = context.read<AppDependencies>();
      await _service.markAllRead(dependencies.apiClient);
      if (!mounted) {
        return;
      }
      setState(() {
        _items = _items
            .map((item) => item.copyWith(readStatus: true))
            .toList(growable: false);
      });
      _emitUnreadHint(0);
      await _notifyUnreadChanged();
      _showMessage('\u5DF2\u5168\u90E8\u6807\u8BB0\u4E3A\u5DF2\u8BFB');
    } on AppException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage(
        '\u64CD\u4F5C\u5931\u8D25\uFF0C\u8BF7\u7A0D\u540E\u91CD\u8BD5',
      );
    } finally {
      if (mounted) {
        setState(() {
          _markingAllRead = false;
        });
      }
    }
  }

  Future<void> _notifyUnreadChanged() async {
    final callback = widget.onUnreadChanged;
    if (callback == null) {
      return;
    }
    try {
      await callback();
    } catch (_) {}
    _scheduleUnreadChangedRetry();
  }

  void _scheduleUnreadChangedRetry() {
    _unreadChangedRetryTimer?.cancel();
    _unreadChangedRetryIndex = 0;
    _runUnreadChangedRetry();
  }

  void _runUnreadChangedRetry() {
    if (!mounted || _unreadChangedRetryIndex >= _unreadSyncRetryDelays.length) {
      return;
    }
    final callback = widget.onUnreadChanged;
    if (callback == null) {
      return;
    }
    final delay = _unreadSyncRetryDelays[_unreadChangedRetryIndex];
    _unreadChangedRetryIndex += 1;
    _unreadChangedRetryTimer = Timer(delay, () async {
      final followup = widget.onUnreadChanged;
      if (!mounted || followup == null) {
        return;
      }
      try {
        await followup();
      } catch (_) {}
      _runUnreadChangedRetry();
    });
  }

  void _emitUnreadHint(int value) {
    final callback = widget.onUnreadHintChanged;
    if (callback == null) {
      return;
    }
    callback(value.clamp(0, 9999).toInt());
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    AppCenterToast.show(context, message);
  }
}

class _MessageItemTile extends StatelessWidget {
  const _MessageItemTile({required this.item, required this.onTap});

  final NotifyMessageItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isUnread = !item.readStatus;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD9E4F1)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x120F2239),
                offset: Offset(0, 1),
                blurRadius: 6,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isUnread
                      ? const Color(0xFFDDEFFF)
                      : const Color(0xFFEFF2F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isUnread
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  color: isUnread
                      ? const Color(0xFF146FC6)
                      : const Color(0xFF8A96A6),
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFF1D2A3A),
                              fontSize: 14,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isUnread)
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF64B4A),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF55657A),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatTime(item.createTime),
                      style: const TextStyle(
                        color: Color(0xFF97A4B5),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: Color(0xFF93A2B7)),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) {
      return '--';
    }
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}

class _EmptyMessageView extends StatelessWidget {
  const _EmptyMessageView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: const <Widget>[
          Icon(
            Icons.mark_email_read_outlined,
            size: 44,
            color: Color(0xFF9AABBF),
          ),
          SizedBox(height: 10),
          Text(
            '\u6682\u65E0\u6D88\u606F',
            style: TextStyle(
              color: Color(0xFF6F8095),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
