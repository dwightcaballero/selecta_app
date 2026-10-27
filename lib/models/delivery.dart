import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/placement.dart';
import 'package:selecta_ops/models/promo.dart';

int? _parseInt(dynamic val) {
  if (val == null) return null;
  if (val is num) return val.toInt();
  if (val is String) return int.tryParse(val.trim());
  return null;
}

double _parseDouble(dynamic val, [double fallback = 0.0]) {
  if (val == null) return fallback;
  if (val is num) return val.toDouble();
  if (val is String) return double.tryParse(val.trim()) ?? fallback;
  return fallback;
}

double? _parseDoubleNullable(dynamic val) {
  if (val == null) return null;
  if (val is num) return val.toDouble();
  if (val is String) return double.tryParse(val.trim());
  return null;
}

bool _parseBool(dynamic val, [bool fallback = false]) {
  if (val == null) return fallback;
  if (val is bool) return val;
  if (val is num) return val != 0;
  if (val is String) {
    final lower = val.trim().toLowerCase();
    if (lower == 'true' || lower == '1') return true;
    if (lower == 'false' || lower == '0') return false;
  }
  return fallback;
}

Timestamp? _parseTimestamp(dynamic val) {
  if (val == null) return null;
  if (val is Timestamp) return val;
  if (val is DateTime) return Timestamp.fromDate(val);
  if (val is String) {
    final dt = DateTime.tryParse(val.trim());
    if (dt != null) return Timestamp.fromDate(dt);
  }
  return null;
}

/// Represents a single ordered / picked product line item within a unified Order-Delivery record.
class OrderItem {
  final String productId;
  final String productName;
  final String imageUrl;
  final String barcode;
  final String productSource; // 'selecta' | 'other'
  final String category; // 'By Piece' | 'By Case' (for Selecta)
  final String tag; // 'Best Seller' | 'New Product' | ''
  final double buyingPrice;
  final double sellingPrice;
  final int orderedQuantity;
  final int pickedQuantity;
  final int returnedQuantity;
  final bool isPicked;
  final String? promoId; // ID of the promo if part of or rewarded by a promo
  final bool isFreeReward; // True if this line item is a free reward item

  const OrderItem({
    required this.productId,
    required this.productName,
    this.imageUrl = '',
    this.barcode = '',
    this.productSource = 'selecta',
    this.category = '',
    this.tag = '',
    this.buyingPrice = 0.0,
    required this.sellingPrice,
    required this.orderedQuantity,
    int? pickedQuantity,
    this.returnedQuantity = 0,
    this.isPicked = false,
    this.promoId,
    this.isFreeReward = false,
  }) : pickedQuantity = pickedQuantity ?? orderedQuantity;

  /// Effective quantity used for order totals (pickedQuantity when > 0, or orderedQuantity).
  int get effectiveQuantity => pickedQuantity;

  /// Net delivered quantity after deducting returns.
  int get deliveredQuantity => (pickedQuantity - returnedQuantity).clamp(0, pickedQuantity);

  /// Total selling price for this line item based on pickedQuantity.
  double get lineTotal => pickedQuantity * sellingPrice;

  /// Total selling price for only the delivered portion.
  double get deliveredLineTotal => deliveredQuantity * sellingPrice;

  /// Total value of returned units for this line item.
  double get returnedLineTotal => returnedQuantity * sellingPrice;

  /// Total buying cost for this line item based on pickedQuantity.
  double get lineCost => pickedQuantity * buyingPrice;

