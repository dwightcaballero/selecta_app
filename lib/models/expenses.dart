import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';

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
  String expenseType; // ExpenseType.salesman or ExpenseType.dealer
  String paymentMethod; // ExpensePaymentMethod.cash or ExpensePaymentMethod.online

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
    this.expenseType = ExpenseType.dealer,
    this.paymentMethod = ExpensePaymentMethod.cash,
  });

  bool get isSalesmanExpense => expenseType == ExpenseType.salesman;
  bool get isDealerExpense => expenseType != ExpenseType.salesman;
  bool get isCash => paymentMethod != ExpensePaymentMethod.online;
  bool get isOnline => paymentMethod == ExpensePaymentMethod.online;

  static Expenses empty({String? expenseType, String? paymentMethod}) => Expenses(
    description: '',
    expenseAmount: 0,
    expenseDate: Timestamp.now(),
    createdBy: '',
    lastUpdatedBy: '',
    createdDate: Timestamp.now(),
    lastupdatedDate: Timestamp.now(),
    createdPage: '',
    lastUpdatedPage: '',
    expenseType: expenseType ?? ExpenseType.dealer,
    paymentMethod: paymentMethod ?? ExpensePaymentMethod.cash,
  );

  Expenses.fromJson(Map<String, Object?> json)
    : this(
        description: json['description']! as String,
        expenseAmount: (json['expenseAmount']! as num).toDouble(),
        expenseDate: json['expenseDate']! as Timestamp,
        createdBy: json['createdBy']! as String,
        lastUpdatedBy: json['lastUpdatedBy']! as String,
        createdDate: json['createdDate']! as Timestamp,
        lastupdatedDate: json['lastupdatedDate']! as Timestamp,
        createdPage: json['createdPage'] as String? ?? '',
        lastUpdatedPage: json['lastUpdatedPage'] as String? ?? '',
        expenseType: json['expenseType'] as String? ?? ExpenseType.dealer,
        paymentMethod: json['paymentMethod'] as String? ?? ExpensePaymentMethod.cash,
      );

  factory Expenses.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      final data = document.data();
      return Expenses(
        description: data?['description'] ?? '',
        expenseAmount: (data?['expenseAmount'] as num?)?.toDouble() ?? 0.0,
        expenseDate: data?['expenseDate'] ?? Timestamp.now(),
        createdBy: data?['createdBy'] ?? '',
        lastUpdatedBy: data?['lastUpdatedBy'] ?? '',
        createdDate: data?['createdDate'] ?? Timestamp.now(),
        lastupdatedDate: data?['lastupdatedDate'] ?? Timestamp.now(),
        createdPage: data?['createdPage'] as String? ?? '',
        lastUpdatedPage: data?['lastUpdatedPage'] as String? ?? '',
        expenseType: data?['expenseType'] as String? ?? ExpenseType.dealer,
        paymentMethod: data?['paymentMethod'] as String? ?? ExpensePaymentMethod.cash,
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
    String? expenseType,
    String? paymentMethod,
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
      expenseType: expenseType ?? this.expenseType,
      paymentMethod: paymentMethod ?? this.paymentMethod,
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
      'expenseType': expenseType,
      'paymentMethod': paymentMethod,
    };
  }
}
