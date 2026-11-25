import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/models/delivery.dart';

class ManualReceiptLine {
  const ManualReceiptLine({
    required this.item,
    required this.receivedQuantity,
    this.shortageReason = '',
  });

  final OrderItem item;
  final int receivedQuantity;
  final String shortageReason;

  factory ManualReceiptLine.fromJson(Map<String, dynamic> json) => ManualReceiptLine(
    item: OrderItem.fromJson(Map<String, dynamic>.from(json['item'] as Map)),
    receivedQuantity: (json['receivedQuantity'] as num).toInt(),
    shortageReason: json['shortageReason'] as String? ?? '',
  );

  Map<String, Object?> toJson() => {
    'item': item.toJson(),
    'receivedQuantity': receivedQuantity,
    'shortageReason': shortageReason,
  };
}

class Purchaseorder {
  Purchaseorder({
    this.poNumber = '',
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
    this.createdPage = '',
    this.lastUpdatedPage = '',
    this.items = const [],
    this.isInventoryReplenished = false,
    this.status = 'pending',
    this.manualReceiptLines = const [],
    this.manualReceiptDate,
    this.manualReceiptRecordedAt,
    this.manualReceiptRecordedBy = '',
    this.manualReceiptRecordedByUid = '',
    this.invoiceVerificationPending = false,
  });

