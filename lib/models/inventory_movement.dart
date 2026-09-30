import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/models/other_product.dart';
import 'package:flutter_app/models/selecta_product.dart';

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
  final double buyingPrice;
  final double sellingPrice;
  final bool isActive;
  final int stockQuantity;
  final int reservedQuantity;
  final int lowStockThreshold;
  final InventoryProductSource source;
  final String category;
  final String tag;
  final Timestamp? updatedAt;

  const InventoryItem({
    required this.id,
    required this.productName,
    required this.imageUrl,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.isActive,
    required this.stockQuantity,
    this.reservedQuantity = 0,
    required this.lowStockThreshold,
    required this.source,
    this.category = '',
    this.tag = '',
    this.updatedAt,
  });

  factory InventoryItem.fromSelectaProduct(SelectaProduct product) {
    return InventoryItem(
      id: product.id,
      productName: product.productName,
      imageUrl: product.imageUrl,
      buyingPrice: product.buyingPrice,
      sellingPrice: product.sellingPrice,
      isActive: product.isActive,
      stockQuantity: product.stockQuantity,
      reservedQuantity: product.reservedQuantity,
      lowStockThreshold: product.lowStockThreshold,
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
      buyingPrice: product.buyingPrice,
      sellingPrice: product.sellingPrice,
      isActive: product.isActive,
      stockQuantity: product.stockQuantity,
      reservedQuantity: product.reservedQuantity,
      lowStockThreshold: product.lowStockThreshold,
      source: InventoryProductSource.other,
      category: '',
      tag: '',
      updatedAt: product.updatedAt,
    );
  }

  double get margin => sellingPrice - buyingPrice;

  double get marginPercent =>
      buyingPrice > 0 ? ((sellingPrice - buyingPrice) / buyingPrice) * 100 : 0;

  int get availableQuantity =>
      (stockQuantity - reservedQuantity) < 0 ? 0 : (stockQuantity - reservedQuantity);

  bool get isOutOfStock => stockQuantity <= 0;

  bool get isAvailableOutOfStock => availableQuantity <= 0;

  bool get isLowStock => stockQuantity > 0 && stockQuantity <= lowStockThreshold;

  double get stockCostValue => stockQuantity * buyingPrice;

  double get stockRetailValue => stockQuantity * sellingPrice;
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
  });

  factory InventoryMovement.fromJson(String id, Map<String, Object?> json) {
    final prev = (json['previousStock'] as num?)?.toInt() ?? 0;
    final next = (json['newStock'] as num?)?.toInt() ?? 0;
    return InventoryMovement(
      id: id,
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      productSource: json['productSource'] as String? ?? 'selecta',
      previousStock: prev,
      newStock: next,
      delta: (json['delta'] as num?)?.toInt() ?? (next - prev),
      reason: json['reason'] as String? ?? 'Manual Adjustment',
      notes: json['notes'] as String? ?? '',
      createdBy: json['createdBy'] as String? ?? '',
      createdAt: json['createdAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  factory InventoryMovement.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
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

  Map<String, Object?> toJson() {
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
      'createdAt': createdAt,
    };
  }
}
