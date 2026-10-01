import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a learned / confirmed alias mapping between a supplier invoice
/// raw or truncated description (e.g. "CORNETTO DISC WH...") and an app product.
class SupplierProductMapping {
  final String id;
  final String rawSupplierText;
  final String normalizedText;
  final String productId;
  final String productName;
  final String productSource; // 'selecta' | 'other'
  final List<String> candidateProductIds;
  final bool isMultiMatch;
  final int usageCount;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  const SupplierProductMapping({
    required this.id,
    required this.rawSupplierText,
    required this.normalizedText,
    required this.productId,
    required this.productName,
    this.productSource = 'selecta',
    this.candidateProductIds = const [],
    this.isMultiMatch = false,
    this.usageCount = 1,
    this.createdAt,
    this.updatedAt,
  });

  /// Normalizes supplier text for consistent fuzzy matching (uppercase, trim, clean ellipses).
  static String normalize(String text) {
    return text
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[\.…]+\s*$'), '') // strip trailing ellipsis / dots
        .trim();
  }

  factory SupplierProductMapping.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final rawCandidateIds = (data['candidateProductIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final primaryProductId = data['productId'] as String? ?? '';
    final candidateProductIds = rawCandidateIds.isNotEmpty
        ? rawCandidateIds
        : (primaryProductId.isNotEmpty ? [primaryProductId] : <String>[]);
    final isMultiMatch = (data['isMultiMatch'] as bool?) ?? (candidateProductIds.length > 1);

    return SupplierProductMapping(
      id: doc.id,
      rawSupplierText: data['rawSupplierText'] as String? ?? '',
      normalizedText: data['normalizedText'] as String? ?? '',
      productId: primaryProductId,
      productName: data['productName'] as String? ?? '',
      productSource: data['productSource'] as String? ?? 'selecta',
      candidateProductIds: candidateProductIds,
      isMultiMatch: isMultiMatch,
      usageCount: (data['usageCount'] as num?)?.toInt() ?? 1,
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'rawSupplierText': rawSupplierText,
      'normalizedText': normalizedText,
      'productId': productId,
      'productName': productName,
      'productSource': productSource,
      'candidateProductIds': candidateProductIds,
      'isMultiMatch': isMultiMatch,
      'usageCount': usageCount,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
