// ignore_for_file: constant_identifier_names

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/models/other_product.dart';
import 'package:selecta_ops/models/selecta_product.dart';

/// Identifies which catalog collection a product belongs to.
enum InventoryProductSource {
  selecta('selecta', 'Selecta'),
  other('other', 'Other');

  final String key;
  final String label;
  const InventoryProductSource(this.key, this.label);

  static InventoryProductSource fromKey(String? raw) {
    if (raw == 'other') return InventoryProductSource.other;
    return InventoryProductSource.selecta;
  }
}

/// Unified representation of an inventory item across both [SelectaProduct] and [OtherProduct].
class InventoryItem {
  final String id;
  final String productName;
  final String imageUrl;
  final String itemCode;
  final String barcode;
  final double buyingPrice;
  final double sellingPrice;
  final bool isActive;
  final int stockQuantity;
  final int incomingQuantity;
  final int reservedQuantity;
  final int preOrderQuantity;
  final int lowStockThreshold;
  final int maxStock;
  final InventoryProductSource source;
  final String category;
  final String tag;
  final Timestamp? updatedAt;

  const InventoryItem({
    required this.id,
    required this.productName,
    required this.imageUrl,
    this.itemCode = '',
    this.barcode = '',
    required this.buyingPrice,
    required this.sellingPrice,
    required this.isActive,
    required this.stockQuantity,
    this.incomingQuantity = 0,
    this.reservedQuantity = 0,
    this.preOrderQuantity = 0,
    required this.lowStockThreshold,
    this.maxStock = 0,
    required this.source,
    this.category = '',
    this.tag = '',
    this.updatedAt,
  });

