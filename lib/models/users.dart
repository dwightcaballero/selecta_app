import 'package:cloud_firestore/cloud_firestore.dart';

class Users {
  String username;
  String role;
  String email;
  String dealerName;
  double dailyRate;

  Users({
    required this.username,
    required this.role,
    required this.email,
    required this.dealerName,
    this.dailyRate = 0.0,
  });

  static Users empty() =>
      Users(username: '', role: '', email: '', dealerName: '', dailyRate: 0.0);

  Users.fromJson(Map<String, Object?> json)
    : this(
        username: json['username']! as String,
        role: json['role']! as String,
        email: json['email']! as String,
        dealerName: json['dealerName']! as String,
        dailyRate: (json['dailyRate'] as num?)?.toDouble() ?? 0.0,
      );

  factory Users.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      final data = document.data();
      return Users(
        username: data?['username'] ?? '',
        role: data?['role'] ?? '',
        email: data?['email'] ?? '',
        dealerName: data?['dealerName'] ?? '',
        dailyRate: (data?['dailyRate'] as num?)?.toDouble() ?? 0.0,
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
    double? dailyRate,
  }) {
    return Users(
      username: username ?? this.username,
      role: role ?? this.role,
      email: email ?? this.email,
      dealerName: dealerName ?? this.dealerName,
      dailyRate: dailyRate ?? this.dailyRate,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'username': username,
      'role': role,
      'email': email,
      'dealerName': dealerName,
      'dailyRate': dailyRate,
    };
  }
}
