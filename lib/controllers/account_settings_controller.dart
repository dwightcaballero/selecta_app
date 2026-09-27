import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controller handling account management operations including password resets,
/// password changes, username/role updates, and account deletion.
class AccountSettingsController {
  /// Sends a password reset email.
  Future<void> resetPassword(String email) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      throw ArgumentError('Email should not be blank!');
    }
    await authService.value.resetPassword(email: cleanEmail);
  }

  /// Changes the user's password using their current password for re-authentication.
  Future<void> changePassword({
    required String email,
    required String oldPassword,
    required String newPassword,
  }) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) throw ArgumentError('Email should not be blank!');
    if (oldPassword.isEmpty) throw ArgumentError('Old password should not be blank!');
    if (newPassword.isEmpty) throw ArgumentError('New password should not be blank!');

    await authService.value.resetPasswordFromCurrentPassword(
      email: cleanEmail,
      currentPassword: oldPassword,
      newPassword: newPassword,
    );
  }

  /// Fetches the currently stored role from SharedPreferences.
  Future<String?> getStoredRole() async {
    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    return await asyncPrefs.getString(SharedPrefKeys.role);
  }

  /// Returns the current authenticated user's display name.
  String getCurrentUsername() {
    return authService.value.currentUser?.displayName ?? '';
  }

  /// Updates username and role, then signs out to force re-authentication.
  Future<void> updateUsernameAndRole({
    required String username,
    required String role,
  }) async {
    final cleanUsername = username.trim();
    if (cleanUsername.isEmpty) throw ArgumentError('Username should not be blank.');
    if (role.isEmpty) throw ArgumentError('Please select a role.');

    await authService.value.updateUsername(username: cleanUsername);

    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.setString(SharedPrefKeys.role, role);

    await authService.value.signOut();
  }

  /// Validates email format for account management forms.
  String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email should not be blank.';
    }
    final emailRegex = RegExp(r'^\S+@\S+\.\S+$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email address.';
    }
    return null;
  }

  /// Deletes the user account permanently.
  Future<void> deleteAccount({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) throw ArgumentError('Email should not be blank.');
    if (password.isEmpty) throw ArgumentError('Password should not be blank.');

    await authService.value.deleteAccount(email: cleanEmail, password: password);
  }

  /// Translates FirebaseAuthException into user-friendly message.
  String getFriendlyErrorMessage(FirebaseAuthException error) {
    return error.message ?? 'Something went wrong.';
  }
}
