import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/services/auth_service.dart';

/// Controller responsible for managing user authentication state streams
/// and determining role-based routing destinations.
class AuthController {
  /// Stream providing live updates on Firebase authentication state changes.
  Stream<User?> get authStateChanges => authService.value.authStateChanges;

  /// Checks whether the currently logged-in user is a Dealer or a Salesman.
  Future<bool> checkIsDealer() async {
    return await KVariables.getIsDealer();
  }
}
