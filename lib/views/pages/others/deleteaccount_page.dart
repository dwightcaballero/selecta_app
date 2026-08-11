import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/views/pages/others/auth_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
final _formkey = GlobalKey<FormState>();

class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  TextEditingController textEditingControllerEmail = TextEditingController();
  TextEditingController textEditingControllerPassword = TextEditingController();
  String errormessage = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text('Delete Account'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formkey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  // validator: (value) => value == null || value.isEmpty ? 'Email should not be blank.' : null,
                  validator: (value) {
                    if (value == null || value.isEmpty){
                      return 'Email should not be blank.';
                    }

                    // Regex validation for format
                    final emailRegex = RegExp(r'^\S+@\S+\.\S+$');
                    if (!emailRegex.hasMatch(value)) {
                      return 'Please enter a valid email address.';
                    }

                    return null;
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    hintText: "Email",),
                  controller: textEditingControllerEmail,
                ),
                SizedBox(height: 10,),
                TextFormField(
                  validator: (value) => value == null || value.isEmpty ? 'Password should not be blank.' : null,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    hintText: "Password",),
                  controller: textEditingControllerPassword,
                ),
                if (errormessage.isNotEmpty)...[
                  SizedBox(height: 10),
                  Text('* $errormessage', style: TextStyle(color: Colors.red),),
                ],
                Spacer(),
                FilledButton(
                  onPressed: () => deleteAccount(),
                  style: FilledButton.styleFrom(minimumSize: Size(double.infinity, 40.0)),
                  child: Text("Delete Account"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void deleteAccount() async {
    if (_formkey.currentState!.validate()){
      try {
        await authService.value.deleteAccount(email: textEditingControllerEmail.text, password: textEditingControllerPassword.text);
        showSuccess();
      } on FirebaseAuthException catch (e) {
        setState(() {
          errormessage = e.message ?? 'Something went wrong.';
        });
      }
    }
    else{
      setState(() {
          errormessage = '';
        });
    }
  }

  void showSuccess(){
    ShowMessage.success(context, 'Account deleted successfully!');
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => AuthPage()));
  }
}