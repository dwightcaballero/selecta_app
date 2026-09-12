import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/users.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/dealer_service.dart';
import 'package:flutter_app/services/user_services.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/snackbar_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  UserService db = UserService();
  List<DropdownMenuEntry<String>> dropdownItems = [];
  TextEditingController dropdowncontroller = TextEditingController();
  TextEditingController txtDealerName = TextEditingController();
  TextEditingController txtEmail = TextEditingController();
  TextEditingController txtPassword = TextEditingController();
  TextEditingController txtConfirmPassword = TextEditingController();
  TextEditingController txtUsername = TextEditingController();

  final _formKey = KVariables.formkey;
  bool _isLoading = false;
  bool _isObscured = true;
  bool _isConfirmPasswordObscured = true;

  bool get _hasValidPassword {
    final password = txtPassword.text;

    return password.length >= 8 && password.contains(RegExp(r'[A-Z]')) && password.contains(RegExp(r'[a-z]')) && password.contains(RegExp(r'[0-9]'));
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
        return 'Email is already registered.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'network-request-failed':
        return 'Network error. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return 'Unable to create the account. Please try again.';
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? const Color(0xFFD32F2F) : const Color(0xFF2E7D32),
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          duration: const Duration(seconds: 4),
        ),
      );
  }

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

    dropdownItems.add(DropdownMenuEntry(value: BusinessRole.dealer, label: BusinessRole.dealer));
    dropdownItems.add(DropdownMenuEntry(value: BusinessRole.salesman, label: BusinessRole.salesman));
  }

  InputDecoration _inputDecoration({required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }

  Widget _textField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    String? Function(String?)? validator,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      validator: validator,
      decoration: _inputDecoration(label: label, icon: icon),
    );
  }

  String? _requiredValidator(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter your $label';
    }

    return null;
  }

  Widget _businessRoleField() {
    return DropdownButtonFormField<String>(
      initialValue: dropdowncontroller.text.isEmpty ? null : dropdowncontroller.text,
      decoration: _inputDecoration(label: 'Business role', icon: Icons.badge_outlined),
      items: dropdownItems.map((entry) {
        return DropdownMenuItem<String>(value: entry.value, child: Text(entry.label));
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
    );
  }

  Future<void> _showRegisterConfirmation() async {
    if (_isLoading) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Create account?'),
          content: const Text('Please confirm that you want to create this account.'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Create account')),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await onRegister();
    }
  }

  Future<void> onRegister() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showSnackBar('Please complete all required fields.', isError: true);
      return;
    }

    if (!_hasValidPassword) {
      _showSnackBar('Password must contain at least 8 characters, one uppercase letter, one lowercase letter, and one number.', isError: true);
      return;
    }

    if (txtPassword.text != txtConfirmPassword.text) {
      _showSnackBar('Passwords do not match.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final dbDealer = DealerService();
      final existingDealer = await dbDealer.getDealerByName(txtDealerName.text.trim());

      if (existingDealer == null) {
        _showSnackBar('Dealer name does not exist. Please contact your administrator.', isError: true);
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

      await authService.value.updateUsername(username: username);

      await authService.value.signOut();

      await authService.value.signIn(email: email, password: password);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', jsonEncode(newRecord.toJson()));

      if (!mounted) return;

      _showSnackBar('Successfully created account [$username].', isError: false);

      Navigator.pop(context, 'Successfully created account [$username].');

      await authService.value.signOut();
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        SnackBarWidget.error(context, _friendlyFirebaseMessage(error));
      }
    } catch (error) {
      if (mounted) {
        SnackBarWidget.error(context, 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _passwordStrengthIndicator() {
    final password = txtPassword.text;
    final hasLength = password.length >= 8;
    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasLowercase = password.contains(RegExp(r'[a-z]'));
    final hasNumber = password.contains(RegExp(r'[0-9]'));

    final requirements = [
      (hasLength, '8+ characters'),
      (hasUppercase, 'Uppercase letter'),
      (hasLowercase, 'Lowercase letter'),
      (hasNumber, 'Number'),
    ];

    final completedCount = requirements.where((item) => item.$1).length;
    final progress = completedCount / requirements.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: progress,
          minHeight: 6,
          borderRadius: BorderRadius.circular(10),
          color: progress == 1 ? Colors.green : Theme.of(context).colorScheme.primary,
          backgroundColor: Colors.grey.shade200,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: requirements.map((requirement) {
            final isComplete = requirement.$1;

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isComplete ? Icons.check_circle : Icons.circle_outlined, size: 15, color: isComplete ? Colors.green : Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(requirement.$2, style: TextStyle(fontSize: 12, color: isComplete ? Colors.green.shade700 : Colors.grey.shade600)),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      // In Register Page:
      appBar: const CustomAppbar(title: 'Create Account', subtitle: 'Start your journey'),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFEFF6FF), Colors.white]),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const SizedBox(height: 12),

                      CircleAvatar(
                        radius: 42,
                        backgroundColor: theme.colorScheme.primary,
                        child: Icon(Icons.person_add_alt_1_rounded, size: 40, color: theme.colorScheme.onPrimary),
                      ),

                      const SizedBox(height: 18),

                      Text(
                        'Join Sedy',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF172033)),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Create your account to get started.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                      ),

                      const SizedBox(height: 24),

                      Card(
                        elevation: 0,
                        color: Colors.white.withValues(alpha: 0.94),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Account details',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF172033)),
                              ),

                              const SizedBox(height: 16),

                              TextFormField(
                                controller: txtEmail,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                decoration: InputDecoration(
                                  labelText: 'Email address',
                                  prefixIcon: const Icon(Icons.email_outlined),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                validator: _validateEmail,
                              ),

                              const SizedBox(height: 16),

                              TextFormField(
                                controller: txtPassword,
                                obscureText: _isObscured,
                                textInputAction: TextInputAction.next,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _isObscured ? 'Show password' : 'Hide password',
                                    onPressed: () {
                                      setState(() {
                                        _isObscured = !_isObscured;
                                      });
                                    },
                                    icon: Icon(_isObscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  ),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Enter a password';
                                  }

                                  if (!_hasValidPassword) {
                                    return 'Password does not meet the requirements';
                                  }

                                  return null;
                                },
                              ),

                              const SizedBox(height: 10),

                              _passwordStrengthIndicator(),

                              const SizedBox(height: 16),

                              TextFormField(
                                controller: txtConfirmPassword,
                                obscureText: _isConfirmPasswordObscured,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'Confirm password',
                                  prefixIcon: const Icon(Icons.lock_reset_outlined),
                                  suffixIcon: IconButton(
                                    tooltip: _isConfirmPasswordObscured ? 'Show password' : 'Hide password',
                                    onPressed: () {
                                      setState(() {
                                        _isConfirmPasswordObscured = !_isConfirmPasswordObscured;
                                      });
                                    },
                                    icon: Icon(_isConfirmPasswordObscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  ),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                validator: _validateConfirmPassword,
                              ),

                              const SizedBox(height: 16),

                              _textField(
                                label: 'Username',
                                icon: Icons.person_outline,
                                controller: txtUsername,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                validator: (value) => _requiredValidator(value, 'username'),
                              ),

                              const SizedBox(height: 12),

                              Text(
                                'Business details',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF172033)),
                              ),

                              const SizedBox(height: 12),

                              _textField(
                                label: 'Dealer name',
                                icon: Icons.storefront_outlined,
                                controller: txtDealerName,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                validator: (value) => _requiredValidator(value, 'dealer name'),
                              ),

                              const SizedBox(height: 16),

                              _businessRoleField(),

                              const SizedBox(height: 20),

                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _isLoading ? null : _showRegisterConfirmation,

                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(52),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  child: _isLoading
                                      ? SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.colorScheme.onPrimary),
                                        )
                                      : const Text('Create account'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      Text('Your information is securely stored.', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade500)),
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
