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
        message: '\u767B\u5F55\u4E2D...',
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
                          '登录',
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
                        label: '账号',
                        hintText: '请输入用户名',
                        prefixIcon: Icons.person_outline,
                        enabled: !_submitting,
                      ),
                      const SizedBox(height: 14),
                      _LoginInput(
                        key: const Key('login-password-input'),
                        controller: _passwordController,
                        label: '密码',
                        hintText: '请输入密码',
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
                        text: _submitting ? '登录中...' : '立即登录',
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
                            '记住账号',
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
                                  '我已阅读并同意',
                                  style: TextStyle(color: Color(0xFF667085)),
                                ),
                                Text(
                                  '《隐私政策》',
                                  style: TextStyle(color: Color(0xFFD23C3C)),
                                ),
                                Text(
                                  '与',
                                  style: TextStyle(color: Color(0xFF667085)),
                                ),
                                Text(
                                  '《用户协议》',
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
      _showMessage('请先勾选协议');
      return;
    }

    final username = _accountController.text.trim();
    final password = _passwordController.text.trim();
    if (username.isEmpty) {
      _showMessage('请输入账号');
      return;
    }
    if (password.isEmpty) {
      _showMessage('请输入密码');
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
      unawaited(_ensureCallSessionInBackground(dependencies));
      unawaited(
        _bindPushAliasInBackground(
          dependencies: dependencies,
          permissionInfo: loginResult.permissionInfo,
        ),
      );

      if (!mounted) {
        return;
      }
      AppFeaturePermissionResolver.instance.clearCache();
      context.go(RoutePaths.home);
    } on AppException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('登录失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
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

  Future<void> _ensureCallSessionInBackground(
    AppDependencies dependencies,
  ) async {
    try {
      dependencies.logger.debug(
        '[PUSH-DEBUG] login: _ensureCallSessionInBackground started',
      );
      final result = await TUICallSessionService.instance.ensureLoggedIn(
        dependencies: dependencies,
      );
      final sdkAppId = TUICallSessionService.instance.activeSdkAppId;
      dependencies.logger.debug(
        '[PUSH-DEBUG] login: ensureLoggedIn result=${result.success}, '
        'hasSdkAppId=${sdkAppId != null && sdkAppId > 0}',
      );
      if (result.success) {
        if (sdkAppId != null && sdkAppId > 0) {
          dependencies.logger.debug(
            '[PUSH-DEBUG] login: calling notifyIMLoggedIn',
          );
          await dependencies.pushService.notifyIMLoggedIn(sdkAppId);
          dependencies.logger.debug(
            '[PUSH-DEBUG] login: notifyIMLoggedIn completed',
          );
        }
      }
    } catch (e) {
      dependencies.logger.error(
        '[PUSH-DEBUG] login: _ensureCallSessionInBackground failed',
        error: e,
      );
    }
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