  InventoryItem copyWith({
    String? id,
    String? productName,
    String? imageUrl,
    String? itemCode,
    String? barcode,
    double? buyingPrice,
    double? sellingPrice,
    bool? isActive,
    int? stockQuantity,
    int? incomingQuantity,
    int? reservedQuantity,
    int? preOrderQuantity,
    int? lowStockThreshold,
    int? maxStock,
    InventoryProductSource? source,
    String? category,
    String? tag,
    Timestamp? updatedAt,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      productName: productName ?? this.productName,
      imageUrl: imageUrl ?? this.imageUrl,
      itemCode: itemCode ?? this.itemCode,
      barcode: barcode ?? this.barcode,
      buyingPrice: buyingPrice ?? this.buyingPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      isActive: isActive ?? this.isActive,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      incomingQuantity: incomingQuantity ?? this.incomingQuantity,
      reservedQuantity: reservedQuantity ?? this.reservedQuantity,
      preOrderQuantity: preOrderQuantity ?? this.preOrderQuantity,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      maxStock: maxStock ?? this.maxStock,
      source: source ?? this.source,
      category: category ?? this.category,
      tag: tag ?? this.tag,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory InventoryItem.fromSelectaProduct(SelectaProduct product) {
    return InventoryItem(
      id: product.id,
      productName: product.productName,
      imageUrl: product.imageUrl,
      itemCode: product.itemCode,
      barcode: product.barcode,
      buyingPrice: product.buyingPrice,
      sellingPrice: product.sellingPrice,
      isActive: product.isActive,
      stockQuantity: product.stockQuantity,
      incomingQuantity: product.incomingQuantity,
      reservedQuantity: product.reservedQuantity,
      preOrderQuantity: 0,
      lowStockThreshold: product.lowStockThreshold,
      maxStock: product.maxStock,
      source: InventoryProductSource.selecta,
      category: product.category,
      tag: product.tag,
      updatedAt: product.updatedAt,
    );
  }

  factory InventoryItem.fromOtherProduct(String id, OtherProduct product) {
    return InventoryItem(
      id: id,
      productName: product.productName,
      imageUrl: product.imageUrl,
      barcode: product.barcode,
      buyingPrice: product.buyingPrice,
      sellingPrice: product.sellingPrice,
      isActive: product.isActive,
      stockQuantity: product.stockQuantity,
      incomingQuantity: 0,
      reservedQuantity: product.reservedQuantity,
      preOrderQuantity: 0,
      lowStockThreshold: product.lowStockThreshold,
      maxStock: 0,
      source: InventoryProductSource.other,
      category: '',
      tag: '',
      updatedAt: product.updatedAt,
    );
  }

  double get margin => sellingPrice - buyingPrice;

  double get marginPercent => buyingPrice > 0 ? ((sellingPrice - buyingPrice) / buyingPrice) * 100 : 0;

  /// Physical on-hand stock in the warehouse.
  int get onHandQuantity => stockQuantity;

  /// Physical unreserved stock in the warehouse (Current Stock - Reserved Stock).
  int get netPhysicalStock => stockQuantity - reservedQuantity;

  /// Available stock = Current stock + Incoming Stock - Reserved stock.
  /// NOTE: As intended, pre-orders for future delivery do NOT deduct from available quantity.
  int get availableQuantity =>
      ((stockQuantity + incomingQuantity) - reservedQuantity) < 0 ? 0 : ((stockQuantity + incomingQuantity) - reservedQuantity);

  /// Shortage quantity based on pre-orders minus current stock on the warehouse (actual stock).
  int get preOrderShortage => (preOrderQuantity - stockQuantity) > 0 ? (preOrderQuantity - stockQuantity) : 0;

  /// True if pre-ordered quantity exceeds current warehouse stock.
  bool get hasPreOrderShortage => preOrderQuantity > stockQuantity;

  /// Remaining stock in warehouse after pre-orders are fulfilled.
  int get remainingStockAfterPreOrder => stockQuantity - preOrderQuantity;

  /// True if product is recommended in Purchase Order due to pre-orders:
  /// 1. Outright shortage: preOrderQuantity > stockQuantity (shortage > 0)
  /// 2. Low stock threshold alert: (stockQuantity - preOrderQuantity) <= lowStockThreshold
  bool get isPreOrderRecommended => preOrderQuantity > 0 && (stockQuantity - preOrderQuantity) <= lowStockThreshold;

  /// True if item is recommended for PO due to pre-orders (shortage or low stock alert).
  bool get hasPreOrderDeficit => isPreOrderRecommended;

  /// Shortage quantity for PO (pre-order minus current warehouse stock).
  int get preOrderDeficit => preOrderShortage;

  /// Quantity recommended to order on Purchase Order:
  /// - If max stock exists (> 0 and > lowStockThreshold): prefills with quantity needed
  ///   to reach the midpoint level between low stock threshold and max stock.
  /// - Else: only prefills what is needed to restore stock to the low-stock threshold.
  int get recommendedPreOrderOrderQuantity {
    final int targetStock;
    if (maxStock > 0 && maxStock > lowStockThreshold) {
      targetStock = ((lowStockThreshold + maxStock) / 2).round();
    } else {
      targetStock = lowStockThreshold;
    }

    final remaining = stockQuantity - preOrderQuantity;
    final needed = targetStock - remaining;
    if (hasPreOrderShortage) {
      return needed > preOrderShortage ? needed : preOrderShortage;
    }
    return needed > 0 ? needed : 1;
  }

  bool get isOutOfStock => stockQuantity <= 0;

  bool get isAvailableOutOfStock => availableQuantity <= 0;

  /// Low Stock indicator based strictly on Current stock - Reserved stock <= lowStockThreshold.
  /// Does NOT include incoming stock in the computation.
  bool get isLowStock => stockQuantity > 0 && netPhysicalStock <= lowStockThreshold;

  /// True if item is either completely out of stock or at or below low stock threshold.
  bool get isNeedsRestock => isOutOfStock || isLowStock;

  /// Target restock quantity: exclusive to Selecta products.
  /// Uses maxStock if configured (> 0), otherwise falls back to (lowStockThreshold * 2).
  int get suggestedRestockQuantity {
    if (source != InventoryProductSource.selecta) return 0;
    final target = maxStock > 0 ? maxStock : (lowStockThreshold * 2);
    final deficit = target - availableQuantity;
    return deficit > 0 ? deficit : 0;
  }

  double get stockCostValue => stockQuantity * buyingPrice;

  double get stockRetailValue => stockQuantity * sellingPrice;

  bool get isSelecta => source == InventoryProductSource.selecta;

  bool get isByPiece => category.toLowerCase().contains('piece');

  bool get isByCase => category.toLowerCase().contains('case');

  String get productSource => source.name;
}

/// Types of inventory movement representing the operational action that triggered a change.
enum MovementType {
  receipt('receipt', 'Stock Receipt'),
  pick('pick', 'Picklist Fulfilled'),
  van_load('van_load', 'Van Load'),
  van_return('van_return', 'Van Return'),
  customer_return('customer_return', 'Customer Return'),
  adjustment('adjustment', 'Manual Adjustment'),
  count_correction('count_correction', 'Count Correction'),
  damage_expiry('damage_expiry', 'Damage / Expiry'),
  reserve('reserve', 'Order Reserved'),
  release('release', 'Reservation Released'),
  incoming_added('incoming_added', 'Incoming PO Added'),
  incoming_adjusted('incoming_adjusted', 'Incoming PO Adjusted'),
  incoming_removed('incoming_removed', 'Incoming PO Removed'),
  reversal('reversal', 'Reversal'),
  settlement('settlement', 'Daily Settlement');

  final String key;
  final String label;
  const MovementType(this.key, this.label);

  String get displayName => label;

  static MovementType fromKey(String? raw) {
    if (raw == null) return MovementType.adjustment;
    for (final val in MovementType.values) {
      if (val.key == raw || val.name == raw) return val;
    }
    return MovementType.adjustment;
  }

  /// Backward-compatibility mapper for legacy movement records with free-text reason strings.
  static MovementType fromLegacyReason(String? reason) {
    if (reason == null) return MovementType.adjustment;
    final r = reason.toLowerCase();
    if (r.contains('van load')) return MovementType.van_load;
    if (r.contains('van return')) return MovementType.van_return;
    if (r.contains('picklist') || r.contains('pick')) return MovementType.pick;
    if (r.contains('po replenish') || r.contains('receipt') || r.contains('replenish') || r.contains('received')) {
      return MovementType.receipt;
    }
    if (r.contains('po placed') || r.contains('incoming')) return MovementType.incoming_added;
    if (r.contains('po revert') || r.contains('cancel') || r.contains('deleted order')) return MovementType.reversal;
    if (r.contains('customer return') || r.contains('item return') || r.contains('return restock')) {
      return MovementType.customer_return;
    }
    if (r.contains('settlement')) return MovementType.settlement;
    if (r.contains('reserve')) return MovementType.reserve;
    if (r.contains('release')) return MovementType.release;
    if (r.contains('correction') || r.contains('count')) return MovementType.count_correction;
    if (r.contains('damage') || r.contains('expir')) return MovementType.damage_expiry;
    return MovementType.adjustment;
  }
}

/// Standardized reason codes for manual stock adjustments and corrections.
enum ReasonCode {
  count_correction('count_correction', 'Count Correction'),
  damaged('damaged', 'Damaged Stock'),
  expired('expired', 'Expired Stock'),
  lost('lost', 'Lost / Missing'),
  found('found', 'Found Stock'),
  supplier_shortage('supplier_shortage', 'Supplier Shortage'),
  data_entry_error('data_entry_error', 'Data Entry Error'),
  other('other', 'Other');

  final String key;
  final String label;
  const ReasonCode(this.key, this.label);

  String get displayName => label;

  static ReasonCode? fromKey(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final val in ReasonCode.values) {
      if (val.key == raw || val.name == raw) return val;
    }
    return null;
  }
}

/// Source document types linked to an inventory movement.
enum ReferenceType {
  order('order', 'Order'),
  delivery('delivery', 'Delivery'),
  picklist('picklist', 'Picklist'),
  purchase_order('purchase_order', 'Purchase Order'),
  van_load('van_load', 'Van Load'),
  return_doc('return', 'Return'),
  manual('manual', 'Manual Adjustment');