  OrderItem copyWith({
    String? productId,
    String? productName,
    String? imageUrl,
    String? barcode,
    String? productSource,
    String? category,
    String? tag,
    double? buyingPrice,
    double? sellingPrice,
    int? orderedQuantity,
    int? pickedQuantity,
    int? returnedQuantity,
    bool? isPicked,
    String? promoId,
    bool? isFreeReward,
  }) {
    return OrderItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      imageUrl: imageUrl ?? this.imageUrl,
      barcode: barcode ?? this.barcode,
      productSource: productSource ?? this.productSource,
      category: category ?? this.category,
      tag: tag ?? this.tag,
      buyingPrice: buyingPrice ?? this.buyingPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      orderedQuantity: orderedQuantity ?? this.orderedQuantity,
      pickedQuantity: pickedQuantity ?? this.pickedQuantity,
      returnedQuantity: returnedQuantity ?? this.returnedQuantity,
      isPicked: isPicked ?? this.isPicked,
      promoId: promoId ?? this.promoId,
      isFreeReward: isFreeReward ?? this.isFreeReward,
    );
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final orderedQty = _parseInt(json['orderedQuantity']) ?? 0;
    final pickedQty = _parseInt(json['pickedQuantity']) ?? orderedQty;
    final returnedQty = _parseInt(json['returnedQuantity']) ?? 0;
    return OrderItem(
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      barcode: (json['barcode'] as String? ?? '').trim(),
      productSource: json['productSource'] as String? ?? 'selecta',
      category: json['category'] as String? ?? '',
      tag: (json['tag'] as String? ?? '').trim(),
      buyingPrice: _parseDouble(json['buyingPrice']),
      sellingPrice: _parseDouble(json['sellingPrice']),
      orderedQuantity: orderedQty,
      pickedQuantity: pickedQty,
      returnedQuantity: returnedQty,
      isPicked: _parseBool(json['isPicked']),
      promoId: json['promoId']?.toString(),
      isFreeReward: _parseBool(json['isFreeReward'], false),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'imageUrl': imageUrl,
      'barcode': barcode,
      'productSource': productSource,
      'category': category,
      'tag': tag,
      'buyingPrice': buyingPrice,
      'sellingPrice': sellingPrice,
      'orderedQuantity': orderedQuantity,
      'pickedQuantity': pickedQuantity,
      'returnedQuantity': returnedQuantity,
      'isPicked': isPicked,
      'promoId': promoId,
      'isFreeReward': isFreeReward,
    };
  }
}

class Delivery {
  String storeName;
  String remarks;
  String transactionStatus;
  String imagePath;

  double orderAmount;
  double? originalOrderAmount;
  double? grossAmount;
  double discountAmount;
  List<AppliedPromo> appliedPromos;
  double cashAmount;
  double onlineAmount;
  double creditAmount;
  double returnAmount;
  String creditStatus;
  Timestamp? deliveryDate;
  String orderType; // 'pre-sell' | 'van-sell'
  String? vanLoadId;

  List<OrderItem> items;
  bool isInventoryReserved;
  bool isInventoryDeducted;
  bool isInventorySettled;
  Timestamp? inventorySettledDate;
  String inventorySettledBy;
  bool isReturnApprovedByDealer;
  Timestamp? returnApprovedDate;
  String returnApprovedBy;
  bool isReturnIncoming;
  bool isRescheduled;
  String rescheduledToDeliveryId;
  Timestamp? rescheduledDate;
  bool isReturnFinalized;
  Timestamp? returnFinalizedDate;
  String returnFinalizedBy;
  Timestamp? picklistCompletedDate;
  String picklistCompletedBy;
  int? picklistSequence;
  int? deliverySequence;
  String? voidReason;
  Timestamp? voidedDate;
  String? voidedBy;

  String? source;
  String? storeOrderId;

  String returnProofStatus;
  String returnProofId;
  String returnProofUrl;
  String returnProofNotes;
  String returnProofSubmittedBy;
  Timestamp? returnProofSubmittedDate;
  String returnProofConfirmedBy;
  Timestamp? returnProofConfirmedDate;
  String returnProofRejectReason;
  bool returnProofRequired;

  String createdBy;
  String lastUpdatedBy;
  Timestamp createdDate;
  Timestamp lastupdatedDate;
  String createdPage;
  String lastUpdatedPage;

  Placement? placement;

