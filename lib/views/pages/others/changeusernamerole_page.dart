import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/account_settings_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/views/pages/others/auth_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';

import 'package:selecta_ops/views/widgets/appbar_widget.dart';

/// Presentation page allowing users to update their display username and role.
class ChangeusernameRolePage extends StatefulWidget {
  const ChangeusernameRolePage({super.key});

  @override
  State<ChangeusernameRolePage> createState() => _ChangeusernameRolePageState();
}

class _ChangeusernameRolePageState extends State<ChangeusernameRolePage> {
  final AccountSettingsController _controller = AccountSettingsController();
  final _formKey = GlobalKey<FormState>();

  String? _selectedRole;
  final TextEditingController textEditingControllerUsername = TextEditingController();
  String errormessage = '';

  final List<DropdownMenuItem<String>> listRole = const [
    DropdownMenuItem(value: BusinessRole.dealer, child: Text(BusinessRole.dealer)),
    DropdownMenuItem(value: BusinessRole.salesman, child: Text(BusinessRole.salesman)),
  ];

  Future<void> _loadRole() async {
    final role = await _controller.getStoredRole();
    if (mounted) {
      setState(() {
        _selectedRole = role;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRole();
    textEditingControllerUsername.text = _controller.getCurrentUsername();
  }

  @override
  void dispose() {
    textEditingControllerUsername.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: const CustomAppbar(
        title: 'Change Username & Role',
        subtitle: 'Profile & Access Management',
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
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.manage_accounts_rounded, color: colorScheme.primary, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'User Identification',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Update your operational handle and access permission tier.',
                                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        validator: (value) => value == null || value.trim().isEmpty ? 'Username should not be blank.' : null,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration: InputDecoration(
                          labelText: 'Display Username',
                          hintText: 'Enter username',
                          prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        controller: textEditingControllerUsername,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        borderRadius: BorderRadius.circular(12),
                        items: listRole,
                        initialValue: _selectedRole,
                        hint: const Text('Select a Role'),
                        decoration: InputDecoration(
                          labelText: 'Operational Role',
                          prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedRole = newValue;
                          });
                        },
                        validator: (value) => value == null || value.isEmpty ? 'Please select a role.' : null,
                        onSaved: (value) {
                          _selectedRole = value;
                        },
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
                        onPressed: changeUsername,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Save Profile Changes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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

  /// Triggers username and role update through controller
  Future<void> changeUsername() async {
    if (_formKey.currentState?.validate() ?? false) {
      try {
        await _controller.updateUsernameAndRole(
          username: textEditingControllerUsername.text,
          role: _selectedRole ?? '',
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
    }
  }

  void showSuccess() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AuthPage()));
    ShowMessage.success(context, 'Username and role changed successfully!');
  }
}