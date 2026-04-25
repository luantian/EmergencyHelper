import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/features/push/data/push_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class PushDebugPage extends StatefulWidget {
  const PushDebugPage({super.key});

  @override
  State<PushDebugPage> createState() => _PushDebugPageState();
}

class _PushDebugPageState extends State<PushDebugPage> {
  bool _loading = true;
  bool _binding = false;
  Map<String, dynamic>? _permissionInfo;
  PushDebugSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _refreshState();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text('推送调试'),
        centerTitle: true,
      ),
      backgroundColor: const Color(0xFFF1F5FA),
      body: _loading && snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshState,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 22),
                children: <Widget>[
                  _buildActionCard(snapshot),
                  const SizedBox(height: 10),
                  _buildRuntimeCard(snapshot),
                  const SizedBox(height: 10),
                  _buildIdentityCard(snapshot),
                  const SizedBox(height: 10),
                  _buildAliasResultCard(snapshot),
                  const SizedBox(height: 10),
                  _buildRidCard(snapshot),
                ],
              ),
            ),
    );
  }

  Widget _buildActionCard(PushDebugSnapshot? snapshot) {
    final canRebind = !_binding && !_loading;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: _cardDecoration(),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: <Widget>[
          ElevatedButton.icon(
            onPressed: _loading ? null : _refreshState,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('刷新状态'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: canRebind ? _rebindAlias : null,
            icon: Icon(
              _binding ? Icons.hourglass_top_rounded : Icons.link_rounded,
              size: 18,
            ),
            label: Text(_binding ? '绑定中...' : '重新绑定别名'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2273C9),
              foregroundColor: Colors.white,
            ),
          ),
          OutlinedButton.icon(
            onPressed: (snapshot?.registrationId ?? '').trim().isEmpty
                ? null
                : () => _copyText('Registration ID', snapshot!.registrationId!),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('复制 RID'),
          ),
        ],
      ),
    );
  }

  Widget _buildRuntimeCard(PushDebugSnapshot? snapshot) {
    final data = snapshot;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: _cardDecoration(),
      child: Column(
        children: <Widget>[
          _DebugRow(
            label: 'SDK 初始化',
            value: data == null ? '--' : (data.initialized ? '已初始化' : '未初始化'),
          ),
          _DebugRow(
            label: '推送可用',
            value: data == null ? '--' : (data.available ? '可用' : '不可用'),
          ),
          _DebugRow(
            label: '运行环境',
            value: data == null ? '--' : (data.production ? '生产环境' : '开发环境'),
          ),
          _DebugRow(label: '通道', value: data?.channel ?? '--'),
          _DebugRow(
            label: 'AppKey',
            value: data == null ? '--' : _maskAppKey(data.appKey),
            hideDivider: true,
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard(PushDebugSnapshot? snapshot) {
    final data = snapshot;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: _cardDecoration(),
      child: Column(
        children: <Widget>[
          _DebugRow(label: '当前 userId', value: _safeText(data?.userId)),
          _DebugRow(label: '已绑定 alias', value: _safeText(data?.boundAlias)),
          _DebugRow(
            label: '待绑定 alias',
            value: _safeText(data?.queuedAlias),
            hideDivider: true,
          ),
        ],
      ),
    );
  }

  Widget _buildAliasResultCard(PushDebugSnapshot? snapshot) {
    final data = snapshot;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: _cardDecoration(),
      child: Column(
        children: <Widget>[
          _DebugRow(
            label: '最近绑定结果码',
            value: _safeText(data?.lastAliasBindCode),
          ),
          _DebugRow(
            label: '最近绑定信息',
            value: _safeText(data?.lastAliasBindMessage),
          ),
          _DebugRow(
            label: '最近绑定时间',
            value: _formatTime(data?.lastAliasBindTime),
            hideDivider: true,
          ),
        ],
      ),
    );
  }

  Widget _buildRidCard(PushDebugSnapshot? snapshot) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Registration ID',
            style: TextStyle(
              color: Color(0xFF1F2B3A),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            _safeText(snapshot?.registrationId),
            style: const TextStyle(
              color: Color(0xFF1F2B3A),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshState() async {
    final dependencies = context.read<AppDependencies>();
    final permissionInfo = await dependencies.authService
        .getCachedPermissionInfo();
    final userId = PushService.extractAliasFromPermissionInfo(permissionInfo);
    await dependencies.pushService.refreshRegistrationId();
    final snapshot = dependencies.pushService.getDebugSnapshot(userId: userId);
    if (!mounted) {
      return;
    }
    setState(() {
      _permissionInfo = permissionInfo;
      _snapshot = snapshot;
      _loading = false;
    });
  }

  Future<void> _rebindAlias() async {
    setState(() {
      _binding = true;
    });
    final dependencies = context.read<AppDependencies>();
    try {
      final permissionInfo =
          _permissionInfo ??
          await dependencies.authService.getCachedPermissionInfo();
      final userId = PushService.extractAliasFromPermissionInfo(permissionInfo);
      if (userId == null || userId.trim().isEmpty) {
        _showMessage('未拿到 userId，无法绑定 alias');
      } else {
        await dependencies.pushService.bindAlias(userId.trim());
        _showMessage('已触发别名绑定: $userId');
      }
      await dependencies.pushService.refreshRegistrationId();
      final snapshot = dependencies.pushService.getDebugSnapshot(
        userId: userId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _permissionInfo = permissionInfo;
        _snapshot = snapshot;
      });
    } catch (error) {
      _showMessage('绑定失败: $error');
    } finally {
      if (mounted) {
        setState(() {
          _binding = false;
        });
      }
    }
  }

  Future<void> _copyText(String label, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    _showMessage('$label 已复制');
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFDDE6F2)),
      boxShadow: const <BoxShadow>[
        BoxShadow(
          color: Color(0x120F2239),
          offset: Offset(0, 2),
          blurRadius: 8,
        ),
      ],
    );
  }

  String _safeText(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '--';
    }
    return value.trim();
  }

  String _maskAppKey(String appKey) {
    final text = appKey.trim();
    if (text.isEmpty) {
      return '--';
    }
    if (text.length <= 8) {
      return text;
    }
    return '${text.substring(0, 4)}****${text.substring(text.length - 4)}';
  }

  String _formatTime(DateTime? time) {
    if (time == null) {
      return '--';
    }
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final min = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s';
  }

  void _showMessage(String message) {
    AppCenterToast.show(context, message);
  }
}

class _DebugRow extends StatelessWidget {
  const _DebugRow({
    required this.label,
    required this.value,
    this.hideDivider = false,
  });

  final String label;
  final String value;
  final bool hideDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: hideDivider
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFFE8EEF7), width: 1),
              ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6E7D90),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF1F2B3A),
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
