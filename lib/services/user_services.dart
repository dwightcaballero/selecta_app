import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/users.dart';

// ignore: constant_identifier_names
const String USERS_COLLECTION_REF = 'users';

class UserService {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference _usersRef;

  UserService() {
    _usersRef = _firestore
        .collection(USERS_COLLECTION_REF)
        .withConverter<Users>(
          fromFirestore: (snapshots, _) => Users.fromJson(snapshots.data()!),
          toFirestore: (user, _) => user.toJson(),
        );
  }

  Future<Users?> getUserByEmail(String email) async {
    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email.trim())
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.map((doc) {
          return Users.fromJson(doc.data() as Map<String, dynamic>);
        }).first;
      }
      return null; // No user found
    } catch (e) {
      return null;
    }
  }

  void addUser(Users user) {
    _usersRef.add(user);
  }

  void updateUser(String userID, Users user) {
    _usersRef.doc(userID).update(user.toJson());
  }

  Future<void> updateUserRoleByEmail(String email, String newRole) async {
    final query = await FirebaseFirestore.instance
        .collection(USERS_COLLECTION_REF)
        .where('email', isEqualTo: email.trim())
        .limit(1)
        .get();
    if (query.docs.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection(USERS_COLLECTION_REF)
          .doc(query.docs.first.id)
          .update({'role': newRole});
    }
  }

  Stream<List<Users>> getAllUsersStream({int? limit}) {
    Query query = _usersRef;
    if (limit != null && limit > 0) {
      query = query.limit(limit);
    }
    return query.snapshots().map(
          (snapshot) => snapshot.docs.map((doc) => doc.data() as Users).toList(),
        );
  }

  void deleteUser(String userID) {
    _usersRef.doc(userID).delete();
  }

  /// Permanently deletes a user account from Firestore, cleans up associated
  /// FCM notification tokens, and records an audit log entry.
  Future<void> deleteUserAccount(Users user) async {
    final cleanEmail = user.email.trim();
    if (cleanEmail.isEmpty) return;

    // 1. Delete user documents matching this email from the users collection
    final userQuery = await FirebaseFirestore.instance
        .collection(USERS_COLLECTION_REF)
        .where('email', isEqualTo: cleanEmail)
        .get();

    for (final doc in userQuery.docs) {
      await doc.reference.delete();
    }

    // 2. Clean up indexed FCM device tokens associated with this user
    try {
      final fcmQuery = await FirebaseFirestore.instance
          .collection('fcm_tokens')
          .where('email', isEqualTo: cleanEmail)
          .get();

      for (final doc in fcmQuery.docs) {
        await doc.reference.delete();
      }
    } catch (_) {}

    // 3. Write an audit log trail
    await Helperfunctions.logDelete(
      user.username.isNotEmpty ? user.username : cleanEmail,
      user.toJson(),
      page: AppPages.superAdmin,
    );
  }

  /// Permanently deletes a user account by email address.
  Future<void> deleteUserByEmail(String email) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) return;

    final existingUser = await getUserByEmail(cleanEmail);
    if (existingUser != null) {
      await deleteUserAccount(existingUser);
    } else {
      final query = await FirebaseFirestore.instance
          .collection(USERS_COLLECTION_REF)
          .where('email', isEqualTo: cleanEmail)
          .get();
      for (final doc in query.docs) {
        await doc.reference.delete();
      }
    }
  }
}
