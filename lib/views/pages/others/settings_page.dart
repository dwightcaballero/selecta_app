import 'package:flutter/material.dart';
import 'package:flutter_app/views/pages/others/changepassword_page.dart';
import 'package:flutter_app/views/pages/others/changeusernamerole_page.dart';
import 'package:flutter_app/views/pages/others/deleteaccount_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text('Settings'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChangeusernameRolePage())),
                child: Text("Change Username")),
              FilledButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChangePasswordPage())),
                child: Text("Change Password")),
              FilledButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => DeleteAccountPage())),
                child: Text("Delete Account"))
            ]
          ),
        ),
      ),
    );
  }
}