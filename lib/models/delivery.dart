import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/placement.dart';

/// Represents a single ordered / picked product line item within a unified Order-Delivery record.
class OrderItem {
  final String productId;
  final String productName;
  final String imageUrl;
  final String productSource; // 'selecta' | 'other'
  final String category; // 'By Piece' | 'By Case' (for Selecta)
  final String tag; // 'Best Seller' | 'New Product' | ''
  final double buyingPrice;
  final double sellingPrice;
  final int orderedQuantity;
  final int pickedQuantity;
  final bool isPicked;

  const OrderItem({
    required this.productId,
    required this.productName,
    this.imageUrl = '',
    this.productSource = 'selecta',
    this.category = '',
    this.tag = '',
    this.buyingPrice = 0.0,
    required this.sellingPrice,
    required this.orderedQuantity,
    int? pickedQuantity,
    this.isPicked = false,
  }) : pickedQuantity = pickedQuantity ?? orderedQuantity;

  /// Effective quantity used for order totals (pickedQuantity when > 0, or orderedQuantity).
  int get effectiveQuantity => pickedQuantity;

  /// Total selling price for this line item based on pickedQuantity.
  double get lineTotal => pickedQuantity * sellingPrice;

  /// Total buying cost for this line item based on pickedQuantity.
  double get lineCost => pickedQuantity * buyingPrice;

  OrderItem copyWith({
    String? productId,
    String? productName,
    String? imageUrl,
    String? productSource,
    String? category,
    String? tag,
    double? buyingPrice,
    double? sellingPrice,
    int? orderedQuantity,
    int? pickedQuantity,
    bool? isPicked,
  }) {
    return OrderItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      imageUrl: imageUrl ?? this.imageUrl,
      productSource: productSource ?? this.productSource,
      category: category ?? this.category,
      tag: tag ?? this.tag,
      buyingPrice: buyingPrice ?? this.buyingPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      orderedQuantity: orderedQuantity ?? this.orderedQuantity,
      pickedQuantity: pickedQuantity ?? this.pickedQuantity,
      isPicked: isPicked ?? this.isPicked,
    );
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final orderedQty = (json['orderedQuantity'] as num?)?.toInt() ?? 0;
    final pickedQty = (json['pickedQuantity'] as num?)?.toInt() ?? orderedQty;
    return OrderItem(
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      productSource: json['productSource'] as String? ?? 'selecta',
      category: json['category'] as String? ?? '',
      tag: (json['tag'] as String? ?? '').trim(),
      buyingPrice: (json['buyingPrice'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (json['sellingPrice'] as num?)?.toDouble() ?? 0.0,
      orderedQuantity: orderedQty,
      pickedQuantity: pickedQty,
      isPicked: json['isPicked'] as bool? ?? false,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'imageUrl': imageUrl,
      'productSource': productSource,
      'category': category,
      'tag': tag,
      'buyingPrice': buyingPrice,
      'sellingPrice': sellingPrice,
      'orderedQuantity': orderedQuantity,
      'pickedQuantity': pickedQuantity,
      'isPicked': isPicked,
    };
  }
}

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

