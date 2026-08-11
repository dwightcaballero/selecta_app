import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';

class ResetpasswordPage extends StatefulWidget {
  const ResetpasswordPage({super.key});

  @override
  State<ResetpasswordPage> createState() => _ResetpasswordPageState();
}

class _ResetpasswordPageState extends State<ResetpasswordPage> {
  TextEditingController textEditingControllerEmail = TextEditingController();
  String errormessage = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text('Reset Password'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 100),
              TextField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  hintText: "Email"),
                controller: textEditingControllerEmail,
                onEditingComplete: () => setState(() {}),
              ),
              if (errormessage.isNotEmpty)...[
                SizedBox(height: 10),
                Text('* $errormessage', style: TextStyle(color: Colors.red),),
              ],
              Spacer(),
              FilledButton(
                onPressed: () => resetPassword(),
                style: FilledButton.styleFrom(minimumSize: Size(double.infinity, 40.0)),
                child: Text("Reset Password"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void resetPassword() async {
    String err = validateInput();
    if (err.isEmpty){
      try {
        await authService.value.resetPassword(email: textEditingControllerEmail.text);
        setState(() {
          errormessage = '';
        });
        checkEmail();
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

  void checkEmail(){
    ShowMessage.success(context, 'Please check your email');
  }

  String validateInput(){
    if (textEditingControllerEmail.text.isEmpty) return 'Email should not be blank!';
    return '';
  }
}