  Delivery({
    required this.storeName,
    required this.remarks,
    required this.transactionStatus,
    required this.imagePath,
    required this.orderAmount,
    this.originalOrderAmount,
    this.grossAmount,
    this.discountAmount = 0.0,
    this.appliedPromos = const [],
    required this.returnAmount,
    required this.creditAmount,
    required this.cashAmount,
    required this.onlineAmount,
    required this.deliveryDate,
    required this.creditStatus,
    this.orderType = OrderType.preSell,
    this.vanLoadId,
    required this.createdBy,
    required this.lastUpdatedBy,
    required this.createdDate,
    required this.lastupdatedDate,
    this.createdPage = '',
    this.lastUpdatedPage = '',
    this.items = const [],
    this.isInventoryReserved = false,
    this.isInventoryDeducted = false,
    this.isInventorySettled = false,
    this.inventorySettledDate,
    this.inventorySettledBy = '',
    this.isReturnApprovedByDealer = false,
    this.returnApprovedDate,
    this.returnApprovedBy = '',
    this.isReturnIncoming = false,
    this.isRescheduled = false,
    this.rescheduledToDeliveryId = '',
    this.rescheduledDate,
    this.isReturnFinalized = false,
    this.returnFinalizedDate,
    this.returnFinalizedBy = '',
    this.picklistCompletedDate,
    this.picklistCompletedBy = '',
    this.picklistSequence,
    this.deliverySequence,
    this.voidReason,
    this.voidedDate,
    this.voidedBy,
    this.source,
    this.storeOrderId,
    this.returnProofStatus = ReturnProofStatus.none,
    this.returnProofId = '',
    this.returnProofUrl = '',
    this.returnProofNotes = '',
    this.returnProofSubmittedBy = '',
    this.returnProofSubmittedDate,
    this.returnProofConfirmedBy = '',
    this.returnProofConfirmedDate,
    this.returnProofRejectReason = '',
    this.returnProofRequired = false,
  });

  /// True if this order/delivery has been voided.
  bool get isVoided => transactionStatus == DeliveryStatus.voided;

  /// True if this order/delivery is a van sale.
  bool get isVanSell => orderType == OrderType.vanSell;

  /// Total number of units across all ordered/picked items.
  int get totalUnits => items.fold<int>(0, (totalUnitsAcc, item) => totalUnitsAcc + item.pickedQuantity);

  /// Total number of Selecta product SKUs in this order.
  int get selectaItemCount => items.where((i) => i.productSource == 'selecta').length;

  /// Total number of Other product SKUs in this order.
  int get otherItemCount => items.where((i) => i.productSource == 'other').length;

  /// True if any items in this delivery have returned quantities recorded.
  bool get hasReturnedItems => items.any((i) => i.returnedQuantity > 0);

  /// Total monetary value of returned products for this delivery.
  double get totalReturnedItemsAmount => items.fold<double>(0.0, (acc, i) => acc + i.returnedLineTotal);

  static Delivery empty() => Delivery(
    storeName: '',
    remarks: '',
    transactionStatus: '',
    imagePath: '',
    orderAmount: 0,
    originalOrderAmount: null,
    grossAmount: null,
    discountAmount: 0.0,
    appliedPromos: const [],
    returnAmount: 0,
    creditAmount: 0,
    cashAmount: 0,
    onlineAmount: 0,
    deliveryDate: null,
    creditStatus: '',
    orderType: OrderType.preSell,
    vanLoadId: null,
    createdBy: '',
    lastUpdatedBy: '',
    createdDate: Timestamp.now(),
    lastupdatedDate: Timestamp.now(),
    createdPage: '',
    lastUpdatedPage: '',
    items: const [],
    isInventoryReserved: false,
    isInventoryDeducted: false,
    isInventorySettled: false,
    inventorySettledDate: null,
    inventorySettledBy: '',
    isReturnApprovedByDealer: false,
    returnApprovedDate: null,
    returnApprovedBy: '',
    isReturnIncoming: false,
    isRescheduled: false,
    rescheduledToDeliveryId: '',
    rescheduledDate: null,
    isReturnFinalized: false,
    returnFinalizedDate: null,
    returnFinalizedBy: '',
    picklistCompletedDate: null,
    picklistCompletedBy: '',
    picklistSequence: null,
    deliverySequence: null,
    voidReason: null,
    voidedDate: null,
    voidedBy: null,
    source: null,
    storeOrderId: null,
    returnProofStatus: ReturnProofStatus.none,
    returnProofId: '',
    returnProofUrl: '',
    returnProofNotes: '',
    returnProofSubmittedBy: '',
    returnProofSubmittedDate: null,
    returnProofConfirmedBy: '',
    returnProofConfirmedDate: null,
    returnProofRejectReason: '',
    returnProofRequired: false,
  );

