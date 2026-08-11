import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KVariables{
  static Future<bool> getIsDealer() async { 
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isDealer') ?? false;
  }

  static final formkey = GlobalKey<FormState>();
}