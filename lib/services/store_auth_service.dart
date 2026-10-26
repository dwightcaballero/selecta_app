// ignore_for_file: constant_identifier_names

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/auth_service.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/services/user_services.dart';

const String STORE_USERNAMES_COLLECTION = 'store_usernames';
const String STORE_LOGIN_ATTEMPTS_COLLECTION = 'store_login_attempts';
const int MAX_FAILED_LOGIN_ATTEMPTS = 5;
const Duration LOCKOUT_DURATION = Duration(minutes: 15);

class StoreAuthResult {
  final User? user;
  final Users userProfile;
  final bool mustChangePassword;

  const StoreAuthResult({required this.user, required this.userProfile, required this.mustChangePassword});
}

class StoreAccountCreationResult {
  final Users user;
  final String temporaryPassword;
  final String uid;

  const StoreAccountCreationResult({required this.user, required this.temporaryPassword, required this.uid});
}

class StoreAuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final UserService _userService;
  final FirebaseFunctions _functions;

  StoreAuthService({FirebaseAuth? auth, FirebaseFirestore? firestore, UserService? userService, FirebaseFunctions? functions})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance,
      _userService = userService ?? UserService(),
      _functions = functions ?? FirebaseFunctions.instance;

  /// Validates a username according to Phase 1.3 rules:
  /// Lowercase letters, digits, '.', '_', '-', between 4 and 20 characters.
  static String? validateUsername(String? username) {
    if (username == null || username.trim().isEmpty) {
      return 'Username is required.';
    }
    final clean = username.trim().toLowerCase();
    if (clean.length < 4 || clean.length > 20) {
      return 'Username must be between 4 and 20 characters.';
    }
    final regex = RegExp(r'^[a-z0-9._-]+$');
    if (!regex.hasMatch(clean)) {
      return 'Username may only contain lowercase letters, numbers, and . _ -';
    }
    return null;
  }

  /// Synthesizes email format for store accounts
  static String syntheticEmail(String username) {
    return '${username.trim().toLowerCase()}@store.selecta.invalid';
  }

  /// Checks if a username is available in the store_usernames collection
  Future<bool> isUsernameAvailable(String username) async {
    final cleanUsername = username.trim().toLowerCase();
    final doc = await _firestore.collection(STORE_USERNAMES_COLLECTION).doc(cleanUsername).get();
    return !doc.exists;
  }

  /// Creates a real store user account
  Future<StoreAccountCreationResult> createStoreAccount({
    required String storeId,
    required String storeName,
    required String username,
    required String dealerName,
    String? defaultPassword,
  }) async {
    final cleanUsername = username.trim().toLowerCase();
    final error = validateUsername(cleanUsername);
    if (error != null) {
      throw FormatException(error);
    }

    final email = syntheticEmail(cleanUsername);
    final password = defaultPassword ?? 'Selecta#${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}!';

    // Account provisioning runs server-side (Admin SDK) so the dealer's own
    // session is never replaced by the newly created store user.
    final String uid;
    try {
      final response = await _functions.httpsCallable('createStoreAccount').call<dynamic>({
        'storeId': storeId,
        'storeName': storeName,
        'dealerName': dealerName,
        'username': cleanUsername,
        'tempPassword': password,
      });
      uid = (response.data as Map?)?['uid'] as String? ?? '';
    } on FirebaseFunctionsException catch (e) {
      throw FormatException(_functionErrorMessage(e, 'createStoreAccount'));
    }

    final storeUserProfile = Users(
      username: cleanUsername,
      role: BusinessRole.hapiStore,
      email: email,
      dealerName: dealerName,
      storeId: storeId,
      storeName: storeName,
      mustChangePassword: true,
    );

    await Helperfunctions.logCreate(cleanUsername, storeUserProfile.toJson(), page: AppPages.hapiStore);

    return StoreAccountCreationResult(user: storeUserProfile, temporaryPassword: password, uid: uid);
  }

  /// Store login with username and password
  Future<StoreAuthResult> storeLogin({required String username, required String password}) async {
    final cleanUsername = username.trim().toLowerCase();

    // 1. Check lockout status
    final attemptRef = _firestore.collection(STORE_LOGIN_ATTEMPTS_COLLECTION).doc(cleanUsername);
    final attemptDoc = await attemptRef.get();

    if (attemptDoc.exists) {
      final data = attemptDoc.data() ?? {};
      final failedCount = (data['failedAttempts'] as num?)?.toInt() ?? 0;
      final lastFailedAt = (data['lastFailedAt'] as Timestamp?)?.toDate();

      if (failedCount >= MAX_FAILED_LOGIN_ATTEMPTS && lastFailedAt != null) {
        final elapsed = DateTime.now().difference(lastFailedAt);
        if (elapsed < LOCKOUT_DURATION) {
          final minutesLeft = (LOCKOUT_DURATION.inMinutes - elapsed.inMinutes).clamp(1, 15);
          throw FormatException('Account is temporarily locked due to too many failed attempts. Please try again in $minutesLeft minute(s).');
        } else {
          // Lockout expired, reset attempts
          await attemptRef.delete();
        }
      }
    }

    // 2. Resolve username -> storeId
    final usernameDoc = await _firestore.collection(STORE_USERNAMES_COLLECTION).doc(cleanUsername).get();
    if (!usernameDoc.exists) {
      await _recordFailedAttempt(attemptRef);
      throw const FormatException('Invalid username or password.');
    }

    final storeId = usernameDoc.data()?['storeId'] as String?;
    if (storeId == null || storeId.isEmpty) {
      await _recordFailedAttempt(attemptRef);
      throw const FormatException('Invalid username or password.');
    }

    // 3. Confirm store has orderingEnabled == true
    final storeDoc = await _firestore.collection(HAPISTORE_COLLECTION_REF).doc(storeId).get();
    if (!storeDoc.exists) {
      await _recordFailedAttempt(attemptRef);
      throw const FormatException('Invalid username or password.');
    }

    final orderingEnabled = (storeDoc.data()?['orderingEnabled'] as bool?) ?? true;
    if (!orderingEnabled) {
      throw const FormatException('Online ordering access for this store has been deactivated. Please contact your dealer.');
    }

    // 4. Authenticate using synthetic email
    final email = syntheticEmail(cleanUsername);
    UserCredential userCredential;
    try {
      userCredential = await authService.value.signIn(email: email, password: password);
    } catch (e) {
      await _recordFailedAttempt(attemptRef);
      throw const FormatException('Invalid username or password.');
    }

    // 5. Success: clear failed attempts
    try {
      await attemptRef.delete();
    } catch (_) {}

    final user = userCredential.user;
    final uid = user?.uid ?? '';

    // 6. Fetch user profile
    var profile = await _userService.getUserByUid(uid);
    profile ??= await _userService.getUserByEmail(email);

    if (profile == null) {
      throw const FormatException('Account profile could not be loaded. Please contact your dealer.');
    }

    return StoreAuthResult(user: user, userProfile: profile, mustChangePassword: profile.mustChangePassword);
  }

  /// Records a failed login attempt for lockout tracking
  Future<void> _recordFailedAttempt(DocumentReference attemptRef) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(attemptRef);
        final currentCount = doc.exists ? ((doc.data() as Map?)?['failedAttempts'] as num? ?? 0).toInt() : 0;
        final newCount = currentCount + 1;
        transaction.set(attemptRef, {'failedAttempts': newCount, 'lastFailedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      });
    } catch (_) {}
  }

  /// Store changes their own password
  Future<void> storeChangePassword({required String currentPassword, required String newPassword}) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw const FormatException('No authenticated session found.');
    }

    if (newPassword.trim().length < 8) {
      throw const FormatException('Password must be at least 8 characters long.');
    }

    // Re-authenticate and update password
    await authService.value.resetPasswordFromCurrentPassword(email: user.email!, currentPassword: currentPassword, newPassword: newPassword);

    // Clear mustChangePassword flag in users document
    await _firestore.collection(USERS_COLLECTION_REF).doc(user.uid).update({'mustChangePassword': false});
  }

  /// Dealer/Admin resets a store's password
  Future<String> resetStorePassword({
    required String storeId,
    required String storeName,
    required String username,
    String? customTemporaryPassword,
  }) async {
    final tempPassword = customTemporaryPassword ?? 'Selecta#${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}!';
    final email = syntheticEmail(username);

    // Prefer the uid linked on the store document; fall back to the synthetic email.
    String? storeUserUid;
    try {
      final storeDoc = await _firestore.collection(HAPISTORE_COLLECTION_REF).doc(storeId).get();
      final linked = storeDoc.data()?['storeUserUid'] as String?;
      if (linked != null && linked.isNotEmpty) storeUserUid = linked;
    } catch (_) {}

    if (storeUserUid == null) {
      final query = await _firestore.collection(USERS_COLLECTION_REF).where('email', isEqualTo: email).limit(1).get();
      if (query.docs.isEmpty) {
        throw const FormatException('User profile for this store not found.');
      }
      storeUserUid = query.docs.first.id;
    }

    // The password must be changed server-side (Admin SDK) so the temporary
    // password shown to the dealer actually works at login. The function also
    // sets mustChangePassword on the user document.
    try {
      await _functions.httpsCallable('resetStorePassword').call<dynamic>({
        'storeUserUid': storeUserUid,
        'newTempPassword': tempPassword,
      });
    } on FirebaseFunctionsException catch (e) {
      throw FormatException(_functionErrorMessage(e, 'resetStorePassword'));
    }

    // Reset failed login attempt lockout
    try {
      await _firestore.collection(STORE_LOGIN_ATTEMPTS_COLLECTION).doc(username.trim().toLowerCase()).delete();
    } catch (_) {}

    // Audit-log reset
    final dealer = _auth.currentUser?.displayName ?? 'Dealer';
    await Helperfunctions.logUpdate(
      username,
      {'mustChangePassword': false},
      {'mustChangePassword': true, 'action': 'resetStorePassword', 'storeId': storeId, 'resetBy': dealer},
      page: AppPages.hapiStore,
    );

    return tempPassword;
  }

  String _functionErrorMessage(FirebaseFunctionsException e, String functionName) {
    if (e.code == 'not-found') {
      return 'The "$functionName" cloud function is not deployed. Deploy it with: firebase deploy --only functions:$functionName';
    }
    return e.message ?? 'Cloud function "$functionName" failed (${e.code}).';
  }

  /// Enables or disables ordering for a store
  Future<void> setOrderingEnabled({required String storeId, required bool enabled}) async {
    await _firestore.collection(HAPISTORE_COLLECTION_REF).doc(storeId).update({'orderingEnabled': enabled});
  }
}
