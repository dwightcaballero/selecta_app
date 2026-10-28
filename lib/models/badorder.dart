import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/selecta_product.dart';

/// Rounds a monetary amount to 2 decimal places using standard arithmetic rounding.
double roundToTwoDecimals(double val) => double.parse(val.toStringAsFixed(2));

class BadOrderItem {
  final String productId;
  final String productName;
  final String category; // 'By Piece' or 'By Case'
  final int quantity;
  final double pricePerPiece; // STORE refund price per piece
  final double subtotal; // STORE line subtotal (rounded to 2 decimals)
  final double supplierPricePerPiece; // SUPPLIER refund price per piece
  final double supplierSubtotal; // SUPPLIER line subtotal (rounded to 2 decimals)
  final int? piecesPerCase; // Snapshot of pieces per case at creation (audit)
  final double? caseSellingPrice; // Snapshot of case selling price at creation (audit)
  final double? caseBuyingPrice; // Snapshot of case buying price at creation (audit)
  final String imageUrl;
  final bool isLegacy; // True if item lacks supplierPricePerPiece snapshot

  const BadOrderItem({
    required this.productId,
    required this.productName,
    required this.category,
    required this.quantity,
    required this.pricePerPiece,
    required this.subtotal,
    this.supplierPricePerPiece = 0.0,
    this.supplierSubtotal = 0.0,
    this.piecesPerCase,
    this.caseSellingPrice,
    this.caseBuyingPrice,
    this.imageUrl = '',
    this.isLegacy = false,
  });

  /// Factory that computes store & supplier refund prices, line subtotals with
  /// line-level rounding, and captures price/packaging audit snapshots.
  factory BadOrderItem.fromProduct({
    required SelectaProduct product,
    required int quantity,
    String? imageUrl,
  }) {
    final storePrice = product.storeRefundPerPiece;
    final supplierPrice = product.supplierRefundPerPiece;
    final storeSub = roundToTwoDecimals(quantity * storePrice);
    final supplierSub = roundToTwoDecimals(quantity * supplierPrice);

    return BadOrderItem(
      productId: product.id,
      productName: product.productName,
      category: product.category,
      quantity: quantity,
      pricePerPiece: storePrice,
      subtotal: storeSub,
      supplierPricePerPiece: supplierPrice,
      supplierSubtotal: supplierSub,
      piecesPerCase: product.isCaseProduct ? product.boPiecesPerCase : null,
      caseSellingPrice: product.isCaseProduct ? product.sellingPrice : null,
      caseBuyingPrice: product.isCaseProduct ? product.buyingPrice : null,
      imageUrl: imageUrl ?? product.imageUrl,
      isLegacy: false,
    );
  }

  factory BadOrderItem.fromJson(Map<String, dynamic> json) {
    final qty = (json['quantity'] as num?)?.toInt() ?? 0;
    final price = (json['pricePerPiece'] as num?)?.toDouble() ?? 0.0;
    final sub = (json['subtotal'] as num?)?.toDouble() ?? (qty * price);

    final hasSupplierPrice = json.containsKey('supplierPricePerPiece') && json['supplierPricePerPiece'] != null;
    final supplierPrice = hasSupplierPrice
        ? (json['supplierPricePerPiece'] as num).toDouble()
        : price;
    final supplierSub = hasSupplierPrice
        ? ((json['supplierSubtotal'] as num?)?.toDouble() ?? roundToTwoDecimals(qty * supplierPrice))
        : sub; // Legacy fallback: supplier values equal store values

    return BadOrderItem(
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      category: json['category'] as String? ?? '',
      quantity: qty,
      pricePerPiece: price,
      subtotal: sub,
      supplierPricePerPiece: supplierPrice,
      supplierSubtotal: supplierSub,
      piecesPerCase: (json['piecesPerCase'] as num?)?.toInt(),
      caseSellingPrice: (json['caseSellingPrice'] as num?)?.toDouble(),
      caseBuyingPrice: (json['caseBuyingPrice'] as num?)?.toDouble(),
      imageUrl: json['imageUrl'] as String? ?? '',
      isLegacy: !hasSupplierPrice,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'category': category,
      'quantity': quantity,
      'pricePerPiece': pricePerPiece,
      'subtotal': subtotal,
      'supplierPricePerPiece': supplierPricePerPiece,
      'supplierSubtotal': supplierSubtotal,
      if (piecesPerCase != null) 'piecesPerCase': piecesPerCase,
      if (caseSellingPrice != null) 'caseSellingPrice': caseSellingPrice,
      if (caseBuyingPrice != null) 'caseBuyingPrice': caseBuyingPrice,
      'imageUrl': imageUrl,
    };
  }
}