  final String key;
  final String label;
  const ReferenceType(this.key, this.label);

  String get displayName => label;

  static ReferenceType? fromKey(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw == 'return') return ReferenceType.return_doc;
    for (final val in ReferenceType.values) {
      if (val.key == raw || val.name == raw) return val;
    }
    return null;
  }
}

/// Standardized disposition actions for returned goods.
enum ReturnDisposition {
  restock('restock', 'Restock to Warehouse'),
  quarantine('quarantine', 'Quarantine for Inspection'),
  write_off('write_off', 'Write-Off / Scrap');

  final String key;
  final String label;
  const ReturnDisposition(this.key, this.label);

  String get displayName => label;

  static ReturnDisposition? fromKey(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final val in ReturnDisposition.values) {
      if (val.key == raw || val.name == raw) return val;
    }
    return null;
  }
}

/// Standardized reason codes for short allocations and picklist short-picks.
enum ShortPickReason {
  out_of_stock('out_of_stock', 'Out of Stock'),
  damaged('damaged', 'Damaged in Warehouse'),
  expired('expired', 'Expired on Shelf'),
  not_found('not_found', 'Cannot Find / Misplaced'),
  other('other', 'Other Override');

  final String key;
  final String label;
  const ShortPickReason(this.key, this.label);

  String get displayName => label;

