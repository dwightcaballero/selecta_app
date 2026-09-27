import 'package:cloud_firestore/cloud_firestore.dart';

class Expenses {
  String description;
  double expenseAmount;
  Timestamp expenseDate;
  String createdBy;
  String lastUpdatedBy;
  Timestamp createdDate;
  Timestamp lastupdatedDate;
  String createdPage;
  String lastUpdatedPage;

  Expenses({
    required this.description,
    required this.expenseAmount,
    required this.expenseDate,
    required this.createdBy,
    required this.lastUpdatedBy,
    required this.createdDate,
    required this.lastupdatedDate,
    this.createdPage = '',
    this.lastUpdatedPage = '',
  });

  static Expenses empty() => Expenses(
    description: '',
    expenseAmount: 0,
    expenseDate: Timestamp.now(),
    createdBy: '',
    lastUpdatedBy: '',
    createdDate: Timestamp.now(),
    lastupdatedDate: Timestamp.now(),
    createdPage: '',
    lastUpdatedPage: '',
  );

  Expenses.fromJson(Map<String, Object?> json)
    : this(
        description: json['description']! as String,
        expenseAmount: json['expenseAmount']! as double,
        expenseDate: json['expenseDate']! as Timestamp,
        createdBy: json['createdBy']! as String,
        lastUpdatedBy: json['lastUpdatedBy']! as String,
        createdDate: json['createdDate']! as Timestamp,
        lastupdatedDate: json['lastupdatedDate']! as Timestamp,
        createdPage: json['createdPage'] as String? ?? '',
        lastUpdatedPage: json['lastUpdatedPage'] as String? ?? '',
      );

  factory Expenses.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      final data = document.data();
      return Expenses(
        description: data?['description'],
        expenseAmount: data?['expenseAmount'],
        expenseDate: data?['expenseDate'],
        createdBy: data?['createdBy'],
        lastUpdatedBy: data?['lastUpdatedBy'],
        createdDate: data?['createdDate'],
        lastupdatedDate: data?['lastupdatedDate'],
        createdPage: data?['createdPage'] as String? ?? '',
        lastUpdatedPage: data?['lastUpdatedPage'] as String? ?? '',
      );
    } else {
      return Expenses.empty();
    }
  }

  Expenses copyWith({
    String? description,
    double? expenseAmount,
    Timestamp? expenseDate,
    String? createdBy,
    String? lastUpdatedBy,
    Timestamp? createdDate,
    Timestamp? lastupdatedDate,
    String? createdPage,
    String? lastUpdatedPage,
  }) {
    return Expenses(
      description: description ?? this.description,
      expenseAmount: expenseAmount ?? this.expenseAmount,
      expenseDate: expenseDate ?? this.expenseDate,
      createdBy: createdBy ?? this.createdBy,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
      createdDate: createdDate ?? this.createdDate,
      lastupdatedDate: lastupdatedDate ?? this.lastupdatedDate,
      createdPage: createdPage ?? this.createdPage,
      lastUpdatedPage: lastUpdatedPage ?? this.lastUpdatedPage,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'description': description,
      'expenseAmount': expenseAmount,
      'expenseDate': expenseDate,
      'createdBy': createdBy,
      'lastUpdatedBy': lastUpdatedBy,
      'createdDate': createdDate,
      'lastupdatedDate': lastupdatedDate,
      'createdPage': createdPage,
      'lastUpdatedPage': lastUpdatedPage,
    };
  }
}
