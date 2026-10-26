import 'package:flutter/material.dart';
import 'package:selecta_ops/services/store_auth_service.dart';
import 'package:selecta_ops/views/pages/store/store_shell.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';

/// Password change screen for store accounts.
/// Supports both forced first-time password changes and regular profile changes.
class StoreChangePasswordPage extends StatefulWidget {
  final bool isForced;

  const StoreChangePasswordPage({
    super.key,
    this.isForced = false,
  });

  @override
  State<StoreChangePasswordPage> createState() => _StoreChangePasswordPageState();
}

class _StoreChangePasswordPageState extends State<StoreChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true);

    try {
      await StoreAuthService().storeChangePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );

      if (mounted) {
        ShowMessage.success(
          context,
          widget.isForced
              ? 'Password successfully set! Welcome to your store portal.'
              : 'Password successfully changed.',
        );

        if (widget.isForced) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const StoreShell()),
            (route) => false,
          );
        } else {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, e.toString().replaceAll('Exception: ', '').replaceAll('FormatException: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !widget.isForced,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isForced ? 'Set New Password' : 'Change Password'),
          automaticallyImplyLeading: !widget.isForced,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: widget.isForced
                            ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: widget.isForced ? colorScheme.primary : colorScheme.outlineVariant,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            widget.isForced ? Icons.security_rounded : Icons.lock_outline_rounded,
                            size: 28,
                            color: widget.isForced ? colorScheme.primary : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.isForced
                                  ? 'For your security, you must create a new password before accessing your store portal.'
                                  : 'Enter your current password and choose a new password of at least 8 characters.',
                              style: const TextStyle(fontSize: 13, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Current Password
                    TextFormField(
                      controller: _currentPasswordController,
                      obscureText: _obscureCurrent,
                      decoration: InputDecoration(
                        labelText: widget.isForced ? 'Temporary Password' : 'Current Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureCurrent ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return 'Please enter your ${widget.isForced ? "temporary" : "current"} password';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // New Password
                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: _obscureNew,
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        helperText: 'Must be at least 8 characters long',
                        prefixIcon: const Icon(Icons.key_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscureNew = !_obscureNew),
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter a new password';
                        }
                        if (val.trim().length < 8) {
                          return 'Password must be at least 8 characters long';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Confirm New Password
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      decoration: InputDecoration(
                        labelText: 'Confirm New Password',
                        prefixIcon: const Icon(Icons.check_circle_outline_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      validator: (val) {
                        if (val != _newPasswordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),

                    AsyncFilledButton(
                      onPressed: _isLoading ? null : _submit,
                      loadingLabel: 'Updating Password...',
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        widget.isForced ? 'Set Password & Continue' : 'Update Password',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
