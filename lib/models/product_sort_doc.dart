import 'package:cloud_firestore/cloud_firestore.dart';

/// Document representing dealer-customized product ordering within sub-categories.
///
/// Stored in Firestore at `product_sort/{dealerId}`.
class ProductSortDoc {
  final String dealerId;
  /// Mapping of subCategoryId -> list of product IDs in custom order for 'By Piece'
  final Map<String, List<String>> byPiece;
  /// Mapping of subCategoryId -> list of product IDs in custom order for 'By Case'
  final Map<String, List<String>> byCase;
  final Timestamp? updatedAt;
  final String updatedBy;

  const ProductSortDoc({
    required this.dealerId,
    this.byPiece = const {},
    this.byCase = const {},
    this.updatedAt,
    this.updatedBy = '',
  });

  static ProductSortDoc empty(String dealerId) => ProductSortDoc(
        dealerId: dealerId,
        byPiece: const {},
        byCase: const {},
        updatedAt: null,
        updatedBy: '',
      );

  factory ProductSortDoc.fromJson(String dealerId, Map<String, dynamic> json) {
    Map<String, List<String>> parseMap(dynamic mapRaw) {
      if (mapRaw is! Map) return {};
      final res = <String, List<String>>{};
      mapRaw.forEach((k, v) {
        if (v is List) {
          res[k.toString()] = v.map((e) => e.toString()).toList();
        }
      });
      return res;
    }

    Timestamp? parseTimestamp(dynamic val) {
      if (val is Timestamp) return val;
      if (val is String && val.isNotEmpty) {
        final dt = DateTime.tryParse(val);
        if (dt != null) return Timestamp.fromDate(dt);
      }
      return null;
    }

    return ProductSortDoc(
      dealerId: dealerId,
      byPiece: parseMap(json['byPiece']),
      byCase: parseMap(json['byCase']),
      updatedAt: parseTimestamp(json['updatedAt']),
      updatedBy: json['updatedBy'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'byPiece': byPiece,
      'byCase': byCase,
      'updatedAt': updatedAt ?? Timestamp.now(),
      'updatedBy': updatedBy,
    };
  }

  ProductSortDoc copyWith({
    String? dealerId,
    Map<String, List<String>>? byPiece,
    Map<String, List<String>>? byCase,
    Timestamp? updatedAt,
    String? updatedBy,
  }) {
    return ProductSortDoc(
      dealerId: dealerId ?? this.dealerId,
      byPiece: byPiece ?? Map.from(this.byPiece),
      byCase: byCase ?? Map.from(this.byCase),
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}
