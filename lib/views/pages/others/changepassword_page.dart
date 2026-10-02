import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/account_settings_controller.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';

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
  String errormessage = '';

  @override
  void dispose() {
    textEditingControllerEmail.dispose();
    textEditingControllerOldPassword.dispose();
    textEditingControllerNewPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('Change Password'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  hintText: "Email",
                ),
                controller: textEditingControllerEmail,
                onEditingComplete: () => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  hintText: "Old Password",
                ),
                controller: textEditingControllerOldPassword,
                onEditingComplete: () => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  hintText: "New Password",
                ),
                controller: textEditingControllerNewPassword,
                onEditingComplete: () => setState(() {}),
              ),
              if (errormessage.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('* $errormessage', style: const TextStyle(color: Colors.red)),
              ],
              const Spacer(),
              FilledButton(
                onPressed: changePassword,
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 40.0)),
                child: const Text("Change Password"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Validates inputs and triggers password change via controller
  void changePassword() async {
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