import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/account_settings_controller.dart';
import 'package:selecta_ops/views/pages/others/auth_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';

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
  String errormessage = '';

  @override
  void dispose() {
    textEditingControllerEmail.dispose();
    textEditingControllerPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('Delete Account'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: _controller.validateEmail,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    hintText: "Email",
                  ),
                  controller: textEditingControllerEmail,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  validator: (value) => value == null || value.isEmpty ? 'Password should not be blank.' : null,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  obscureText: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    hintText: "Password",
                  ),
                  controller: textEditingControllerPassword,
                ),
                if (errormessage.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('* $errormessage', style: const TextStyle(color: Colors.red)),
                ],
                const Spacer(),
                FilledButton(
                  onPressed: deleteAccount,
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 40.0)),
                  child: const Text("Delete Account"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Validates form and initiates account deletion via controller
  void deleteAccount() async {
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