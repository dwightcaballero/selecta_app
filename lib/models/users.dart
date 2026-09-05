import 'package:cloud_firestore/cloud_firestore.dart';

class Users {
  String username;
  String role;
  String email;
  String dealerName;

  Users({
    required this.username,
    required this.role,
    required this.email,
    required this.dealerName,
  });

  static Users empty() =>
      Users(username: '', role: '', email: '', dealerName: '');

  Users.fromJson(Map<String, Object?> json)
    : this(
        username: json['username']! as String,
        role: json['role']! as String,
        email: json['email']! as String,
        dealerName: json['dealerName']! as String,
      );

  factory Users.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      final data = document.data();
      return Users(
        username: data?['username'],
        role: data?['role'],
        email: data?['email'],
        dealerName: data?['dealerName'],
      );
    } else {
      return Users.empty();
    }
  }

  Users copyWith({
    String? username,
    String? role,
    String? email,
    String? dealerName,
  }) {
    return Users(
      username: username ?? this.username,
      role: role ?? this.role,
      email: email ?? this.email,
      dealerName: dealerName ?? this.dealerName,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'username': username,
      'role': role,
      'email': email,
      'dealerName': dealerName,
    };
  }
}