  static ShortPickReason? fromKey(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final val in ShortPickReason.values) {
      if (val.key == raw || val.name == raw) return val;
    }
    return null;
  }
}

/// Represents a recorded stock adjustment or movement in `inventory_movements`.
class InventoryMovement {
  final String id;
  final String productId;
  final String productName;
  final String productSource; // 'selecta' | 'other'
  final int previousStock;
  final int newStock;
  final int delta;
  final String reason;
  final String notes;
  final String createdBy;
  final Timestamp createdAt;

  // Rich audit trail fields (all backward-compatible)
  final MovementType movementType;
  final ReasonCode? reasonCode;
  final ReferenceType? referenceType;
  final String? referenceId;
  final String? referenceLabel;
  final int? previousReserved;
  final int? newReserved;
  final int? previousIncoming;
  final int? newIncoming;
  final int? requestedQuantity;
  final bool clamped;
  final String? actorUid;
  final String? actorRole;
  final String? actorName;
  final String source; // 'app' | 'system' | 'migration'
  final String? deviceId;
  final String? appVersion;
  final String? batchId;

  // Phase 8: Per-workflow audit & cross-cutting tracking fields
  final String? correlationId;
  final String? idempotencyKey;
  final String? sourceLocation;
  final String? targetLocation;
  final bool isOverride;
  final String? overrideReason;
  final double? costPrice;
  final double? sellingPrice;
  final ReturnDisposition? disposition;
  final ShortPickReason? shortPickReason;

  // Hardening, offline-safety, server-timing, and cycle count tracking
  final Timestamp? clientCreatedAt;
  final bool wasOffline;
  final int? sequenceNumber;
  final bool isBlind;
  final int? countRound;
  final int? systemQuantityAtStart;

