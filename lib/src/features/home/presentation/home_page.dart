import 'dart:async';

import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/features/home/presentation/tabs/contacts_tab_page.dart';
import 'package:emergency_helper/src/features/home/presentation/tabs/message_tab_page.dart';
import 'package:emergency_helper/src/features/home/presentation/tabs/mine_tab_page.dart';
import 'package:emergency_helper/src/features/home/presentation/tabs/workbench_tab_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _currentIndex = 2;
  int _unreadCount = 0;
  bool _loadingUnread = false;
  bool _pendingUnreadRefresh = false;
  Timer? _unreadPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.microtask(() async {
      await _clearPushBadgeAndNotifications();
      await _refreshUnreadCount();
    });
    _unreadPollTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _refreshUnreadCount(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unreadPollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleAppResumed());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      MessageTabPage(
        onUnreadChanged: _refreshUnreadCount,
        onUnreadHintChanged: _applyUnreadHint,
        isActive: _currentIndex == 0,
        unreadCountHint: _unreadCount,
      ),
      const ContactsTabPage(),
      const WorkbenchTabPage(),
      const MineTabPage(),
    ];
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: tabs),
      bottomNavigationBar: BottomNavigationBar(
        key: const Key('main-bottom-nav'),
        currentIndex: _currentIndex,
        onTap: (value) {
          setState(() {
            _currentIndex = value;
          });
          unawaited(_refreshUnreadCount());
        },
        backgroundColor: Colors.white,
        elevation: 8,
        selectedItemColor: AppTheme.primaryBlue,
        unselectedItemColor: const Color(0xFF8FA0B5),
        selectedFontSize: 13,
        unselectedFontSize: 13,
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: _TabIcon(
              icon: Icons.chat_bubble_outline_rounded,
              isActive: _currentIndex == 0,
              badgeCount: _unreadCount,
            ),
            label: '\u6D88\u606F',
          ),
          BottomNavigationBarItem(
            icon: _TabIcon(
              icon: Icons.contact_page_outlined,
              isActive: _currentIndex == 1,
            ),
            label: '\u901A\u8BAF\u5F55',
          ),
          BottomNavigationBarItem(
            icon: _TabIcon(
              icon: Icons.desktop_windows_outlined,
              isActive: _currentIndex == 2,
            ),
            label: '\u5DE5\u4F5C\u53F0',
          ),
          BottomNavigationBarItem(
            icon: _TabIcon(
              icon: Icons.perm_identity_outlined,
              isActive: _currentIndex == 3,
            ),
            label: '\u6211\u7684',
          ),
        ],
      ),
      backgroundColor: AppTheme.pageBackground,
    );
  }

  Future<void> _refreshUnreadCount() async {
    if (_loadingUnread) {
      _pendingUnreadRefresh = true;
      return;
    }
    _loadingUnread = true;
    try {
      final dependencies = context.read<AppDependencies>();
      final response = await dependencies.apiClient.getJson(
        AppConstants.notifyMessageUnreadCountPath,
      );
      final code = _asInt(response['code']) ?? 0;
      if (code != 0) {
        return;
      }
      final nextCount = (_asInt(response['data']) ?? 0).clamp(0, 9999);
      await _syncPushBadge(nextCount);
      if (!mounted || nextCount == _unreadCount) {
        return;
      }
      setState(() {
        _unreadCount = nextCount;
      });
    } catch (_) {
      // Keep current badge value when transient network failures happen.
    } finally {
      _loadingUnread = false;
      if (_pendingUnreadRefresh && mounted) {
        _pendingUnreadRefresh = false;
        unawaited(_refreshUnreadCount());
      }
    }
  }

  Future<void> _handleAppResumed() async {
    await _clearPushBadgeAndNotifications();
    await _refreshUnreadCount();
  }

  void _applyUnreadHint(int count) {
    final normalized = count.clamp(0, 9999).toInt();
    if (!mounted || normalized == _unreadCount) {
      return;
    }
    setState(() {
      _unreadCount = normalized;
    });
    unawaited(_syncPushBadge(normalized));
  }

  Future<void> _syncPushBadge(int count) async {
    if (!mounted) {
      return;
    }
    try {
      final dependencies = context.read<AppDependencies>();
      await dependencies.pushService.syncBadgeCount(count);
    } catch (_) {}
  }

  Future<void> _clearPushBadgeAndNotifications() async {
    if (!mounted) {
      return;
    }
    try {
      final dependencies = context.read<AppDependencies>();
      await dependencies.pushService.clearBadgeAndNotifications();
    } catch (_) {}
  }

  int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}

class _TabIcon extends StatelessWidget {
  const _TabIcon({
    required this.icon,
    required this.isActive,
    this.badgeCount = 0,
  });

  final IconData icon;
  final bool isActive;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final iconColor = isActive ? AppTheme.primaryBlue : const Color(0xFF8FA0B5);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const SizedBox(width: 40, height: 34),
        Positioned.fill(
          child: Align(child: Icon(icon, size: 28, color: iconColor)),
        ),
        if (badgeCount > 0)
          Positioned(
            top: -4,
            right: -6,
            child: _MessageBadge(count: badgeCount),
          ),
      ],
    );
  }
}

class _MessageBadge extends StatelessWidget {
  const _MessageBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    final minWidth = label.length > 2 ? 24.0 : 18.0;
    return Container(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        color: Color(0xFFF64B4A),
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}
