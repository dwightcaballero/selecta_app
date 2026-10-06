import 'package:cloud_firestore/cloud_firestore.dart';

/// Lightweight record of a supplier stock sheet scan for a single day.
/// Tracks which products were out of stock versus available, with minimal Firestore writes.
class SupplierOosLog {
  /// Date key in format YYYY-MM-DD (also used as document ID).
  final String date;

  /// Normalized date timestamp.
  final DateTime scanDate;

  /// Audit timestamp when the document was scanned.
  final Timestamp scannedAt;

  /// Product IDs from dealer inventory that were confirmed OUT OF STOCK on this day.
  final List<String> outOfStockProductIds;

  /// All dealer catalog product IDs that were verified/present in the supplier document.
  final List<String> matchedProductIds;

  final String? notes;

  const SupplierOosLog({
    required this.date,
    required this.scanDate,
    required this.scannedAt,
    required this.outOfStockProductIds,
    required this.matchedProductIds,
    this.notes,
  });

  factory SupplierOosLog.fromMap(String id, Map<String, dynamic> map) {
    final scannedAtTs = map['scannedAt'] as Timestamp? ?? Timestamp.now();
    DateTime parsedDate;
    if (map['scanDate'] is Timestamp) {
      parsedDate = (map['scanDate'] as Timestamp).toDate();
    } else {
      parsedDate = DateTime.tryParse(id) ?? scannedAtTs.toDate();
    }

    return SupplierOosLog(
      date: id,
      scanDate: parsedDate,
      scannedAt: scannedAtTs,
      outOfStockProductIds: List<String>.from(map['outOfStockProductIds'] ?? const []),
      matchedProductIds: List<String>.from(map['matchedProductIds'] ?? const []),
      notes: map['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'scanDate': Timestamp.fromDate(scanDate),
      'scannedAt': scannedAt,
      'outOfStockProductIds': outOfStockProductIds,
      'matchedProductIds': matchedProductIds,
      'notes': ?notes,
    };
  }

  bool isProductOutOfStock(String productId) => outOfStockProductIds.contains(productId);

  bool isProductTracked(String productId) => matchedProductIds.contains(productId);
}

enum SupplierProductDayStatus {
  inStock,
  outOfStock,
  notRecorded,
}
