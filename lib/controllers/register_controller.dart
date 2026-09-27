import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/users.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/dealer_service.dart';
import 'package:flutter_app/services/user_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Password requirement compliance status and strength progress.
class PasswordRequirementStatus {
  final bool hasMinLength;
  final bool hasUppercase;
  final bool hasLowercase;
  final bool hasNumber;

  PasswordRequirementStatus({
    required this.hasMinLength,
    required this.hasUppercase,
    required this.hasLowercase,
    required this.hasNumber,
  });

  bool get isValid => hasMinLength && hasUppercase && hasLowercase && hasNumber;

  int get completedCount =>
      (hasMinLength ? 1 : 0) +
      (hasUppercase ? 1 : 0) +
      (hasLowercase ? 1 : 0) +
      (hasNumber ? 1 : 0);

  double get progress => completedCount / 4.0;
}

/// Controller managing user account registration, dealer validation,
/// user record persistence, audit trail creation, and input validations.
class RegisterController {
  final UserService _userService;
  final DealerService _dealerService;

  RegisterController({
    UserService? userService,
    DealerService? dealerService,
  })  : _userService = userService ?? UserService(),
        _dealerService = dealerService ?? DealerService();

  /// Evaluates password requirement rules
  PasswordRequirementStatus evaluatePassword(String password) {
    return PasswordRequirementStatus(
      hasMinLength: password.length >= 8,
      hasUppercase: password.contains(RegExp(r'[A-Z]')),
      hasLowercase: password.contains(RegExp(r'[a-z]')),
      hasNumber: password.contains(RegExp(r'[0-9]')),
    );
  }

  /// Validates email format
  String? validateEmail(String? value) {
    final email = value?.trim() ?? '';
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    if (email.isEmpty) return 'Enter your email address';
    if (!emailPattern.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  /// Registers a new user account with dealer verification, audit log, and local caching
  Future<void> register({
    required String email,
    required String password,
    required String username,
    required String dealerName,
    required String role,
  }) async {
    final cleanEmail = email.trim();
    final cleanUsername = username.trim();
    final cleanDealerName = dealerName.trim();

    final existingDealer = await _dealerService.getDealerByName(cleanDealerName);
    if (existingDealer == null) {
      throw const FormatException('Dealer name does not exist. Please contact your administrator.');
    }

    await authService.value.createAccount(email: cleanEmail, password: password);
    await authService.value.signIn(email: cleanEmail, password: password);

    final newRecord = Users(
      email: cleanEmail,
      username: cleanUsername,
      role: role,
      dealerName: cleanDealerName,
    );

    _userService.addUser(newRecord);
    await Helperfunctions.logCreate(cleanUsername, newRecord.toJson(), page: AppPages.register);

    await authService.value.updateUsername(username: cleanUsername);
    await authService.value.signOut();
    await authService.value.signIn(email: cleanEmail, password: password);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', jsonEncode(newRecord.toJson()));

    await authService.value.signOut();
  }

  /// Maps Firebase authentication exceptions to user-friendly error messages
  String getFriendlyErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'This email is already registered. Please log in.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Please use a stronger password.';
      case 'network-request-failed':
        return 'Network connection issue. Please check your internet connection.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return error.message ?? 'Unable to create account. Please try again.';
    }
  }
}
