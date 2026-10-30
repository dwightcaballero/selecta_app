import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/account_settings_controller.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';

import 'package:selecta_ops/views/widgets/appbar_widget.dart';

/// Presentation page allowing an authenticated user to change their password.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final AccountSettingsController _controller = AccountSettingsController();

  final TextEditingController textEditingControllerEmail = TextEditingController();
  final TextEditingController textEditingControllerOldPassword = TextEditingController();
  final TextEditingController textEditingControllerNewPassword = TextEditingController();
  bool _obscureOldPassword = true;
  bool _obscureNewPassword = true;
  String errormessage = '';

  @override
  void dispose() {
    textEditingControllerEmail.dispose();
    textEditingControllerOldPassword.dispose();
    textEditingControllerNewPassword.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges {
    return textEditingControllerEmail.text.isNotEmpty ||
        textEditingControllerOldPassword.text.isNotEmpty ||
        textEditingControllerNewPassword.text.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_hasUnsavedChanges) {
          final shouldDiscard = await ShowMessage.confirm(
            context,
            title: 'Discard Changes?',
            message: 'You have entered password information. Are you sure you want to discard it?',
            confirmText: 'Discard',
            cancelText: 'Keep Editing',
            isDestructive: true,
            icon: Icons.warning_amber_rounded,
          );
          if (shouldDiscard && context.mounted) {
            Navigator.pop(context);
          }
        } else {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: const CustomAppbar(
          title: 'Change Password',
          subtitle: 'Update your security credentials',
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                elevation: 0,
                color: theme.cardTheme.color ?? (isDark ? const Color(0xFF1E2430) : Colors.white),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF384152) : colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.lock_reset_rounded, color: colorScheme.primary, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Password Security',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Enter your email and current password to set a new one.',
                                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          hintText: 'Enter your account email',
                          prefixIcon: const Icon(Icons.email_outlined, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        controller: textEditingControllerEmail,
                        onEditingComplete: () => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        decoration: InputDecoration(
                          labelText: 'Old Password',
                          hintText: 'Enter current password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureOldPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                            onPressed: () => setState(() => _obscureOldPassword = !_obscureOldPassword),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        obscureText: _obscureOldPassword,
                        controller: textEditingControllerOldPassword,
                        onEditingComplete: () => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          hintText: 'Enter new password',
                          prefixIcon: const Icon(Icons.key_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureNewPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                            onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        obscureText: _obscureNewPassword,
                        controller: textEditingControllerNewPassword,
                        onEditingComplete: () => setState(() {}),
                      ),
                      if (errormessage.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: colorScheme.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, size: 16, color: colorScheme.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(errormessage, style: TextStyle(color: colorScheme.error, fontSize: 13, fontWeight: FontWeight.w500)),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      AsyncFilledButton(
                        onPressed: changePassword,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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

  /// Validates inputs and triggers password change via controller
  Future<void> changePassword() async {
    final email = textEditingControllerEmail.text.trim();
    final oldPassword = textEditingControllerOldPassword.text;
    final newPassword = textEditingControllerNewPassword.text;

    if (email.isEmpty) {
      setState(() => errormessage = 'Email should not be blank!');
      return;
    }
    if (oldPassword.isEmpty) {
      setState(() => errormessage = 'Old password should not be blank!');
      return;
    }
    if (newPassword.isEmpty) {
      setState(() => errormessage = 'New password should not be blank!');
      return;
    }

    try {
      await _controller.changePassword(
        email: email,
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
      if (mounted) {
        showSuccess();
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        errormessage = _controller.getFriendlyErrorMessage(e);
      });
    } catch (e) {
      setState(() {
        errormessage = e.toString();
      });
    }
  }

  void showSuccess() {
    Navigator.pop(context);
    ShowMessage.success(context, 'Password changed successfully!');
  }
}