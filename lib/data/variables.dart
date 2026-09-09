import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/models/users.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KVariables {
  static Future<bool> getIsDealer() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // 1. Read the JSON string
    String? jsonString = prefs.getString('user_data');

    if (jsonString == null) {
      return false; // No data saved yet
    }

    // 2. Decode the string to a Map
    Map<String, dynamic> userMap = jsonDecode(jsonString) as Map<String, dynamic>;

    // 3. Convert Map back into the UserModel object
    var user = Users.fromJson(userMap);
    return user.role == BusinessRole.dealer ? true : false;
  }

  static Future<Users?> getUser() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // 1. Read the JSON string
    String? jsonString = prefs.getString('user_data');

    if (jsonString == null) {
      return null; // No data saved yet
    }

    // 2. Decode the string to a Map
    Map<String, dynamic> userMap = jsonDecode(jsonString) as Map<String, dynamic>;

    // 3. Convert Map back into the UserModel object
    return Users.fromJson(userMap);
  }

  static final formkey = GlobalKey<FormState>();
}