class BadOrder {
  String id;
  String hapistore;
  Timestamp badorderDate;
  String imagePath;
  String status;
  String notes;
  List<BadOrderItem> items;
  double badorderAmount;
  double supplierAmount;
  int schemaVersion;
  String createdBy;
  String lastUpdatedBy;
  Timestamp createdDate;
  Timestamp lastupdatedDate;
  String createdPage;
  String lastUpdatedPage;
  bool isStoreRefunded;
  Timestamp? storeRefundedDate;
  String? storeRefundedBy;
  String? batchId;
  String? batchNumber;

  BadOrder({
    this.id = '',
    required this.hapistore,
    required this.badorderDate,
    this.imagePath = '',
    this.status = BadOrderStatus.storePullout,
    this.notes = '',
    this.items = const [],
    double? badorderAmount,
    double? supplierAmount,
    this.schemaVersion = 3,
    required this.createdBy,
    required this.lastUpdatedBy,
    required this.createdDate,
    required this.lastupdatedDate,
    this.createdPage = '',
    this.lastUpdatedPage = '',
    this.isStoreRefunded = false,
    this.storeRefundedDate,
    this.storeRefundedBy,
    this.batchId,
    this.batchNumber,
  })  : badorderAmount = badorderAmount ??
            items.fold<double>(0.0, (total, item) => total + item.subtotal),
        supplierAmount = supplierAmount ??
            items.fold<double>(0.0, (total, item) => total + item.supplierSubtotal);

  /// Backwards-compatibility getter for description (maps to notes)
  String get description => notes;
  set description(String val) => notes = val;

  /// Check if this is a new bad order record with itemized entries.
  bool get isNewRecord => items.isNotEmpty || schemaVersion >= 2;

  /// Whether this record has full dual-pricing snapshots (store vs supplier).
  bool get hasDualPricing => items.isNotEmpty && items.every((i) => !i.isLegacy);

  /// Net loss for the dealer (store refund - expected supplier refund).
  /// For legacy records without supplier snapshots, net loss equals full badorderAmount.
  double get netLossAmount =>
      hasDualPricing ? (totalAmount - totalSupplierAmount) : totalAmount;

  /// Computes the total store refund amount from items (or flat badorderAmount for legacy records).
  double get totalAmount =>
      items.isNotEmpty ? items.fold<double>(0.0, (total, item) => total + item.subtotal) : badorderAmount;

  /// Computes the total expected supplier refund amount from items.
  double get totalSupplierAmount =>
      items.fold<double>(0.0, (total, item) => total + item.supplierSubtotal);

  static BadOrder empty() => BadOrder(
        hapistore: '',
        badorderDate: Timestamp.now(),
        imagePath: '',
        status: BadOrderStatus.storePullout,
        notes: '',
        items: const [],
        badorderAmount: 0.0,
        supplierAmount: 0.0,
        schemaVersion: 3,
        createdBy: '',
        lastUpdatedBy: '',
        createdDate: Timestamp.now(),
        lastupdatedDate: Timestamp.now(),
        isStoreRefunded: false,
        storeRefundedDate: null,
        storeRefundedBy: null,
      );