  List<OrderItem> items;
  bool isInventoryReserved;
  bool isInventoryDeducted;
  Timestamp? picklistCompletedDate;
  String picklistCompletedBy;
  int? picklistSequence;
  int? deliverySequence;

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
    this.createdPage = '',
    this.lastUpdatedPage = '',
    this.items = const [],
    this.isInventoryReserved = false,
    this.isInventoryDeducted = false,
    this.picklistCompletedDate,
    this.picklistCompletedBy = '',
    this.picklistSequence,
    this.deliverySequence,
  });

  /// Total number of units across all ordered/picked items.
  int get totalUnits => items.fold<int>(0, (totalUnitsAcc, item) => totalUnitsAcc + item.pickedQuantity);

  /// Total number of Selecta product SKUs in this order.
  int get selectaItemCount => items.where((i) => i.productSource == 'selecta').length;

  /// Total number of Other product SKUs in this order.
  int get otherItemCount => items.where((i) => i.productSource == 'other').length;

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
    createdPage: '',
    lastUpdatedPage: '',
    items: const [],
    isInventoryReserved: false,
    isInventoryDeducted: false,
    picklistCompletedDate: null,
    picklistCompletedBy: '',
    picklistSequence: null,
    deliverySequence: null,
  );

  static List<OrderItem> _parseItems(Object? raw) {
    if (raw is List) {
      final list = raw.whereType<Map>().map((e) => OrderItem.fromJson(Map<String, dynamic>.from(e))).toList();
      list.sort((a, b) {
        final catComp = Helperfunctions.compareCategoryHierarchy(a.category, b.category);
        if (catComp != 0) return catComp;
        return Helperfunctions.compareBySrpAndName(nameA: a.productName, priceA: a.sellingPrice, nameB: b.productName, priceB: b.sellingPrice);
      });
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
        orderAmount: (json['orderAmount'] as num?)?.toDouble() ?? 0.0,
        returnAmount: (json['returnAmount'] as num?)?.toDouble() ?? 0.0,
        creditAmount: (json['creditAmount'] as num?)?.toDouble() ?? 0.0,
        cashAmount: (json['cashAmount'] as num?)?.toDouble() ?? 0.0,
        onlineAmount: (json['onlineAmount'] as num?)?.toDouble() ?? 0.0,
        deliveryDate: json['deliveryDate'] as Timestamp?,
        creditStatus: json['creditStatus'] as String? ?? '',
        createdBy: json['createdBy'] as String? ?? '',
        lastUpdatedBy: json['lastUpdatedBy'] as String? ?? '',
        createdDate: json['createdDate'] as Timestamp? ?? Timestamp.now(),
        lastupdatedDate: json['lastupdatedDate'] as Timestamp? ?? Timestamp.now(),
        createdPage: json['createdPage'] as String? ?? '',
        lastUpdatedPage: json['lastUpdatedPage'] as String? ?? '',
        items: _parseItems(json['items']),
        isInventoryReserved: json['isInventoryReserved'] as bool? ?? false,
        isInventoryDeducted: json['isInventoryDeducted'] as bool? ?? false,
        picklistCompletedDate: json['picklistCompletedDate'] as Timestamp?,
        picklistCompletedBy: json['picklistCompletedBy'] as String? ?? '',
        picklistSequence: (json['picklistSequence'] as num?)?.toInt(),
        deliverySequence: (json['deliverySequence'] as num?)?.toInt(),
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
    double? deliveryAmount,
    double? returnAmount,
    double? creditAmount,
    String? creditStatus,
    double? cashAmount,
    double? onlineAmount,
    Timestamp? deliveryDate,
    List<OrderItem>? items,
    bool? isInventoryReserved,
    bool? isInventoryDeducted,
    Timestamp? picklistCompletedDate,
    String? picklistCompletedBy,
    int? picklistSequence,
    bool clearPicklistSequence = false,
    int? deliverySequence,
    bool clearDeliverySequence = false,
    String? createdBy,
    String? lastUpdatedBy,
    Timestamp? createdDate,
    Timestamp? lastupdatedDate,
    String? createdPage,
    String? lastUpdatedPage,
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
      items: items ?? this.items,
      isInventoryReserved: isInventoryReserved ?? this.isInventoryReserved,
      isInventoryDeducted: isInventoryDeducted ?? this.isInventoryDeducted,
      picklistCompletedDate: picklistCompletedDate ?? this.picklistCompletedDate,
      picklistCompletedBy: picklistCompletedBy ?? this.picklistCompletedBy,
      picklistSequence: clearPicklistSequence ? null : (picklistSequence ?? this.picklistSequence),
      deliverySequence: clearDeliverySequence ? null : (deliverySequence ?? this.deliverySequence),
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
      'items': items.map((e) => e.toJson()).toList(),
      'isInventoryReserved': isInventoryReserved,
      'isInventoryDeducted': isInventoryDeducted,
      'picklistCompletedDate': picklistCompletedDate,
      'picklistCompletedBy': picklistCompletedBy,
      'picklistSequence': picklistSequence,
      'deliverySequence': deliverySequence,
      'createdBy': createdBy,
      'lastUpdatedBy': lastUpdatedBy,
      'createdDate': createdDate,
      'lastupdatedDate': lastupdatedDate,
      'createdPage': createdPage,
      'lastUpdatedPage': lastUpdatedPage,
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
  static String returnAmount = 'returnAmount';
  static String creditAmount = 'creditAmount';
  static String cashAmount = 'cashAmount';
  static String onlineAmount = 'onlineAmount';
  static String deliveryDate = 'deliveryDate';
  static String creditStatus = 'creditStatus';
  static String items = 'items';
  static String isInventoryReserved = 'isInventoryReserved';
  static String isInventoryDeducted = 'isInventoryDeducted';

  static String createdBy = 'createdBy';
  static String lastUpdatedBy = 'lastUpdatedBy';
  static String createdDate = 'createdDate';
  static String lastupdatedDate = 'lastupdatedDate';
  static String createdPage = 'createdPage';
  static String lastUpdatedPage = 'lastUpdatedPage';
}
