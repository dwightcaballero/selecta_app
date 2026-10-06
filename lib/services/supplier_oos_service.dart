import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/supplier_oos_log.dart';

/// Structure containing supplier availability metrics for a specific product and month.
class SupplierProductHistory {
  final String productId;
  final String productName;
  final int year;
  final int month;
  final Map<DateTime, SupplierProductDayStatus> dailyStatus;
  final int totalRecordedDays;
  final int inStockDays;
  final int outOfStockDays;
  final int currentOosStreak;
  final int longestOosStreak;

  const SupplierProductHistory({
    required this.productId,
    required this.productName,
    required this.year,
    required this.month,
    required this.dailyStatus,
    required this.totalRecordedDays,
    required this.inStockDays,
    required this.outOfStockDays,
    required this.currentOosStreak,
    required this.longestOosStreak,
  });

  double get availabilityRate =>
      totalRecordedDays > 0 ? (inStockDays / totalRecordedDays) * 100 : 0.0;
}

/// Lean service managing supplier out-of-stock (OOS) daily records.
/// Performs 1 single write per daily scan, keeping database costs and reads minimal.
class SupplierOosService {
  final FirebaseFirestore _firestore;

  SupplierOosService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collectionName = 'supplier_oos_logs';

  /// Records or merges a single daily scan of supplier stock status.
  /// Exactly 1 document write per scan.
  Future<void> recordDailyScan({
    required DateTime scanDate,
    required List<String> outOfStockProductIds,
    required List<String> matchedProductIds,
    String? notes,
  }) async {
    final dateKey = DateFormat('yyyy-MM-dd').format(scanDate);
    final docRef = _firestore.collection(collectionName).doc(dateKey);

    final snapshot = await docRef.get();
    if (snapshot.exists) {
      final existing = SupplierOosLog.fromMap(dateKey, snapshot.data()!);
      final mergedOos = {
        ...existing.outOfStockProductIds,
        ...outOfStockProductIds,
      }.toList();
      final mergedMatched = {
        ...existing.matchedProductIds,
        ...matchedProductIds,
      }.toList();

      await docRef.set({
        'date': dateKey,
        'scanDate': Timestamp.fromDate(scanDate),
        'scannedAt': Timestamp.now(),
        'outOfStockProductIds': mergedOos,
        'matchedProductIds': mergedMatched,
        'notes': ?notes,
      }, SetOptions(merge: true));
    } else {
      final log = SupplierOosLog(
        date: dateKey,
        scanDate: scanDate,
        scannedAt: Timestamp.now(),
        outOfStockProductIds: outOfStockProductIds,
        matchedProductIds: matchedProductIds,
        notes: notes,
      );
      await docRef.set(log.toMap());
    }
  }

  /// Fetches all daily scan logs recorded for a given year and month.
  Future<List<SupplierOosLog>> getLogsForMonth(int year, int month) async {
    final startKey = '$year-${month.toString().padLeft(2, '0')}-01';
    final endKey = '$year-${month.toString().padLeft(2, '0')}-31';

    final query = await _firestore
        .collection(collectionName)
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: startKey)
        .where(FieldPath.documentId, isLessThanOrEqualTo: endKey)
        .get();

    return query.docs.map((d) => SupplierOosLog.fromMap(d.id, d.data())).toList();
  }

  /// Computes the calendar availability and streak insights for a given product in a month.
  Future<SupplierProductHistory> getProductHistory({
    required String productId,
    required String productName,
    required int year,
    required int month,
  }) async {
    final logs = await getLogsForMonth(year, month);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final Map<DateTime, SupplierProductDayStatus> statusMap = {};

    int recordedCount = 0;
    int inStockCount = 0;
    int oosCount = 0;

    // Map logs by YYYY-MM-DD
    final Map<String, SupplierOosLog> logByDate = {
      for (final log in logs) log.date: log,
    };

    int currentStreak = 0;
    int maxStreak = 0;
    int tempStreak = 0;

    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      final key = DateFormat('yyyy-MM-dd').format(date);
      final log = logByDate[key];

      if (log == null) {
        statusMap[date] = SupplierProductDayStatus.notRecorded;
        continue;
      }

      recordedCount++;
      if (log.isProductOutOfStock(productId)) {
        statusMap[date] = SupplierProductDayStatus.outOfStock;
        oosCount++;
        tempStreak++;
        if (tempStreak > maxStreak) maxStreak = tempStreak;
      } else {
        // Tracked and not OOS -> available
        statusMap[date] = SupplierProductDayStatus.inStock;
        inStockCount++;
        tempStreak = 0;
      }
    }

    // Calculate current streak backwards from latest recorded day
    final recordedDaysDescending = statusMap.entries
        .where((e) => e.value != SupplierProductDayStatus.notRecorded)
        .toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    for (final entry in recordedDaysDescending) {
      if (entry.value == SupplierProductDayStatus.outOfStock) {
        currentStreak++;
      } else {
        break;
      }
    }

    return SupplierProductHistory(
      productId: productId,
      productName: productName,
      year: year,
      month: month,
      dailyStatus: statusMap,
      totalRecordedDays: recordedCount,
      inStockDays: inStockCount,
      outOfStockDays: oosCount,
      currentOosStreak: currentStreak,
      longestOosStreak: maxStreak,
    );
  }

  /// Generates a supplier concern message that the dealer can send to their Selecta representative.
  String generateConcernMessage(SupplierProductHistory history) {
    final monthName = DateFormat('MMMM yyyy').format(DateTime(history.year, history.month));
    final buffer = StringBuffer();
    buffer.writeln('📋 *Selecta Dealer Stock Availability Concern*');
    buffer.writeln('Product: *${history.productName}*');
    buffer.writeln('Period: $monthName');
    buffer.writeln('• Total Recorded Days: ${history.totalRecordedDays}');
    buffer.writeln('• Out-of-Stock (OOS) Days: ${history.outOfStockDays} days');
    buffer.writeln('• Supplier Availability Rate: ${history.availabilityRate.toStringAsFixed(1)}%');
    if (history.currentOosStreak > 1) {
      buffer.writeln('⚠️ *Currently Out-of-Stock for ${history.currentOosStreak} consecutive recorded days.*');
    }
    buffer.writeln();
    buffer.writeln('We have local customer demand but cannot replenish due to supplier stockout. Kindly advise when this item will be replenished at the depot. Thank you!');
    return buffer.toString();
  }
}
