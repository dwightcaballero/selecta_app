import 'package:cloud_firestore/cloud_firestore.dart';

class Breakdown {
  Timestamp breakdownDate;

  double bankDepositAmount;
  double breakdownAmount;
  double expectedAmount;
  double discrepancy;

  int cent;
  int b1000;
  int b500;
  int b200;
  int b100;
  int b50;
  int b20;
  int c20;
  int c10;
  int c5;
  int c1;

  String createdBy;
  String lastUpdatedBy;
  Timestamp createdDate;
  Timestamp lastupdatedDate;

  Breakdown({
    required this.breakdownDate,
    required this.bankDepositAmount,
    required this.breakdownAmount,
    required this.expectedAmount,
    required this.discrepancy,
    required this.cent,
    required this.b1000,
    required this.b500,
    required this.b200,
    required this.b100,
    required this.b50,
    required this.b20,
    required this.c20,
    required this.c10,
    required this.c5,
    required this.c1,
    required this.createdBy,
    required this.lastUpdatedBy,
    required this.createdDate,
    required this.lastupdatedDate,
  });

  static Breakdown empty() => Breakdown(
    breakdownDate: Timestamp.now(),
    bankDepositAmount: 0,
    breakdownAmount: 0,
    expectedAmount: 0,
    discrepancy: 0,
    cent: 0,
    b1000: 0,
    b500: 0,
    b200: 0,
    b100: 0,
    b50: 0,
    b20: 0,
    c20: 0,
    c10: 0,
    c5: 0,
    c1: 0,

    createdBy: '',
    lastUpdatedBy: '',
    createdDate: Timestamp.now(),
    lastupdatedDate: Timestamp.now(),
  );

  Breakdown.fromJson(Map<String, Object?> json)
    : this(
        breakdownDate: json['breakdownDate']! as Timestamp,
        bankDepositAmount: json['bankDepositAmount']! as double,
        breakdownAmount: json['breakdownAmount']! as double,
        expectedAmount: json['expectedAmount']! as double,
        discrepancy: json['discrepancy']! as double,
        cent: json['cent']! as int,
        b1000: json['b1000']! as int,
        b500: json['b500']! as int,
        b200: json['b200']! as int,
        b100: json['b100']! as int,
        b50: json['b50']! as int,
        b20: json['b20']! as int,
        c20: json['c20']! as int,
        c10: json['c10']! as int,
        c5: json['c5']! as int,
        c1: json['c1']! as int,

        createdBy: json['createdBy']! as String,
        lastUpdatedBy: json['lastUpdatedBy']! as String,
        createdDate: json['createdDate']! as Timestamp,
        lastupdatedDate: json['lastupdatedDate']! as Timestamp,
      );

  factory Breakdown.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    if (document.data() != null) {
      final data = document.data();
      return Breakdown(
        breakdownDate: data?['breakdownDate'],
        bankDepositAmount: data?['bankDepositAmount'],
        breakdownAmount: data?['breakdownAmount'],
        expectedAmount: data?['expectedAmount'],
        discrepancy: data?['discrepancy'],
        cent: data?['cent'],
        b1000: data?['b1000'],
        b500: data?['b500'],
        b200: data?['b200'],
        b100: data?['b100'],
        b50: data?['b50'],
        b20: data?['b20'],
        c20: data?['c20'],
        c10: data?['c10'],
        c5: data?['c5'],
        c1: data?['c1'],

        createdBy: data?['createdBy'],
        lastUpdatedBy: data?['lastUpdatedBy'],
        createdDate: data?['createdDate'],
        lastupdatedDate: data?['lastupdatedDate'],
      );
    } else {
      return Breakdown.empty();
    }
  }

  Breakdown copyWith({
    Timestamp? breakdownDate,
    double? bankDepositAmount,
    double? breakdownAmount,
    double? expectedAmount,
    double? discrepancy,
    int? cent,
    int? b1000,
    int? b500,
    int? b200,
    int? b100,
    int? b50,
    int? b20,
    int? c20,
    int? c10,
    int? c5,
    int? c1,

    String? createdBy,
    String? lastUpdatedBy,
    Timestamp? createdDate,
    Timestamp? lastupdatedDate,
  }) {
    return Breakdown(
      breakdownDate: breakdownDate ?? this.breakdownDate,
      bankDepositAmount: bankDepositAmount ?? this.bankDepositAmount,
      breakdownAmount: breakdownAmount ?? this.breakdownAmount,
      expectedAmount: expectedAmount ?? this.expectedAmount,
      discrepancy: discrepancy ?? this.discrepancy,
      cent: cent ?? this.cent,

      b1000: b1000 ?? this.b1000,
      b500: b500 ?? this.b500,
      b200: b200 ?? this.b200,
      b100: b100 ?? this.b100,
      b50: b50 ?? this.b50,
      b20: b20 ?? this.b20,
      c20: c20 ?? this.c20,
      c10: c10 ?? this.c10,
      c5: c5 ?? this.c5,
      c1: c1 ?? this.c1,

      createdBy: createdBy ?? this.createdBy,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
      createdDate: createdDate ?? this.createdDate,
      lastupdatedDate: lastupdatedDate ?? this.lastupdatedDate,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'breakdownDate': breakdownDate,
      'bankDepositAmount': bankDepositAmount,
      'breakdownAmount': breakdownAmount,
      'expectedAmount': expectedAmount,
      'discrepancy': discrepancy,
      'cent': cent,

      'b1000': b1000,
      'b500': b500,
      'b200': b200,
      'b100': b100,
      'b50': b50,
      'b20': b20,
      'c20': c20,
      'c10': c10,
      'c5': c5,
      'c1': c1,

      'createdBy': createdBy,
      'lastUpdatedBy': lastUpdatedBy,
      'createdDate': createdDate,
      'lastupdatedDate': lastupdatedDate,
    };
  }
}
