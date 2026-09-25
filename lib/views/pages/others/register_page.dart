import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/users.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/dealer_service.dart';
import 'package:flutter_app/services/user_services.dart';
import 'package:flutter_app/views/pages/others/login_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/snackbar_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final UserService db = UserService();
  final List<DropdownMenuEntry<String>> dropdownItems = [];
  final TextEditingController dropdowncontroller = TextEditingController();
  final TextEditingController txtConfirmPassword = TextEditingController();
  final TextEditingController txtDealerName = TextEditingController();
  final TextEditingController txtEmail = TextEditingController();
  final TextEditingController txtPassword = TextEditingController();
  final TextEditingController txtUsername = TextEditingController();

  // Page-local GlobalKey to prevent Duplicate GlobalKey exceptions
  final _formKey = GlobalKey<FormState>();
  bool _isConfirmPasswordObscured = true;
  bool _isLoading = false;
  bool _isObscured = true;

  @override
  void dispose() {
    txtEmail.dispose();
    txtPassword.dispose();
    txtConfirmPassword.dispose();
    txtUsername.dispose();
    txtDealerName.dispose();
    dropdowncontroller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    dropdownItems.add(const DropdownMenuEntry(value: BusinessRole.dealer, label: BusinessRole.dealer));
    dropdownItems.add(const DropdownMenuEntry(value: BusinessRole.salesman, label: BusinessRole.salesman));
  }

  Future<void> onRegister() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      SnackBarWidget.error(context, 'Please complete all required fields correctly.');
      return;
    }

    if (!_hasValidPassword) {
      SnackBarWidget.error(context, 'Password must satisfy all security requirements.');
      return;
    }

    if (txtPassword.text != txtConfirmPassword.text) {
      SnackBarWidget.error(context, 'Passwords do not match.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final dbDealer = DealerService();
      final existingDealer = await dbDealer.getDealerByName(txtDealerName.text.trim());

      if (existingDealer == null) {
        if (mounted) {
          SnackBarWidget.error(context, 'Dealer name does not exist. Please contact your administrator.');
        }
        return;
      }

      final email = txtEmail.text.trim();
      final password = txtPassword.text;
      final username = txtUsername.text.trim();
      final dealerName = txtDealerName.text.trim();
      final role = dropdowncontroller.text;

      await authService.value.createAccount(email: email, password: password);
      await authService.value.signIn(email: email, password: password);

      final newRecord = Users(email: email, username: username, role: role, dealerName: dealerName);

      db.addUser(newRecord);
      await Helperfunctions.logCreate(username, newRecord.toJson());

      await authService.value.updateUsername(username: username);
      await authService.value.signOut();
      await authService.value.signIn(email: email, password: password);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', jsonEncode(newRecord.toJson()));

      if (!mounted) return;

      ShowMessage.success(context, 'Successfully created account [$username]!');
      Navigator.pop(context, 'Successfully created account [$username].');
      await authService.value.signOut();
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        SnackBarWidget.error(context, _friendlyFirebaseMessage(error));
      }
    } catch (error) {
      if (mounted) {
        SnackBarWidget.error(context, 'Unable to create account. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool get _hasValidPassword {
    final password = txtPassword.text;
    return password.length >= 8 &&
        password.contains(RegExp(r'[A-Z]')) &&
        password.contains(RegExp(r'[a-z]')) &&
        password.contains(RegExp(r'[0-9]'));
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    if (email.isEmpty) {
      return 'Enter your email address';
    }

    if (!emailPattern.hasMatch(email)) {
      return 'Enter a valid email address';
    }

    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Confirm your password';
    }

    if (value != txtPassword.text) {
      return 'Passwords do not match';
    }

    return null;
  }

  String _friendlyFirebaseMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'This email is already registered. Please log in.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Please use a stronger password.';
      case 'network-request-failed':
        return 'Network connection issue. Please check your internet connection.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return error.message ?? 'Unable to create account. Please try again.';
    }
  }

  InputDecoration _inputDecoration(BuildContext context, {required String label, required IconData icon, Widget? suffixIcon}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: colorScheme.onSurfaceVariant),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.error, width: 2),
      ),
    );
  }

  String? _requiredValidator(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter your $label';
    }
    return null;
  }

  Future<void> _showRegisterConfirmation() async {
    if (_isLoading) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      SnackBarWidget.error(context, 'Please complete all required fields before proceeding.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.person_add_rounded, color: colorScheme.primary),
              const SizedBox(width: 10),
              const Text('Create Account?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Text(
            'Confirm registration for "${txtUsername.text.trim()}" at "${txtDealerName.text.trim()}".',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await onRegister();
    }
  }

  Widget _passwordStrengthIndicator() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final password = txtPassword.text;
    final hasLength = password.length >= 8;
    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasLowercase = password.contains(RegExp(r'[a-z]'));
    final hasNumber = password.contains(RegExp(r'[0-9]'));

    final requirements = [
      (hasLength, '8+ characters'),
      (hasUppercase, 'Uppercase letter'),
      (hasLowercase, 'Lowercase letter'),
      (hasNumber, 'Number (0-9)'),
    ];

    final completedCount = requirements.where((item) => item.$1).length;
    final progress = completedCount / requirements.length;
    final isFull = completedCount == requirements.length;

    Color progressColor;
    if (progress <= 0.25) {
      progressColor = colorScheme.error;
    } else if (progress <= 0.75) {
      progressColor = Colors.orange;
    } else {
      progressColor = Colors.green;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Password strength',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              isFull ? 'Strong' : completedCount >= 2 ? 'Moderate' : 'Weak',
              style: theme.textTheme.labelSmall?.copyWith(
                color: progressColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            backgroundColor: colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: requirements.map((requirement) {
            final isComplete = requirement.$1;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isComplete ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 14,
                  color: isComplete ? Colors.green : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  requirement.$2,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isComplete ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                    fontWeight: isComplete ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSectionHeader({required IconData icon, required String title, required String subtitle}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            Text(
              subtitle,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: const CustomAppbar(title: 'Create Account', subtitle: 'Start your journey'),
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [colorScheme.surface, colorScheme.surfaceContainerLowest]
                : [colorScheme.primaryContainer.withValues(alpha: 0.25), colorScheme.surface],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const SizedBox(height: 8),

                      // Avatar Header
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.person_add_alt_1_rounded, size: 42, color: colorScheme.primary),
                      ),
                      const SizedBox(height: 14),

                      Text(
                        'Join Sedy',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),

                      Text(
                        'Create an account to access sales and distribution tools.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Account Details Card
                      Card(
                        elevation: 0,
                        color: isDark ? colorScheme.surfaceContainer : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(
                            color: isDark ? colorScheme.outlineVariant.withValues(alpha: 0.3) : colorScheme.outlineVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(
                                icon: Icons.lock_outline_rounded,
                                title: 'Account Credentials',
                                subtitle: 'Login information and credentials',
                              ),
                              const SizedBox(height: 18),

                              // Email
                              TextFormField(
                                controller: txtEmail,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                decoration: _inputDecoration(
                                  context,
                                  label: 'Email address',
                                  icon: Icons.email_outlined,
                                ),
                                validator: _validateEmail,
                              ),
                              const SizedBox(height: 16),

                              // Password
                              TextFormField(
                                controller: txtPassword,
                                obscureText: _isObscured,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.newPassword],
                                onChanged: (_) => setState(() {}),
                                decoration: _inputDecoration(
                                  context,
                                  label: 'Password',
                                  icon: Icons.lock_outline_rounded,
                                  suffixIcon: IconButton(
                                    tooltip: _isObscured ? 'Show password' : 'Hide password',
                                    onPressed: () => setState(() => _isObscured = !_isObscured),
                                    icon: Icon(_isObscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Enter a password';
                                  }
                                  if (!_hasValidPassword) {
                                    return 'Password does not meet requirements';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 10),

                              // Password Strength indicator
                              _passwordStrengthIndicator(),
                              const SizedBox(height: 16),

                              // Confirm Password
                              TextFormField(
                                controller: txtConfirmPassword,
                                obscureText: _isConfirmPasswordObscured,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.newPassword],
                                decoration: _inputDecoration(
                                  context,
                                  label: 'Confirm password',
                                  icon: Icons.lock_reset_rounded,
                                  suffixIcon: IconButton(
                                    tooltip: _isConfirmPasswordObscured ? 'Show password' : 'Hide password',
                                    onPressed: () => setState(() => _isConfirmPasswordObscured = !_isConfirmPasswordObscured),
                                    icon: Icon(_isConfirmPasswordObscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  ),
                                ),
                                validator: _validateConfirmPassword,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Business & Profile Details Card
                      Card(
                        elevation: 0,
                        color: isDark ? colorScheme.surfaceContainer : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(
                            color: isDark ? colorScheme.outlineVariant.withValues(alpha: 0.3) : colorScheme.outlineVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(
                                icon: Icons.badge_outlined,
                                title: 'Profile & Business',
                                subtitle: 'Your organization information',
                              ),
                              const SizedBox(height: 18),

                              // Username
                              TextFormField(
                                controller: txtUsername,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                autofillHints: const [AutofillHints.username],
                                decoration: _inputDecoration(
                                  context,
                                  label: 'Username',
                                  icon: Icons.person_outline_rounded,
                                ),
                                validator: (value) => _requiredValidator(value, 'username'),
                              ),
                              const SizedBox(height: 16),

                              // Dealer Name
                              TextFormField(
                                controller: txtDealerName,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                decoration: _inputDecoration(
                                  context,
                                  label: 'Dealer name',
                                  icon: Icons.storefront_outlined,
                                ),
                                validator: (value) => _requiredValidator(value, 'dealer name'),
                              ),
                              const SizedBox(height: 16),

                              // Business Role dropdown
                              DropdownButtonFormField<String>(
                                initialValue: dropdowncontroller.text.isEmpty ? null : dropdowncontroller.text,
                                decoration: _inputDecoration(
                                  context,
                                  label: 'Business role',
                                  icon: Icons.work_outline_rounded,
                                ),
                                items: dropdownItems.map((entry) {
                                  return DropdownMenuItem<String>(
                                    value: entry.value,
                                    child: Text(entry.label),
                                  );
                                }).toList(),
                                onChanged: _isLoading
                                    ? null
                                    : (value) {
                                        setState(() {
                                          dropdowncontroller.text = value ?? '';
                                        });
                                      },
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Select a business role';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _showRegisterConfirmation,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: colorScheme.onPrimary,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.person_add_rounded, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Create Account',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Link back to Login
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Already have an account?',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    if (Navigator.canPop(context)) {
                                      Navigator.pop(context);
                                    } else {
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(builder: (context) => const LoginPage()),
                                      );
                                    }
                                  },
                            child: Text(
                              'Log in',
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Security reassurance footer
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shield_outlined, size: 14, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                          const SizedBox(width: 6),
                          Text(
                            'Your credentials are fully encrypted and secure.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
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
}
