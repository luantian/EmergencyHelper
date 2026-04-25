import 'dart:async';

import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/core/widgets/app_loading_overlay.dart';
import 'package:emergency_helper/src/features/home/data/notify_message_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MessageDetailPage extends StatefulWidget {
  const MessageDetailPage({
    super.key,
    required this.messageId,
    this.initialItem,
    this.onReadChanged,
  });

  final int messageId;
  final NotifyMessageItem? initialItem;
  final Future<void> Function()? onReadChanged;

  @override
  State<MessageDetailPage> createState() => _MessageDetailPageState();
}

class MessageDetailRouteExtra {
  const MessageDetailRouteExtra({
    this.initialItem,
    this.onReadChanged,
  });

  final NotifyMessageItem? initialItem;
  final Future<void> Function()? onReadChanged;
}

class _MessageDetailPageState extends State<MessageDetailPage> {
  final NotifyMessageService _service = const NotifyMessageService();

  NotifyMessageItem? _item;
  bool _loading = false;
  bool _markingRead = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _item = widget.initialItem;
    Future<void>.microtask(() async {
      await _markAsReadIfNeeded();
      await _loadDetail();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text('\u6D88\u606F\u8BE6\u60C5'),
      ),
      backgroundColor: const Color(0xFFF3F6FA),
      body: AppLoadingOverlay(
        loading: _loading && _item == null,
        message: '\u52A0\u8F7D\u4E2D...',
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_errorText != null && _item == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.info_outline,
                color: Color(0xFF97A4B5),
                size: 38,
              ),
              const SizedBox(height: 10),
              Text(
                _errorText!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF596A80),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _loadDetail,
                child: const Text('\u91CD\u8BD5'),
              ),
            ],
          ),
        ),
      );
    }

    final item = _item;
    if (item == null) {
      return const SizedBox.shrink();
    }

    return RefreshIndicator(
      onRefresh: _loadDetail,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDCE6F3)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x120F2239),
                  offset: Offset(0, 1),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Color(0xFF1C2A3B),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    _InfoChip(
                      icon: Icons.schedule_outlined,
                      label: _formatTime(item.createTime),
                    ),
                    if ((item.senderName ?? '').isNotEmpty)
                      _InfoChip(
                        icon: Icons.person_outline,
                        label: item.senderName!,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1, color: Color(0xFFE3EAF4)),
                const SizedBox(height: 12),
                Text(
                  item.content,
                  style: const TextStyle(
                    color: Color(0xFF2A3A4E),
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadDetail() async {
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
      _errorText = null;
    });

    try {
      final dependencies = context.read<AppDependencies>();
      final detail = await _service.getDetail(
        dependencies.apiClient,
        widget.messageId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _item = detail;
      });
    } on AppException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = '\u6D88\u606F\u8BE6\u60C5\u52A0\u8F7D\u5931\u8D25\uFF0C\u8BF7\u7A0D\u540E\u91CD\u8BD5';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _markAsReadIfNeeded() async {
    if (_markingRead || widget.messageId <= 0) {
      return;
    }
    final current = _item;
    if (current != null && current.readStatus) {
      return;
    }

    _markingRead = true;
    try {
      final dependencies = context.read<AppDependencies>();
      await _service.markRead(dependencies.apiClient, <int>[widget.messageId]);
      if (mounted) {
        setState(() {
          final currentItem = _item;
          if (currentItem != null && !currentItem.readStatus) {
            _item = currentItem.copyWith(readStatus: true);
          }
        });
      }
      final callback = widget.onReadChanged;
      if (callback != null) {
        try {
          await callback();
        } catch (_) {}
      }
    } catch (_) {
      // Keep detail page available even when mark-read request fails.
    } finally {
      _markingRead = false;
    }
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: const Color(0xFF5E7390)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF5E7390),
              fontSize: 11.5,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
