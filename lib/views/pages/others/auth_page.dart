import 'package:flutter/material.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/views/pages/home_page.dart';
import 'package:flutter_app/views/pages/others/loading_page.dart';
import 'package:flutter_app/views/pages/others/welcome_page.dart';

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable:  authService,
      builder: (context, authService, child) {
        return  StreamBuilder(
          stream: authService.authStateChanges,
          builder: (BuildContext context, AsyncSnapshot snapshot) {
            Widget widget;
            if (snapshot.connectionState == ConnectionState.waiting){
              widget = LoadingPage();
            }
            else if(snapshot.hasData){
              widget = HomePage();
            }
            else{
              widget = WelcomePage();
            }
            return widget;
          },
        );
      },
    );
  }
}