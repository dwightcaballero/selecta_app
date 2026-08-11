import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  TextEditingController textEditingControllerEmail = TextEditingController();
  TextEditingController textEditingControllerOldPassword = TextEditingController();
  TextEditingController textEditingControllerNewPassword = TextEditingController();
  String errormessage = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text('Change Password'),
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
                  hintText: "Email"),
                controller: textEditingControllerEmail,
                onEditingComplete: () => setState(() {}),
              ),

              SizedBox(height: 10),
              TextField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  hintText: "Old Password"),
                controller: textEditingControllerOldPassword,
                onEditingComplete: () => setState(() {}),
              ),

              SizedBox(height: 10),
              TextField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  hintText: "New Password"),
                controller: textEditingControllerNewPassword,
                onEditingComplete: () => setState(() {}),
              ),

              if (errormessage.isNotEmpty)...[
                SizedBox(height: 10),
                Text('* $errormessage', style: TextStyle(color: Colors.red),),
              ],
              Spacer(),
              FilledButton(
                onPressed: () => changePassword(),
                style: FilledButton.styleFrom(minimumSize: Size(double.infinity, 40.0)),
                child: Text("Change Password"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void changePassword() async {
    String err = validateInput();
    if (err.isEmpty){
      try {
        await authService.value.resetPasswordFromCurrentPassword(
          email: textEditingControllerEmail.text, 
          currentPassword: textEditingControllerOldPassword.text, 
          newPassword: textEditingControllerNewPassword.text);
        showSuccess();
      } on FirebaseAuthException catch (e) {
        setState(() {
          errormessage = e.message ?? 'Something went wrong.';
        });
      }
    }
    else{
      setState(() {
        errormessage = err;
      });
    }
    
  }

  void showSuccess(){
    Navigator.pop(context);
    ShowMessage.success(context, 'Password changed successfully!');
  }

  String validateInput(){
    if (textEditingControllerEmail.text.isEmpty) return 'Email should not be blank!';
    if (textEditingControllerOldPassword.text.isEmpty) return 'Old password should not be blank!';
    if (textEditingControllerNewPassword.text.isEmpty) return 'New password should not be blank!';
    return '';
  }
}