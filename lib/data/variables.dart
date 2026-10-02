import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/user_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KVariables {
  static Future<bool> getIsDealer() async {
    final user = await getUser();
    return user?.role == BusinessRole.dealer;
  }

  static Future<Users?> getUser() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // 1. Read from SharedPreferences
    String? jsonString = prefs.getString('user_data');
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        Map<String, dynamic> userMap = jsonDecode(jsonString) as Map<String, dynamic>;
        return Users.fromJson(userMap);
      } catch (_) {}
    }

    // 2. Fallback: Query Firestore if not cached locally
    final currentEmail = FirebaseAuth.instance.currentUser?.email;
    if (currentEmail != null && currentEmail.isNotEmpty) {
      try {
        final db = UserService();
        final user = await db.getUserByEmail(currentEmail);
        if (user != null) {
          await prefs.setString('user_data', jsonEncode(user.toJson()));
          return user;
        }
      } catch (_) {}
    }

    return null;
  }

  static final formkey = GlobalKey<FormState>();

  static DateTime firstDayOfTheMonth() {
    DateTime now = DateTime.now();
    // Gets the 1st day of the current month at 12:00 AM (00:00:00)
    DateTime firstDayOfMonth = DateTime(now.year, now.month, 1);
    return firstDayOfMonth;
  }

  static DateTime lastDayOfTheMonth() {
    final now = DateTime.now();
    final lastMomentOfMonth = DateTime(
      now.year,
      now.month + 1,
      0, // Rolls back to the last day of the target month
      23, // Hour
      59, // Minute
      59, // Second
      999, // Millisecond
    );
    return lastMomentOfMonth;
  }
}
