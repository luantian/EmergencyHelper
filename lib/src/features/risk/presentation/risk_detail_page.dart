import 'dart:io';

import 'package:emergency_helper/src/core/auth/app_feature_permission.dart';
import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/media/app_video_player_page.dart';
import 'package:emergency_helper/src/core/routing/route_paths.dart';
import 'package:emergency_helper/src/features/risk/data/risk_center.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/core/widgets/app_empty_view.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class RiskDetailPage extends StatelessWidget {
  const RiskDetailPage({required this.riskId, super.key});

  final String riskId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: RiskCenter.instance,
      builder: (context, _) {
        final risk = RiskCenter.instance.riskById(riskId);
        if (risk == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('\u98CE\u9669\u4FE1\u606F'),
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const AppEmptyView(
                      icon: Icons.warning_amber_outlined,
                      message: '\u8BE5\u98CE\u9669\u4E0D\u5B58\u5728\u6216\u5DF2\u88AB\u5220\u9664',
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('\u8FD4\u56DE'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2088E8),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 10,
                        ),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final canOperate = risk.status == RiskProcessStatus.processing;
        final typeLabel = _normalizeRiskType(risk.type) ?? risk.type;
        final statusText = _statusText(risk.status);

        return Scaffold(
          key: const Key('risk-detail-root'),
          appBar: AppBar(
            title: const Text('\u98CE\u9669\u4FE1\u606F'),
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
          ),
          backgroundColor: const Color(0xFFF3F6FA),
          body: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  children: <Widget>[
                    _buildSummaryCard(
                      title: risk.secondaryRisk,
                      statusText: statusText,
                      typeText: typeLabel,
                      levelText: risk.level,
                      levelColor: _levelTagColor(risk.level),
                      reportTime: _formatTime(risk.reportTime),
                      location: risk.location,
                    ),
                    const SizedBox(height: 10),
                    _buildSection(
                      title: '\u98CE\u9669\u4FE1\u606F',
                      child: Column(
                        children: <Widget>[
                          _buildInfoRow(
                            '\u884D\u751F\u98CE\u9669',
                            risk.secondaryRisk,
                          ),
                          if ((risk.relatedEvent ?? '').trim().isNotEmpty)
                            _buildInfoRow(
                              '\u5173\u8054\u4E8B\u4EF6',
                              risk.relatedEvent!,
                            ),
                          _buildInfoRow(
                            '\u98CE\u9669\u63CF\u8FF0',
                            risk.description,
                          ),
                          _buildInfoRow(
                            '\u98CE\u9669\u72B6\u6001',
                            null,
                            valueWidget: _statusTag(statusText),
                          ),
                          _buildInfoRow('\u98CE\u9669\u7EA7\u522B', risk.level),
                          _buildInfoRow('\u98CE\u9669\u7C7B\u578B', typeLabel),
                          _buildInfoRow(
                            '\u4E0A\u62A5\u5355\u4F4D',
                            risk.department,
                          ),
                          _buildInfoRow(
                            '\u4E0A\u62A5\u65F6\u95F4',
                            _formatTime(risk.reportTime),
                          ),
                          _buildInfoRow(
                            '\u53D1\u751F\u5730\u70B9',
                            risk.location,
                            onTap: () =>
                                _openLocationInMap(context, risk.location),
                          ),
                          _buildInfoRow(
                            '\u6240\u5C5E\u8857\u9053',
                            risk.street,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildSection(
                      title: '\u9644\u4EF6\u4FE1\u606F',
                      child: _buildAttachment(context, risk),
                    ),
                    const SizedBox(height: 10),
                    _buildSection(
                      title: '\u98CE\u9669\u52A8\u6001',
                      child: _buildTimeline(context, risk.timeline),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              if (canOperate)
                FutureBuilder<AppFeaturePermission>(
                  future: _resolveFeaturePermission(context),
                  builder: (context, snapshot) {
                    final permission =
                        snapshot.data ?? const AppFeaturePermission.unknown();
                    final canFeedback = permission.canRiskFeedback;
                    final canTransfer = permission.canRiskTransfer;
                    final canClose = permission.canRiskClose;
                    return Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(color: Color(0xFFD8E2EE)),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: _actionButton(
                              text: '\u53CD\u9988',
                              icon: Icons.chat_bubble_outline_rounded,
                              enabled: canFeedback,
                              onPressed: canFeedback
                                  ? () {
                                      context.push(
                                        RoutePaths.riskFeedbackById(risk.id),
                                      );
                                    }
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _actionButton(
                              text: '\u8F6C\u6D3E',
                              icon: Icons.send_outlined,
                              enabled: canTransfer,
                              onPressed: canTransfer
                                  ? () async {
                                      final selectedNames = await context
                                          .push<List<String>>(
                                            RoutePaths.riskTransferPickerById(
                                              risk.id,
                                            ),
                                          );
                                      if (!context.mounted ||
                                          selectedNames == null ||
                                          selectedNames.isEmpty) {
                                        return;
                                      }
                                      final receiverNames = selectedNames.join(
                                        '\u3001',
                                      );
                                      final operatorName =
                                          await _resolveCurrentUserName(
                                            context,
                                          );
                                      if (!context.mounted) {
                                        return;
                                      }
                                      RiskCenter.instance.transfer(
                                        risk.id,
                                        receiverNames: receiverNames,
                                        transferUser: operatorName,
                                      );
                                      _showMessage(
                                        context,
                                        '\u98CE\u9669\u5DF2\u8F6C\u6D3E\uFF1A$receiverNames',
                                      );
                                    }
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _actionButton(
                              text: '\u529E\u7ED3',
                              icon: Icons.task_alt_rounded,
                              enabled: canClose,
                              onPressed: canClose
                                  ? () async {
                                      final operatorName =
                                          await _resolveCurrentUserName(
                                            context,
                                          );
                                      if (!context.mounted) {
                                        return;
                                      }
                                      RiskCenter.instance.finish(
                                        risk.id,
                                        finisher: operatorName,
                                      );
                                      _showMessage(
                                        context,
                                        '\u98CE\u9669\u5DF2\u529E\u7ED3',
                                      );
                                    }
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<AppFeaturePermission> _resolveFeaturePermission(BuildContext context) {
    final dependencies = context.read<AppDependencies>();
    return AppFeaturePermissionResolver.instance.resolve(
      dependencies.authService,
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String statusText,
    required String typeText,
    required String levelText,
    required Color levelColor,
    required String reportTime,
    required String location,
  }) {
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
                  title,
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
                '\u7C7B\u578B\uFF1A$typeText',
              ),
              _metaTag(
                Icons.flag_outlined,
                '\u7EA7\u522B\uFF1A$levelText',
                foreground: levelColor,
                background: levelColor.withValues(alpha: 0.12),
              ),
              _metaTag(Icons.schedule_rounded, reportTime),
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
                  location,
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

  Future<void> _openLocationInMap(
    BuildContext context,
    String? rawLocation,
  ) async {
    final location = (rawLocation ?? '').trim();
    if (location.isEmpty || location == '--') {
      _showMessage(
        context,
        '\u5730\u70B9\u4FE1\u606F\u4E3A\u7A7A\uFF0C\u65E0\u6CD5\u5BFC\u822A',
      );
      return;
    }

    final options = await _collectAvailableMapOptions(location);
    final installedOptions = options
        .where((option) => option.installed)
        .toList(growable: false);
    if (!context.mounted) {
      return;
    }
    if (installedOptions.isEmpty) {
      _showMessage(
        context,
        '\u672A\u68C0\u6D4B\u5230\u53EF\u7528\u5730\u56FE\u5E94\u7528',
      );
      return;
    }

    _MapLaunchOption? selected;
    if (installedOptions.length == 1) {
      selected = installedOptions.first;
    } else {
      selected = await showModalBottomSheet<_MapLaunchOption>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: false,
        builder: (sheetContext) {
          return SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4DDE8),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.layers_rounded,
                        color: Color(0xFF2D6CDF),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '\u9009\u62E9\u5730\u56FE',
                        style: TextStyle(
                          color: Color(0xFF1A2330),
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F6FC),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${installedOptions.length}/${options.length}\u53EF\u7528',
                          style: const TextStyle(
                            color: Color(0xFF6B7C90),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < options.length; i++) ...<Widget>[
                    _buildMapOptionTile(
                      option: options[i],
                      onTap: () => Navigator.of(sheetContext).pop(options[i]),
                    ),
                    if (i != options.length - 1) const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 10),
                  const Text(
                    '\u7070\u8272\u9879\u8868\u793A\u5F53\u524D\u8BBE\u5907\u672A\u5B89\u88C5',
                    style: TextStyle(
                      color: Color(0xFF8A97A8),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    if (!context.mounted || selected == null) {
      return;
    }
    var opened = await launchUrl(
      selected.uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      opened = await launchUrl(selected.uri, mode: LaunchMode.platformDefault);
    }
    if (!opened && context.mounted) {
      _showMessage(context, '\u65E0\u6CD5\u6253\u5F00\u5730\u56FE');
    }
  }

  Future<List<_MapLaunchOption>> _collectAvailableMapOptions(
    String location,
  ) async {
    final candidates = <_MapLaunchOption>[
      _MapLaunchOption(
        type: _MapAppType.baidu,
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
        type: _MapAppType.gaode,
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
        type: _MapAppType.tencent,
        label: '\u817E\u8BAF\u5730\u56FE',
        uri: Uri.parse(
          'qqmap://map/search?keyword=${Uri.encodeComponent(location)}&referer=EmergencyHelper',
        ),
      ),
      _MapLaunchOption(
        type: _MapAppType.petal,
        label: '\u534E\u4E3A\u5730\u56FE',
        uri: Uri.parse(
          'petalmaps://map/search?query=${Uri.encodeComponent(location)}',
        ),
      ),
      _MapLaunchOption(
        type: _MapAppType.system,
        label: '\u7CFB\u7EDF\u5730\u56FE',
        uri: Uri.parse('geo:0,0?q=${Uri.encodeComponent(location)}'),
      ),
    ];

    final resolved = <_MapLaunchOption>[];
    for (final option in candidates) {
      var installed = false;
      try {
        installed = await canLaunchUrl(option.uri);
      } catch (_) {}
      resolved.add(option.copyWith(installed: installed));
    }

    if (!resolved.any((option) => option.installed)) {
      final systemIndex = resolved.indexWhere(
        (option) => option.type == _MapAppType.system,
      );
      if (systemIndex >= 0) {
        resolved[systemIndex] = resolved[systemIndex].copyWith(installed: true);
      }
    }
    return resolved;
  }

  Widget _buildMapOptionTile({
    required _MapLaunchOption option,
    required VoidCallback onTap,
  }) {
    final enabled = option.installed;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: enabled ? const Color(0xFFF6FAFF) : const Color(0xFFF6F7F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: enabled ? const Color(0xFFD6E6FA) : const Color(0xFFE6EBF2),
            ),
          ),
          child: Row(
            children: <Widget>[
              _buildMapOptionIcon(option),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      option.label,
                      style: TextStyle(
                        color: enabled
                            ? const Color(0xFF1A2330)
                            : const Color(0xFF98A2B3),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled ? option.subtitle : '\u672A\u5B89\u88C5',
                      style: TextStyle(
                        color: enabled
                            ? const Color(0xFF6F7E91)
                            : const Color(0xFFA8B1BE),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF6F7E91),
                  size: 20,
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAEFF6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '\u672A\u5B89\u88C5',
                    style: TextStyle(
                      color: Color(0xFF8A97A8),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapOptionIcon(_MapLaunchOption option) {
    final primaryColor = _mapPrimaryColor(option.type);
    final isSystem = option.type == _MapAppType.system;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            primaryColor.withValues(alpha: 0.24),
            primaryColor.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withValues(alpha: 0.35)),
      ),
      child: isSystem
          ? Icon(Icons.public_rounded, color: primaryColor, size: 20)
          : Text(
              option.shortLabel,
              style: TextStyle(
                color: primaryColor,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
    );
  }

  Color _mapPrimaryColor(_MapAppType type) {
    switch (type) {
      case _MapAppType.baidu:
        return const Color(0xFFE23D37);
      case _MapAppType.gaode:
        return const Color(0xFF2AA06D);
      case _MapAppType.tencent:
        return const Color(0xFF1E88E5);
      case _MapAppType.petal:
        return const Color(0xFF3A66E8);
      case _MapAppType.system:
        return const Color(0xFF6D7C90);
    }
  }

  Widget _buildAttachment(BuildContext context, RiskRecord risk) {
    final attachments = _collectRiskAttachments(risk);
    if (attachments.isEmpty) {
      return const Text(
        '\u6682\u65E0\u9644\u4EF6',
        style: TextStyle(color: Color(0xFF8F9BAB), fontSize: 13.5),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < attachments.length; i++) ...[
          _buildAttachmentTile(
            context,
            attachment: attachments[i],
            prefixText: '',
          ),
          if (i != attachments.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _buildTimeline(BuildContext context, List<RiskTimelineItem> items) {
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
            _buildTimelineItem(context, items[i], i == items.length - 1),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(
    BuildContext context,
    RiskTimelineItem item,
    bool isLast,
  ) {
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
                  if (_collectTimelineAttachments(item).isNotEmpty)
                    _buildTimelineAttachment(context, item),
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

  Widget _buildTimelineAttachment(BuildContext context, RiskTimelineItem item) {
    final attachments = _collectTimelineAttachments(item);
    if (attachments.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        children: [
          for (var i = 0; i < attachments.length; i++) ...[
            _buildAttachmentTile(
              context,
              attachment: attachments[i],
              prefixText: '\u9644\u4EF6\uFF1A',
            ),
            if (i != attachments.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildAttachmentTile(
    BuildContext context, {
    required RiskAttachmentPayload attachment,
    required String prefixText,
  }) {
    final displayName = attachment.name.trim().isEmpty
        ? '\u9644\u4EF6'
        : attachment.name.trim();
    final source = _resolveAttachmentSourceFromPayload(attachment);
    final isImage = _isImageResource(
      name: displayName,
      source: source,
      type: attachment.type,
    );
    final isVideo = _isVideoResource(
      name: displayName,
      source: source,
      type: attachment.type,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        if (source == null || source.trim().isEmpty) {
          _showMessage(
            context,
            '\u9644\u4EF6\u5730\u5740\u65E0\u6548\uFF0C\u65E0\u6CD5\u9884\u89C8',
          );
          return;
        }
        final resolved = source;
        final isNetwork = _isNetworkSource(resolved);
        if (isImage) {
          await _showImagePreview(
            context,
            source: resolved,
            title: displayName,
            isNetwork: isNetwork,
          );
          return;
        }
        if (isVideo) {
          if (isNetwork) {
            await _showVideoPreviewDialog(
              context,
              url: resolved,
              title: displayName,
            );
          } else {
            await _openAttachment(context, resolved, isVideo: true);
          }
          return;
        }
        await _openAttachment(context, resolved, isVideo: isVideo);
      },
      child: Container(
        width: double.infinity,
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
                '$prefixText$displayName',
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
            if (source != null && source.trim().isNotEmpty)
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
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2088E8),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFB9CFEB),
          disabledForegroundColor: Colors.white,
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

  String _statusText(RiskProcessStatus status) {
    switch (status) {
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
        default:
          return '\u5176\u4ED6';
      }
    }
    return text;
  }

  static String _formatTime(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  static String _formatTimelineTime(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}\n${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  List<RiskAttachmentPayload> _collectRiskAttachments(RiskRecord risk) {
    final result = <RiskAttachmentPayload>[];
    final unique = <String>{};
    for (final item in risk.attachments) {
      final name = item.name.trim();
      final path = item.path.trim();
      if (name.isEmpty || path.isEmpty) {
        continue;
      }
      final key = '$name|$path';
      if (unique.add(key)) {
        result.add(item);
      }
    }
    final legacyName = (risk.attachmentName ?? '').trim();
    final legacyPath = (risk.attachmentPath ?? '').trim();
    if (legacyName.isNotEmpty && legacyPath.isNotEmpty) {
      final key = '$legacyName|$legacyPath';
      if (unique.add(key)) {
        result.add(
          RiskAttachmentPayload(
            name: legacyName,
            path: legacyPath,
            type: risk.attachmentType,
          ),
        );
      }
    }
    return result;
  }

  List<RiskAttachmentPayload> _collectTimelineAttachments(
    RiskTimelineItem item,
  ) {
    final result = <RiskAttachmentPayload>[];
    final unique = <String>{};
    for (final attachment in item.attachments) {
      final name = attachment.name.trim();
      final path = attachment.path.trim();
      if (name.isEmpty || path.isEmpty) {
        continue;
      }
      final key = '$name|$path';
      if (unique.add(key)) {
        result.add(attachment);
      }
    }
    final legacyName = (item.attachmentName ?? '').trim();
    final legacyPath = (item.attachmentPath ?? '').trim();
    if (legacyName.isNotEmpty && legacyPath.isNotEmpty) {
      final key = '$legacyName|$legacyPath';
      if (unique.add(key)) {
        result.add(
          RiskAttachmentPayload(
            name: legacyName,
            path: legacyPath,
            type: item.attachmentType,
          ),
        );
      }
    }
    return result;
  }

  String? _resolveAttachmentSourceFromPayload(
    RiskAttachmentPayload attachment,
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

  bool _isImageResource({required String name, String? source, String? type}) {
    final normalizedType = (type ?? '').toLowerCase().trim();
    if (normalizedType.startsWith('image/')) {
      return true;
    }
    final probe = '${name.toLowerCase()} ${source?.toLowerCase() ?? ''}';
    return probe.contains('.png') ||
        probe.contains('.jpg') ||
        probe.contains('.jpeg') ||
        probe.contains('.webp') ||
        probe.contains('.gif') ||
        probe.contains('.bmp') ||
        probe.contains('.heic') ||
        probe.contains('.heif');
  }

  bool _isVideoResource({required String name, String? source, String? type}) {
    final normalizedType = (type ?? '').toLowerCase().trim();
    if (normalizedType.startsWith('video/')) {
      return true;
    }
    final probe = '${name.toLowerCase()} ${source?.toLowerCase() ?? ''}';
    return probe.contains('.mp4') ||
        probe.contains('.mov') ||
        probe.contains('.m4v') ||
        probe.contains('.3gp') ||
        probe.contains('.mkv') ||
        probe.contains('.webm');
  }

  Future<void> _showImagePreview(
    BuildContext context, {
    required String source,
    required String title,
    required bool isNetwork,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
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
                        onPressed: () => Navigator.of(dialogContext).pop(),
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

  Future<void> _showVideoPreviewDialog(
    BuildContext context, {
    required String url,
    required String title,
  }) async {
    final safeUrl = _normalizeHttpUrl(url);
    if (safeUrl.trim().isEmpty) {
      _showMessage(
        context,
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

  Future<void> _openAttachment(
    BuildContext context,
    String source, {
    bool isVideo = false,
  }) async {
    try {
      if (isVideo) {
        final safeSource = _isNetworkSource(source)
            ? _normalizeHttpUrl(source)
            : source.trim();
        if (safeSource.isEmpty) {
          _showMessage(
            context,
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

      if (!context.mounted) {
        return;
      }

      Uri? uri;
      if (_isNetworkSource(source) ||
          source.toLowerCase().startsWith('content://')) {
        final networkSource = _isNetworkSource(source)
            ? _normalizeHttpUrl(source)
            : source;
        uri = Uri.tryParse(networkSource);
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
          context,
          '\u9644\u4EF6\u5730\u5740\u65E0\u6548\uFF0C\u65E0\u6CD5\u6253\u5F00',
        );
        return;
      }

      var opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      if (!opened && context.mounted) {
        _showMessage(context, '\u65E0\u6CD5\u6253\u5F00\u9644\u4EF6');
      }
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _showMessage(context, '\u6253\u5F00\u9644\u4EF6\u5931\u8D25');
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

  Future<String> _resolveCurrentUserName(BuildContext context) async {
    try {
      final dependencies = context.read<AppDependencies>();
      var info = await dependencies.authService.getCachedPermissionInfo();
      var parsed = _parseCurrentUserName(info);
      if (parsed == null || parsed.isEmpty) {
        await dependencies.authService.fetchUserProfileAndCache();
        info = await dependencies.authService.getCachedPermissionInfo();
        parsed = _parseCurrentUserName(info);
      }
      return (parsed == null || parsed.isEmpty)
          ? '\u5F53\u524D\u7528\u6237'
          : parsed;
    } catch (_) {
      return '\u5F53\u524D\u7528\u6237';
    }
  }

  String? _parseCurrentUserName(Map<String, dynamic>? info) {
    if (info == null) {
      return null;
    }
    final permissionInfo = _asMap(info['permissionInfo']) ?? info;
    final profileInfo = _asMap(info['profileInfo']);
    final permissionData = _asMap(permissionInfo['data']) ?? permissionInfo;
    final permissionUser = _asMap(permissionData['user']) ?? permissionData;
    final profileData = _asMap(profileInfo?['data']);

    return _asText(permissionUser['nickname']) ??
        _asText(permissionUser['name']) ??
        _asText(permissionUser['username']) ??
        _asText(profileData?['nickname']) ??
        _asText(profileData?['name']) ??
        _asText(profileData?['username']);
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

  static void _showMessage(BuildContext context, String message) {
    AppCenterToast.show(context, message);
  }
}

enum _MapAppType { baidu, gaode, tencent, petal, system }

class _MapLaunchOption {
  const _MapLaunchOption({
    required this.type,
    required this.label,
    required this.uri,
    this.installed = false,
  });

  final _MapAppType type;

  final String label;
  final Uri uri;
  final bool installed;

  String get shortLabel {
    switch (type) {
      case _MapAppType.baidu:
        return '\u767E';
      case _MapAppType.gaode:
        return '\u9AD8';
      case _MapAppType.tencent:
        return '\u817E';
      case _MapAppType.petal:
        return '\u82B1';
      case _MapAppType.system:
        return '';
    }
  }

  String get subtitle {
    switch (type) {
      case _MapAppType.baidu:
        return '\u5730\u70B9\u68C0\u7D22\u4E0E\u5BFC\u822A';
      case _MapAppType.gaode:
        return '\u8DEF\u7EBF\u89C4\u5212\u4E0E\u5BFC\u822A';
      case _MapAppType.tencent:
        return '\u516C\u4EA4\u4E0E\u51FA\u884C\u8DEF\u7EBF';
      case _MapAppType.petal:
        return '\u534E\u4E3A\u5730\u56FE\u5BFC\u822A';
      case _MapAppType.system:
        return '\u4F7F\u7528\u624B\u673A\u9ED8\u8BA4\u5730\u56FE';
    }
  }

  _MapLaunchOption copyWith({bool? installed}) {
    return _MapLaunchOption(
      type: type,
      label: label,
      uri: uri,
      installed: installed ?? this.installed,
    );
  }
}
