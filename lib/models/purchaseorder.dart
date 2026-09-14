import 'package:cloud_firestore/cloud_firestore.dart';

class Purchaseorder {
  Purchaseorder({
    required this.invoiceNumber,
    required this.orderAmount,
    required this.orderDate,
    required this.overpayment,
    required this.isSettled,
    required this.createdBy,
    required this.lastUpdatedBy,
    required this.createdDate,
    required this.lastupdatedDate,
    required this.invoiceAmount,
    required this.invoiceDate,
    this.imagePath = '',
  });

  Purchaseorder.fromJson(Map<String, Object?> json)
    : this(
        invoiceNumber: json['invoiceNumber']! as String,
        orderAmount: json['orderAmount']! as double,
        orderDate: json['orderDate']! as Timestamp,
        overpayment: json['overpayment']! as double,
        isSettled: json['isSettled'] as bool?,
        createdBy: json['createdBy']! as String,
        lastUpdatedBy: json['lastUpdatedBy']! as String,
        createdDate: json['createdDate']! as Timestamp,
        lastupdatedDate: json['lastupdatedDate']! as Timestamp,
        invoiceAmount: json['invoiceAmount']! as double,
        invoiceDate: json['invoiceDate']! as Timestamp,
        imagePath: json['imagePath'] as String? ?? '',
      );

  factory Purchaseorder.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      final data = document.data();
      return Purchaseorder(
        invoiceNumber: data?['invoiceNumber'],
        orderAmount: data?['orderAmount'],
        orderDate: data?['orderDate'],
        overpayment: data?['overpayment'],
        isSettled: data?['isSettled'],
        createdBy: data?['createdBy'],
        lastUpdatedBy: data?['lastUpdatedBy'],
        createdDate: data?['createdDate'],
        lastupdatedDate: data?['lastupdatedDate'],
        invoiceAmount: data?['invoiceAmount'],
        invoiceDate: data?['invoiceDate'],
        imagePath: data?['imagePath'] ?? '',
      );
    } else {
      return Purchaseorder.empty();
    }
  }

  String createdBy;
  Timestamp createdDate;
  String imagePath;
  double invoiceAmount;
  String invoiceNumber;
  bool? isSettled;
  String lastUpdatedBy;
  Timestamp lastupdatedDate;
  double orderAmount;
  Timestamp orderDate;
  double overpayment;
  Timestamp invoiceDate;

  static Purchaseorder empty() => Purchaseorder(
    invoiceNumber: '',
    orderAmount: 0.0,
    orderDate: Timestamp.now(),
    overpayment: 0.0,
    isSettled: null,
    createdBy: '',
    lastUpdatedBy: '',
    createdDate: Timestamp.now(),
    lastupdatedDate: Timestamp.now(),
    invoiceAmount: 0.0,
    invoiceDate: Timestamp.now(),
    imagePath: '',
  );

  Purchaseorder copyWith({
    String? invoiceNumber,
    double? orderAmount,
    Timestamp? orderDate,
    double? overpayment,
    bool? isSettled,
    Timestamp? invoiceDate,
    String? createdBy,
    String? lastUpdatedBy,
    Timestamp? createdDate,
    Timestamp? lastupdatedDate,
    double? invoiceAmount,
    String? imagePath,
  }) {
    return Purchaseorder(
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      orderAmount: orderAmount ?? this.orderAmount,
      orderDate: orderDate ?? this.orderDate,
      overpayment: overpayment ?? this.overpayment,
      isSettled: isSettled ?? this.isSettled,
      createdBy: createdBy ?? this.createdBy,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
      createdDate: createdDate ?? this.createdDate,
      lastupdatedDate: lastupdatedDate ?? this.lastupdatedDate,
      invoiceAmount: invoiceAmount ?? this.invoiceAmount,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      imagePath: imagePath ?? this.imagePath,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'invoiceNumber': invoiceNumber,
      'orderAmount': orderAmount,
      'orderDate': orderDate,
      'overpayment': overpayment,
      'isSettled': isSettled,
      'createdBy': createdBy,
      'lastUpdatedBy': lastUpdatedBy,
      'createdDate': createdDate,
      'lastupdatedDate': lastupdatedDate,
      'invoiceAmount': invoiceAmount,
      'invoiceDate': invoiceDate,
      'imagePath': imagePath,
    };
  }
}
