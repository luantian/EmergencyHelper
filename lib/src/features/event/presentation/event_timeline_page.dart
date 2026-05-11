import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/widgets/app_empty_view.dart';
import 'package:emergency_helper/src/core/widgets/app_loading_overlay.dart';
import 'package:emergency_helper/src/features/event/data/event_center.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class EventTimelinePage extends StatefulWidget {
  const EventTimelinePage({required this.eventId, super.key});

  final String eventId;

  @override
  State<EventTimelinePage> createState() => _EventTimelinePageState();
}

class _EventTimelinePageState extends State<EventTimelinePage> {
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadTimeline);
  }

  Future<void> _loadTimeline() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final dependencies = context.read<AppDependencies>();
      EventCenter.instance.bindApiClient(dependencies.apiClient);
      await EventCenter.instance.loadEventDetail(widget.eventId);
    } on AppException catch (error) {
      _loadError = error.message;
    } catch (_) {
      _loadError = '加载事件动态失败，请稍后重试';
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: EventCenter.instance,
      builder: (context, _) {
        final event = EventCenter.instance.eventById(widget.eventId);
        return Scaffold(
          key: const Key('event-timeline-root'),
          appBar: AppBar(
            title: const Text('事件动态'),
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
            actions: <Widget>[
              IconButton(
                onPressed: _loading ? null : _loadTimeline,
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
              ),
            ],
          ),
          backgroundColor: const Color(0xFFF2F3F5),
          body: AppLoadingOverlay(
            loading: _loading,
            message: '加载中...',
            child: _buildBody(event),
          ),
        );
      },
    );
  }

  Widget _buildBody(EventRecord? event) {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF6A7480), fontSize: 14),
              ),
              const SizedBox(height: 10),
              ElevatedButton(onPressed: _loadTimeline, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    if (event == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: AppEmptyView(
            icon: Icons.event_busy_outlined,
            message: '该事件不存在或已被删除',
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD8DEE6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                event.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1B2027),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '当前阶段：${event.status.label}',
                style: const TextStyle(fontSize: 15, color: Color(0xFF445061)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD8DEE6)),
          ),
          child: ListView.builder(
            itemCount: event.timeline.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) {
              final item = event.timeline[index];
              final isLast = index == event.timeline.length - 1;
              return _TimelineCell(item: item, isLast: isLast);
            },
          ),
        ),
      ],
    );
  }
}

class _TimelineCell extends StatelessWidget {
  const _TimelineCell({required this.item, required this.isLast});

  final EventTimelineItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              _formatTime(item.time),
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1A2027),
                height: 1.35,
              ),
            ),
          ),
          Column(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF2088E8),
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: const Color(0xFF2088E8),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.stage,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A2027),
                    ),
                  ),
                  if ((item.receiverNames ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '接收人：${item.receiverNames!}',
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF222A33),
                        ),
                      ),
                    ),
                  if ((item.content ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '内容：${item.content!}',
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF222A33),
                        ),
                      ),
                    ),
                  if ((item.operatorName ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '操作人：${item.operatorName!}',
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF222A33),
                        ),
                      ),
                    ),
                  if ((item.attachmentName ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '附件：${item.attachmentName!}',
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF4D5868),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${value.year}-${two(value.month)}-${two(value.day)}';
    final time = '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
    return '$date\n$time';
  }
}
