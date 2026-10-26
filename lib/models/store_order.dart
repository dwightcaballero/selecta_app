import 'package:cloud_firestore/cloud_firestore.dart';

class StoreOrderStatus {
  static const String submitted = 'Submitted';
  static const String approved = 'Approved';
  static const String rejected = 'Rejected';
  static const String cancelled = 'Cancelled';
  static const String outForDelivery = 'Out for Delivery';
  static const String delivered = 'Delivered';

  static const List<String> all = [
    submitted,
    approved,
    outForDelivery,
    delivered,
    cancelled,
    rejected,
  ];

  static bool isTerminal(String status) =>
      status == delivered || status == cancelled || status == rejected;
}

class StoreOrderItem {
  final String productId;
  final String name;
  final String uom; // 'piece' | 'case'
  final int qty;
  final double unitPrice;
  final double lineTotal;
  final int qtyApproved;
  final String category;
  final String imageUrl;
  final String flavor;
  final int? piecesPerCase;

  const StoreOrderItem({
    required this.productId,
    String? name,
    String? productName,
    this.uom = 'piece',
    String? packaging,
    int? qty,
    int? qtyOrdered,
    required this.unitPrice,
    double? lineTotal,
    double? totalPrice,
    int? qtyApproved,
    this.category = '',
    this.imageUrl = '',
    this.flavor = '',
    this.piecesPerCase,
  })  : name = name ?? productName ?? '',
        qty = qty ?? qtyOrdered ?? 0,
        lineTotal = lineTotal ?? totalPrice ?? ((qty ?? qtyOrdered ?? 0) * unitPrice),
        qtyApproved = qtyApproved ?? (qty ?? qtyOrdered ?? 0);

  String get productName => name;
  String get packaging => uom;
  int get qtyOrdered => qty;
  int get effectiveQty => qtyApproved > 0 ? qtyApproved : qty;
  double get totalPrice => lineTotal;
  double get effectivePrice => (qtyApproved * unitPrice);

