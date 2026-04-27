import 'dart:convert';

import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/features/push/data/push_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class BusinessDebugPage extends StatefulWidget {
  const BusinessDebugPage({super.key});

  @override
  State<BusinessDebugPage> createState() => _BusinessDebugPageState();
}

class _BusinessDebugPageState extends State<BusinessDebugPage> {
  bool _loading = true;
  bool _refreshing = false;
  _BusinessDebugData? _data;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_refresh);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text('\u4E1A\u52A1\u8C03\u8BD5'),
        centerTitle: true,
      ),
      backgroundColor: const Color(0xFFF1F5FA),
      body: _loading && data == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 22),
                children: <Widget>[
                  _buildActionCard(data),
                  const SizedBox(height: 10),
                  _buildTokenCard(data),
                  const SizedBox(height: 10),
                  _buildAuthCard(data),
                  const SizedBox(height: 10),
                  _buildUserCard(data),
                  const SizedBox(height: 10),
                  _buildPushCard(data),
                  const SizedBox(height: 10),
                  _buildPermissionCard(data),
                ],
              ),
            ),
    );
  }

  Widget _buildActionCard(_BusinessDebugData? data) {
    final allText = data?.copyAllText ?? '';
    final canCopyAll = allText.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: _cardDecoration(),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: <Widget>[
          ElevatedButton.icon(
            onPressed: _refreshing ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(
              _refreshing ? '\u5237\u65B0\u4E2D...' : '\u5237\u65B0\u6570\u636E',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
            ),
          ),
          OutlinedButton.icon(
            onPressed: canCopyAll
                ? () => _copyText('\u4E1A\u52A1\u8C03\u8BD5\u5168\u90E8\u5185\u5BB9', allText)
                : null,
            icon: const Icon(Icons.copy_all_rounded, size: 18),
            label: const Text('\u590D\u5236\u5168\u90E8'),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenCard(_BusinessDebugData? data) {
    final token = data?.accessToken ?? '--';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '\u5F53\u524D\u7528\u6237 Token',
            style: TextStyle(
              color: Color(0xFF1F2B3A),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            token,
            style: const TextStyle(
              color: Color(0xFF1F2B3A),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: token.trim().isEmpty || token == '--'
                  ? null
                  : () => _copyText('Token', token),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('\u590D\u5236 Token'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthCard(_BusinessDebugData? data) {
    return _buildRowsCard(
      title: '\u8BA4\u8BC1\u4FE1\u606F',
      rows: <_CopyRowData>[
        _CopyRowData(
          label: 'API Base URL',
          value: data?.apiBaseUrl ?? '--',
        ),
        _CopyRowData(
          label: 'accessToken',
          value: data?.accessToken ?? '--',
        ),
        _CopyRowData(
          label: 'refreshToken',
          value: data?.refreshToken ?? '--',
        ),
        _CopyRowData(
          label: 'expiresTime(ms)',
          value: data?.expiresTimeMs ?? '--',
        ),
        _CopyRowData(
          label: '\u8FC7\u671F\u65F6\u95F4',
          value: data?.expiresAtText ?? '--',
        ),
        _CopyRowData(
          label: '\u5F53\u524D\u72B6\u6001',
          value: data?.tokenStatus ?? '--',
        ),
        _CopyRowData(
          label: '\u8BB0\u4F4F\u8D26\u53F7',
          value: data?.rememberAccountText ?? '--',
        ),
        _CopyRowData(
          label: '\u8BB0\u4F4F\u7684\u8D26\u53F7',
          value: data?.rememberedUsername ?? '--',
          hideDivider: true,
        ),
      ],
    );
  }

  Widget _buildUserCard(_BusinessDebugData? data) {
    return _buildRowsCard(
      title: '\u5F53\u524D\u7528\u6237',
      rows: <_CopyRowData>[
        _CopyRowData(label: 'userId', value: data?.userId ?? '--'),
        _CopyRowData(
          label: '\u7528\u6237\u540D',
          value: data?.username ?? '--',
        ),
        _CopyRowData(
          label: '\u59D3\u540D',
          value: data?.nickname ?? '--',
        ),
        _CopyRowData(
          label: '\u6240\u5C5E\u5355\u4F4D',
          value: data?.deptName ?? '--',
        ),
        _CopyRowData(
          label: '\u804C\u52A1',
          value: data?.postName ?? '--',
        ),
        _CopyRowData(
          label: '\u624B\u673A\u53F7',
          value: data?.mobile ?? '--',
        ),
        _CopyRowData(
          label: '\u89D2\u8272',
          value: data?.rolesText ?? '--',
        ),
        _CopyRowData(
          label: '\u6743\u9650',
          value: data?.permissionsText ?? '--',
          hideDivider: true,
        ),
      ],
    );
  }

  Widget _buildPushCard(_BusinessDebugData? data) {
    return _buildRowsCard(
      title: '\u63A8\u9001\u72B6\u6001',
      rows: <_CopyRowData>[
        _CopyRowData(
          label: 'registrationId',
          value: data?.registrationId ?? '--',
        ),
        _CopyRowData(
          label: 'boundAlias',
          value: data?.boundAlias ?? '--',
        ),
        _CopyRowData(
          label: 'queuedAlias',
          value: data?.queuedAlias ?? '--',
        ),
        _CopyRowData(
          label: 'channel',
          value: data?.channel ?? '--',
        ),
        _CopyRowData(
          label: 'lastAliasBindCode',
          value: data?.lastAliasBindCode ?? '--',
        ),
        _CopyRowData(
          label: 'lastAliasBindMessage',
          value: data?.lastAliasBindMessage ?? '--',
        ),
        _CopyRowData(
          label: 'lastAliasBindTime',
          value: data?.lastAliasBindTimeText ?? '--',
          hideDivider: true,
        ),
      ],
    );
  }

  Widget _buildPermissionCard(_BusinessDebugData? data) {
    final text = data?.permissionInfoJson ?? '--';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '\u6743\u9650\u7F13\u5B58 JSON',
            style: TextStyle(
              color: Color(0xFF1F2B3A),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            text,
            style: const TextStyle(
              color: Color(0xFF2B3A4A),
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: text.trim().isEmpty || text == '--'
                  ? null
                  : () => _copyText('permissionInfoJson', text),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('\u590D\u5236 JSON'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowsCard({
    required String title,
    required List<_CopyRowData> rows,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: _cardDecoration(),
      child: Column(
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4, top: 2),
              child: Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF1F2B3A),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          for (final row in rows)
            _CopyRow(
              data: row,
              onCopy: (value) => _copyText(row.label, value),
            ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      return;
    }
    if (mounted) {
      setState(() {
        _refreshing = true;
        if (_data == null) {
          _loading = true;
        }
      });
    }

    try {
      final dependencies = context.read<AppDependencies>();
      final accessToken =
          (await dependencies.authLocalStore.getAccessToken())?.trim() ?? '';
      final refreshToken =
          (await dependencies.authLocalStore.getRefreshToken())?.trim() ?? '';
      final expiresTimeMs = await dependencies.authLocalStore
          .getAccessTokenExpiresTimeMs();
      final remembered = await dependencies.authLocalStore
          .getRememberedCredential();
      final permissionInfo =
          await dependencies.authService.getCachedPermissionInfo();

      final permissionData = _extractPermissionData(permissionInfo);
      final user = _asMap(permissionData?['user']);
      final profileData = _asMap(_asMap(permissionInfo?['profileInfo'])?['data']);
      final profileDept = _asMap(profileData?['dept']);
      final roles = _asStringList(permissionData?['roles']);
      final permissions = _asStringList(permissionData?['permissions']);

      final userId =
          PushService.extractAliasFromPermissionInfo(permissionInfo) ??
          _asText(user?['id']) ??
          _asText(profileData?['id']) ??
          '--';
      final username =
          _asText(user?['username']) ??
          _asText(profileData?['username']) ??
          '--';
      final nickname =
          _asText(user?['nickname']) ??
          _asText(profileData?['nickname']) ??
          '--';
      final deptName =
          _asText(user?['deptName']) ??
          _asText(_asMap(user?['dept'])?['name']) ??
          _asText(profileDept?['name']) ??
          '--';
      final postName =
          _asText(user?['postName']) ??
          _asText(user?['position']) ??
          _firstPostName(profileData?['posts']) ??
          '--';
      final mobile =
          _asText(user?['mobile']) ??
          _asText(user?['phone']) ??
          _asText(profileData?['mobile']) ??
          _asText(profileData?['phone']) ??
          '--';

      final pushSnapshot = dependencies.pushService.getDebugSnapshot(
        userId: userId == '--' ? null : userId,
      );
      final expiresAt = _formatExpiresTime(expiresTimeMs);
      final tokenStatus = _resolveTokenStatus(
        token: accessToken,
        expiresTimeMs: expiresTimeMs,
      );
      final permissionJson = _toPrettyJson(permissionInfo);

      final built = _BusinessDebugData(
        apiBaseUrl: AppConstants.apiBaseUrl,
        accessToken: _normalizeText(accessToken),
        refreshToken: _normalizeText(refreshToken),
        expiresTimeMs: expiresTimeMs?.toString() ?? '--',
        expiresAtText: expiresAt,
        tokenStatus: tokenStatus,
        rememberAccountText: remembered.rememberAccount ? '\u662F' : '\u5426',
        rememberedUsername: _normalizeText(remembered.username),
        userId: userId,
        username: username,
        nickname: nickname,
        deptName: deptName,
        postName: postName,
        mobile: mobile,
        rolesText: roles.isEmpty ? '--' : roles.join(' / '),
        permissionsText: permissions.isEmpty ? '--' : permissions.join(', '),
        registrationId: _normalizeText(pushSnapshot.registrationId),
        boundAlias: _normalizeText(pushSnapshot.boundAlias),
        queuedAlias: _normalizeText(pushSnapshot.queuedAlias),
        channel: _normalizeText(pushSnapshot.channel),
        lastAliasBindCode: _normalizeText(pushSnapshot.lastAliasBindCode),
        lastAliasBindMessage: _normalizeText(pushSnapshot.lastAliasBindMessage),
        lastAliasBindTimeText: _formatDateTime(pushSnapshot.lastAliasBindTime),
        permissionInfoJson: permissionJson,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _data = built;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        _showMessage('\u5237\u65B0\u4E1A\u52A1\u8C03\u8BD5\u6570\u636E\u5931\u8D25: $error');
        setState(() {
          _loading = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  String _resolveTokenStatus({
    required String token,
    required int? expiresTimeMs,
  }) {
    if (token.trim().isEmpty) {
      return '\u672A\u767B\u5F55';
    }
    if (expiresTimeMs == null || expiresTimeMs <= 0) {
      return '\u5DF2\u767B\u5F55 (\u65E0 expiresTime)';
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return now >= expiresTimeMs ? '\u5DF2\u8FC7\u671F' : '\u6709\u6548';
  }

  String _formatExpiresTime(int? value) {
    if (value == null || value <= 0) {
      return '--';
    }
    return _formatDateTime(DateTime.fromMillisecondsSinceEpoch(value));
  }

  String _formatDateTime(DateTime? time) {
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

  String _toPrettyJson(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) {
      return '--';
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(map);
    } catch (_) {
      return map.toString();
    }
  }

  Future<void> _copyText(String label, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    _showMessage('$label \u5DF2\u590D\u5236');
  }

  Map<String, dynamic>? _extractPermissionData(Map<String, dynamic>? info) {
    if (info == null) {
      return null;
    }
    final wrapped = _asMap(info['permissionInfo']) ?? info;
    return _asMap(wrapped['data']) ?? wrapped;
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

  List<String> _asStringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => _asText(item))
          .whereType<String>()
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final single = _asText(value);
    if (single == null || single.isEmpty) {
      return const <String>[];
    }
    return <String>[single];
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

  String _normalizeText(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return '--';
    }
    return text;
  }

  String? _firstPostName(Object? posts) {
    if (posts is List) {
      for (final item in posts) {
        final map = _asMap(item);
        final name = _asText(map?['name']);
        if (name != null) {
          return name;
        }
      }
    }
    return null;
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

  void _showMessage(String message) {
    AppCenterToast.show(context, message);
  }
}

class _CopyRowData {
  const _CopyRowData({
    required this.label,
    required this.value,
    this.hideDivider = false,
  });

  final String label;
  final String value;
  final bool hideDivider;
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.data, required this.onCopy});

  final _CopyRowData data;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onCopy(data.value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: data.hideDivider
              ? null
              : const Border(
                  bottom: BorderSide(color: Color(0xFFE8EEF7), width: 1),
                ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  data.label,
                  style: const TextStyle(
                    color: Color(0xFF6E7D90),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Text(
                data.value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Color(0xFF1F2B3A),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => onCopy(data.value),
              tooltip: '\u590D\u5236',
              constraints: const BoxConstraints(minHeight: 32, minWidth: 32),
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
              icon: const Icon(
                Icons.copy_rounded,
                size: 16,
                color: Color(0xFF7F8DA3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessDebugData {
  const _BusinessDebugData({
    required this.apiBaseUrl,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresTimeMs,
    required this.expiresAtText,
    required this.tokenStatus,
    required this.rememberAccountText,
    required this.rememberedUsername,
    required this.userId,
    required this.username,
    required this.nickname,
    required this.deptName,
    required this.postName,
    required this.mobile,
    required this.rolesText,
    required this.permissionsText,
    required this.registrationId,
    required this.boundAlias,
    required this.queuedAlias,
    required this.channel,
    required this.lastAliasBindCode,
    required this.lastAliasBindMessage,
    required this.lastAliasBindTimeText,
    required this.permissionInfoJson,
  });

  final String apiBaseUrl;
  final String accessToken;
  final String refreshToken;
  final String expiresTimeMs;
  final String expiresAtText;
  final String tokenStatus;
  final String rememberAccountText;
  final String rememberedUsername;
  final String userId;
  final String username;
  final String nickname;
  final String deptName;
  final String postName;
  final String mobile;
  final String rolesText;
  final String permissionsText;
  final String registrationId;
  final String boundAlias;
  final String queuedAlias;
  final String channel;
  final String lastAliasBindCode;
  final String lastAliasBindMessage;
  final String lastAliasBindTimeText;
  final String permissionInfoJson;

  String get copyAllText {
    final buffer = StringBuffer()
      ..writeln('apiBaseUrl: $apiBaseUrl')
      ..writeln('accessToken: $accessToken')
      ..writeln('refreshToken: $refreshToken')
      ..writeln('expiresTimeMs: $expiresTimeMs')
      ..writeln('expiresAt: $expiresAtText')
      ..writeln('tokenStatus: $tokenStatus')
      ..writeln('rememberAccount: $rememberAccountText')
      ..writeln('rememberedUsername: $rememberedUsername')
      ..writeln('userId: $userId')
      ..writeln('username: $username')
      ..writeln('nickname: $nickname')
      ..writeln('deptName: $deptName')
      ..writeln('postName: $postName')
      ..writeln('mobile: $mobile')
      ..writeln('roles: $rolesText')
      ..writeln('permissions: $permissionsText')
      ..writeln('registrationId: $registrationId')
      ..writeln('boundAlias: $boundAlias')
      ..writeln('queuedAlias: $queuedAlias')
      ..writeln('channel: $channel')
      ..writeln('lastAliasBindCode: $lastAliasBindCode')
      ..writeln('lastAliasBindMessage: $lastAliasBindMessage')
      ..writeln('lastAliasBindTime: $lastAliasBindTimeText')
      ..writeln()
      ..writeln('permissionInfoJson:')
      ..writeln(permissionInfoJson);
    return buffer.toString();
  }
}
