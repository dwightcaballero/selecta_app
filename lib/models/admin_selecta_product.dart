import 'package:cloud_firestore/cloud_firestore.dart';

/// Master Selecta product model managed exclusively by Admins.
/// Consists only of imageUrl, productName, buyingPrice, and sellingPrice.
/// Serves as the centralized source of truth for all dealers across Firebase databases.
class AdminSelectaProduct {
  final String id;
  final String productName;
  final String imageUrl;
  final String barcode;
  final double buyingPrice;
  final double sellingPrice;
  final String category; // 'By Piece' or 'By Case'
  final String tag; // 'Best Seller', 'New Product', or ''
  final String? subCategoryId; // null = Unassigned
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  const AdminSelectaProduct({
    required this.id,
    required this.productName,
    required this.imageUrl,
    this.barcode = '',
    this.buyingPrice = 0.0,
    this.sellingPrice = 0.0,
    this.category = 'By Piece',
    this.tag = '',
    this.subCategoryId,
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
        barcode: '',
        buyingPrice: 0.0,
        sellingPrice: 0.0,
        category: 'By Piece',
        tag: '',
        subCategoryId: null,
      );

  factory AdminSelectaProduct.fromJson(String id, Map<String, Object?> json) {
    final legacyPrice = (json['price'] as num?)?.toDouble() ?? 0.0;
    final buyingPrice = (json['buyingPrice'] as num?)?.toDouble() ?? legacyPrice;
    final sellingPrice = (json['sellingPrice'] as num?)?.toDouble() ?? legacyPrice;
    final rawCategory = (json['category'] as String? ?? '').trim();
    final isCase = rawCategory.toLowerCase().contains('case');
    final category = isCase ? 'By Case' : 'By Piece';

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
      barcode: (json['barcode'] as String? ?? '').trim(),
      buyingPrice: buyingPrice,
      sellingPrice: sellingPrice,
      category: category,
      tag: (json['tag'] as String? ?? '').trim(),
      subCategoryId: json['subCategoryId'] as String?,
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

    final rawCategory = readString('category');
    final isCase = rawCategory.toLowerCase().contains('case');
    final category = isCase ? 'By Case' : 'By Piece';
    final subCatId = readString('subCategoryId');

    return AdminSelectaProduct(
      id: id,
      productName: readString('productName'),
      imageUrl: readString('imageUrl'),
      barcode: readString('barcode'),
      buyingPrice: buyingPrice,
      sellingPrice: sellingPrice,
      category: category,
      tag: readString('tag'),
      subCategoryId: subCatId.isNotEmpty ? subCatId : null,
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
    String? barcode,
    double? buyingPrice,
    double? sellingPrice,
    String? category,
    String? tag,
    String? subCategoryId,
    bool clearSubCategoryId = false,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return AdminSelectaProduct(
      id: id ?? this.id,
      productName: productName ?? this.productName,
      imageUrl: imageUrl ?? this.imageUrl,
      barcode: barcode ?? this.barcode,
      buyingPrice: buyingPrice ?? this.buyingPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      category: category ?? this.category,
      tag: tag ?? this.tag,
      subCategoryId: clearSubCategoryId ? null : (subCategoryId ?? this.subCategoryId),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'productName': productName,
      'imageUrl': imageUrl,
      'barcode': barcode,
      'buyingPrice': buyingPrice,
      'sellingPrice': sellingPrice,
      'category': category,
      'tag': tag,
      if (subCategoryId != null) 'subCategoryId': subCategoryId,
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
      'barcode': barcode,
      'buyingPrice': buyingPrice,
      'sellingPrice': sellingPrice,
      'category': category,
      'tag': tag,
      if (subCategoryId != null) 'subCategoryId': subCategoryId,
      'updatedAt': (updatedAt ?? Timestamp.now()).toDate().toUtc().toIso8601String(),
    };
  }
}
