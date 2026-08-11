import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/users.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/user_services.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  TextEditingController txtEmail = TextEditingController();
  TextEditingController txtPassword = TextEditingController();
  TextEditingController txtUsername = TextEditingController();
  TextEditingController dropdowncontroller = TextEditingController();
  List<DropdownMenuEntry<String>> dropdownItems = [];
  UserService db = UserService();
  final _formKey = KVariables.formkey;
  bool _isLoading = false;
  bool _isObscured = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Register'),
      body: _isLoading
      ? KForms.loadingScreen
      : Center(
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                spacing: 10,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KForms.txtFormEmail('Email', txtEmail),
                  KForms.txtFormPassword('Password', txtPassword, _isObscured, () => setState(() {_isObscured = !_isObscured;})),
                  KForms.txtFormString('Username', txtUsername),
                  KForms.dropdown('Role', dropdownItems, dropdowncontroller),
                  KForms.regularButton('Register', KButtonStyle.save, () => KForms.alertDialogConfirm(ConfirmTitle.save, ConfirmMessage.save, context, onRegister))
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void onRegister() async {
    if (_formKey.currentState!.validate()){
      setState(() => _isLoading = true);

      try {
        // create auth record
        await authService.value.createAccount(email: txtEmail.text, password: txtPassword.text);

        // sign in with user credentials
        await authService.value.signIn(email: txtEmail.text, password: txtPassword.text);

        // create user record
        Users newRecord = Users(
          email: txtEmail.text,
          username: txtUsername.text,  
          role: dropdowncontroller.text,
          createdBy: '',
          lastUpdatedBy: '', 
          createdDate: Timestamp.now(), 
          lastupdatedDate: Timestamp.now());
        db.addUser(newRecord);

        // update username based on credentials
        await authService.value.updateUsername(username: '[${dropdowncontroller.text}] ${txtUsername.text}');

        // sign out and sign in again in order for the username to be updated
        await authService.value.signOut();
        await authService.value.signIn(email: txtEmail.text, password: txtPassword.text);

        // save the user role in shared preferences cache
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isDealer', dropdowncontroller.text == BusinessRole.dealer? true : false );

      } on FirebaseAuthException catch (e) {
        if (mounted) ShowMessage.error(context, e.message?? 'There was an error upon creating an account');
        setState(() => _isLoading = false);
        return;
      }

      if (mounted){
        Navigator.pop(context); // go back to previous page
        ShowMessage.success(context, "Successfully created an account [${txtUsername.text}]");
      }
    }
    else{
      ShowMessage.error(context, 'Please fill up the required fields');
    }
  }

  @override void initState() {
    super.initState();

    dropdownItems.add(DropdownMenuEntry(value: BusinessRole.dealer, label: BusinessRole.dealer));
    dropdownItems.add(DropdownMenuEntry(value: BusinessRole.salesman, label: BusinessRole.salesman));
  }

  @override
  void dispose() {
    txtEmail.dispose();
    txtPassword.dispose();
    txtUsername.dispose();
    dropdowncontroller.dispose();
    super.dispose();
  }

}