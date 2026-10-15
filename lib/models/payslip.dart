import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';

class PayslipDeductionItem {
  final String title;
  final double amount;
  final Timestamp date;
  final String expenseId;
  final String category;

  PayslipDeductionItem({
    required this.title,
    required this.amount,
    required this.date,
    this.expenseId = '',
    this.category = 'Expense',
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'amount': amount,
        'date': date,
        'expenseId': expenseId,
        'category': category,
      };

  factory PayslipDeductionItem.fromJson(Map<String, dynamic> json) =>
      PayslipDeductionItem(
        title: json['title'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        date: json['date'] as Timestamp? ?? Timestamp.now(),
        expenseId: json['expenseId'] as String? ?? '',
        category: json['category'] as String? ?? 'Expense',
      );
}

class Payslip {
  String id;
  String payslipNumber;
  String dealerName;
  String salesmanUsername;
  String salesmanEmail;
  Timestamp periodStart;
  Timestamp periodEnd;
  String cutoffWeekLabel;

  double dailyRate;
  double daysWorked;
  double basePay;

  double incentiveAmount;
  String incentiveRemarks;
  double grossPay;

  double expensesDeduction;
  List<PayslipDeductionItem> deductions;
  double otherDeductions;
  String otherDeductionsRemarks;
  double totalDeductions;

  double netPay;
  String status;
  String remarks;

  String createdBy;
  String lastUpdatedBy;
  Timestamp createdDate;
  Timestamp lastUpdatedDate;
  Timestamp? issuedDate;
  Timestamp? acknowledgedDate;

  Payslip({
    this.id = '',
    required this.payslipNumber,
    required this.dealerName,
    required this.salesmanUsername,
    this.salesmanEmail = '',
    required this.periodStart,
    required this.periodEnd,
    required this.cutoffWeekLabel,
    required this.dailyRate,
    required this.daysWorked,
    required this.basePay,
    this.incentiveAmount = 0.0,
    this.incentiveRemarks = '',
    required this.grossPay,
    this.expensesDeduction = 0.0,
    this.deductions = const [],
    this.otherDeductions = 0.0,
    this.otherDeductionsRemarks = '',
    required this.totalDeductions,
    required this.netPay,
    this.status = PayslipStatus.draft,
    this.remarks = '',
    required this.createdBy,
    required this.lastUpdatedBy,
    required this.createdDate,
    required this.lastUpdatedDate,
    this.issuedDate,
    this.acknowledgedDate,
  });

  static Payslip empty() => Payslip(
        id: '',
        payslipNumber: '',
        dealerName: '',
        salesmanUsername: '',
        salesmanEmail: '',
        periodStart: Timestamp.now(),
        periodEnd: Timestamp.now(),
        cutoffWeekLabel: '',
        dailyRate: 0.0,
        daysWorked: 0.0,
        basePay: 0.0,
        incentiveAmount: 0.0,
        incentiveRemarks: '',
        grossPay: 0.0,
        expensesDeduction: 0.0,
        deductions: [],
        otherDeductions: 0.0,
        otherDeductionsRemarks: '',
        totalDeductions: 0.0,
        netPay: 0.0,
        status: PayslipStatus.draft,
        remarks: '',
        createdBy: '',
        lastUpdatedBy: '',
        createdDate: Timestamp.now(),
        lastUpdatedDate: Timestamp.now(),
      );

  factory Payslip.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Payslip.fromJson(data, docId: doc.id);
  }

  factory Payslip.fromJson(Map<String, dynamic> json, {String docId = ''}) {
    final deductionList = (json['deductions'] as List<dynamic>?)
            ?.map((e) => PayslipDeductionItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        [];

    return Payslip(
      id: docId.isNotEmpty ? docId : (json['id'] as String? ?? ''),
      payslipNumber: json['payslipNumber'] as String? ?? '',
      dealerName: json['dealerName'] as String? ?? '',
      salesmanUsername: json['salesmanUsername'] as String? ?? '',
      salesmanEmail: json['salesmanEmail'] as String? ?? '',
      periodStart: json['periodStart'] as Timestamp? ?? Timestamp.now(),
      periodEnd: json['periodEnd'] as Timestamp? ?? Timestamp.now(),
      cutoffWeekLabel: json['cutoffWeekLabel'] as String? ?? '',
      dailyRate: (json['dailyRate'] as num?)?.toDouble() ?? 0.0,
      daysWorked: (json['daysWorked'] as num?)?.toDouble() ?? 0.0,
      basePay: (json['basePay'] as num?)?.toDouble() ?? 0.0,
      incentiveAmount: (json['incentiveAmount'] as num?)?.toDouble() ?? 0.0,
      incentiveRemarks: json['incentiveRemarks'] as String? ?? '',
      grossPay: (json['grossPay'] as num?)?.toDouble() ?? 0.0,
      expensesDeduction: (json['expensesDeduction'] as num?)?.toDouble() ?? 0.0,
      deductions: deductionList,
      otherDeductions: (json['otherDeductions'] as num?)?.toDouble() ?? 0.0,
      otherDeductionsRemarks: json['otherDeductionsRemarks'] as String? ?? '',
      totalDeductions: (json['totalDeductions'] as num?)?.toDouble() ?? 0.0,
      netPay: (json['netPay'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? PayslipStatus.draft,
      remarks: json['remarks'] as String? ?? '',
      createdBy: json['createdBy'] as String? ?? '',
      lastUpdatedBy: json['lastUpdatedBy'] as String? ?? '',
      createdDate: json['createdDate'] as Timestamp? ?? Timestamp.now(),
      lastUpdatedDate: json['lastUpdatedDate'] as Timestamp? ?? Timestamp.now(),
      issuedDate: json['issuedDate'] as Timestamp?,
      acknowledgedDate: json['acknowledgedDate'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() => {
        'payslipNumber': payslipNumber,
        'dealerName': dealerName,
        'salesmanUsername': salesmanUsername,
        'salesmanEmail': salesmanEmail,
        'periodStart': periodStart,
        'periodEnd': periodEnd,
        'cutoffWeekLabel': cutoffWeekLabel,
        'dailyRate': dailyRate,
        'daysWorked': daysWorked,
        'basePay': basePay,
        'incentiveAmount': incentiveAmount,
        'incentiveRemarks': incentiveRemarks,
        'grossPay': grossPay,
        'expensesDeduction': expensesDeduction,
        'deductions': deductions.map((e) => e.toJson()).toList(),
        'otherDeductions': otherDeductions,
        'otherDeductionsRemarks': otherDeductionsRemarks,
        'totalDeductions': totalDeductions,
        'netPay': netPay,
        'status': status,
        'remarks': remarks,
        'createdBy': createdBy,
        'lastUpdatedBy': lastUpdatedBy,
        'createdDate': createdDate,
        'lastUpdatedDate': lastUpdatedDate,
        'issuedDate': issuedDate,
        'acknowledgedDate': acknowledgedDate,
      };

  Payslip copyWith({
    String? id,
    String? payslipNumber,
    String? dealerName,
    String? salesmanUsername,
    String? salesmanEmail,
    Timestamp? periodStart,
    Timestamp? periodEnd,
    String? cutoffWeekLabel,
    double? dailyRate,
    double? daysWorked,
    double? basePay,
    double? incentiveAmount,
    String? incentiveRemarks,
    double? grossPay,
    double? expensesDeduction,
    List<PayslipDeductionItem>? deductions,
    double? otherDeductions,
    String? otherDeductionsRemarks,
    double? totalDeductions,
    double? netPay,
    String? status,
    String? remarks,
    String? createdBy,
    String? lastUpdatedBy,
    Timestamp? createdDate,
    Timestamp? lastUpdatedDate,
    Timestamp? issuedDate,
    Timestamp? acknowledgedDate,
  }) {
    return Payslip(
      id: id ?? this.id,
      payslipNumber: payslipNumber ?? this.payslipNumber,
      dealerName: dealerName ?? this.dealerName,
      salesmanUsername: salesmanUsername ?? this.salesmanUsername,
      salesmanEmail: salesmanEmail ?? this.salesmanEmail,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      cutoffWeekLabel: cutoffWeekLabel ?? this.cutoffWeekLabel,
      dailyRate: dailyRate ?? this.dailyRate,
      daysWorked: daysWorked ?? this.daysWorked,
      basePay: basePay ?? this.basePay,
      incentiveAmount: incentiveAmount ?? this.incentiveAmount,
      incentiveRemarks: incentiveRemarks ?? this.incentiveRemarks,
      grossPay: grossPay ?? this.grossPay,
      expensesDeduction: expensesDeduction ?? this.expensesDeduction,
      deductions: deductions ?? this.deductions,
      otherDeductions: otherDeductions ?? this.otherDeductions,
      otherDeductionsRemarks: otherDeductionsRemarks ?? this.otherDeductionsRemarks,
      totalDeductions: totalDeductions ?? this.totalDeductions,
      netPay: netPay ?? this.netPay,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
      createdBy: createdBy ?? this.createdBy,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
      createdDate: createdDate ?? this.createdDate,
      lastUpdatedDate: lastUpdatedDate ?? this.lastUpdatedDate,
      issuedDate: issuedDate ?? this.issuedDate,
      acknowledgedDate: acknowledgedDate ?? this.acknowledgedDate,
    );
  }
}
