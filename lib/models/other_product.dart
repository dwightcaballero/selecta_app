import 'package:cloud_firestore/cloud_firestore.dart';

class OtherProduct {
  String productName;
  String imageUrl;
  double buyingPrice;
  double sellingPrice;
  bool isActive;
  Timestamp? createdAt;
  Timestamp? updatedAt;

  OtherProduct({
    required this.productName,
    required this.imageUrl,
    required this.buyingPrice,
    required this.sellingPrice,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  static OtherProduct empty() => OtherProduct(
        productName: '',
        imageUrl: '',
        buyingPrice: 0.0,
        sellingPrice: 0.0,
        isActive: true,
      );

  factory OtherProduct.fromJson(Map<String, Object?> json) {
    return OtherProduct(
      productName: json['productName'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      buyingPrice: (json['buyingPrice'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (json['sellingPrice'] as num?)?.toDouble() ?? 0.0,
      isActive: json['isActive'] as bool? ?? true,
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
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return OtherProduct(
      productName: productName ?? this.productName,
      imageUrl: imageUrl ?? this.imageUrl,
      buyingPrice: buyingPrice ?? this.buyingPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      isActive: isActive ?? this.isActive,
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
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  double get margin => sellingPrice - buyingPrice;

  double get marginPercent =>
      buyingPrice > 0 ? ((sellingPrice - buyingPrice) / buyingPrice) * 100 : 0;
}
