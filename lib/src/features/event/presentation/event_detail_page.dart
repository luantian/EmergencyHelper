import 'dart:io';

import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/media/app_video_player_page.dart';
import 'package:emergency_helper/src/core/routing/route_paths.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/core/widgets/app_loading_overlay.dart';
import 'package:emergency_helper/src/features/event/data/event_center.dart';
import 'package:emergency_helper/src/features/event/presentation/event_transfer_picker_page.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class EventDetailPage extends StatefulWidget {
  const EventDetailPage({required this.eventId, super.key});

  final String eventId;

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  bool _loading = true;
  bool _operating = false;
  String? _loadError;
  bool _canTransfer = false;
  bool _canFeedback = false;
  bool _canClose = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadDetail);
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _canTransfer = false;
      _canFeedback = false;
      _canClose = false;
    });

    String? loadError;
    for (var attempt = 0; attempt < 2; attempt += 1) {
      try {
        final dependencies = context.read<AppDependencies>();
        EventCenter.instance.bindApiClient(dependencies.apiClient);
        await EventCenter.instance.loadEventDetail(widget.eventId);
        await _loadOperatePermissions(dependencies);
        loadError = null;
        break;
      } on AppException catch (error) {
        final hasCached =
            EventCenter.instance.eventById(widget.eventId) != null;
        loadError = hasCached ? null : error.message;
        final canRetry = attempt == 0 && _shouldAutoRetry(loadError);
        if (canRetry) {
          await Future<void>.delayed(const Duration(milliseconds: 320));
          continue;
        }
        break;
      } catch (_) {
        final hasCached =
            EventCenter.instance.eventById(widget.eventId) != null;
        loadError = hasCached
            ? null
            : '\u52A0\u8F7D\u4E8B\u4EF6\u8BE6\u60C5\u5931\u8D25\uFF0C\u8BF7\u7A0D\u540E\u91CD\u8BD5';
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 320));
          continue;
        }
        break;
      }
    }

    if (mounted) {
      setState(() {
        _loading = false;
        _loadError = loadError;
      });
    }
  }

  Future<void> _loadOperatePermissions(AppDependencies dependencies) async {
    EventCenter.instance.bindApiClient(dependencies.apiClient);
    final canTransfer = await EventCenter.instance.canTransfer(widget.eventId);
    final canFeedback = await EventCenter.instance.canFeedback(widget.eventId);
    final canClose = await EventCenter.instance.canClose();

    if (!mounted) {
      return;
    }
    setState(() {
      _canTransfer = canTransfer;
      _canFeedback = canFeedback;
      _canClose = canClose;
    });
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

  Future<void> _onTransfer(EventRecord event) async {
    final canTransfer = await EventCenter.instance.canTransfer(event.id);
    if (!mounted) {
      return;
    }
    if (!canTransfer) {
      setState(() {
        _canTransfer = false;
      });
      _showMessage(
        '\u5F53\u524D\u8D26\u53F7\u65E0\u4E8B\u4EF6\u8F6C\u6D3E\u6743\u9650',
      );
      return;
    }
    final selection = await context.push<EventTransferSelection>(
      RoutePaths.eventTransferPickerById(event.id),
    );
    if (!mounted || selection == null || selection.userIds.isEmpty) {
      return;
    }

    setState(() => _operating = true);
    try {
      await EventCenter.instance.transfer(
        eventId: event.id,
        userIds: selection.userIds,
        content: '\u8BF7\u5C3D\u5FEB\u5230\u73B0\u573A\u5904\u7406',
      );
      _showMessage(
        '\u4E8B\u4EF6\u5DF2\u8F6C\u6D3E\uFF1A${selection.userNames.join('\u3001')}',
      );
      await _loadDetail();
    } on AppException catch (error) {
      _showMessage(
        _friendlyOperateError(
          error.message,
          fallback: '\u8F6C\u6D3E\u5931\u8D25',
        ),
      );
    } catch (_) {
      _showMessage(
        '\u8F6C\u6D3E\u5931\u8D25\uFF0C\u8BF7\u7A0D\u540E\u91CD\u8BD5',
      );
    } finally {
      if (mounted) {
        setState(() => _operating = false);
      }
    }
  }

  Future<void> _onClose(EventRecord event) async {
    final canClose = await EventCenter.instance.canClose();
    if (!mounted) {
      return;
    }
    if (!canClose) {
      setState(() {
        _canClose = false;
      });
      _showMessage(
        '\u5F53\u524D\u8D26\u53F7\u65E0\u4E8B\u4EF6\u529E\u7ED3\u6743\u9650',
      );
      return;
    }
    setState(() => _operating = true);
    try {
      await EventCenter.instance.finish(
        event.id,
        closeReason: '\u4E8B\u4EF6\u5DF2\u5904\u7406\u5B8C\u6BD5',
      );
      _showMessage('\u4E8B\u4EF6\u5DF2\u529E\u7ED3');
      await _loadDetail();
    } on AppException catch (error) {
      _showMessage(
        _friendlyOperateError(
          error.message,
          fallback: '\u529E\u7ED3\u5931\u8D25',
        ),
      );
    } catch (_) {
      _showMessage(
        '\u529E\u7ED3\u5931\u8D25\uFF0C\u8BF7\u7A0D\u540E\u91CD\u8BD5',
      );
    } finally {
      if (mounted) {
        setState(() => _operating = false);
      }
    }
  }

  String _friendlyOperateError(String message, {required String fallback}) {
    final text = message.trim();
    if (text.isEmpty) {
      return '$fallback\uFF0C\u8BF7\u7A0D\u540E\u91CD\u8BD5';
    }
    if (text == '\u7CFB\u7EDF\u5F02\u5E38') {
      return '$fallback\uFF1A\u5F53\u524D\u8D26\u53F7\u6682\u65E0\u6743\u9650\u6216\u8BE5\u4E8B\u4EF6\u72B6\u6001\u4E0D\u5141\u8BB8\u64CD\u4F5C';
    }
    return text;
  }

  Future<void> _onFeedback(EventRecord event) async {
    final canFeedback = await EventCenter.instance.canFeedback(event.id);
    if (!mounted) {
      return;
    }
    if (!canFeedback) {
      setState(() {
        _canFeedback = false;
      });
      _showMessage(
        '\u5F53\u524D\u8D26\u53F7\u65E0\u4E8B\u4EF6\u53CD\u9988\u6743\u9650',
      );
      return;
    }
    final submitted = await context.push<bool>(
      RoutePaths.eventFeedbackById(event.id),
    );
    if (!mounted || submitted != true) {
      return;
    }
    await _loadDetail();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: EventCenter.instance,
      builder: (context, _) {
        final event = EventCenter.instance.eventById(widget.eventId);
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: '\u8FD4\u56DE',
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  context.pop();
                  return;
                }
                context.go(RoutePaths.eventList);
              },
            ),
            title: const Text('\u4E8B\u4EF6\u8BE6\u60C5'),
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
            actions: <Widget>[
              IconButton(
                onPressed: _loading || _operating ? null : _loadDetail,
                icon: const Icon(Icons.refresh),
                tooltip: '\u5237\u65B0',
              ),
            ],
          ),
          backgroundColor: const Color(0xFFF3F6FA),
          body: AppLoadingOverlay(
            loading: _loading || _operating,
            message: _loading
                ? '\u52A0\u8F7D\u4E2D...'
                : '\u5904\u7406\u4E2D...',
            child: _buildBody(event),
          ),
        );
      },
    );
  }

  Widget _buildBody(EventRecord? event) {
    if (event == null && _loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF5B6776), fontSize: 14),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _loadDetail,
                child: const Text('\u91CD\u8BD5'),
              ),
            ],
          ),
        ),
      );
    }
    if (event == null) {
      return const Center(
        child: Text('\u4E8B\u4EF6\u4E0D\u5B58\u5728\u6216\u5DF2\u5220\u9664'),
      );
    }

    final canOperate = event.status == EventProcessStatus.processing;
    final canTransfer = canOperate && _canTransfer;
    final canFeedback = canOperate && _canFeedback;
    final canClose = canOperate && _canClose;
    final typeLabel = _normalizeEventType(event.type) ?? event.type;
    final statusText = _statusText(event.status);

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            children: <Widget>[
              if (_loadError != null) _buildErrorBanner(),
              _buildSummaryCard(event, statusText, typeLabel),
              const SizedBox(height: 10),
              _buildSection(
                title: '\u4E8B\u4EF6\u4FE1\u606F',
                child: Column(
                  children: <Widget>[
                    _buildInfoRow('\u4E8B\u4EF6\u540D\u79F0', event.name),
                    _buildInfoRow(
                      '\u4E8B\u4EF6\u63CF\u8FF0',
                      event.description,
                    ),
                    _buildInfoRow(
                      '\u4E8B\u4EF6\u72B6\u6001',
                      null,
                      valueWidget: _statusTag(statusText),
                    ),
                    _buildInfoRow('\u4E8B\u4EF6\u7EA7\u522B', event.level),
                    _buildInfoRow('\u4E8B\u4EF6\u7C7B\u578B', typeLabel),
                    _buildInfoRow('\u4E0A\u62A5\u5355\u4F4D', event.department),
                    _buildInfoRow(
                      '\u4E0A\u62A5\u65F6\u95F4',
                      _formatTime(event.reportTime),
                    ),
                    _buildInfoRow(
                      '\u4E8B\u4EF6\u5730\u70B9',
                      event.location,
                      onTap: () => _openLocationInMap(event.location),
                    ),
                    _buildInfoRow('\u6240\u5C5E\u8857\u9053', event.street),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _buildSection(
                title: '\u9644\u4EF6\u4FE1\u606F',
                child: _buildAttachments(event),
              ),
              const SizedBox(height: 10),
              _buildSection(
                title: '\u4E8B\u4EF6\u52A8\u6001',
                child: _buildTimeline(event.timeline),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFD8E2EE))),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _actionButton(
                  text: '\u53CD\u9988',
                  icon: Icons.chat_bubble_outline_rounded,
                  enabled: canFeedback,
                  onPressed: () => _onFeedback(event),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  text: '\u8F6C\u6D3E',
                  icon: Icons.send_outlined,
                  enabled: canTransfer,
                  onPressed: () => _onTransfer(event),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  text: '\u529E\u7ED3',
                  icon: Icons.task_alt_rounded,
                  enabled: canClose,
                  onPressed: () => _onClose(event),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF2C67A)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFC6781B),
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _loadError!,
              style: const TextStyle(
                color: Color(0xFF8A5A14),
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
          TextButton(
            onPressed: _loadDetail,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('\u91CD\u8BD5'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    EventRecord event,
    String statusText,
    String typeLabel,
  ) {
    final levelColor = _levelTagColor(event.level);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6E1EE)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120F2239),
            offset: Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  event.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF131C28),
                    fontSize: 16,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _statusTag(statusText),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _metaTag(
                Icons.label_outline_rounded,
                '\u7C7B\u578B\uFF1A$typeLabel',
              ),
              _metaTag(
                Icons.flag_outlined,
                '\u7EA7\u522B\uFF1A${event.level}',
                foreground: levelColor,
                background: levelColor.withValues(alpha: 0.12),
              ),
              _metaTag(Icons.schedule_rounded, _formatTime(event.reportTime)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.place_outlined,
                  size: 14,
                  color: Color(0xFF6E8097),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  event.location,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF3E4E62),
                    fontSize: 12.5,
                    height: 1.32,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6E1EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF192331),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String? value, {
    Widget? valueWidget,
    VoidCallback? onTap,
  }) {
    final text = value?.trim() ?? '';
    final displayValue = text.isEmpty ? '--' : text;
    final canOpenMap = onTap != null && displayValue != '--';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6A7A8E),
                fontSize: 12.5,
                height: 1.32,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child:
                valueWidget ?? _buildInfoValue(displayValue, canOpenMap, onTap),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoValue(
    String displayValue,
    bool canOpenMap,
    VoidCallback? onTap,
  ) {
    if (!canOpenMap || onTap == null) {
      return Text(
        displayValue,
        style: const TextStyle(
          color: Color(0xFF1A2330),
          fontSize: 13.5,
          height: 1.35,
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              displayValue,
              style: const TextStyle(
                color: Color(0xFF2088E8),
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.map_outlined, size: 16, color: Color(0xFF2088E8)),
          ),
        ],
      ),
    );
  }

  Future<void> _openLocationInMap(String? rawLocation) async {
    final location = (rawLocation ?? '').trim();
    if (location.isEmpty || location == '--') {
      _showMessage(
        '\u5730\u70B9\u4FE1\u606F\u4E3A\u7A7A\uFF0C\u65E0\u6CD5\u5BFC\u822A',
      );
      return;
    }

    final options = await _collectAvailableMapOptions(location);
    if (!mounted) {
      return;
    }
    if (options.isEmpty) {
      _showMessage(
        '\u672A\u68C0\u6D4B\u5230\u53EF\u7528\u5730\u56FE\u5E94\u7528',
      );
      return;
    }

    _MapLaunchOption? selected;
    if (options.length == 1) {
      selected = options.first;
    } else {
      selected = await showModalBottomSheet<_MapLaunchOption>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
        builder: (sheetContext) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: 10),
                const Text(
                  '\u9009\u62E9\u5730\u56FE',
                  style: TextStyle(
                    color: Color(0xFF1A2330),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                for (final option in options)
                  ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.map_outlined,
                      color: Color(0xFF2088E8),
                    ),
                    title: Text(option.label),
                    onTap: () => Navigator.of(sheetContext).pop(option),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
    }

    if (!mounted || selected == null) {
      return;
    }
    var opened = await launchUrl(
      selected.uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      opened = await launchUrl(selected.uri, mode: LaunchMode.platformDefault);
    }
    if (!opened && mounted) {
      _showMessage('\u65E0\u6CD5\u6253\u5F00\u5730\u56FE');
    }
  }

  Future<List<_MapLaunchOption>> _collectAvailableMapOptions(
    String location,
  ) async {
    final options = <_MapLaunchOption>[
      _MapLaunchOption(
        label: '\u767E\u5EA6\u5730\u56FE',
        uri: Uri(
          scheme: 'baidumap',
          host: 'map',
          path: '/geocoder',
          queryParameters: <String, String>{
            'src': 'EmergencyHelper',
            'address': location,
          },
        ),
      ),
      _MapLaunchOption(
        label: '\u9AD8\u5FB7\u5730\u56FE',
        uri: Uri(
          scheme: 'androidamap',
          host: 'poi',
          queryParameters: <String, String>{
            'sourceApplication': 'EmergencyHelper',
            'keywords': location,
            'dev': '0',
          },
        ),
      ),
      _MapLaunchOption(
        label: '\u817E\u8BAF\u5730\u56FE',
        uri: Uri.parse(
          'qqmap://map/search?keyword=${Uri.encodeComponent(location)}&referer=EmergencyHelper',
        ),
      ),
      _MapLaunchOption(
        label: '\u534E\u4E3A\u5730\u56FE',
        uri: Uri.parse(
          'petalmaps://map/search?query=${Uri.encodeComponent(location)}',
        ),
      ),
      _MapLaunchOption(
        label: '\u7CFB\u7EDF\u5730\u56FE',
        uri: Uri.parse('geo:0,0?q=${Uri.encodeComponent(location)}'),
      ),
    ];

    final available = <_MapLaunchOption>[];
    for (final option in options) {
      try {
        if (await canLaunchUrl(option.uri)) {
          available.add(option);
        }
      } catch (_) {}
    }
    if (available.isEmpty) {
      final systemFallback = options.lastWhere(
        (option) => option.label == '\u7CFB\u7EDF\u5730\u56FE',
        orElse: () => options.last,
      );
      available.add(systemFallback);
    }
    return available;
  }

  Widget _buildAttachments(EventRecord event) {
    final attachments = event.attachments;
    if (attachments.isEmpty) {
      return const Text(
        '\u6682\u65E0\u9644\u4EF6',
        style: TextStyle(color: Color(0xFF8F9BAB), fontSize: 13.5),
      );
    }
    return Column(
      children: <Widget>[
        for (var i = 0; i < attachments.length; i++) ...<Widget>[
          _buildAttachmentItem(attachments[i]),
          if (i != attachments.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildAttachmentItem(EventAttachmentPayload attachment) {
    final name = attachment.name.trim().isEmpty
        ? '\u9644\u4EF6\u6587\u4EF6'
        : attachment.name.trim();
    final resolvedSource = _resolveAttachmentSourceFromPayload(attachment);
    final isImage = _isImageResource(
      name: name,
      pathOrUrl: resolvedSource,
      type: attachment.type,
    );
    final isVideo = _isVideoResource(
      name: name,
      pathOrUrl: resolvedSource,
      type: attachment.type,
    );
    final isNetwork =
        resolvedSource != null && _isNetworkSource(resolvedSource);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final source = resolvedSource;
        if (source == null || source.trim().isEmpty) {
          _showMessage(
            '\u9644\u4EF6\u5730\u5740\u65E0\u6548\uFF0C\u65E0\u6CD5\u9884\u89C8',
          );
          return;
        }
        if (isImage) {
          await _showImagePreview(source, name, isNetwork: isNetwork);
          return;
        }
        if (isVideo) {
          if (isNetwork) {
            await _showVideoPreviewDialog(source, name);
          } else {
            await _openAttachment(source, isVideo: true);
          }
          return;
        }
        await _openAttachment(source);
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFE),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFDCE5F1)),
        ),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: (isImage && resolvedSource != null)
                  ? (isNetwork
                        ? Image.network(
                            resolvedSource,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _buildBrokenThumb(),
                          )
                        : Image.file(
                            File(resolvedSource),
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _buildBrokenThumb(),
                          ))
                  : Container(
                      width: 72,
                      height: 72,
                      color: const Color(0xFFEFF3F8),
                      alignment: Alignment.center,
                      child: Icon(
                        isVideo
                            ? Icons.play_circle_outline_rounded
                            : Icons.attach_file_rounded,
                        color: const Color(0xFF5C6F86),
                        size: 30,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF1A2330),
                      fontSize: 13.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isVideo
                        ? '\u70B9\u51FB\u64AD\u653E\u89C6\u9891'
                        : (isImage
                              ? '\u70B9\u51FB\u67E5\u770B\u5927\u56FE'
                              : '\u70B9\u51FB\u6253\u5F00\u9644\u4EF6'),
                    style: const TextStyle(
                      color: Color(0xFF2088E8),
                      fontSize: 12.5,
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
  }

  Widget _buildBrokenThumb() {
    return Container(
      width: 72,
      height: 72,
      color: const Color(0xFFEFF3F8),
      alignment: Alignment.center,
      child: const Icon(
        Icons.broken_image_outlined,
        color: Color(0xFF9AA3AE),
        size: 24,
      ),
    );
  }

  Widget _buildTimeline(List<EventTimelineItem> items) {
    if (items.isEmpty) {
      return const Text(
        '\u6682\u65E0\u52A8\u6001',
        style: TextStyle(color: Color(0xFF7C8794), fontSize: 13.5),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDCE5F1)),
      ),
      child: Column(
        children: <Widget>[
          for (var i = 0; i < items.length; i++)
            _buildTimelineItem(items[i], i == items.length - 1),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(EventTimelineItem item, bool isLast) {
    return IntrinsicHeight(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 98,
              child: Text(
                _formatTimelineTime(item.time),
                style: const TextStyle(
                  color: Color(0xFF405166),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ),
            Column(
              children: <Widget>[
                SizedBox(
                  height: 19,
                  child: Center(
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2088E8),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 1),
                      color: const Color(0xFF2088E8),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.stage,
                    style: const TextStyle(
                      color: Color(0xFF1A2330),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((item.receiverNames ?? '').trim().isNotEmpty)
                    _timelineMeta(
                      '\u63A5\u6536\u4EBA\uFF1A${item.receiverNames!}',
                    ),
                  if ((item.content ?? '').trim().isNotEmpty)
                    _timelineMeta('\u5185\u5BB9\uFF1A${item.content!}'),
                  if ((item.operatorName ?? '').trim().isNotEmpty)
                    _timelineMeta(
                      '\u64CD\u4F5C\u4EBA\uFF1A${item.operatorName!}',
                    ),
                  if (_timelineAttachments(item).isNotEmpty)
                    _buildTimelineAttachments(item),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timelineMeta(String text, {Color color = const Color(0xFF334355)}) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12.5, height: 1.28),
      ),
    );
  }

  Widget _buildTimelineAttachments(EventTimelineItem item) {
    final attachments = _timelineAttachments(item);
    if (attachments.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        children: [
          for (var i = 0; i < attachments.length; i++) ...[
            _buildTimelineAttachmentItem(attachments[i]),
            if (i != attachments.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineAttachmentItem(EventAttachmentPayload attachment) {
    final rawName = attachment.name.trim();
    final name = rawName.isEmpty ? '附件文件' : rawName;
    final source = attachment.path.trim().isNotEmpty
        ? attachment.path
        : attachment.name;
    final resolvedSource = _resolveAttachmentSource(source);
    final isImage = _isImageResource(
      name: name,
      pathOrUrl: resolvedSource ?? source,
      type: attachment.type,
    );
    final isVideo = _isVideoResource(
      name: name,
      pathOrUrl: resolvedSource ?? source,
      type: attachment.type,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final targetSource = resolvedSource;
        if (targetSource == null) {
          _showMessage(
            '\u9644\u4EF6\u5730\u5740\u65E0\u6548\uFF0C\u65E0\u6CD5\u9884\u89C8',
          );
          return;
        }
        final isNetwork = _isNetworkSource(targetSource);
        if (isImage) {
          await _showImagePreview(targetSource, name, isNetwork: isNetwork);
          return;
        }
        if (isVideo) {
          if (isNetwork) {
            await _showVideoPreviewDialog(targetSource, name);
          } else {
            await _openAttachment(targetSource, isVideo: true);
          }
          return;
        }
        await _openAttachment(targetSource);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F8FE),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD5E2F3)),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              isVideo
                  ? Icons.play_circle_outline_rounded
                  : Icons.image_outlined,
              size: 16,
              color: const Color(0xFF3D6FA7),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '\u9644\u4EF6\uFF1A$name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF36516F),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              isVideo ? '\u64AD\u653E' : '\u9884\u89C8',
              style: const TextStyle(
                color: Color(0xFF2088E8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<EventAttachmentPayload> _timelineAttachments(EventTimelineItem item) {
    final result = <EventAttachmentPayload>[];
    final unique = <String>{};

    void append(EventAttachmentPayload attachment) {
      final name = attachment.name.trim();
      final path = attachment.path.trim();
      final type = (attachment.type ?? '').trim();
      if (path.isEmpty) {
        return;
      }
      final key = '$name|$path|$type';
      if (unique.add(key)) {
        result.add(
          EventAttachmentPayload(
            id: attachment.id,
            name: name.isEmpty ? 'attachment' : name,
            path: path,
            type: type.isEmpty ? null : type,
          ),
        );
      }
    }

    for (final attachment in item.attachments) {
      append(attachment);
    }

    final legacyName = (item.attachmentName ?? '').trim();
    final legacyPath = (item.attachmentPath ?? '').trim();
    if (legacyPath.isNotEmpty) {
      append(
        EventAttachmentPayload(
          name: legacyName.isEmpty
              ? (legacyPath.isEmpty ? 'attachment' : legacyPath)
              : legacyName,
          path: legacyPath,
          type: item.attachmentType,
        ),
      );
    }
    return result;
  }

  Widget _metaTag(
    IconData icon,
    String text, {
    Color background = const Color(0xFFF3F7FC),
    Color foreground = const Color(0xFF4D6078),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD9E4F1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: foreground,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusTag(String text) {
    final isProcessing = text == '\u5904\u7406\u4E2D';
    final fg = isProcessing ? const Color(0xFF1F9A3C) : const Color(0xFF5C687B);
    final bg = isProcessing ? const Color(0xFFE8F8EC) : const Color(0xFFE9ECF2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
      ),
    );
  }

  Widget _actionButton({
    required String text,
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2088E8),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFAEC8E7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          elevation: 0,
        ),
        icon: Icon(icon, size: 15),
        label: Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  String _statusText(EventProcessStatus status) {
    switch (status) {
      case EventProcessStatus.processing:
        return '\u5904\u7406\u4E2D';
      case EventProcessStatus.finished:
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

  String? _normalizeEventType(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text == '--' || text.toLowerCase() == 'null') {
      return null;
    }
    return text;
  }

  String _formatTime(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  String _formatTimelineTime(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}\n${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  String? _resolveAttachmentSourceFromPayload(
    EventAttachmentPayload attachment,
  ) {
    final byPath = _resolveAttachmentSource(attachment.path);
    if (byPath != null && byPath.trim().isNotEmpty) {
      return byPath;
    }
    return _resolveAttachmentSource(attachment.name);
  }

  String? _resolveAttachmentSource(String rawSource) {
    final text = rawSource.trim().replaceAll('\\', '/');
    if (text.isEmpty) {
      return null;
    }
    if (_isNetworkSource(text)) {
      return _normalizeHttpUrl(text);
    }
    if (_isLikelyLocalSource(text)) {
      return text;
    }
    return _resolveAttachmentUrl(text);
  }

  bool _isNetworkSource(String source) {
    final lower = source.toLowerCase().trim();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  bool _isLikelyLocalSource(String source) {
    final lower = source.toLowerCase().trim();
    if (lower.startsWith('file://') ||
        lower.startsWith('/storage/') ||
        lower.startsWith('/data/')) {
      return true;
    }
    return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(source);
  }

  String? _resolveAttachmentUrl(String rawPath) {
    final text = rawPath.trim().replaceAll('\\', '/');
    if (text.isEmpty) {
      return null;
    }
    final lower = text.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return _normalizeHttpUrl(text);
    }
    if (lower.startsWith('/admin-api/') || lower.startsWith('admin-api/')) {
      final path = text.startsWith('/') ? text : '/$text';
      return _normalizeHttpUrl('${AppConstants.apiBaseUrl}$path');
    }
    if (lower.startsWith('/uploadfile/')) {
      return _normalizeHttpUrl('${AppConstants.apiBaseUrl}$text');
    }
    if (lower.startsWith('uploadfile/')) {
      return _normalizeHttpUrl('${AppConstants.apiBaseUrl}/$text');
    }
    if (lower.startsWith('/upload/')) {
      final tail = text.substring('/upload/'.length);
      return _normalizeHttpUrl('${AppConstants.apiBaseUrl}/uploadFile/$tail');
    }
    if (lower.startsWith('upload/')) {
      final tail = text.substring('upload/'.length);
      return _normalizeHttpUrl('${AppConstants.apiBaseUrl}/uploadFile/$tail');
    }

    final normalized = text.startsWith('/') ? text.substring(1) : text;
    if (normalized.isEmpty) {
      return null;
    }
    return _normalizeHttpUrl(
      '${AppConstants.apiBaseUrl}/uploadFile/$normalized',
    );
  }

  String _normalizeHttpUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.host.isNotEmpty) {
      return parsed.toString();
    }
    return Uri.encodeFull(trimmed);
  }

  bool _isImageResource({
    required String name,
    String? pathOrUrl,
    String? type,
  }) {
    final normalizedType = (type ?? '').toLowerCase().trim();
    if (normalizedType.startsWith('image/')) {
      return true;
    }
    final probe = '${name.toLowerCase()} ${pathOrUrl?.toLowerCase() ?? ''}';
    return probe.contains('.png') ||
        probe.contains('.jpg') ||
        probe.contains('.jpeg') ||
        probe.contains('.webp') ||
        probe.contains('.gif') ||
        probe.contains('.bmp') ||
        probe.contains('.heic') ||
        probe.contains('.heif');
  }

  bool _isVideoResource({
    required String name,
    String? pathOrUrl,
    String? type,
  }) {
    final normalizedType = (type ?? '').toLowerCase().trim();
    if (normalizedType.startsWith('video/')) {
      return true;
    }
    final probe = '${name.toLowerCase()} ${pathOrUrl?.toLowerCase() ?? ''}';
    return probe.contains('.mp4') ||
        probe.contains('.mov') ||
        probe.contains('.m4v') ||
        probe.contains('.3gp') ||
        probe.contains('.mkv') ||
        probe.contains('.webm');
  }

  Future<void> _showImagePreview(
    String source,
    String title, {
    required bool isNetwork,
  }) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 26,
          ),
          clipBehavior: Clip.none,
          child: Container(
            color: Colors.black,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  color: const Color(0xFF11161D),
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: isNetwork
                        ? Image.network(
                            source,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 260,
                              height: 220,
                              child: Center(
                                child: Text(
                                  '\u56FE\u7247\u52A0\u8F7D\u5931\u8D25',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                            ),
                          )
                        : Image.file(
                            File(source),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 260,
                              height: 220,
                              child: Center(
                                child: Text(
                                  '\u56FE\u7247\u52A0\u8F7D\u5931\u8D25',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showVideoPreviewDialog(String url, String title) async {
    if (!mounted) {
      return;
    }
    final safeUrl = _normalizeHttpUrl(url);
    if (safeUrl.trim().isEmpty) {
      _showMessage(
        '\u89C6\u9891\u5730\u5740\u65E0\u6548\uFF0C\u65E0\u6CD5\u64AD\u653E',
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AppVideoPlayerPage(videoUrl: safeUrl, title: title),
      ),
    );
  }

  Future<void> _openAttachment(String source, {bool isVideo = false}) async {
    if (isVideo) {
      final safeSource = _isNetworkSource(source)
          ? _normalizeHttpUrl(source)
          : source.trim();
      if (safeSource.isEmpty) {
        _showMessage(
          '\u89C6\u9891\u5730\u5740\u65E0\u6548\uFF0C\u65E0\u6CD5\u64AD\u653E',
        );
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AppVideoPlayerPage(
            videoUrl: safeSource,
            title: _attachmentTitleFromSource(source),
          ),
        ),
      );
      return;
    }

    Uri? uri;
    if (_isNetworkSource(source) ||
        source.toLowerCase().startsWith('content://')) {
      final safeSource = _isNetworkSource(source)
          ? _normalizeHttpUrl(source)
          : source;
      uri = Uri.tryParse(safeSource);
    } else if (source.toLowerCase().startsWith('file://')) {
      uri = Uri.tryParse(source);
    } else {
      final file = File(source);
      if (file.existsSync()) {
        uri = Uri.file(file.path);
      }
    }
    if (uri == null) {
      _showMessage(
        '\u9644\u4EF6\u5730\u5740\u65E0\u6548\uFF0C\u65E0\u6CD5\u6253\u5F00',
      );
      return;
    }

    var opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
    if (!opened) {
      _showMessage('\u65E0\u6CD5\u6253\u5F00\u9644\u4EF6');
    }
  }

  String _attachmentTitleFromSource(String source) {
    final normalized = source.replaceAll('\\', '/');
    final text = normalized.trim();
    if (text.isEmpty) {
      return '\u89C6\u9891\u9884\u89C8';
    }
    final index = text.lastIndexOf('/');
    final name = index >= 0 ? text.substring(index + 1) : text;
    final clean = name.trim();
    return clean.isEmpty ? '\u89C6\u9891\u9884\u89C8' : clean;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    AppCenterToast.show(context, message);
  }
}

class _MapLaunchOption {
  const _MapLaunchOption({required this.label, required this.uri});

  final String label;
  final Uri uri;
}