  StoreOrderItem copyWith({
    String? productId,
    String? name,
    String? uom,
    int? qty,
    double? unitPrice,
    double? lineTotal,
    int? qtyApproved,
    String? category,
    String? imageUrl,
  }) {
    return StoreOrderItem(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      uom: uom ?? this.uom,
      qty: qty ?? this.qty,
      unitPrice: unitPrice ?? this.unitPrice,
      lineTotal: lineTotal ?? this.lineTotal,
      qtyApproved: qtyApproved ?? this.qtyApproved,
      category: category ?? this.category,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  factory StoreOrderItem.fromJson(Map<String, dynamic> json) {
    final qty = (json['qty'] as num?)?.toInt() ?? 0;
    final unitPrice = (json['unitPrice'] as num?)?.toDouble() ?? 0.0;
    final lineTotal = (json['lineTotal'] as num?)?.toDouble() ?? (qty * unitPrice);
    final qtyApproved = (json['qtyApproved'] as num?)?.toInt() ?? qty;

    return StoreOrderItem(
      productId: json['productId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      uom: json['uom'] as String? ?? 'piece',
      qty: qty,
      unitPrice: unitPrice,
      lineTotal: lineTotal,
      qtyApproved: qtyApproved,
      category: json['category'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'name': name,
      'uom': uom,
      'qty': qty,
      'unitPrice': unitPrice,
      'lineTotal': lineTotal,
      'qtyApproved': qtyApproved,
      'category': category,
      'imageUrl': imageUrl,
    };
  }
}

class StoreOrderStatusHistory {
  final String status;
  final Timestamp at;
  final String byUid;
  final String byName;

  const StoreOrderStatusHistory({
    required this.status,
    required this.at,
    required this.byUid,
    required this.byName,
  });

  factory StoreOrderStatusHistory.fromJson(Map<String, dynamic> json) {
    final rawAt = json['at'];
    Timestamp at;
    if (rawAt is Timestamp) {
      at = rawAt;
    } else if (rawAt is DateTime) {
      at = Timestamp.fromDate(rawAt);
    } else {
      at = Timestamp.now();
    }

    return StoreOrderStatusHistory(
      status: json['status'] as String? ?? '',
      at: at,
      byUid: json['byUid'] as String? ?? '',
      byName: json['byName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'at': at,
      'byUid': byUid,
      'byName': byName,
    };
  }

  DateTime get timestamp => at.toDate();
  String? get note => byName.isNotEmpty ? byName : null;
}

class StoreOrder {
  final String id;
  final String orderNo;
  final String storeId;
  final String storeName;
  final String status;
  final List<StoreOrderItem> items;
  final double totalAmount;
  final double? approvedAmount;
  final Timestamp? deliveryDate;
  final String? remarks;
  final String? rejectReason;
  final String source;
  final String? deliveryId;
  final List<StoreOrderStatusHistory> statusHistory;
  final String createdBy;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const StoreOrder({
    required this.id,
    required this.orderNo,
    required this.storeId,
    required this.storeName,
    required this.status,
    required this.items,
    required this.totalAmount,
    this.approvedAmount,
    this.deliveryDate,
    this.remarks,
    this.rejectReason,
    this.source = 'store',
    this.deliveryId,
    this.statusHistory = const [],
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  String get orderNumber => orderNo;
  double get estimatedTotal => totalAmount;
  double? get approvedTotal => approvedAmount;
  String? get rejectionReason => rejectReason;

  bool get isSubmitted => status == StoreOrderStatus.submitted;
  bool get isApproved => status == StoreOrderStatus.approved;
  bool get isOutForDelivery => status == StoreOrderStatus.outForDelivery;
  bool get isDelivered => status == StoreOrderStatus.delivered;
  bool get isCancelled => status == StoreOrderStatus.cancelled;
  bool get isRejected => status == StoreOrderStatus.rejected;

  /// Effective total amount to show: approved amount once approved/delivered, or estimated total amount.
  double get effectiveAmount => (approvedAmount != null && approvedAmount! > 0) ? approvedAmount! : totalAmount;

  /// Total count of individual item units ordered.
  int get totalQuantity => items.fold(0, (acc, item) => acc + item.qty);

  /// Total count of approved item units.
  int get totalApprovedQuantity => items.fold(0, (acc, item) => acc + item.qtyApproved);

  StoreOrder copyWith({
    String? id,
    String? orderNo,
    String? storeId,
    String? storeName,
    String? status,
    List<StoreOrderItem>? items,
    double? totalAmount,
    double? approvedAmount,
    bool clearApprovedAmount = false,
    Timestamp? deliveryDate,
    bool clearDeliveryDate = false,
    String? remarks,
    String? rejectReason,
    String? source,
    String? deliveryId,
    bool clearDeliveryId = false,
    List<StoreOrderStatusHistory>? statusHistory,
    String? createdBy,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return StoreOrder(
      id: id ?? this.id,
      orderNo: orderNo ?? this.orderNo,
      storeId: storeId ?? this.storeId,
      storeName: storeName ?? this.storeName,
      status: status ?? this.status,
      items: items ?? this.items,
      totalAmount: totalAmount ?? this.totalAmount,
      approvedAmount: clearApprovedAmount ? null : (approvedAmount ?? this.approvedAmount),
      deliveryDate: clearDeliveryDate ? null : (deliveryDate ?? this.deliveryDate),
      remarks: remarks ?? this.remarks,
      rejectReason: rejectReason ?? this.rejectReason,
      source: source ?? this.source,
      deliveryId: clearDeliveryId ? null : (deliveryId ?? this.deliveryId),
      statusHistory: statusHistory ?? this.statusHistory,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory StoreOrder.fromJson(Map<String, dynamic> json, {String? id, String? docId}) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    final items = rawItems
        .map((i) => StoreOrderItem.fromJson(Map<String, dynamic>.from(i as Map)))
        .toList();

    final rawHistory = json['statusHistory'] as List<dynamic>? ?? [];
    final history = rawHistory
        .map((h) => StoreOrderStatusHistory.fromJson(Map<String, dynamic>.from(h as Map)))
        .toList();

    Timestamp parseTs(dynamic val) {
      if (val is Timestamp) return val;
      if (val is DateTime) return Timestamp.fromDate(val);
      return Timestamp.now();
    }

    Timestamp? parseNullableTs(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val;
      if (val is DateTime) return Timestamp.fromDate(val);
      return null;
    }

    final effectiveId = id ?? docId ?? (json['id'] as String?) ?? '';

    return StoreOrder(
      id: effectiveId,
      orderNo: json['orderNo'] as String? ?? '',
      storeId: json['storeId'] as String? ?? '',
      storeName: json['storeName'] as String? ?? '',
      status: json['status'] as String? ?? StoreOrderStatus.submitted,
      items: items,
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
      approvedAmount: (json['approvedAmount'] as num?)?.toDouble(),
      deliveryDate: parseNullableTs(json['deliveryDate']),
      remarks: json['remarks'] as String?,
      rejectReason: json['rejectReason'] as String?,
      source: json['source'] as String? ?? 'store',
      deliveryId: json['deliveryId'] as String?,
      statusHistory: history,
      createdBy: json['createdBy'] as String? ?? '',
      createdAt: parseTs(json['createdAt']),
      updatedAt: parseTs(json['updatedAt']),
    );
  }

  factory StoreOrder.fromSnapshot(DocumentSnapshot doc) {
    return StoreOrder.fromJson(
      Map<String, dynamic>.from((doc.data() as Map?) ?? {}),
      id: doc.id,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'orderNo': orderNo,
      'storeId': storeId,
      'storeName': storeName,
      'status': status,
      'items': items.map((i) => i.toJson()).toList(),
      'totalAmount': totalAmount,
      'approvedAmount': approvedAmount,
      'deliveryDate': deliveryDate,
      'remarks': remarks,
      'rejectReason': rejectReason,
      'source': source,
      'deliveryId': deliveryId,
      'statusHistory': statusHistory.map((h) => h.toJson()).toList(),
      'createdBy': createdBy,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
