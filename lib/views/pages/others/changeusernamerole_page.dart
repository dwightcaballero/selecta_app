import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/views/pages/others/auth_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChangeusernameRolePage extends StatefulWidget {
  const ChangeusernameRolePage({super.key});

  @override
  State<ChangeusernameRolePage> createState() => _ChangeusernameRolePageState();
}

class _ChangeusernameRolePageState extends State<ChangeusernameRolePage> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedRole;
  TextEditingController textEditingControllerUsername = TextEditingController();
  String errormessage = '';

  List<DropdownMenuItem<String>> listRole = [
    DropdownMenuItem(value: BusinessRole.dealer, child: Text(BusinessRole.dealer)),
    DropdownMenuItem(value: BusinessRole.salesman, child: Text(BusinessRole.salesman)),
  ];

  Future<void> _getRole() async {
    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    var role = await asyncPrefs.getString(SharedPrefKeys.role);
    
    setState(() {
      _selectedRole = role;
    });
  }

  @override
  void initState() {
    super.initState();
    _getRole();
    textEditingControllerUsername.text = authService.value.currentUser!.displayName ?? '';
  }
  
  @override
  void dispose() {
    super.dispose();
    textEditingControllerUsername.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text('Change Username and Role'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  validator: (value) => value == null || value.isEmpty ? 'Username should not be blank.' : null,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
                    hintText: "Username",),
                  controller: textEditingControllerUsername,
                ),
                SizedBox(height: 10,),
                DropdownButtonFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  borderRadius: BorderRadius.circular(10),
                  items: listRole, 
                  initialValue: _selectedRole,
                  hint: Text('Select a Role'),
                  decoration: InputDecoration(border: OutlineInputBorder()),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedRole = newValue;
                    });
                  },
                  validator: (value) => value == null || value.isEmpty ? 'Please select a role.' : null,
                  onSaved: (value) {
                    _selectedRole = value;
                  },
                ),
                if (errormessage.isNotEmpty)...[
                  SizedBox(height: 10),
                  Text('* $errormessage', style: TextStyle(color: Colors.red),),
                ],
                SizedBox(height: 10,),
                FilledButton(
                  onPressed: () => changeUsername(),
                  style: FilledButton.styleFrom(minimumSize: Size(double.infinity, 40.0)),
                  child: Text("Submit"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void changeUsername() async {
    if (_formKey.currentState!.validate()){
      try {
        await authService.value.updateUsername(username: textEditingControllerUsername.text);

        final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
        await asyncPrefs.setString(SharedPrefKeys.role, _selectedRole!);

        await authService.value.signOut();
        showSuccess();
      } on FirebaseAuthException catch (e) {
        setState(() {
          errormessage = e.message ?? 'Something went wrong.';
        });
      }
    }
  }

  void showSuccess(){
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => AuthPage()));
    ShowMessage.success(context, 'Username and role changed successfully!');
  }
}