  factory BadOrder.fromJson(Map<String, Object?> json, [String docId = '']) {
    final rawItems = json['items'];
    List<BadOrderItem> parsedItems = [];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map) {
          parsedItems.add(BadOrderItem.fromJson(item.cast<String, dynamic>()));
        }
      }
    }

    final rawAmount = (json['badorderAmount'] as num?)?.toDouble();
    final computedAmount = parsedItems.isNotEmpty
        ? parsedItems.fold<double>(0.0, (total, item) => total + item.subtotal)
        : (rawAmount ?? 0.0);

    final rawSupplierAmount = (json['supplierAmount'] as num?)?.toDouble();
    final computedSupplierAmount = rawSupplierAmount ??
        (parsedItems.isNotEmpty
            ? parsedItems.fold<double>(0.0, (total, item) => total + item.supplierSubtotal)
            : computedAmount);

    final schemaVer = (json['schemaVersion'] as num?)?.toInt() ??
        (parsedItems.any((i) => !i.isLegacy) ? 3 : (parsedItems.isNotEmpty ? 2 : 1));

    return BadOrder(
      id: docId.isNotEmpty ? docId : (json['id'] as String? ?? ''),
      hapistore: json['hapistore'] as String? ?? '',
      badorderDate: json['badorderDate'] as Timestamp? ?? Timestamp.now(),
      imagePath: json['imagePath'] as String? ?? json['imageUrl'] as String? ?? '',
      status: json['status'] as String? ?? BadOrderStatus.storePullout,
      notes: json['notes'] as String? ?? json['description'] as String? ?? '',
      items: parsedItems,
      badorderAmount: computedAmount,
      supplierAmount: computedSupplierAmount,
      schemaVersion: schemaVer,
      createdBy: json['createdBy'] as String? ?? '',
      lastUpdatedBy: json['lastUpdatedBy'] as String? ?? '',
      createdDate: json['createdDate'] as Timestamp? ?? Timestamp.now(),
      lastupdatedDate: json['lastupdatedDate'] as Timestamp? ?? Timestamp.now(),
      createdPage: json['createdPage'] as String? ?? '',
      lastUpdatedPage: json['lastUpdatedPage'] as String? ?? '',
      isStoreRefunded: json['isStoreRefunded'] as bool? ?? false,
      storeRefundedDate: json['storeRefundedDate'] as Timestamp?,
      storeRefundedBy: json['storeRefundedBy'] as String?,
      batchId: json['batchId'] as String?,
      batchNumber: json['batchNumber'] as String?,
    );
  }

  factory BadOrder.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    if (document.data() != null) {
      return BadOrder.fromJson(document.data()!, document.id);
    } else {
      return BadOrder.empty();
    }
  }

  BadOrder copyWith({
    String? id,
    String? hapistore,
    Timestamp? badorderDate,
    String? imagePath,
    String? status,
    String? notes,
    List<BadOrderItem>? items,
    double? badorderAmount,
    double? supplierAmount,
    int? schemaVersion,
    String? createdBy,
    String? lastUpdatedBy,
    Timestamp? createdDate,
    Timestamp? lastupdatedDate,
    String? createdPage,
    String? lastUpdatedPage,
    bool? isStoreRefunded,
    Timestamp? storeRefundedDate,
    String? storeRefundedBy,
    String? batchId,
    String? batchNumber,
    bool clearBatch = false,
  }) {
    return BadOrder(
      id: id ?? this.id,
      hapistore: hapistore ?? this.hapistore,
      badorderDate: badorderDate ?? this.badorderDate,
      imagePath: imagePath ?? this.imagePath,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      items: items ?? this.items,
      badorderAmount: badorderAmount ?? this.badorderAmount,
      supplierAmount: supplierAmount ?? this.supplierAmount,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdBy: createdBy ?? this.createdBy,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
      createdDate: createdDate ?? this.createdDate,
      lastupdatedDate: lastupdatedDate ?? this.lastupdatedDate,
      createdPage: createdPage ?? this.createdPage,
      lastUpdatedPage: lastUpdatedPage ?? this.lastUpdatedPage,
      isStoreRefunded: isStoreRefunded ?? this.isStoreRefunded,
      storeRefundedDate: storeRefundedDate ?? this.storeRefundedDate,
      storeRefundedBy: storeRefundedBy ?? this.storeRefundedBy,
      batchId: clearBatch ? null : (batchId ?? this.batchId),
      batchNumber: clearBatch ? null : (batchNumber ?? this.batchNumber),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'hapistore': hapistore,
      'badorderDate': badorderDate,
      'imagePath': imagePath,
      'status': status,
      'notes': notes,
      'description': notes,
      'items': items.map((i) => i.toJson()).toList(),
      'badorderAmount': totalAmount,
      'supplierAmount': totalSupplierAmount,
      'schemaVersion': schemaVersion,
      'createdBy': createdBy,
      'lastUpdatedBy': lastUpdatedBy,
      'createdDate': createdDate,
      'lastupdatedDate': lastupdatedDate,
      'createdPage': createdPage,
      'lastUpdatedPage': lastUpdatedPage,
      'isStoreRefunded': isStoreRefunded,
      if (storeRefundedDate != null) 'storeRefundedDate': storeRefundedDate,
      if (storeRefundedBy != null) 'storeRefundedBy': storeRefundedBy,
      if (batchId != null) 'batchId': batchId,
      if (batchNumber != null) 'batchNumber': batchNumber,
    };
  }
}
