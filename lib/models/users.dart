import 'package:cloud_firestore/cloud_firestore.dart';

class Users {
  String username;
  String role;
  String email;
  
  String createdBy;
  String lastUpdatedBy;
  Timestamp createdDate;
  Timestamp lastupdatedDate;

  Users({
    required this.username,
    required this.role,
    required this.email,
    required this.createdBy,
    required this.lastUpdatedBy,
    required this.createdDate,
    required this.lastupdatedDate,
  });

  static Users empty() => Users(
    username: '', 
    role: '', 
    email: '', 
    createdBy: '',
    lastUpdatedBy: '',
    createdDate: Timestamp.now(), 
    lastupdatedDate: Timestamp.now()
  );

  Users.fromJson(Map<String, Object?> json) 
  : this(
      username: json['username']! as String,
      role: json['role']! as String,
      email: json['email']! as String,
      createdBy: json['createdBy']! as String,
      lastUpdatedBy: json['lastUpdatedBy']! as String,
      createdDate: json['createdDate']! as Timestamp,
      lastupdatedDate: json['lastupdatedDate']! as Timestamp,
    );

  factory Users.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document){
    if (document.data() != null){
      final data = document.data();
      return Users(
        username: data?['username'],
        role: data?['role'],
        email: data?['email'],
        createdBy: data?['createdBy'],
        lastUpdatedBy: data?['lastUpdatedBy'],
        createdDate: data?['createdDate'],
        lastupdatedDate: data?['lastupdatedDate']);
    }
    else{
      return Users.empty();
    }
  }

  Users copyWith({
    String? username,
    String? role,
    String? email,
    String? createdBy,
    String? lastUpdatedBy,
    Timestamp? createdDate,
    Timestamp? lastupdatedDate,
  }) {
    return Users(
      username: username ?? this.username,
      role: role ?? this.role,
      email: email ?? this.email,
      createdBy: createdBy ?? this.createdBy,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
      createdDate: createdDate ?? this.createdDate,
      lastupdatedDate: lastupdatedDate ?? this.lastupdatedDate);
  }

  Map<String,Object?> toJson(){
    return {
      'username': username,
      'role': role,
      'email': email,
      'createdBy': createdBy,
      'lastUpdatedBy': lastUpdatedBy,
      'createdDate': createdDate,
      'lastupdatedDate': lastupdatedDate,
    };
  }
}