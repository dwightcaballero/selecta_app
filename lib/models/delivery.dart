import 'package:cloud_firestore/cloud_firestore.dart';

class Delivery {
  String storeName;
  String remarks;
  String transactionStatus;
  String imagePath;

  double orderAmount;
  double cashAmount;
  double onlineAmount;
  double creditAmount;
  double returnAmount;
  String creditStatus;
  Timestamp? deliveryDate;

  String createdBy;
  String lastUpdatedBy;
  Timestamp createdDate;
  Timestamp lastupdatedDate;

  Delivery({
    required this.storeName,
    required this.remarks,
    required this.transactionStatus,
    required this.imagePath,
    required this.orderAmount,
    required this.returnAmount,
    required this.creditAmount,
    required this.cashAmount,
    required this.onlineAmount,
    required this.deliveryDate,
    required this.creditStatus,
    required this.createdBy,
    required this.lastUpdatedBy,
    required this.createdDate,
    required this.lastupdatedDate,
  });

  static Delivery empty() => Delivery(
    storeName: '',
    remarks: '',
    transactionStatus: '',
    imagePath: '',
    orderAmount: 0,
    returnAmount: 0,
    creditAmount: 0,
    cashAmount: 0,
    onlineAmount: 0,
    deliveryDate: null,
    creditStatus: '',
    createdBy: '',
    lastUpdatedBy: '',
    createdDate: Timestamp.now(),
    lastupdatedDate: Timestamp.now(),
  );

  Delivery.fromJson(Map<String, Object?> json)
    : this(
        storeName: json['storeName']! as String,
        remarks: json['remarks']! as String,
        transactionStatus: json['transactionStatus']! as String,
        imagePath: json['imagePath'] == null
            ? ''
            : json['imagePath']! as String,
        orderAmount: json['orderAmount']! as double,
        returnAmount: json['returnAmount']! as double,
        creditAmount: json['creditAmount']! as double,
        cashAmount: json['cashAmount']! as double,
        onlineAmount: json['onlineAmount']! as double,
        deliveryDate: json['deliveryDate'] as Timestamp?,
        creditStatus: json['creditStatus'] as String,
        createdBy: json['createdBy']! as String,
        lastUpdatedBy: json['lastUpdatedBy']! as String,
        createdDate: json['createdDate']! as Timestamp,
        lastupdatedDate: json['lastupdatedDate']! as Timestamp,
      );

  factory Delivery.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    if (document.data() != null) {
      final data = document.data();
      return Delivery(
        storeName: data?['storeName'],
        remarks: data?['remarks'],
        transactionStatus: data?['transactionStatus'],
        imagePath: data?['imagePath'],
        orderAmount: data?['orderAmount'],
        returnAmount: data?['returnAmount'],
        creditAmount: data?['creditAmount'],
        cashAmount: data?['cashAmount'],
        onlineAmount: data?['onlineAmount'],
        deliveryDate: data?['deliveryDate'],
        creditStatus: data?['creditStatus'],
        createdBy: data?['createdBy'],
        lastUpdatedBy: data?['lastUpdatedBy'],
        createdDate: data?['createdDate'],
        lastupdatedDate: data?['lastupdatedDate'],
      );
    } else {
      return Delivery.empty();
    }
  }

  Delivery copyWith({
    String? storeName,
    String? remarks,
    String? transactionStatus,
    String? imagePath,
    double? orderAmount,
    double? deliveryAmount,
    double? returnAmount,
    double? creditAmount,
    String? creditStatus,
    double? cashAmount,
    double? onlineAmount,
    Timestamp? deliveryDate,

    String? createdBy,
    String? lastUpdatedBy,
    Timestamp? createdDate,
    Timestamp? lastupdatedDate,
  }) {
    return Delivery(
      storeName: storeName ?? this.storeName,
      remarks: remarks ?? this.remarks,
      transactionStatus: transactionStatus ?? this.transactionStatus,
      imagePath: imagePath ?? this.imagePath,
      orderAmount: orderAmount ?? this.orderAmount,
      returnAmount: returnAmount ?? this.returnAmount,
      creditAmount: creditAmount ?? this.creditAmount,
      cashAmount: cashAmount ?? this.cashAmount,
      onlineAmount: onlineAmount ?? this.onlineAmount,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      creditStatus: creditStatus ?? this.creditStatus,
      createdBy: createdBy ?? this.createdBy,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
      createdDate: createdDate ?? this.createdDate,
      lastupdatedDate: lastupdatedDate ?? this.lastupdatedDate,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'storeName': storeName,
      'remarks': remarks,
      'transactionStatus': transactionStatus,
      'imagePath': imagePath,
      'orderAmount': orderAmount,
      'returnAmount': returnAmount,
      'creditAmount': creditAmount,
      'cashAmount': cashAmount,
      'onlineAmount': onlineAmount,
      'deliveryDate': deliveryDate,
      'creditStatus': creditStatus,
      'createdBy': createdBy,
      'lastUpdatedBy': lastUpdatedBy,
      'createdDate': createdDate,
      'lastupdatedDate': lastupdatedDate,
    };
  }
}

class DeliveryModelString {
  static String storeName = 'storeName';
  static String remarks = 'remarks';
  static String transactionStatus = 'transactionStatus';
  static String imagePath = 'imagePath';
  static String orderAmount = 'orderAmount';
  static String returnAmount = 'returnAmount';
  static String creditAmount = 'creditAmount';
  static String cashAmount = 'cashAmount';
  static String onlineAmount = 'onlineAmount';
  static String deliveryDate = 'deliveryDate';
  static String creditStatus = 'creditStatus';

  static String createdBy = 'createdBy';
  static String lastUpdatedBy = 'lastUpdatedBy';
  static String createdDate = 'createdDate';
  static String lastupdatedDate = 'lastupdatedDate';
}
