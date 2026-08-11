import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/views/pages/others/login_page.dart';
import 'package:flutter_app/views/pages/others/register_page.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('Welcome'),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsetsGeometry.all(20),
            child: Column(
              spacing: 10,
              children: [
                KForms.regularButton('Register', KButtonStyle.normal, () => Helperfunctions.navigateTo(context, RegisterPage())),
                KForms.regularButton('Login', KButtonStyle.normal, () => Helperfunctions.navigateTo(context, LoginPage()))
              ],
            ),
          ),
        ),
      ),
    );
  }
}