  static List<OrderItem> _parseItems(Object? raw) {
    if (raw is List) {
      final list = raw.whereType<Map>().map((e) => OrderItem.fromJson(Map<String, dynamic>.from(e))).toList();
      list.sort((a, b) => Helperfunctions.compareProducts(
            nameA: a.productName,
            priceA: a.sellingPrice,
            nameB: b.productName,
            priceB: b.sellingPrice,
            productIdA: a.productId,
            productIdB: b.productId,
            categoryA: a.category,
            categoryB: b.category,
          ));
      return list;
    }
    return const [];
  }

  Delivery.fromJson(Map<String, Object?> json)
    : this(
        storeName: json['storeName'] as String? ?? '',
        remarks: json['remarks'] as String? ?? '',
        transactionStatus: json['transactionStatus'] as String? ?? '',
        imagePath: json['imagePath'] as String? ?? '',
        orderAmount: _parseDouble(json['orderAmount']),
        originalOrderAmount: _parseDoubleNullable(json['originalOrderAmount']),
        grossAmount: _parseDoubleNullable(json['grossAmount']),
        discountAmount: _parseDouble(json['discountAmount']),
        appliedPromos: (json['appliedPromos'] as List<dynamic>?)
                ?.map((e) => AppliedPromo.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        returnAmount: _parseDouble(json['returnAmount']),
        creditAmount: _parseDouble(json['creditAmount']),
        cashAmount: _parseDouble(json['cashAmount']),
        onlineAmount: _parseDouble(json['onlineAmount']),
        deliveryDate: _parseTimestamp(json['deliveryDate']),
        creditStatus: json['creditStatus'] as String? ?? '',
        orderType: json['orderType'] as String? ?? OrderType.preSell,
        vanLoadId: json['vanLoadId'] as String?,
        createdBy: json['createdBy'] as String? ?? '',
        lastUpdatedBy: json['lastUpdatedBy'] as String? ?? '',
        createdDate: _parseTimestamp(json['createdDate']) ?? Timestamp.now(),
        lastupdatedDate: _parseTimestamp(json['lastupdatedDate']) ?? Timestamp.now(),
        createdPage: json['createdPage'] as String? ?? '',
        lastUpdatedPage: json['lastUpdatedPage'] as String? ?? '',
        items: _parseItems(json['items']),
        isInventoryReserved: _parseBool(json['isInventoryReserved']),
        isInventoryDeducted: _parseBool(json['isInventoryDeducted']),
        isInventorySettled: _parseBool(json['isInventorySettled']),
        inventorySettledDate: _parseTimestamp(json['inventorySettledDate']),
        inventorySettledBy: json['inventorySettledBy'] as String? ?? '',
        isReturnApprovedByDealer: _parseBool(json['isReturnApprovedByDealer']),
        returnApprovedDate: _parseTimestamp(json['returnApprovedDate']),
        returnApprovedBy: json['returnApprovedBy'] as String? ?? '',
        isReturnIncoming: _parseBool(json['isReturnIncoming']),
        isRescheduled: _parseBool(json['isRescheduled']),
        rescheduledToDeliveryId: json['rescheduledToDeliveryId'] as String? ?? '',
        rescheduledDate: _parseTimestamp(json['rescheduledDate']),
        isReturnFinalized: _parseBool(json['isReturnFinalized']),
        returnFinalizedDate: _parseTimestamp(json['returnFinalizedDate']),
        returnFinalizedBy: json['returnFinalizedBy'] as String? ?? '',
        picklistCompletedDate: _parseTimestamp(json['picklistCompletedDate']),
        picklistCompletedBy: json['picklistCompletedBy'] as String? ?? '',
        picklistSequence: _parseInt(json['picklistSequence']),
        deliverySequence: _parseInt(json['deliverySequence']),
        voidReason: json['voidReason'] as String?,
        voidedDate: _parseTimestamp(json['voidedDate']),
        voidedBy: json['voidedBy'] as String?,
        source: json['source'] as String?,
        storeOrderId: json['storeOrderId'] as String?,
        returnProofStatus: (json['returnProofStatus'] as String? ?? ReturnProofStatus.none).trim(),
        returnProofId: (json['returnProofId'] as String? ?? '').trim(),
        returnProofUrl: (json['returnProofUrl'] as String? ?? '').trim(),
        returnProofNotes: (json['returnProofNotes'] as String? ?? '').trim(),
        returnProofSubmittedBy: (json['returnProofSubmittedBy'] as String? ?? '').trim(),
        returnProofSubmittedDate: _parseTimestamp(json['returnProofSubmittedDate']),
        returnProofConfirmedBy: (json['returnProofConfirmedBy'] as String? ?? '').trim(),
        returnProofConfirmedDate: _parseTimestamp(json['returnProofConfirmedDate']),
        returnProofRejectReason: (json['returnProofRejectReason'] as String? ?? '').trim(),
        returnProofRequired: _parseBool(json['returnProofRequired']),
      );

  factory Delivery.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      return Delivery.fromJson(document.data()!.cast<String, Object?>());
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
    double? originalOrderAmount,
    double? grossAmount,
    double? discountAmount,
    List<AppliedPromo>? appliedPromos,
    double? deliveryAmount,
    double? returnAmount,
    double? creditAmount,
    String? creditStatus,
    String? orderType,
    String? vanLoadId,
    double? cashAmount,
    double? onlineAmount,
    Timestamp? deliveryDate,
    List<OrderItem>? items,
    bool? isInventoryReserved,
    bool? isInventoryDeducted,
    bool? isInventorySettled,
    Timestamp? inventorySettledDate,
    String? inventorySettledBy,
    bool? isReturnApprovedByDealer,
    Timestamp? returnApprovedDate,
    String? returnApprovedBy,
    bool? isReturnIncoming,
    bool? isRescheduled,
    String? rescheduledToDeliveryId,
    Timestamp? rescheduledDate,
    bool? isReturnFinalized,
    Timestamp? returnFinalizedDate,
    String? returnFinalizedBy,
    Timestamp? picklistCompletedDate,
    String? picklistCompletedBy,
    int? picklistSequence,
    bool clearPicklistSequence = false,
    int? deliverySequence,
    bool clearDeliverySequence = false,
    String? voidReason,
    Timestamp? voidedDate,
    String? voidedBy,
    String? createdBy,
    String? lastUpdatedBy,
    Timestamp? createdDate,
    Timestamp? lastupdatedDate,
    String? createdPage,
    String? lastUpdatedPage,
    String? source,
    String? storeOrderId,
    String? returnProofStatus,
    String? returnProofId,
    String? returnProofUrl,
    String? returnProofNotes,
    String? returnProofSubmittedBy,
    Timestamp? returnProofSubmittedDate,
    String? returnProofConfirmedBy,
    Timestamp? returnProofConfirmedDate,
    String? returnProofRejectReason,
    bool? returnProofRequired,
  }) {
    return Delivery(
      storeName: storeName ?? this.storeName,
      remarks: remarks ?? this.remarks,
      transactionStatus: transactionStatus ?? this.transactionStatus,
      imagePath: imagePath ?? this.imagePath,
      orderAmount: orderAmount ?? this.orderAmount,
      originalOrderAmount: originalOrderAmount ?? this.originalOrderAmount,
      grossAmount: grossAmount ?? this.grossAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      appliedPromos: appliedPromos ?? this.appliedPromos,
      returnAmount: returnAmount ?? this.returnAmount,
      creditAmount: creditAmount ?? this.creditAmount,
      cashAmount: cashAmount ?? this.cashAmount,
      onlineAmount: onlineAmount ?? this.onlineAmount,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      creditStatus: creditStatus ?? this.creditStatus,
      orderType: orderType ?? this.orderType,
      vanLoadId: vanLoadId ?? this.vanLoadId,
      items: items ?? this.items,
      isInventoryReserved: isInventoryReserved ?? this.isInventoryReserved,
      isInventoryDeducted: isInventoryDeducted ?? this.isInventoryDeducted,
      isInventorySettled: isInventorySettled ?? this.isInventorySettled,
      inventorySettledDate: inventorySettledDate ?? this.inventorySettledDate,
      inventorySettledBy: inventorySettledBy ?? this.inventorySettledBy,
      isReturnApprovedByDealer: isReturnApprovedByDealer ?? this.isReturnApprovedByDealer,
      returnApprovedDate: returnApprovedDate ?? this.returnApprovedDate,
      returnApprovedBy: returnApprovedBy ?? this.returnApprovedBy,
      isReturnIncoming: isReturnIncoming ?? this.isReturnIncoming,
      isRescheduled: isRescheduled ?? this.isRescheduled,
      rescheduledToDeliveryId: rescheduledToDeliveryId ?? this.rescheduledToDeliveryId,
      rescheduledDate: rescheduledDate ?? this.rescheduledDate,
      isReturnFinalized: isReturnFinalized ?? this.isReturnFinalized,
      returnFinalizedDate: returnFinalizedDate ?? this.returnFinalizedDate,
      returnFinalizedBy: returnFinalizedBy ?? this.returnFinalizedBy,
      picklistCompletedDate: picklistCompletedDate ?? this.picklistCompletedDate,
      picklistCompletedBy: picklistCompletedBy ?? this.picklistCompletedBy,
      picklistSequence: clearPicklistSequence ? null : (picklistSequence ?? this.picklistSequence),
      deliverySequence: clearDeliverySequence ? null : (deliverySequence ?? this.deliverySequence),
      voidReason: voidReason ?? this.voidReason,
      voidedDate: voidedDate ?? this.voidedDate,
      voidedBy: voidedBy ?? this.voidedBy,
      createdBy: createdBy ?? this.createdBy,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
      createdDate: createdDate ?? this.createdDate,
      lastupdatedDate: lastupdatedDate ?? this.lastupdatedDate,
      createdPage: createdPage ?? this.createdPage,
      lastUpdatedPage: lastUpdatedPage ?? this.lastUpdatedPage,
      source: source ?? this.source,
      storeOrderId: storeOrderId ?? this.storeOrderId,
      returnProofStatus: returnProofStatus ?? this.returnProofStatus,
      returnProofId: returnProofId ?? this.returnProofId,
      returnProofUrl: returnProofUrl ?? this.returnProofUrl,
      returnProofNotes: returnProofNotes ?? this.returnProofNotes,
      returnProofSubmittedBy: returnProofSubmittedBy ?? this.returnProofSubmittedBy,
      returnProofSubmittedDate: returnProofSubmittedDate ?? this.returnProofSubmittedDate,
      returnProofConfirmedBy: returnProofConfirmedBy ?? this.returnProofConfirmedBy,
      returnProofConfirmedDate: returnProofConfirmedDate ?? this.returnProofConfirmedDate,
      returnProofRejectReason: returnProofRejectReason ?? this.returnProofRejectReason,
      returnProofRequired: returnProofRequired ?? this.returnProofRequired,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'storeName': storeName,
      'remarks': remarks,
      'transactionStatus': transactionStatus,
      'imagePath': imagePath,
      'orderAmount': orderAmount,
      'originalOrderAmount': originalOrderAmount,
      'grossAmount': grossAmount,
      'discountAmount': discountAmount,
      'appliedPromos': appliedPromos.map((e) => e.toJson()).toList(),
      'returnAmount': returnAmount,
      'creditAmount': creditAmount,
      'cashAmount': cashAmount,
      'onlineAmount': onlineAmount,
      'deliveryDate': deliveryDate,
      'creditStatus': creditStatus,
      'orderType': orderType,
      'vanLoadId': vanLoadId,
      'items': items.map((e) => e.toJson()).toList(),
      'isInventoryReserved': isInventoryReserved,
      'isInventoryDeducted': isInventoryDeducted,
      'isInventorySettled': isInventorySettled,
      'inventorySettledDate': inventorySettledDate,
      'inventorySettledBy': inventorySettledBy,
      'isReturnApprovedByDealer': isReturnApprovedByDealer,
      'returnApprovedDate': returnApprovedDate,
      'returnApprovedBy': returnApprovedBy,
      'isReturnIncoming': isReturnIncoming,
      'isRescheduled': isRescheduled,
      'rescheduledToDeliveryId': rescheduledToDeliveryId,
      'rescheduledDate': rescheduledDate,
      'isReturnFinalized': isReturnFinalized,
      'returnFinalizedDate': returnFinalizedDate,
      'returnFinalizedBy': returnFinalizedBy,
      'picklistCompletedDate': picklistCompletedDate,
      'picklistCompletedBy': picklistCompletedBy,
      'picklistSequence': picklistSequence,
      'deliverySequence': deliverySequence,
      'voidReason': voidReason,
      'voidedDate': voidedDate,
      'voidedBy': voidedBy,
      'createdBy': createdBy,
      'lastUpdatedBy': lastUpdatedBy,
      'createdDate': createdDate,
      'lastupdatedDate': lastupdatedDate,
      'createdPage': createdPage,
      'lastUpdatedPage': lastUpdatedPage,
      'returnProofStatus': returnProofStatus,
      'returnProofId': returnProofId,
      'returnProofUrl': returnProofUrl,
      'returnProofNotes': returnProofNotes,
      'returnProofSubmittedBy': returnProofSubmittedBy,
      'returnProofSubmittedDate': returnProofSubmittedDate,
      'returnProofConfirmedBy': returnProofConfirmedBy,
      'returnProofConfirmedDate': returnProofConfirmedDate,
      'returnProofRejectReason': returnProofRejectReason,
      'returnProofRequired': returnProofRequired,
      if (source != null) 'source': source,
      if (storeOrderId != null) 'storeOrderId': storeOrderId,
    };
  }
}

