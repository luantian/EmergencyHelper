import 'dart:async';
import 'dart:io';

import 'package:emergency_helper/src/core/constants/app_constants.dart';
import 'package:emergency_helper/src/core/auth/app_feature_permission.dart';
import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/routing/route_paths.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/core/widgets/app_loading_overlay.dart';
import 'package:emergency_helper/src/features/event/data/event_center.dart';
import 'package:emergency_helper/src/features/push/data/push_service.dart';
import 'package:emergency_helper/src/features/risk/data/risk_center.dart';
import 'package:emergency_helper/src/features/trtc/data/tuicall_session_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:getwidget/getwidget.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _agree = true;
  bool _rememberAccount = false;
  bool _obscurePassword = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadRememberedCredential);
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      body: AppLoadingOverlay(
        loading: _submitting,
        message: '\u767b\u5f55\u4e2d...',
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x19000000),
                        blurRadius: 22,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Center(
                        child: Text(
                          '\u767b\u5f55',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2D3138),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: Container(
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FB),
                            borderRadius: BorderRadius.circular(52),
                            border: Border.all(color: const Color(0xFFE6EAF1)),
                          ),
                          child: ClipOval(
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: SvgPicture.asset(
                                AppConstants.splashLogoAsset,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _LoginInput(
                        key: const Key('login-account-input'),
                        controller: _accountController,
                        label: '\u8d26\u53f7',
                        hintText: '\u8bf7\u8f93\u5165\u8d26\u53f7',
                        prefixIcon: Icons.person_outline,
                        enabled: !_submitting,
                      ),
                      const SizedBox(height: 14),
                      _LoginInput(
                        key: const Key('login-password-input'),
                        controller: _passwordController,
                        label: '\u5bc6\u7801',
                        hintText: '\u8bf7\u8f93\u5165\u5bc6\u7801',
                        prefixIcon: Icons.lock_outline,
                        obscureText: _obscurePassword,
                        enabled: !_submitting,
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: _submitting
                              ? null
                              : () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                        ),
                      ),
                      const SizedBox(height: 18),
                      GFButton(
                        key: const Key('login-submit-button'),
                        onPressed: _submitting ? null : _onLogin,
                        text: _submitting
                            ? '\u767b\u5f55\u4e2d...'
                            : '\u7acb\u5373\u767b\u5f55',
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        color: AppTheme.primaryBlue,
                        fullWidthButton: true,
                        shape: GFButtonShape.pills,
                        size: GFSize.LARGE,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Checkbox(
                            key: const Key('login-remember-checkbox'),
                            value: _rememberAccount,
                            onChanged: _submitting
                                ? null
                                : (value) {
                                    setState(() {
                                      _rememberAccount = value ?? false;
                                    });
                                  },
                          ),
                          const Text(
                            '\u8bb0\u4f4f\u8d26\u53f7',
                            style: TextStyle(color: Color(0xFF667085)),
                          ),
                        ],
                      ),
                      Row(
                        children: <Widget>[
                          Checkbox(
                            key: const Key('login-agreement-checkbox'),
                            value: _agree,
                            onChanged: _submitting
                                ? null
                                : (value) {
                                    setState(() {
                                      _agree = value ?? false;
                                    });
                                  },
                          ),
                          const Expanded(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: <Widget>[
                                Text(
                                  '\u6211\u5df2\u9605\u8bfb\u5e76\u540c\u610f',
                                  style: TextStyle(color: Color(0xFF667085)),
                                ),
                                Text(
                                  '\u300a\u7528\u6237\u534f\u8bae\u300b',
                                  style: TextStyle(color: Color(0xFFD23C3C)),
                                ),
                                Text(
                                  '\u548c',
                                  style: TextStyle(color: Color(0xFF667085)),
                                ),
                                Text(
                                  '\u300a\u9690\u79c1\u653f\u7b56\u300b',
                                  style: TextStyle(color: Color(0xFFD23C3C)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onLogin() async {
    if (!_agree) {
      _showMessage('\u8bf7\u5148\u52fe\u9009\u540c\u610f\u534f\u8bae');
      return;
    }

    final username = _accountController.text.trim();
    final password = _passwordController.text.trim();
    if (username.isEmpty) {
      _showMessage('\u8bf7\u8f93\u5165\u8d26\u53f7');
      return;
    }
    if (password.isEmpty) {
      _showMessage('\u8bf7\u8f93\u5165\u5bc6\u7801');
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final dependencies = context.read<AppDependencies>();
      if (_isFlutterTestEnv()) {
        await dependencies.authLocalStore.saveRememberedCredential(
          rememberAccount: _rememberAccount,
          username: username,
        );
        EventCenter.instance.resetSessionCache(notify: false);
        RiskCenter.instance.resetSessionData(notify: false);
        if (!mounted) {
          return;
        }
        AppFeaturePermissionResolver.instance.clearCache();
        context.go(RoutePaths.home);
        return;
      }

      final loginResult = await dependencies.authService.login(
        tenantId: AppConstants.defaultTenantId,
        username: username,
        password: password,
      );
      await dependencies.authLocalStore.saveRememberedCredential(
        rememberAccount: _rememberAccount,
        username: username,
      );
      EventCenter.instance.resetSessionCache(notify: false);
      RiskCenter.instance.resetSessionData(notify: false);

      if (!mounted) {
        return;
      }
      AppFeaturePermissionResolver.instance.clearCache();
      context.go(RoutePaths.home);

      unawaited(
        _runPostLoginBackgroundJobs(
          dependencies: dependencies,
          permissionInfo: loginResult.permissionInfo,
        ),
      );
    } on AppException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage(
        '\u767b\u5f55\u5931\u8d25\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5',
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _runPostLoginBackgroundJobs({
    required AppDependencies dependencies,
    required Map<String, dynamic> permissionInfo,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final userIdHint = _extractUserIdFromPermissionInfo(permissionInfo);
    unawaited(
      TUICallSessionService.instance.warmupSessionAndPushInBackground(
        dependencies: dependencies,
        userIdHint: userIdHint,
      ),
    );
    unawaited(
      _bindPushAliasInBackground(
        dependencies: dependencies,
        permissionInfo: permissionInfo,
      ),
    );
  }

  bool _isFlutterTestEnv() {
    return Platform.environment.containsKey('FLUTTER_TEST') &&
        Platform.environment['FLUTTER_TEST'] != 'false';
  }

  Future<void> _loadRememberedCredential() async {
    final dependencies = context.read<AppDependencies>();
    final remembered = await dependencies.authLocalStore
        .getRememberedCredential();
    if (!mounted) {
      return;
    }

    if (remembered.rememberAccount && remembered.username.trim().isNotEmpty) {
      setState(() {
        _rememberAccount = true;
        _accountController.text = remembered.username;
        _passwordController.clear();
      });
      return;
    }

    setState(() {
      _rememberAccount = remembered.rememberAccount;
      _passwordController.clear();
    });
  }

  Future<void> _bindPushAliasInBackground({
    required AppDependencies dependencies,
    required Map<String, dynamic> permissionInfo,
  }) async {
    try {
      await dependencies.pushService.clearBadgeAndNotifications();
      await dependencies.pushService.bindAliasFromPermissionInfo(
        permissionInfo,
      );
    } catch (_) {
      // Keep login fast and retry silently once.
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        await dependencies.pushService.bindAliasFromPermissionInfo(
          permissionInfo,
        );
      } catch (_) {}
    }
  }

  String? _extractUserIdFromPermissionInfo(Map<String, dynamic> info) {
    return PushService.extractAliasFromPermissionInfo(info);
  }

  void _showMessage(String message) {
    AppCenterToast.show(context, message);
  }
}

class _LoginInput extends StatelessWidget {
  const _LoginInput({
    super.key,
    required this.controller,
    required this.label,
    required this.hintText,
    required this.prefixIcon,
    required this.enabled,
    this.obscureText = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final IconData prefixIcon;
  final bool enabled;
  final bool obscureText;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF5A6373),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: key,
          controller: controller,
          obscureText: obscureText,
          enabled: enabled,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Color(0xFFA4ACB9)),
            prefixIcon: Icon(prefixIcon),
            suffixIcon: suffix,
            filled: true,
            fillColor: const Color(0xFFF7F9FC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE4E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE4E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppTheme.primaryBlue,
                width: 1.4,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }
}
