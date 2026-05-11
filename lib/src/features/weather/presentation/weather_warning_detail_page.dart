import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/core/widgets/app_loading_overlay.dart';
import 'package:emergency_helper/src/features/weather/data/event_weather_warning_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class WeatherWarningDetailPage extends StatefulWidget {
  const WeatherWarningDetailPage({super.key});

  @override
  State<WeatherWarningDetailPage> createState() => _WeatherWarningDetailPageState();
}

class _WeatherWarningDetailPageState extends State<WeatherWarningDetailPage> {
  final EventWeatherWarningService _service = EventWeatherWarningService();
  EventWeatherWarningItem? _item;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dependencies = context.read<AppDependencies>();
      final list = await _service.fetchWarningList(dependencies.apiClient);
      if (!mounted) return;
      setState(() {
        _item = list.isNotEmpty ? list.first : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败，请稍后重试';
        _loading = false;
      });
    }
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  Color _levelColor(String level) {
    final raw = level.toLowerCase();
    if (raw == '1' || raw.contains('red') || raw.contains('红')) return const Color(0xFFE55B5B);
    if (raw == '2' || raw.contains('orange') || raw.contains('橙')) return const Color(0xFFE49A2D);
    if (raw == '3' || raw.contains('yellow') || raw.contains('黄')) return const Color(0xFFF6B434);
    if (raw == '4' || raw.contains('blue') || raw.contains('蓝')) return const Color(0xFF4B81CD);
    return const Color(0xFF7E8DA2);
  }

  String _levelLabel(String level) {
    final raw = level.toLowerCase();
    if (raw == '1' || raw.contains('red') || raw.contains('红')) return '红色预警';
    if (raw == '2' || raw.contains('orange') || raw.contains('橙')) return '橙色预警';
    if (raw == '3' || raw.contains('yellow') || raw.contains('黄')) return '黄色预警';
    if (raw == '4' || raw.contains('blue') || raw.contains('蓝')) return '蓝色预警';
    return level.isEmpty ? '预警' : level;
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final color = item != null ? _levelColor(item.level) : const Color(0xFF7E8DA2);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text('气象预警详情'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _loadData,
            tooltip: '刷新',
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF3F6FA),
      body: AppLoadingOverlay(
        loading: _loading && _item == null,
        message: '加载中...',
        child: _error != null && _item == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF97A4B5), size: 38),
                    const SizedBox(height: 10),
                    Text(_error!, textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF596A80), fontSize: 13)),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _loadData, child: const Text('重试')),
                  ],
                ),
              )
            : item == null
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_outlined, size: 44, color: Color(0xFF9AABBF)),
                        SizedBox(height: 10),
                        Text('暂无气象预警信息',
                            style: TextStyle(color: Color(0xFF6F8095), fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFDCE6F3)),
                          boxShadow: const [
                            BoxShadow(color: Color(0x120F2239), offset: Offset(0, 1), blurRadius: 8),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: color.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    _levelLabel(item.level),
                                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _formatTime(item.publishTime),
                                  style: const TextStyle(color: Color(0xFF97A4B5), fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              item.title,
                              style: const TextStyle(
                                color: Color(0xFF1C2A3B),
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Divider(height: 1, color: Color(0xFFE3EAF4)),
                            const SizedBox(height: 12),
                            Text(
                              item.content,
                              style: const TextStyle(color: Color(0xFF2A3A4E), fontSize: 15, height: 1.7),
                            ),
                          ],
                        ),
                      ),
                      if (item.province.isNotEmpty || item.city.isNotEmpty)
                        const SizedBox(height: 8),
                      if (item.province.isNotEmpty || item.city.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFDCE6F3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_outlined, size: 18, color: Color(0xFF5E7390)),
                              const SizedBox(width: 6),
                              Text(
                                [item.province, item.city].where((s) => s.isNotEmpty).join(' · ') ?? '',
                                style: const TextStyle(color: Color(0xFF5E7390), fontSize: 13),
                              ),
                              if (item.org.isNotEmpty) ...[
                                const SizedBox(width: 16),
                                const Icon(Icons.business_outlined, size: 18, color: Color(0xFF5E7390)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    item.org,
                                    style: const TextStyle(color: Color(0xFF5E7390), fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}
