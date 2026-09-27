import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/models/users.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/user_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Data class holding the result of a successful login operation.
class LoginResult {
  final Users? user;
  final bool isDealer;

  LoginResult({
    required this.user,
    required this.isDealer,
  });
}

/// Controller responsible for sign-in logic, user session initialization,
/// local cache synchronization, and password reset requests.
class LoginController {
  final UserService _userService;

  LoginController({UserService? userService})
      : _userService = userService ?? UserService();

  /// Authenticates user, synchronizes profile data and persists to SharedPreferences.
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim();
    await authService.value.signIn(email: cleanEmail, password: password);

    final record = await _userService.getUserByEmail(cleanEmail);
    if (record != null) {
      await authService.value.updateUsername(username: record.username);

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(record.toJson());
      await prefs.setString('user_data', jsonString);
    }

    final isDealer = record?.role == BusinessRole.dealer;
    return LoginResult(user: record, isDealer: isDealer);
  }

  /// Sends a password reset email to the specified email address.
  Future<void> sendPasswordResetEmail(String email) async {
    await authService.value.resetPassword(email: email.trim());
  }

  /// Maps Firebase authentication exceptions to user-friendly error messages.
  String getFriendlyErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network connection error. Check your internet.';
      default:
        return 'Unable to sign in. Please verify your details.';
    }
  }
}
