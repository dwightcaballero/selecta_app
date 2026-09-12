import 'package:flutter/material.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/views/pages/others/login_page.dart';
import 'package:flutter_app/views/pages/others/register_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const CustomAppbar(title: '', showBackButton: false),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFEFF6FF), Colors.white]),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    Hero(
                      tag: 'sedy-logo',
                      child: Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.28), blurRadius: 26, offset: const Offset(0, 12)),
                          ],
                        ),
                        child: Icon(Icons.storefront_rounded, size: 56, color: theme.colorScheme.onPrimary),
                      ),
                    ),

                    const SizedBox(height: 28),

                    Text(
                      'Welcome to Sedy',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF172033)),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'Manage your business activities quickly and easily.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey.shade600, height: 1.5),
                    ),

                    const SizedBox(height: 24),

                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _featureChip(icon: Icons.dashboard_outlined, label: 'Dashboard', context: context),
                        _featureChip(icon: Icons.sync_rounded, label: 'Real-time updates', context: context),
                        _featureChip(icon: Icons.security_outlined, label: 'Secure', context: context),
                      ],
                    ),

                    const SizedBox(height: 32),

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
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => Helperfunctions.navigateTo(context, const LoginPage()),
                                icon: const Icon(Icons.login_rounded),
                                label: const Text('Login'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => Helperfunctions.navigateTo(context, const RegisterPage()),
                                icon: const Icon(Icons.person_add_alt_1_rounded),
                                label: const Text('Create an account'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    Text('Secure • Simple • Reliable', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade500, letterSpacing: 0.5)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _featureChip({required IconData icon, required String label, required BuildContext context}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}