  Purchaseorder.fromJson(Map<String, Object?> json)
    : this(
        poNumber: json['poNumber'] as String? ?? (json['invoiceNumber'] as String? ?? ''),
        invoiceNumber: json['invoiceNumber'] as String? ?? '',
        orderAmount: (json['orderAmount'] as num?)?.toDouble() ?? 0.0,
        orderDate: json['orderDate']! as Timestamp,
        overpayment: (json['overpayment'] as num?)?.toDouble() ?? 0.0,
        isSettled: json['isSettled'] as bool?,
        createdBy: json['createdBy']! as String,
        lastUpdatedBy: json['lastUpdatedBy']! as String,
        createdDate: json['createdDate']! as Timestamp,
        lastupdatedDate: json['lastupdatedDate']! as Timestamp,
        invoiceAmount: (json['invoiceAmount'] as num?)?.toDouble() ?? 0.0,
        invoiceDate: json['invoiceDate']! as Timestamp,
        imagePath: json['imagePath'] as String? ?? '',
        createdPage: json['createdPage'] as String? ?? '',
        lastUpdatedPage: json['lastUpdatedPage'] as String? ?? '',
        items: json['items'] != null
            ? (json['items'] as List<dynamic>)
                .map((e) => OrderItem.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList()
            : const [],
        isInventoryReplenished: json['isInventoryReplenished'] as bool? ?? false,
        status: json['status'] as String? ?? 'pending',
        manualReceiptLines: (json['manualReceiptLines'] as List<dynamic>? ?? [])
            .map((e) => ManualReceiptLine.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        manualReceiptDate: json['manualReceiptDate'] as Timestamp?,
        manualReceiptRecordedAt: json['manualReceiptRecordedAt'] as Timestamp?,
        manualReceiptRecordedBy: json['manualReceiptRecordedBy'] as String? ?? '',
        manualReceiptRecordedByUid: json['manualReceiptRecordedByUid'] as String? ?? '',
        invoiceVerificationPending: json['invoiceVerificationPending'] as bool? ?? false,
      );

  factory Purchaseorder.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      final data = document.data();
      return Purchaseorder(
        poNumber: data?['poNumber'] as String? ?? (data?['invoiceNumber'] as String? ?? ''),
        invoiceNumber: data?['invoiceNumber'] ?? '',
        orderAmount: (data?['orderAmount'] as num?)?.toDouble() ?? 0.0,
        orderDate: data?['orderDate'] ?? Timestamp.now(),
        overpayment: (data?['overpayment'] as num?)?.toDouble() ?? 0.0,
        isSettled: data?['isSettled'],
        createdBy: data?['createdBy'] ?? '',
        lastUpdatedBy: data?['lastUpdatedBy'] ?? '',
        createdDate: data?['createdDate'] ?? Timestamp.now(),
        lastupdatedDate: data?['lastupdatedDate'] ?? Timestamp.now(),
        invoiceAmount: (data?['invoiceAmount'] as num?)?.toDouble() ?? 0.0,
        invoiceDate: data?['invoiceDate'] ?? Timestamp.now(),
        imagePath: data?['imagePath'] ?? '',
        createdPage: data?['createdPage'] as String? ?? '',
        lastUpdatedPage: data?['lastUpdatedPage'] as String? ?? '',
        items: data?['items'] != null
            ? (data!['items'] as List<dynamic>)
                .map((e) => OrderItem.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList()
            : const [],
        isInventoryReplenished: data?['isInventoryReplenished'] as bool? ?? false,
        status: data?['status'] as String? ?? 'pending',
        manualReceiptLines: (data?['manualReceiptLines'] as List<dynamic>? ?? [])
            .map((e) => ManualReceiptLine.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        manualReceiptDate: data?['manualReceiptDate'] as Timestamp?,
        manualReceiptRecordedAt: data?['manualReceiptRecordedAt'] as Timestamp?,
        manualReceiptRecordedBy: data?['manualReceiptRecordedBy'] as String? ?? '',
        manualReceiptRecordedByUid: data?['manualReceiptRecordedByUid'] as String? ?? '',
        invoiceVerificationPending: data?['invoiceVerificationPending'] as bool? ?? false,
      );
    } else {
      return Purchaseorder.empty();
    }
  }

  String poNumber;
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
  String createdPage;
  String lastUpdatedPage;
  List<OrderItem> items;
  bool isInventoryReplenished;
  List<ManualReceiptLine> manualReceiptLines;
  Timestamp? manualReceiptDate;
  Timestamp? manualReceiptRecordedAt;
  String manualReceiptRecordedBy;
  String manualReceiptRecordedByUid;
  bool invoiceVerificationPending;
  double get manualReceiptValue => manualReceiptLines.fold<double>(
    0,
    (total, line) => total + line.receivedQuantity * line.item.buyingPrice,
  );

  /// Workflow status: 'pending' (PO created, stocks not arrived yet)
  /// or 'invoiced' / 'confirmed' (official invoice attached, inventory permanently replenished).
  String status;

  static Purchaseorder empty() => Purchaseorder(
    poNumber: '',
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
    createdPage: '',
    lastUpdatedPage: '',
    items: const [],
    isInventoryReplenished: false,
    status: 'pending',
  );

  Purchaseorder copyWith({
    String? poNumber,
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
    String? createdPage,
    String? lastUpdatedPage,
    List<OrderItem>? items,
    bool? isInventoryReplenished,
    String? status,
    List<ManualReceiptLine>? manualReceiptLines,
    Timestamp? manualReceiptDate,
    Timestamp? manualReceiptRecordedAt,
    String? manualReceiptRecordedBy,
    String? manualReceiptRecordedByUid,
    bool? invoiceVerificationPending,
  }) {
    return Purchaseorder(
      poNumber: poNumber ?? this.poNumber,
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
      createdPage: createdPage ?? this.createdPage,
      lastUpdatedPage: lastUpdatedPage ?? this.lastUpdatedPage,
      items: items ?? this.items,
      isInventoryReplenished: isInventoryReplenished ?? this.isInventoryReplenished,
      status: status ?? this.status,
      manualReceiptLines: manualReceiptLines ?? this.manualReceiptLines,
      manualReceiptDate: manualReceiptDate ?? this.manualReceiptDate,
      manualReceiptRecordedAt: manualReceiptRecordedAt ?? this.manualReceiptRecordedAt,
      manualReceiptRecordedBy: manualReceiptRecordedBy ?? this.manualReceiptRecordedBy,
      manualReceiptRecordedByUid: manualReceiptRecordedByUid ?? this.manualReceiptRecordedByUid,
      invoiceVerificationPending: invoiceVerificationPending ?? this.invoiceVerificationPending,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'poNumber': poNumber,
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
      'createdPage': createdPage,
      'lastUpdatedPage': lastUpdatedPage,
      'items': items.map((e) => e.toJson()).toList(),
      'isInventoryReplenished': isInventoryReplenished,
      'status': status,
      'manualReceiptLines': manualReceiptLines.map((e) => e.toJson()).toList(),
      'manualReceiptDate': manualReceiptDate,
      'manualReceiptRecordedAt': manualReceiptRecordedAt,
      'manualReceiptRecordedBy': manualReceiptRecordedBy,
      'manualReceiptRecordedByUid': manualReceiptRecordedByUid,
      'invoiceVerificationPending': invoiceVerificationPending,
    };
  }
}
