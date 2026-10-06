import 'package:cloud_firestore/cloud_firestore.dart';

class OtherProduct {
  String productName;
  String imageUrl;
  double buyingPrice;
  double sellingPrice;
  bool isActive;
  int stockQuantity;
  int reservedQuantity;
  int lowStockThreshold;
  Timestamp? createdAt;
  Timestamp? updatedAt;

  OtherProduct({
    required this.productName,
    required this.imageUrl,
    required this.buyingPrice,
    required this.sellingPrice,
    this.isActive = true,
    this.stockQuantity = 0,
    this.reservedQuantity = 0,
    this.lowStockThreshold = 10,
    this.createdAt,
    this.updatedAt,
  });

  static OtherProduct empty() => OtherProduct(
        productName: '',
        imageUrl: '',
        buyingPrice: 0.0,
        sellingPrice: 0.0,
        isActive: true,
        stockQuantity: 0,
        reservedQuantity: 0,
        lowStockThreshold: 10,
      );

  factory OtherProduct.fromJson(Map<String, Object?> json) {
    return OtherProduct(
      productName: json['productName'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      buyingPrice: (json['buyingPrice'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (json['sellingPrice'] as num?)?.toDouble() ?? 0.0,
      isActive: json['isActive'] as bool? ?? true,
      stockQuantity: (json['stockQuantity'] as num?)?.toInt() ?? 0,
      reservedQuantity: (json['reservedQuantity'] as num?)?.toInt() ?? 0,
      lowStockThreshold: (json['lowStockThreshold'] as num?)?.toInt() ?? 10,
      createdAt: json['createdAt'] as Timestamp?,
      updatedAt: json['updatedAt'] as Timestamp?,
    );
  }

  factory OtherProduct.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      final data = document.data()!;
      return OtherProduct(
        productName: data['productName'] ?? '',
        imageUrl: data['imageUrl'] ?? '',
        buyingPrice: (data['buyingPrice'] as num?)?.toDouble() ?? 0.0,
        sellingPrice: (data['sellingPrice'] as num?)?.toDouble() ?? 0.0,
        isActive: data['isActive'] as bool? ?? true,
        stockQuantity: (data['stockQuantity'] as num?)?.toInt() ?? 0,
        reservedQuantity: (data['reservedQuantity'] as num?)?.toInt() ?? 0,
        lowStockThreshold: (data['lowStockThreshold'] as num?)?.toInt() ?? 10,
        createdAt: data['createdAt'] as Timestamp?,
        updatedAt: data['updatedAt'] as Timestamp?,
      );
    }
    return OtherProduct.empty();
  }

  OtherProduct copyWith({
    String? productName,
    String? imageUrl,
    double? buyingPrice,
    double? sellingPrice,
    bool? isActive,
    int? stockQuantity,
    int? reservedQuantity,
    int? lowStockThreshold,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return OtherProduct(
      productName: productName ?? this.productName,
      imageUrl: imageUrl ?? this.imageUrl,
      buyingPrice: buyingPrice ?? this.buyingPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      isActive: isActive ?? this.isActive,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      reservedQuantity: reservedQuantity ?? this.reservedQuantity,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'productName': productName,
      'imageUrl': imageUrl,
      'buyingPrice': buyingPrice,
      'sellingPrice': sellingPrice,
      'isActive': isActive,
      'stockQuantity': stockQuantity,
      'reservedQuantity': reservedQuantity,
      'lowStockThreshold': lowStockThreshold,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  double get margin => sellingPrice - buyingPrice;

  double get marginPercent =>
      buyingPrice > 0 ? ((sellingPrice - buyingPrice) / buyingPrice) * 100 : 0;

  int get availableQuantity =>
      (stockQuantity - reservedQuantity) < 0 ? 0 : (stockQuantity - reservedQuantity);

  bool get isOutOfStock => stockQuantity <= 0;

  bool get isAvailableOutOfStock => availableQuantity <= 0;

  bool get isLowStock => stockQuantity > 0 && availableQuantity <= lowStockThreshold;

  double get stockCostValue => stockQuantity * buyingPrice;

  double get stockRetailValue => stockQuantity * sellingPrice;
}
