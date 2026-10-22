import 'package:cloud_firestore/cloud_firestore.dart';

/// Metadata for a daily end-of-day stock snapshot stored in `inventory_snapshots/{yyyy-MM-dd}`.
class InventorySnapshot {
  final String dateKey; // 'yyyy-MM-dd'
  final DateTime capturedAt;
  final String capturedBy;
  final int totalProducts;
  final int totalStockQuantity;
  final int totalReservedQuantity;
  final int totalIncomingQuantity;
  final double totalStockCostValue;
  final double totalStockRetailValue;
  final String status;
  final List<InventorySnapshotItem> items;

  InventorySnapshot({
    String? dateKey,
    DateTime? capturedAt,
    DateTime? snapshotAt,
    String? date,
    String? id,
    this.capturedBy = 'Dealer',
    required this.totalProducts,
    required this.totalStockQuantity,
    this.totalReservedQuantity = 0,
    this.totalIncomingQuantity = 0,
    this.totalStockCostValue = 0,
    this.totalStockRetailValue = 0,
    this.status = 'captured',
    this.items = const [],
  })  : dateKey = id ?? date ?? dateKey ?? '',
        capturedAt = snapshotAt ?? capturedAt ?? DateTime.now();

  String get id => dateKey;
  String get date => dateKey;
  DateTime get snapshotAt => capturedAt;

  factory InventorySnapshot.fromJson(String id, Map<String, dynamic> json, {List<InventorySnapshotItem> items = const []}) {
    return InventorySnapshot(
      dateKey: id,
      capturedAt: (json['capturedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      capturedBy: json['capturedBy'] as String? ?? 'Dealer',
      totalProducts: (json['totalProducts'] as num?)?.toInt() ?? 0,
      totalStockQuantity: (json['totalStockQuantity'] as num?)?.toInt() ?? 0,
      totalReservedQuantity: (json['totalReservedQuantity'] as num?)?.toInt() ?? 0,
      totalIncomingQuantity: (json['totalIncomingQuantity'] as num?)?.toInt() ?? 0,
      totalStockCostValue: (json['totalStockCostValue'] as num?)?.toDouble() ?? 0.0,
      totalStockRetailValue: (json['totalStockRetailValue'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'captured',
      items: items,
    );
  }

  factory InventorySnapshot.fromSnapshot(DocumentSnapshot doc, {List<InventorySnapshotItem> items = const []}) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return InventorySnapshot.fromJson(doc.id, data, items: items);
  }

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'capturedAt': FieldValue.serverTimestamp(),
        'capturedBy': capturedBy,
        'totalProducts': totalProducts,
        'totalStockQuantity': totalStockQuantity,
        'totalReservedQuantity': totalReservedQuantity,
        'totalIncomingQuantity': totalIncomingQuantity,
        'totalStockCostValue': totalStockCostValue,
        'totalStockRetailValue': totalStockRetailValue,
        'status': status,
      };
}

/// Product-level inventory snapshot record stored in `inventory_snapshots/{yyyy-MM-dd}/items/{productId}`.
class InventorySnapshotItem {
  final String productId;
  final String productName;
  final String productSource;
  final int stockQuantity;
  final int reservedQuantity;
  final int incomingQuantity;
  final double buyingPrice;
  final double sellingPrice;
  final DateTime capturedAt;
  final String capturedBy;
  final int openingStock;
  final int closingStock;
  final int totalIn;
  final int totalOut;
  final bool reconciled;

  InventorySnapshotItem({
    required this.productId,
    required this.productName,
    required this.productSource,
    int? stockQuantity,
    int? reservedQuantity,
    int? incomingQuantity,
    double? buyingPrice,
    double? sellingPrice,
    DateTime? capturedAt,
    String? capturedBy,
    int? openingStock,
    int? closingStock,
    int? totalIn,
    int? totalOut,
    bool? reconciled,
    int? reserved,
  })  : openingStock = openingStock ?? 0,
        closingStock = closingStock ?? stockQuantity ?? 0,
        totalIn = totalIn ?? 0,
        totalOut = totalOut ?? 0,
        reconciled = reconciled ?? ((openingStock ?? 0) + (totalIn ?? 0) - (totalOut ?? 0) == (closingStock ?? stockQuantity ?? 0)),
        stockQuantity = closingStock ?? stockQuantity ?? 0,
        reservedQuantity = reserved ?? reservedQuantity ?? 0,
        incomingQuantity = incomingQuantity ?? 0,
        buyingPrice = buyingPrice ?? 0.0,
        sellingPrice = sellingPrice ?? 0.0,
        capturedAt = capturedAt ?? DateTime.now(),
        capturedBy = capturedBy ?? 'Dealer';

  factory InventorySnapshotItem.fromJson(String id, Map<String, dynamic> json) {
    final closing = (json['closingStock'] as num?)?.toInt() ?? (json['stockQuantity'] as num?)?.toInt() ?? 0;
    final opening = (json['openingStock'] as num?)?.toInt() ?? 0;
    final inQ = (json['totalIn'] as num?)?.toInt() ?? 0;
    final outQ = (json['totalOut'] as num?)?.toInt() ?? 0;
    final isReconciled = json['reconciled'] as bool? ?? (opening + inQ - outQ == closing);

    return InventorySnapshotItem(
      productId: id,
      productName: json['productName'] as String? ?? '',
      productSource: json['productSource'] as String? ?? 'selecta',
      openingStock: opening,
      closingStock: closing,
      totalIn: inQ,
      totalOut: outQ,
      reconciled: isReconciled,
      stockQuantity: closing,
      reservedQuantity: (json['reservedQuantity'] as num?)?.toInt() ?? (json['reserved'] as num?)?.toInt() ?? 0,
      incomingQuantity: (json['incomingQuantity'] as num?)?.toInt() ?? 0,
      buyingPrice: (json['buyingPrice'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (json['sellingPrice'] as num?)?.toDouble() ?? 0.0,
      capturedAt: (json['capturedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      capturedBy: json['capturedBy'] as String? ?? 'Dealer',
    );
  }

  factory InventorySnapshotItem.fromSnapshot(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return InventorySnapshotItem.fromJson(doc.id, data);
  }

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'productSource': productSource,
        'openingStock': openingStock,
        'closingStock': closingStock,
        'totalIn': totalIn,
        'totalOut': totalOut,
        'reconciled': reconciled,
        'stockQuantity': stockQuantity,
        'reservedQuantity': reservedQuantity,
        'incomingQuantity': incomingQuantity,
        'buyingPrice': buyingPrice,
        'sellingPrice': sellingPrice,
        'capturedAt': FieldValue.serverTimestamp(),
        'capturedBy': capturedBy,
      };
}
