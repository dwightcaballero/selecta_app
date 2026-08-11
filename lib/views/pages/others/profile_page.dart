import 'package:flutter/material.dart';
import 'package:flutter_app/data/notifiers.dart';
import 'package:flutter_app/views/pages/others/welcome_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 75,
            backgroundImage: AssetImage('assets/images/logo.png'),
          ),
          FilledButton(
            onPressed: () {
              selectedPageNotifier.value = 0;
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => WelcomePage()));
            }, 
            child: Text("Logout"))
        ],
      ),
    );
  }
}