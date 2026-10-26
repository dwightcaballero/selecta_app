import 'package:flutter/material.dart';
import 'package:selecta_ops/services/store_auth_service.dart';
import 'package:selecta_ops/views/pages/store/store_change_password_page.dart';
import 'package:selecta_ops/views/pages/store/store_shell.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';

/// Store Owner Login Page for self-ordering portal.
/// Accepts unique store username + password. Handles 5-attempt/15-min lockout
/// and routes to forced password change if first-time login.
class StoreLoginPage extends StatefulWidget {
  const StoreLoginPage({super.key});

  @override
  State<StoreLoginPage> createState() => _StoreLoginPageState();
}

class _StoreLoginPageState extends State<StoreLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true);

    try {
      final username = _usernameController.text.trim().toLowerCase();
      final password = _passwordController.text;

      final result = await StoreAuthService().storeLogin(
        username: username,
        password: password,
      );

      if (!mounted) return;

      ShowMessage.success(context, 'Welcome back, ${result.userProfile.storeName.isNotEmpty ? result.userProfile.storeName : username}!');

      if (result.mustChangePassword) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const StoreChangePasswordPage(isForced: true),
          ),
          (route) => false,
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const StoreShell()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString().replaceAll('Exception: ', '').replaceAll('FormatException: ', '');
        ShowMessage.error(context, message);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Portal'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand / Logo Icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.storefront_rounded, size: 44, color: colorScheme.primary),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      'Hapi Store Ordering',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in with your store username to place orders with your dealer',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13.5),
                    ),
                    const SizedBox(height: 28),

                    // Inputs Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _usernameController,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.username],
                            decoration: InputDecoration(
                              labelText: 'Store Username',
                              prefixIcon: const Icon(Icons.alternate_email_rounded),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              hintText: 'e.g. storename',
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Enter your store username';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => _login(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              ),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'Enter your password';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          AsyncFilledButton(
                            onPressed: _isLoading ? null : _login,
                            loadingLabel: 'Signing In...',
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Sign In as Store', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Return to staff login
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Dealer or Salesman?', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Staff Sign In', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
    );
  }
}
