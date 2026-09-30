import 'package:cloud_firestore/cloud_firestore.dart';

/// Master Selecta product model managed exclusively by Admins.
/// Consists only of imageUrl, productName, buyingPrice, and sellingPrice.
/// Serves as the centralized source of truth for all dealers across Firebase databases.
class AdminSelectaProduct {
  final String id;
  final String productName;
  final String imageUrl;
  final double buyingPrice;
  final double sellingPrice;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  const AdminSelectaProduct({
    required this.id,
    required this.productName,
    required this.imageUrl,
    this.buyingPrice = 0.0,
    this.sellingPrice = 0.0,
    this.createdAt,
    this.updatedAt,
  });

  /// Gross margin amount (sellingPrice - buyingPrice).
  double get margin => sellingPrice - buyingPrice;

  /// Margin percentage relative to buying price.
  double get marginPercent =>
      buyingPrice > 0 ? ((sellingPrice - buyingPrice) / buyingPrice) * 100 : 0;

  static AdminSelectaProduct empty() => const AdminSelectaProduct(
        id: '',
        productName: '',
        imageUrl: '',
        buyingPrice: 0.0,
        sellingPrice: 0.0,
      );

  factory AdminSelectaProduct.fromJson(String id, Map<String, Object?> json) {
    final legacyPrice = (json['price'] as num?)?.toDouble() ?? 0.0;
    final buyingPrice = (json['buyingPrice'] as num?)?.toDouble() ?? legacyPrice;
    final sellingPrice = (json['sellingPrice'] as num?)?.toDouble() ?? legacyPrice;

    Timestamp? parseTimestamp(Object? val) {
      if (val is Timestamp) return val;
      if (val is String && val.isNotEmpty) {
        final dt = DateTime.tryParse(val);
        if (dt != null) return Timestamp.fromDate(dt);
      }
      if (val is int) {
        return Timestamp.fromMillisecondsSinceEpoch(val);
      }
      return null;
    }

    return AdminSelectaProduct(
      id: id,
      productName: (json['productName'] as String? ?? '').trim(),
      imageUrl: (json['imageUrl'] as String? ?? '').trim(),
      buyingPrice: buyingPrice,
      sellingPrice: sellingPrice,
      createdAt: parseTimestamp(json['createdAt']),
      updatedAt: parseTimestamp(json['updatedAt']),
    );
  }

  /// Parses a document returned from the Firestore REST API (`documents` list item).
  factory AdminSelectaProduct.fromFirestoreRestDoc(Map<String, dynamic> doc) {
    final fullName = doc['name'] as String? ?? '';
    final id = fullName.isNotEmpty ? fullName.split('/').last : '';
    final fields = (doc['fields'] as Map<String, dynamic>?) ?? {};

    String readString(String key) {
      final f = fields[key] as Map<String, dynamic>?;
      return (f?['stringValue'] as String? ?? '').trim();
    }

    double readDouble(String key) {
      final f = fields[key] as Map<String, dynamic>?;
      if (f == null) return 0.0;
      if (f.containsKey('doubleValue')) {
        return (f['doubleValue'] as num?)?.toDouble() ?? 0.0;
      }
      if (f.containsKey('integerValue')) {
        return double.tryParse(f['integerValue'].toString()) ?? 0.0;
      }
      return 0.0;
    }

    Timestamp? readTimestamp(String key) {
      final f = fields[key] as Map<String, dynamic>?;
      final tsStr = f?['timestampValue'] as String?;
      if (tsStr != null && tsStr.isNotEmpty) {
        final dt = DateTime.tryParse(tsStr);
        if (dt != null) return Timestamp.fromDate(dt);
      }
      return null;
    }

    final legacyPrice = readDouble('price');
    final buyingPrice = fields.containsKey('buyingPrice') ? readDouble('buyingPrice') : legacyPrice;
    final sellingPrice = fields.containsKey('sellingPrice') ? readDouble('sellingPrice') : legacyPrice;

    final docUpdateTime = doc['updateTime'] as String?;
    Timestamp? updatedAt = readTimestamp('updatedAt');
    if (updatedAt == null && docUpdateTime != null) {
      final dt = DateTime.tryParse(docUpdateTime);
      if (dt != null) updatedAt = Timestamp.fromDate(dt);
    }

    return AdminSelectaProduct(
      id: id,
      productName: readString('productName'),
      imageUrl: readString('imageUrl'),
      buyingPrice: buyingPrice,
      sellingPrice: sellingPrice,
      createdAt: readTimestamp('createdAt'),
      updatedAt: updatedAt,
    );
  }

  factory AdminSelectaProduct.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      return AdminSelectaProduct.fromJson(document.id, document.data()!.cast<String, Object?>());
    }
    return AdminSelectaProduct.empty();
  }

  AdminSelectaProduct copyWith({
    String? id,
    String? productName,
    String? imageUrl,
    double? buyingPrice,
    double? sellingPrice,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return AdminSelectaProduct(
      id: id ?? this.id,
      productName: productName ?? this.productName,
      imageUrl: imageUrl ?? this.imageUrl,
      buyingPrice: buyingPrice ?? this.buyingPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
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
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  /// Portable JSON map for exporting/importing the Admin catalog across databases or GitHub.
  Map<String, Object?> toExportJson() {
    return {
      'id': id,
      'productName': productName,
      'imageUrl': imageUrl,
      'buyingPrice': buyingPrice,
      'sellingPrice': sellingPrice,
      'updatedAt': (updatedAt ?? Timestamp.now()).toDate().toUtc().toIso8601String(),
    };
  }
}
