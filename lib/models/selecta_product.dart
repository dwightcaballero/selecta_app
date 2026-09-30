import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a Selecta product in the catalog.
class SelectaProduct {
  final String id;
  final String productName;
  final String imageUrl;
  final String itemCode;
  final double buyingPrice;
  final double sellingPrice;
  final String category;
  final bool isActive;
  final int stockQuantity;
  final int lowStockThreshold;
  final Timestamp? importedAt;
  final Timestamp? updatedAt;

  const SelectaProduct({
    required this.id,
    required this.productName,
    required this.imageUrl,
    required this.itemCode,
    this.buyingPrice = 0.0,
    this.sellingPrice = 0.0,
    required this.category,
    this.isActive = true,
    this.stockQuantity = 0,
    this.lowStockThreshold = 10,
    this.importedAt,
    this.updatedAt,
  });

  /// Backward-compatible price accessor (selling price).
  double get price => sellingPrice;

  /// Gross margin amount (sellingPrice - buyingPrice).
  double get margin => sellingPrice - buyingPrice;

  /// Margin percentage relative to buying price.
  double get marginPercent =>
      buyingPrice > 0 ? ((sellingPrice - buyingPrice) / buyingPrice) * 100 : 0;

  /// True when stock is 0 or less.
  bool get isOutOfStock => stockQuantity <= 0;

  /// True when stock is positive but at or below [lowStockThreshold].
  bool get isLowStock => stockQuantity > 0 && stockQuantity <= lowStockThreshold;

  /// Total inventory value at buying cost.
  double get stockCostValue => stockQuantity * buyingPrice;

  /// Total inventory value at selling price.
  double get stockRetailValue => stockQuantity * sellingPrice;

  static SelectaProduct empty() => const SelectaProduct(
        id: '',
        productName: '',
        imageUrl: '',
        itemCode: '',
        buyingPrice: 0.0,
        sellingPrice: 0.0,
        category: '',
        isActive: true,
        stockQuantity: 0,
        lowStockThreshold: 10,
      );

  factory SelectaProduct.fromJson(String id, Map<String, Object?> json) {
    final legacyPrice = (json['price'] as num?)?.toDouble() ?? 0.0;
    final buyingPrice = (json['buyingPrice'] as num?)?.toDouble() ?? legacyPrice;
    final sellingPrice = (json['sellingPrice'] as num?)?.toDouble() ?? legacyPrice;

    return SelectaProduct(
      id: id,
      productName: json['productName'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      itemCode: json['itemCode'] as String? ?? '',
      buyingPrice: buyingPrice,
      sellingPrice: sellingPrice,
      category: json['category'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? true,
      stockQuantity: (json['stockQuantity'] as num?)?.toInt() ?? 0,
      lowStockThreshold: (json['lowStockThreshold'] as num?)?.toInt() ?? 10,
      importedAt: json['importedAt'] as Timestamp?,
      updatedAt: json['updatedAt'] as Timestamp?,
    );
  }

  factory SelectaProduct.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      return SelectaProduct.fromJson(document.id, document.data()!.cast<String, Object?>());
    }
    return SelectaProduct.empty();
  }

  SelectaProduct copyWith({
    String? id,
    String? productName,
    String? imageUrl,
    String? itemCode,
    double? buyingPrice,
    double? sellingPrice,
    String? category,
    bool? isActive,
    int? stockQuantity,
    int? lowStockThreshold,
    Timestamp? importedAt,
    Timestamp? updatedAt,
  }) {
    return SelectaProduct(
      id: id ?? this.id,
      productName: productName ?? this.productName,
      imageUrl: imageUrl ?? this.imageUrl,
      itemCode: itemCode ?? this.itemCode,
      buyingPrice: buyingPrice ?? this.buyingPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      category: category ?? this.category,
      isActive: isActive ?? this.isActive,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      importedAt: importedAt ?? this.importedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Creates or updates a dealer's [SelectaProduct] from the master [AdminSelectaProduct],
  /// preserving the dealer's local [isActive] status and stock levels if already present.
  factory SelectaProduct.fromAdminProduct({
    required String id,
    required String productName,
    required String imageUrl,
    required double buyingPrice,
    required double sellingPrice,
    bool isActive = true,
    int stockQuantity = 0,
    int lowStockThreshold = 10,
    String itemCode = '',
    String category = '',
    Timestamp? importedAt,
    Timestamp? updatedAt,
  }) {
    return SelectaProduct(
      id: id,
      productName: productName,
      imageUrl: imageUrl,
      itemCode: itemCode,
      buyingPrice: buyingPrice,
      sellingPrice: sellingPrice,
      category: category,
      isActive: isActive,
      stockQuantity: stockQuantity,
      lowStockThreshold: lowStockThreshold,
      importedAt: importedAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'productName': productName,
      'imageUrl': imageUrl,
      'itemCode': itemCode,
      'buyingPrice': buyingPrice,
      'sellingPrice': sellingPrice,
      'price': sellingPrice, // backward compatibility
      'category': category,
      'isActive': isActive,
      'stockQuantity': stockQuantity,
      'lowStockThreshold': lowStockThreshold,
      'importedAt': importedAt,
      'updatedAt': updatedAt,
    };
  }
}
