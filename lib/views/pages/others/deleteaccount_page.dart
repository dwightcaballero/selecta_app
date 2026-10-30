import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/account_settings_controller.dart';
import 'package:selecta_ops/views/pages/others/auth_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';

import 'package:selecta_ops/views/widgets/appbar_widget.dart';

/// Presentation page for confirming and executing permanent user account deletion.
class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final AccountSettingsController _controller = AccountSettingsController();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController textEditingControllerEmail = TextEditingController();
  final TextEditingController textEditingControllerPassword = TextEditingController();
  bool _obscurePassword = true;
  String errormessage = '';

  @override
  void dispose() {
    textEditingControllerEmail.dispose();
    textEditingControllerPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: const CustomAppbar(
        title: 'Delete Account',
        subtitle: 'Permanent account removal',
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
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colorScheme.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Warning: Irreversible Action',
                                    style: TextStyle(
                                      color: colorScheme.error,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Deleting your account will permanently remove your login credentials, personal preferences, and profile data.',
                                    style: TextStyle(
                                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                                      fontSize: 12.5,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: _controller.validateEmail,
                        decoration: InputDecoration(
                          labelText: 'Confirm Email',
                          hintText: 'Enter your registered email',
                          prefixIcon: const Icon(Icons.email_outlined, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        controller: textEditingControllerEmail,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        validator: (value) => value == null || value.isEmpty ? 'Password should not be blank.' : null,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
                          hintText: 'Enter your password to verify identity',
                          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        controller: textEditingControllerPassword,
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
                        onPressed: deleteAccount,
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.error,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Permanently Delete Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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

  /// Validates form and initiates account deletion via controller
  Future<void> deleteAccount() async {
    if (_formKey.currentState?.validate() ?? false) {
      try {
        await _controller.deleteAccount(
          email: textEditingControllerEmail.text,
          password: textEditingControllerPassword.text,
        );
        if (mounted) {
          showSuccess();
        }
      } on FirebaseAuthException catch (e) {
        if (mounted) {
          setState(() {
            errormessage = _controller.getFriendlyErrorMessage(e);
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            errormessage = e.toString();
          });
        }
      }
    } else {
      setState(() {
        errormessage = '';
      });
    }
  }

  void showSuccess() {
    ShowMessage.success(context, 'Account deleted successfully!');
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AuthPage()));
  }
}