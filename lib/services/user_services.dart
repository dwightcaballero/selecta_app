import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/models/users.dart';

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
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty)
        return querySnapshot.docs.map((doc) {
          return Users.fromJson(doc.data() as Map<String, dynamic>);
        }).first;
      return null; // No user found
    } catch (e) {
      print("Error fetching user: $e");
      return null;
    }
  }

  void addUser(Users user) {
    _usersRef.add(user);
  }

  void updateUser(String userID, Users user) {
    _usersRef.doc(userID).update(user.toJson());
  }

  void deleteUser(String userID) {
    _usersRef.doc(userID).delete();
  }
}
