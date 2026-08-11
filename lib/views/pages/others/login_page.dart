import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/user_services.dart';
import 'package:flutter_app/views/pages/home_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  TextEditingController txtEmail = TextEditingController();
  TextEditingController txtPassword = TextEditingController();
  bool _isObscured = true;
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Login'),
      body: isLoading
      ? KForms.loadingScreen
      : Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  KForms.txtFormEmail('Email', txtEmail),
                  KForms.txtFormPassword('Password', txtPassword, _isObscured, () => setState(() {_isObscured = !_isObscured;})),
                  KForms.regularButton('Login', KButtonStyle.normal, onSignIn)
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void onSignIn() async {
    if (_formKey.currentState!.validate()){
      setState(() => isLoading = true);
      try {
        // sign in with user credentials
        await authService.value.signIn(email: txtEmail.text, password: txtPassword.text);

        // update username based on credentials
        UserService db = UserService();
        var record = await db.getUserByEmail(txtEmail.text);
        if (record != null) {
          await authService.value.updateUsername(username: '[${record.role}] ${record.username}');

          // save the user role in shared preferences cache
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setBool('isDealer', record.role == BusinessRole.dealer? true : false );
        }

        if (mounted){
          ShowMessage.success(context, 'Successfully logged in!');
          Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const HomePage()),(Route<dynamic> route) => false,); // This removes all previous routes
        }
      } on FirebaseAuthException catch (e) {
        if (mounted) ShowMessage.error(context, e.message ?? 'Login: No message from FirebaseAuthException');
      }
      
      setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    super.dispose();
    txtEmail.dispose();
    txtPassword.dispose();
  }
}