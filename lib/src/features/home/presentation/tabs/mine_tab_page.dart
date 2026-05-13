import 'dart:async';
import 'dart:io';

import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/auth/app_feature_permission.dart';
import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/routing/route_paths.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/core/utils/file_logger.dart';
import 'package:share_plus/share_plus.dart';
import 'package:emergency_helper/src/features/event/data/event_center.dart';
import 'package:emergency_helper/src/features/risk/data/risk_center.dart';
import 'package:emergency_helper/src/features/trtc/data/tuicall_session_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart' as rtc;
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

class MineTabPage extends StatefulWidget {
  const MineTabPage({super.key});

  @override
  State<MineTabPage> createState() => _MineTabPageState();
}

class _MineTabPageState extends State<MineTabPage> {
  bool _loggingOut = false;
  bool _loadingProfile = true;
  UserProfileViewData _profile = const UserProfileViewData();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text('\u6211\u7684'),
        centerTitle: true,
      ),
      backgroundColor: const Color(0xFFF1F5FA),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 22),
          children: <Widget>[
            _ProfileHeroCard(profile: profile, loading: _loadingProfile),
            const SizedBox(height: 10),
            _ProfileInfoCard(profile: profile, loading: _loadingProfile),
            const SizedBox(height: 10),
            _ActionCard(
              onChangePassword: () => context.push(RoutePaths.changePassword),
              onPushDebug: () => context.push(RoutePaths.pushDebug),
              onBusinessDebug: () => context.push(RoutePaths.businessDebug),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _exportLogFile,
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('导出运行日志', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('logout-button'),
                onPressed: _loggingOut ? null : _onLogout,
                icon: Icon(
                  _loggingOut
                      ? Icons.hourglass_top_rounded
                      : Icons.logout_rounded,
                  size: 18,
                ),
                label: Text(
                  _loggingOut
                      ? '\u9000\u51FA\u4E2D...'
                      : '\u9000\u51FA\u767B\u5F55',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadProfile() async {
    try {
      final dependencies = context.read<AppDependencies>();
      var info = await dependencies.authService.getCachedPermissionInfo();
      var parsed = _parseProfile(info);

      if (_needsProfileRefresh(parsed) && !_isFlutterTestEnv()) {
        await dependencies.authService.fetchUserProfileAndCache();
        info = await dependencies.authService.getCachedPermissionInfo();
        parsed = _parseProfile(info);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _profile = parsed;
        _loadingProfile = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingProfile = false;
      });
    }
  }

  /// Share the current log file via system share sheet (WeChat, email, etc.).
  Future<void> _exportLogFile() async {
    final logPath = FileLogger.logPath;
    if (logPath == null) {
      if (mounted) {
        AppCenterToast.show(context, '日志文件未初始化');
      }
      return;
    }

    final srcFile = File(logPath);
    if (!srcFile.existsSync()) {
      if (mounted) {
        AppCenterToast.show(context, '日志文件不存在');
      }
      return;
    }

    try {
      final result = await Share.shareXFiles(
        [XFile(logPath)],
        subject: '应急助手运行日志',
      );
      debugPrint('[MineTabPage] share log result: ${result.status}');
    } catch (e) {
      debugPrint('[MineTabPage] share log failed: $e');
      if (mounted) {
        AppCenterToast.show(context, '分享失败: $e');
      }
    }
  }

  Future<void> _onLogout() async {
    if (_loggingOut) {
      return;
    }
    setState(() {
      _loggingOut = true;
    });

    try {
      // Show full-screen loading dialog that covers bottom tab bar too.
      _showLogoutDialog();

      final dependencies = context.read<AppDependencies>();
      final shouldNotifyServer = !_isFlutterTestEnv();
      final tokenSnapshot = shouldNotifyServer
          ? await dependencies.authLocalStore.getAccessToken()
          : null;
      dependencies.apiClient.cancelAllPendingRequests(reason: 'MANUAL_LOGOUT');
      dependencies.apiClient.resetAuthExpiredState();

      // Dispose call observer and uninit TUICallEngine so native SDK
      // goes offline and stops receiving incoming call notifications.
      TUICallSessionService.instance.disposeCallObserver();
      try {
        await rtc.TUICallEngine.instance
            .unInit()
            .timeout(const Duration(seconds: 5));
        debugPrint('[TRTC-DEBUG][Logout] TUICallEngine.unInit success');
      } catch (e) {
        debugPrint('[TRTC-DEBUG][Logout] TUICallEngine.unInit failed: $e');
      }
      TUICallSessionService.instance.clearLocalSessionState();

      await _runWithTimeout(
        dependencies.pushService.unbindAlias(),
        timeout: const Duration(seconds: 1),
      );
      await _runWithTimeout(
        dependencies.pushService.unregisterPush(),
        timeout: const Duration(seconds: 3),
      );

      // Logout from Tencent IM SDK to disconnect the long-poll session.
      // Without this, TIMPush may continue receiving pushes because the IM
      // SDK session stays active even after unregisterPush.
      try {
        await TencentImSDKPlugin.v2TIMManager
            .logout()
            .timeout(const Duration(seconds: 3));
        debugPrint('[MineTabPage] IM SDK logout success');
      } catch (e) {
        debugPrint('[MineTabPage] IM SDK logout failed: $e');
      }

      await dependencies.authLocalStore.clear();
      EventCenter.instance.resetSessionCache(notify: false);
      RiskCenter.instance.resetSessionData(notify: false);
      AppFeaturePermissionResolver.instance.clearCache();

      if (shouldNotifyServer) {
        await _runWithTimeout(
          _notifyServerLogout(
            dependencies: dependencies,
            accessToken: tokenSnapshot,
          ),
          timeout: const Duration(seconds: 3),
        );
      }
      await _runWithTimeout(
        dependencies.pushService.clearBadgeAndNotifications(),
        timeout: const Duration(seconds: 2),
      );

      if (!mounted) {
        return;
      }
      // Pop the dialog before navigating.
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      context.go(RoutePaths.login);
    } on AppException catch (error) {
      // Pop the dialog and show error.
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _showMessage(error.message);
    } catch (_) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _showMessage(
        '\u9000\u51FA\u767B\u5F55\u5931\u8D25\uFF0C\u8BF7\u7A0D\u540E\u91CD\u8BD5',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loggingOut = false;
        });
      }
    }
  }

  void _showLogoutDialog() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      barrierColor: const Color(0x66000000),
      transitionDuration: Duration.zero,
      pageBuilder: (context, anim1, anim2) {
        return PopScope(
          canPop: false,
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: Container(
                width: 140,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceWhite,
                  borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    SizedBox(height: 14),
                    Text(
                      '\u9000\u51FA\u767B\u5F55\u4E2D...',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _notifyServerLogout({
    required AppDependencies dependencies,
    required String? accessToken,
  }) async {
    final token = (accessToken ?? '').trim();
    if (token.isEmpty) {
      return;
    }
    try {
      await dependencies.apiClient.postJson(
        AppConstants.authLogoutPath,
        headers: <String, String>{'authorization': token},
        withAuthorization: false,
      );
    } catch (_) {}
  }

  Future<void> _runWithTimeout(
    Future<void> task, {
    required Duration timeout,
  }) async {
    try {
      await task.timeout(timeout);
    } catch (_) {}
  }

  bool _isFlutterTestEnv() {
    return Platform.environment.containsKey('FLUTTER_TEST') &&
        Platform.environment['FLUTTER_TEST'] != 'false';
  }

  UserProfileViewData _parseProfile(Map<String, dynamic>? info) {
    if (info == null) {
      return const UserProfileViewData();
    }

    final permissionInfo = _asMap(info['permissionInfo']) ?? info;
    final profileInfo = _asMap(info['profileInfo']);

    final permissionData = _asMap(permissionInfo['data']) ?? permissionInfo;
    final permissionUser = _asMap(permissionData['user']) ?? permissionData;

    final profileData = _asMap(profileInfo?['data']);
    final profileDept = _asMap(profileData?['dept']);
    final profilePosts = profileData?['posts'];

    final deptName =
        _asText(permissionUser['deptName']) ??
        _asText(_asMap(permissionUser['dept'])?['name']) ??
        _asText(profileDept?['name']) ??
        _asText(permissionUser['orgName']);
    final postName =
        _asText(permissionUser['postName']) ??
        _asText(permissionUser['position']) ??
        _firstPostName(profilePosts) ??
        _asText(profileData?['title']);
    final mobile =
        _asText(permissionUser['mobile']) ??
        _asText(permissionUser['phone']) ??
        _asText(profileData?['mobile']) ??
        _asText(profileData?['phone']);

    return UserProfileViewData(
      nickname:
          _asText(permissionUser['nickname']) ??
          _asText(profileData?['nickname']) ??
          _asText(permissionUser['username']) ??
          _asText(profileData?['username']) ??
          '\u672A\u77E5\u7528\u6237',
      title:
          _asText(permissionUser['title']) ??
          _asText(profileData?['title']) ??
          postName ??
          '\u5E94\u6025\u52A9\u624B',
      username:
          _asText(permissionUser['username']) ??
          _asText(profileData?['username']) ??
          '--',
      department: deptName ?? '--',
      job: postName ?? '--',
      mobile: mobile ?? '--',
    );
  }

  bool _needsProfileRefresh(UserProfileViewData profile) {
    return profile.department == '--' ||
        profile.job == '--' ||
        profile.mobile == '--';
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

  void _showMessage(String message) {
    AppCenterToast.show(context, message);
  }
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({required this.profile, required this.loading});

  final UserProfileViewData profile;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final nickname = loading ? '\u52A0\u8F7D\u4E2D...' : profile.nickname;
    final title = loading ? '--' : profile.title;
    final username = loading ? '--' : profile.username;
    final avatarText = _buildAvatarText(nickname);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: <Color>[AppTheme.primaryBlue, Color(0xFF4EA9F4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x2B67BAFF),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        children: <Widget>[
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(29),
              border: Border.all(color: const Color(0x59FFFFFF)),
            ),
            child: Text(
              avatarText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xE8E8F3FF),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x29FFFFFF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '\u8D26\u53F7: $username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _buildAvatarText(String nickname) {
    final text = nickname.trim();
    if (text.isEmpty || text == '--' || text == '\u52A0\u8F7D\u4E2D...') {
      return '\u6211';
    }
    return text.substring(0, 1);
  }
}

class _ProfileInfoCard extends StatelessWidget {
  const _ProfileInfoCard({required this.profile, required this.loading});

  final UserProfileViewData profile;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(
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
      ),
      child: Column(
        children: <Widget>[
          _InfoRow(
            label: '\u6240\u5C5E\u5355\u4F4D',
            value: loading ? '--' : profile.department,
          ),
          _InfoRow(label: '\u804C\u52A1', value: loading ? '--' : profile.job),
          _InfoRow(
            label: '\u624B\u673A\u53F7',
            value: loading ? '--' : profile.mobile,
            hideDivider: true,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
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
      padding: const EdgeInsets.symmetric(vertical: 10),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF1F2B3A),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.onChangePassword,
    required this.onPushDebug,
    required this.onBusinessDebug,
  });

  final VoidCallback onChangePassword;
  final VoidCallback onPushDebug;
  final VoidCallback onBusinessDebug;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE6F2)),
      ),
      child: Column(
        children: <Widget>[
          ListTile(
            key: const Key('open-change-password-button'),
            dense: true,
            leading: const Icon(Icons.lock_outline, color: Color(0xFF386EBB)),
            title: const Text(
              '\u4FEE\u6539\u5BC6\u7801',
              style: TextStyle(
                color: Color(0xFF1F2B3A),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text(
              '\u5B9A\u671F\u4FEE\u6539\u5BC6\u7801\u53EF\u63D0\u5347\u8D26\u53F7\u5B89\u5168',
              style: TextStyle(color: Color(0xFF7A889A), fontSize: 12),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF8A97A8),
            ),
            onTap: onChangePassword,
          ),
          const Divider(height: 1, color: Color(0xFFE8EEF7)),
          ListTile(
            key: const Key('open-push-debug-button'),
            dense: true,
            leading: const Icon(
              Icons.notifications_active_outlined,
              color: Color(0xFF386EBB),
            ),
            title: const Text(
              '\u63A8\u9001\u8C03\u8BD5',
              style: TextStyle(
                color: Color(0xFF1F2B3A),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text(
              '\u67E5\u770B userId\u3001Registration ID \u548C alias \u7ED1\u5B9A\u7ED3\u679C',
              style: TextStyle(color: Color(0xFF7A889A), fontSize: 12),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF8A97A8),
            ),
            onTap: onPushDebug,
          ),
          const Divider(height: 1, color: Color(0xFFE8EEF7)),
          ListTile(
            key: const Key('open-business-debug-button'),
            dense: true,
            leading: const Icon(
              Icons.bug_report_outlined,
              color: Color(0xFF386EBB),
            ),
            title: const Text(
              '\u4E1A\u52A1\u8C03\u8BD5',
              style: TextStyle(
                color: Color(0xFF1F2B3A),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text(
              '\u8F93\u51FA Token\u3001\u7528\u6237\u3001\u6743\u9650\u3001\u63A8\u9001\u72B6\u6001\uFF0C\u652F\u6301\u9010\u9879\u590D\u5236',
              style: TextStyle(color: Color(0xFF7A889A), fontSize: 12),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF8A97A8),
            ),
            onTap: onBusinessDebug,
          ),
        ],
      ),
    );
  }
}

class UserProfileViewData {
  const UserProfileViewData({
    this.nickname = '\u672A\u77E5\u7528\u6237',
    this.title = '\u5E94\u6025\u52A9\u624B',
    this.username = '--',
    this.department = '--',
    this.job = '--',
    this.mobile = '--',
  });

  final String nickname;
  final String title;
  final String username;
  final String department;
  final String job;
  final String mobile;
}
