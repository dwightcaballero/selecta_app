import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionLog {
  String dealerName;
  String loggedBy;
  String loggedRole;
  String logAction;
  Timestamp loggedDate;
  String message;
  String details;
  String page;
  String appVersion;

  TransactionLog({
    required this.dealerName,
    required this.loggedBy,
    required this.loggedRole,
    required this.logAction,
    required this.loggedDate,
    required this.message,
    required this.details,
    this.page = '',
    this.appVersion = '',
  });

  static TransactionLog empty() => TransactionLog(
    dealerName: '',
    loggedBy: '',
    loggedRole: '',
    logAction: '',
    loggedDate: Timestamp.now(),
    message: '',
    details: '',
    page: '',
    appVersion: '',
  );

  TransactionLog.fromJson(Map<String, Object?> json)
    : this(
        dealerName: json['dealerName']! as String,
        loggedBy: json['loggedBy']! as String,
        loggedRole: json['loggedRole']! as String,
        logAction: json['logAction']! as String,
        loggedDate: json['loggedDate']! as Timestamp,
        message: json['message']! as String,
        details: json['details']! as String,
        page: json['page'] as String? ?? '',
        appVersion: json['appVersion'] as String? ?? '',
      );

  factory TransactionLog.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    if (document.data() != null) {
      final data = document.data();
      return TransactionLog(
        dealerName: data?['dealerName'],
        loggedBy: data?['loggedBy'],
        loggedRole: data?['loggedRole'],
        logAction: data?['logAction'],
        loggedDate: data?['loggedDate'],
        message: data?['message'],
        details: data?['details'],
        page: data?['page'] as String? ?? '',
        appVersion: data?['appVersion'] as String? ?? '',
      );
    } else {
      return TransactionLog.empty();
    }
  }

  TransactionLog copyWith({
    String? dealerName,
    String? loggedBy,
    String? loggedRole,
    String? logAction,
    Timestamp? loggedDate,
    String? message,
    String? details,
    String? page,
    String? appVersion,
  }) {
    return TransactionLog(
      dealerName: dealerName ?? this.dealerName,
      loggedBy: loggedBy ?? this.loggedBy,
      loggedRole: loggedRole ?? this.loggedRole,
      logAction: logAction ?? this.logAction,
      loggedDate: loggedDate ?? this.loggedDate,
      message: message ?? this.message,
      details: details ?? this.details,
      page: page ?? this.page,
      appVersion: appVersion ?? this.appVersion,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'dealerName': dealerName,
      'loggedBy': loggedBy,
      'loggedRole': loggedRole,
      'logAction': logAction,
      'loggedDate': loggedDate,
      'message': message,
      'details': details,
      'page': page,
      'appVersion': appVersion,
    };
  }
}
