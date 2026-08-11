import 'package:flutter/material.dart';

class ShowMessage{
  static void listError(BuildContext context, List<String> listError){
    String errorMessage = '';
    for (var err in listError) {
      errorMessage = '$errorMessage- $err\n'; 
    }

    showDialog(context: context, builder: (context) {
      return AlertDialog(
        title: Text("Error", style: TextStyle(color: Colors.red ),),
        content: Text(errorMessage),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: Text("Close")),
        ],
      );
      },
    ); 

    // log message
  }

  static void error(BuildContext context, String error){
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
        backgroundColor: Colors.redAccent,
      )
    );
  }

  static void success(BuildContext context, String message){
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
        backgroundColor: Colors.blueAccent,
      )
    );

    // log message
  }
}