class DeliveryModelString {
  static String storeName = 'storeName';
  static String picklistSequence = 'picklistSequence';
  static String deliverySequence = 'deliverySequence';
  static String remarks = 'remarks';
  static String transactionStatus = 'transactionStatus';
  static String imagePath = 'imagePath';
  static String orderAmount = 'orderAmount';
  static String originalOrderAmount = 'originalOrderAmount';
  static String grossAmount = 'grossAmount';
  static String discountAmount = 'discountAmount';
  static String appliedPromos = 'appliedPromos';
  static String returnAmount = 'returnAmount';
  static String creditAmount = 'creditAmount';
  static String cashAmount = 'cashAmount';
  static String onlineAmount = 'onlineAmount';
  static String deliveryDate = 'deliveryDate';
  static String creditStatus = 'creditStatus';
  static String orderType = 'orderType';
  static String vanLoadId = 'vanLoadId';
  static String items = 'items';
  static String isInventoryReserved = 'isInventoryReserved';
  static String isInventoryDeducted = 'isInventoryDeducted';
  static String isInventorySettled = 'isInventorySettled';
  static String inventorySettledDate = 'inventorySettledDate';
  static String inventorySettledBy = 'inventorySettledBy';
  static String isReturnApprovedByDealer = 'isReturnApprovedByDealer';
  static String returnApprovedDate = 'returnApprovedDate';
  static String returnApprovedBy = 'returnApprovedBy';
  static String isReturnIncoming = 'isReturnIncoming';
  static String isRescheduled = 'isRescheduled';
  static String rescheduledToDeliveryId = 'rescheduledToDeliveryId';
  static String rescheduledDate = 'rescheduledDate';
  static String isReturnFinalized = 'isReturnFinalized';
  static String returnFinalizedDate = 'returnFinalizedDate';
  static String returnFinalizedBy = 'returnFinalizedBy';
  static String voidReason = 'voidReason';
  static String voidedDate = 'voidedDate';
  static String voidedBy = 'voidedBy';
  static String source = 'source';
  static String storeOrderId = 'storeOrderId';

  static String returnProofStatus = 'returnProofStatus';
  static String returnProofId = 'returnProofId';
  static String returnProofUrl = 'returnProofUrl';
  static String returnProofNotes = 'returnProofNotes';
  static String returnProofSubmittedBy = 'returnProofSubmittedBy';
  static String returnProofSubmittedDate = 'returnProofSubmittedDate';
  static String returnProofConfirmedBy = 'returnProofConfirmedBy';
  static String returnProofConfirmedDate = 'returnProofConfirmedDate';
  static String returnProofRejectReason = 'returnProofRejectReason';
  static String returnProofRequired = 'returnProofRequired';

  static String createdBy = 'createdBy';
  static String lastUpdatedBy = 'lastUpdatedBy';
  static String createdDate = 'createdDate';
  static String lastupdatedDate = 'lastupdatedDate';
  static String createdPage = 'createdPage';
  static String lastUpdatedPage = 'lastUpdatedPage';
}
