import 'package:emergency_helper/src/core/di/app_dependencies.dart';
import 'package:emergency_helper/src/core/errors/app_exception.dart';
import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/core/widgets/app_center_toast.dart';
import 'package:emergency_helper/src/core/widgets/app_loading_overlay.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('修改密码'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: AppLoadingOverlay(
        loading: _submitting,
        message: '提交中...',
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _PasswordInput(
                    key: const Key('change-old-password'),
                    controller: _oldController,
                    label: '旧密码',
                    hintText: '请输入旧密码',
                    obscureText: _obscureOld,
                    onToggle: () {
                      setState(() {
                        _obscureOld = !_obscureOld;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  _PasswordInput(
                    key: const Key('change-new-password'),
                    controller: _newController,
                    label: '新密码',
                    hintText: '请输入新密码（至少6位）',
                    obscureText: _obscureNew,
                    onToggle: () {
                      setState(() {
                        _obscureNew = !_obscureNew;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  _PasswordInput(
                    key: const Key('change-confirm-password'),
                    controller: _confirmController,
                    label: '确认新密码',
                    hintText: '请再次输入新密码',
                    obscureText: _obscureConfirm,
                    onToggle: () {
                      setState(() {
                        _obscureConfirm = !_obscureConfirm;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      key: const Key('change-password-submit'),
                      onPressed: _submitting ? null : _onSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('确认修改'),
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

  Future<void> _onSubmit() async {
    final oldText = _oldController.text.trim();
    final newText = _newController.text.trim();
    final confirmText = _confirmController.text.trim();

    if (oldText.isEmpty || newText.isEmpty || confirmText.isEmpty) {
      _showMessage('请完整填写密码信息');
      return;
    }
    if (newText.length < 6) {
      _showMessage('新密码长度至少 6 位');
      return;
    }
    if (newText != confirmText) {
      _showMessage('两次输入的新密码不一致');
      return;
    }
    if (oldText == newText) {
      _showMessage('新密码不能与旧密码相同');
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final dependencies = context.read<AppDependencies>();
      await dependencies.authService.updateProfilePassword(
        oldPassword: oldText,
        newPassword: newText,
      );
      if (!mounted) {
        return;
      }
      _showMessage('密码修改成功');
      Navigator.of(context).pop();
    } on AppException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('修改密码失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    AppCenterToast.show(context, message);
  }
}

class _PasswordInput extends StatelessWidget {
  const _PasswordInput({
    super.key,
    required this.controller,
    required this.label,
    required this.hintText,
    required this.obscureText,
    required this.onToggle,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final bool obscureText;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF5A6373),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: key,
          controller: controller,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor: const Color(0xFFF7F9FC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE4E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE4E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.primaryBlue),
            ),
            suffixIcon: IconButton(
              onPressed: onToggle,
              icon: Icon(
                obscureText
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
