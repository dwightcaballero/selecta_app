import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/supplier_product_mapping.dart';

class SupplierMappingService {
  SupplierMappingService({String collectionPath = supplierCollection})
      : _collection = FirebaseFirestore.instance.collection(collectionPath);

  /// Learned aliases from supplier invoices / purchase orders.
  static const String supplierCollection = 'supplier_product_mappings';

  /// Learned aliases from store-order receipts of the external booking app.
  static const String bookingReceiptCollection = 'booking_receipt_mappings';

  final CollectionReference<Map<String, dynamic>> _collection;

  List<SupplierProductMapping>? _cachedMappings;
  DateTime? _lastCacheTime;

  /// Fetches all learned supplier invoice mappings, caching for 5 minutes by default.
  Future<List<SupplierProductMapping>> getAllMappings({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedMappings != null &&
        _lastCacheTime != null &&
        DateTime.now().difference(_lastCacheTime!) < const Duration(minutes: 5)) {
      return _cachedMappings!;
    }

    try {
      final snapshot = await _collection.get();
      _cachedMappings = snapshot.docs.map((doc) => SupplierProductMapping.fromFirestore(doc)).toList();
      _lastCacheTime = DateTime.now();
      return _cachedMappings!;
    } catch (_) {
      return _cachedMappings ?? [];
    }
  }

  /// Searches known mappings for a match against the raw invoice text.
  /// Handles exact normalized matches, as well as prefix matches for truncated names.
  SupplierProductMapping? findMatch(
    String rawSupplierText, {
    List<SupplierProductMapping>? mappings,
  }) {
    final list = mappings ?? _cachedMappings ?? [];
    if (list.isEmpty || rawSupplierText.trim().isEmpty) return null;

    final targetNormalized = SupplierProductMapping.normalize(rawSupplierText);
    if (targetNormalized.isEmpty) return null;

    // 1. Exact normalized match
    for (final mapping in list) {
      if (mapping.normalizedText == targetNormalized) {
        return mapping;
      }
    }

    // 2. Prefix / Truncation match:
    // If the invoice was cut off (e.g. "CORNETTO DISC WH"), but we know "CORNETTO DISC WHITE"
    // or vice versa, match if the prefix is at least 6 characters.
    if (targetNormalized.length >= 6) {
      for (final mapping in list) {
        if (mapping.normalizedText.startsWith(targetNormalized) ||
            targetNormalized.startsWith(mapping.normalizedText)) {
          return mapping;
        }
      }
    }

    return null;
  }

  /// Saves or updates a confirmed mapping between a supplier invoice string and a catalog product.
  Future<void> saveOrUpdateMapping({
    required String rawSupplierText,
    required InventoryItem product,
  }) async {
    final normalized = SupplierProductMapping.normalize(rawSupplierText);
    if (normalized.isEmpty) return;

    try {
      final query = await _collection.where('normalizedText', isEqualTo: normalized).limit(1).get();

      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        final data = doc.data();
        final rawCandidates = (data['candidateProductIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
        final existingPrimary = data['productId'] as String? ?? '';
        final candidates = Set<String>.from(rawCandidates);
        if (existingPrimary.isNotEmpty) candidates.add(existingPrimary);
        candidates.add(product.id);

        final isMulti = candidates.length > 1;

        await doc.reference.update({
          'productId': product.id,
          'productName': product.productName,
          'productSource': product.source.key,
          'candidateProductIds': candidates.toList(),
          'isMultiMatch': isMulti,
          'usageCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _collection.add({
          'rawSupplierText': rawSupplierText.trim(),
          'normalizedText': normalized,
          'productId': product.id,
          'productName': product.productName,
          'productSource': product.source.key,
          'candidateProductIds': [product.id],
          'isMultiMatch': false,
          'usageCount': 1,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // Invalidate cache
      _cachedMappings = null;
      _lastCacheTime = null;
    } catch (_) {
      // Best-effort save; non-blocking
    }
  }
}
