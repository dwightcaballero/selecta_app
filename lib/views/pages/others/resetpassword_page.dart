import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/account_settings_controller.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';

/// Presentation page for submitting a password reset request via email.
class ResetpasswordPage extends StatefulWidget {
  const ResetpasswordPage({super.key});

  @override
  State<ResetpasswordPage> createState() => _ResetpasswordPageState();
}

class _ResetpasswordPageState extends State<ResetpasswordPage> {
  final AccountSettingsController _controller = AccountSettingsController();
  final TextEditingController textEditingControllerEmail = TextEditingController();
  String errormessage = '';

  @override
  void dispose() {
    textEditingControllerEmail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.blue, title: const Text('Reset Password')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 100),
              TextField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  hintText: "Email",
                ),
                controller: textEditingControllerEmail,
                onEditingComplete: () => setState(() {}),
              ),
              if (errormessage.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('* $errormessage', style: const TextStyle(color: Colors.red)),
              ],
              const Spacer(),
              FilledButton(
                onPressed: resetPassword,
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 40.0)),
                child: const Text("Reset Password"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Initiates password reset request via controller
  void resetPassword() async {
    final email = textEditingControllerEmail.text.trim();
    if (email.isEmpty) {
      setState(() {
        errormessage = 'Email should not be blank!';
      });
      return;
    }

    try {
      await _controller.resetPassword(email);
      setState(() {
        errormessage = '';
      });
      if (mounted) {
        ShowMessage.success(context, 'Please check your email');
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
}