  const InventoryMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.productSource,
    required this.previousStock,
    required this.newStock,
    required this.delta,
    required this.reason,
    this.notes = '',
    required this.createdBy,
    required this.createdAt,
    this.movementType = MovementType.adjustment,
    this.reasonCode,
    this.referenceType,
    this.referenceId,
    this.referenceLabel,
    this.previousReserved,
    this.newReserved,
    this.previousIncoming,
    this.newIncoming,
    this.requestedQuantity,
    this.clamped = false,
    this.actorUid,
    this.actorRole,
    this.actorName,
    this.source = 'app',
    this.deviceId,
    this.appVersion,
    this.batchId,
    this.correlationId,
    this.idempotencyKey,
    this.sourceLocation,
    this.targetLocation,
    this.isOverride = false,
    this.overrideReason,
    this.costPrice,
    this.sellingPrice,
    this.disposition,
    this.shortPickReason,
    this.clientCreatedAt,
    this.wasOffline = false,
    this.sequenceNumber,
    this.isBlind = false,
    this.countRound,
    this.systemQuantityAtStart,
  });

  factory InventoryMovement.fromJson(String id, Map<String, Object?> json) {
    final prev = (json['previousStock'] as num?)?.toInt() ?? 0;
    final next = (json['newStock'] as num?)?.toInt() ?? 0;
    final rawReason = json['reason'] as String? ?? 'Manual Adjustment';

    final MovementType mType;
    if (json.containsKey('movementType') && json['movementType'] != null) {
      mType = MovementType.fromKey(json['movementType'] as String?);
    } else {
      mType = MovementType.fromLegacyReason(rawReason);
    }

    final reasonCode = ReasonCode.fromKey(json['reasonCode'] as String?);
    final refType = ReferenceType.fromKey(json['referenceType'] as String?);
    final disposition = ReturnDisposition.fromKey(json['disposition'] as String?);
    final shortPickReason = ShortPickReason.fromKey(json['shortPickReason'] as String?);
    final legacyCreatedBy = json['createdBy'] as String? ?? '';
    final actorName = json['actorName'] as String? ?? (legacyCreatedBy.isNotEmpty ? legacyCreatedBy : null);

    final rawCreated = json['createdAt'];
    final rawClientCreated = json['clientCreatedAt'];
    final Timestamp resolvedCreatedAt;
    if (rawCreated is Timestamp) {
      resolvedCreatedAt = rawCreated;
    } else if (rawClientCreated is Timestamp) {
      resolvedCreatedAt = rawClientCreated;
    } else {
      resolvedCreatedAt = Timestamp.now();
    }

    return InventoryMovement(
      id: id,
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      productSource: json['productSource'] as String? ?? 'selecta',
      previousStock: prev,
      newStock: next,
      delta: (json['delta'] as num?)?.toInt() ?? (next - prev),
      reason: rawReason,
      notes: json['notes'] as String? ?? '',
      createdBy: legacyCreatedBy,
      createdAt: resolvedCreatedAt,
      movementType: mType,
      reasonCode: reasonCode,
      referenceType: refType,
      referenceId: json['referenceId'] as String?,
      referenceLabel: json['referenceLabel'] as String?,
      previousReserved: (json['previousReserved'] as num?)?.toInt(),
      newReserved: (json['newReserved'] as num?)?.toInt(),
      previousIncoming: (json['previousIncoming'] as num?)?.toInt(),
      newIncoming: (json['newIncoming'] as num?)?.toInt(),
      requestedQuantity: (json['requestedQuantity'] as num?)?.toInt(),
      clamped: (json['clamped'] as bool?) ?? false,
      actorUid: json['actorUid'] as String?,
      actorRole: json['actorRole'] as String?,
      actorName: actorName,
      source: json['source'] as String? ?? 'app',
      deviceId: json['deviceId'] as String?,
      appVersion: json['appVersion'] as String?,
      batchId: json['batchId'] as String?,
      correlationId: json['correlationId'] as String?,
      idempotencyKey: json['idempotencyKey'] as String?,
      sourceLocation: json['sourceLocation'] as String?,
      targetLocation: json['targetLocation'] as String?,
      isOverride: (json['isOverride'] as bool?) ?? false,
      overrideReason: json['overrideReason'] as String?,
      costPrice: (json['costPrice'] as num?)?.toDouble(),
      sellingPrice: (json['sellingPrice'] as num?)?.toDouble(),
      disposition: disposition,
      shortPickReason: shortPickReason,
      clientCreatedAt: rawClientCreated is Timestamp ? rawClientCreated : (rawCreated is Timestamp ? rawCreated : null),
      wasOffline: (json['wasOffline'] as bool?) ?? false,
      sequenceNumber: (json['sequenceNumber'] as num?)?.toInt(),
      isBlind: (json['isBlind'] as bool?) ?? false,
      countRound: (json['countRound'] as num?)?.toInt(),
      systemQuantityAtStart: (json['systemQuantityAtStart'] as num?)?.toInt(),
    );
  }

  factory InventoryMovement.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      return InventoryMovement(
        id: doc.id,
        productId: '',
        productName: '',
        productSource: 'selecta',
        previousStock: 0,
        newStock: 0,
        delta: 0,
        reason: '',
        createdBy: '',
        createdAt: Timestamp.now(),
      );
    }
    return InventoryMovement.fromJson(doc.id, data.cast<String, Object?>());
  }

  InventoryMovement copyWith({
    String? id,
    String? productId,
    String? productName,
    String? productSource,
    int? previousStock,
    int? newStock,
    int? delta,
    String? reason,
    String? notes,
    String? createdBy,
    Timestamp? createdAt,
    MovementType? movementType,
    ReasonCode? reasonCode,
    ReferenceType? referenceType,
    String? referenceId,
    String? referenceLabel,
    int? previousReserved,
    int? newReserved,
    int? previousIncoming,
    int? newIncoming,
    int? requestedQuantity,
    bool? clamped,
    String? actorUid,
    String? actorRole,
    String? actorName,
    String? source,
    String? deviceId,
    String? appVersion,
    String? batchId,
    String? correlationId,
    String? idempotencyKey,
    String? sourceLocation,
    String? targetLocation,
    bool? isOverride,
    String? overrideReason,
    double? costPrice,
    double? sellingPrice,
    ReturnDisposition? disposition,
    ShortPickReason? shortPickReason,
    Timestamp? clientCreatedAt,
    bool? wasOffline,
    int? sequenceNumber,
    bool? isBlind,
    int? countRound,
    int? systemQuantityAtStart,
  }) {
    return InventoryMovement(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSource: productSource ?? this.productSource,
      previousStock: previousStock ?? this.previousStock,
      newStock: newStock ?? this.newStock,
      delta: delta ?? this.delta,
      reason: reason ?? this.reason,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      movementType: movementType ?? this.movementType,
      reasonCode: reasonCode ?? this.reasonCode,
      referenceType: referenceType ?? this.referenceType,
      referenceId: referenceId ?? this.referenceId,
      referenceLabel: referenceLabel ?? this.referenceLabel,
      previousReserved: previousReserved ?? this.previousReserved,
      newReserved: newReserved ?? this.newReserved,
      previousIncoming: previousIncoming ?? this.previousIncoming,
      newIncoming: newIncoming ?? this.newIncoming,
      requestedQuantity: requestedQuantity ?? this.requestedQuantity,
      clamped: clamped ?? this.clamped,
      actorUid: actorUid ?? this.actorUid,
      actorRole: actorRole ?? this.actorRole,
      actorName: actorName ?? this.actorName,
      source: source ?? this.source,
      deviceId: deviceId ?? this.deviceId,
      appVersion: appVersion ?? this.appVersion,
      batchId: batchId ?? this.batchId,
      correlationId: correlationId ?? this.correlationId,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      sourceLocation: sourceLocation ?? this.sourceLocation,
      targetLocation: targetLocation ?? this.targetLocation,
      isOverride: isOverride ?? this.isOverride,
      overrideReason: overrideReason ?? this.overrideReason,
      costPrice: costPrice ?? this.costPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      disposition: disposition ?? this.disposition,
      shortPickReason: shortPickReason ?? this.shortPickReason,
      clientCreatedAt: clientCreatedAt ?? this.clientCreatedAt,
      wasOffline: wasOffline ?? this.wasOffline,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      isBlind: isBlind ?? this.isBlind,
      countRound: countRound ?? this.countRound,
      systemQuantityAtStart: systemQuantityAtStart ?? this.systemQuantityAtStart,
    );
  }

  Map<String, Object?> toJson({bool forFirestore = true}) {
    return {
      'productId': productId,
      'productName': productName,
      'productSource': productSource,
      'previousStock': previousStock,
      'newStock': newStock,
      'delta': delta,
      'reason': reason,
      'notes': notes,
      'createdBy': createdBy,
      'createdAt': forFirestore ? FieldValue.serverTimestamp() : createdAt,
      'clientCreatedAt': clientCreatedAt ?? createdAt,
      'movementType': movementType.key,
      if (reasonCode != null) 'reasonCode': reasonCode!.key,
      if (referenceType != null) 'referenceType': referenceType!.key,
      if (referenceId != null) 'referenceId': referenceId,
      if (referenceLabel != null) 'referenceLabel': referenceLabel,
      if (previousReserved != null) 'previousReserved': previousReserved,
      if (newReserved != null) 'newReserved': newReserved,
      if (previousIncoming != null) 'previousIncoming': previousIncoming,
      if (newIncoming != null) 'newIncoming': newIncoming,
      if (requestedQuantity != null) 'requestedQuantity': requestedQuantity,
      'clamped': clamped,
      if (actorUid != null) 'actorUid': actorUid,
      if (actorRole != null) 'actorRole': actorRole,
      if (actorName != null) 'actorName': actorName,
      'source': source,
      if (deviceId != null) 'deviceId': deviceId,
      if (appVersion != null) 'appVersion': appVersion,
      if (batchId != null) 'batchId': batchId,
      if (correlationId != null) 'correlationId': correlationId,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
      if (sourceLocation != null) 'sourceLocation': sourceLocation,
      if (targetLocation != null) 'targetLocation': targetLocation,
      'isOverride': isOverride,
      if (overrideReason != null) 'overrideReason': overrideReason,
      if (costPrice != null) 'costPrice': costPrice,
      if (sellingPrice != null) 'sellingPrice': sellingPrice,
      if (disposition != null) 'disposition': disposition!.key,
      if (shortPickReason != null) 'shortPickReason': shortPickReason!.key,
      'wasOffline': wasOffline,
      if (sequenceNumber != null) 'sequenceNumber': sequenceNumber,
      if (isBlind) 'isBlind': isBlind,
      if (countRound != null) 'countRound': countRound,
      if (systemQuantityAtStart != null) 'systemQuantityAtStart': systemQuantityAtStart,
    };
  }

  /// Whether this movement modified physical on-hand stock.
  bool get hasPhysicalStockChange => delta != 0;

  /// Whether this movement modified reserved stock.
  bool get hasReservedStockChange =>
      previousReserved != null && newReserved != null && previousReserved != newReserved;

  /// Whether this movement modified incoming stock.
  bool get hasIncomingStockChange =>
      previousIncoming != null && newIncoming != null && previousIncoming != newIncoming;

  /// Delta for reserved stock.
  int get reservedDelta => (newReserved ?? 0) - (previousReserved ?? 0);

  /// Delta for incoming stock.
  int get incomingDelta => (newIncoming ?? 0) - (previousIncoming ?? 0);

  /// Display string for who performed the action.
  String get displayActor => actorName ?? (createdBy.isNotEmpty ? createdBy : 'System');
}
