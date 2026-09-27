import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/controllers/account_settings_controller.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/views/pages/others/auth_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';

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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('Change Username and Role'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  validator: (value) => value == null || value.trim().isEmpty ? 'Username should not be blank.' : null,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
                    hintText: "Username",
                  ),
                  controller: textEditingControllerUsername,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  borderRadius: BorderRadius.circular(10),
                  items: listRole,
                  initialValue: _selectedRole,
                  hint: const Text('Select a Role'),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
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
                  const SizedBox(height: 10),
                  Text('* $errormessage', style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: changeUsername,
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 40.0)),
                  child: const Text("Submit"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Triggers username and role update through controller
  void changeUsername() async {
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