import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';

class Users {
  String username;
  String role;
  String email;
  String dealerName;
  double dailyRate;
  String storeId;
  String storeName;
  bool mustChangePassword;

  Users({
    required this.username,
    required this.role,
    required this.email,
    required this.dealerName,
    this.dailyRate = 0.0,
    this.storeId = '',
    this.storeName = '',
    this.mustChangePassword = false,
  });

  /// True if the user is an Admin.
  bool get isAdmin => role == BusinessRole.admin;

  /// True if the user is either a Dealer or an Admin (inheriting Dealer rights).
  bool get isDealerOrAdmin => role == BusinessRole.dealer || role == BusinessRole.admin;

  /// True if the user is a Hapi Store self-ordering account.
  bool get isStore => role == BusinessRole.hapiStore;

  /// True if the user is a Dealer.
  bool get isDealer => role == 'Dealer' || role == BusinessRole.dealer;

  static Users empty() =>
      Users(
        username: '',
        role: '',
        email: '',
        dealerName: '',
        dailyRate: 0.0,
        storeId: '',
        storeName: '',
        mustChangePassword: false,
      );

  Users.fromJson(Map<String, Object?> json)
    : this(
        username: (json['username'] as String?) ?? '',
        role: (json['role'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
        dealerName: (json['dealerName'] as String?) ?? '',
        dailyRate: (json['dailyRate'] as num?)?.toDouble() ?? 0.0,
        storeId: (json['storeId'] as String?) ?? '',
        storeName: (json['storeName'] as String?) ?? '',
        mustChangePassword: (json['mustChangePassword'] as bool?) ?? false,
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
        storeId: data?['storeId'] ?? '',
        storeName: data?['storeName'] ?? '',
        mustChangePassword: data?['mustChangePassword'] ?? false,
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
    String? storeId,
    String? storeName,
    bool? mustChangePassword,
  }) {
    return Users(
      username: username ?? this.username,
      role: role ?? this.role,
      email: email ?? this.email,
      dealerName: dealerName ?? this.dealerName,
      dailyRate: dailyRate ?? this.dailyRate,
      storeId: storeId ?? this.storeId,
      storeName: storeName ?? this.storeName,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'username': username,
      'role': role,
      'email': email,
      'dealerName': dealerName,
      'dailyRate': dailyRate,
      'storeId': storeId,
      'storeName': storeName,
      'mustChangePassword': mustChangePassword,
    };
  }
}
