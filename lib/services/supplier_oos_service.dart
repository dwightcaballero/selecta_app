import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/selecta_product.dart';
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

  /// Stream of all daily scan logs recorded for a given year and month.
  Stream<List<SupplierOosLog>> getLogsStreamForMonth(int year, int month) {
    final startKey = '$year-${month.toString().padLeft(2, '0')}-01';
    final endKey = '$year-${month.toString().padLeft(2, '0')}-31';

    return _firestore
        .collection(collectionName)
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: startKey)
        .where(FieldPath.documentId, isLessThanOrEqualTo: endKey)
        .snapshots()
        .map((snap) => snap.docs.map((d) => SupplierOosLog.fromMap(d.id, d.data())).toList());
  }

  /// Deletes a daily scan log by its dateKey (YYYY-MM-DD).
  Future<void> deleteDailyScan(String dateKey) async {
    await _firestore.collection(collectionName).doc(dateKey).delete();
  }

  /// Computes product OOS summaries for a list of Selecta products, sorted by SRP ascending.
  List<ProductOosSummary> computeSummaries({
    required List<SelectaProduct> products,
    required List<SupplierOosLog> monthLogs,
  }) {
    // Sort logs chronologically
    final sortedLogs = List<SupplierOosLog>.from(monthLogs)
      ..sort((a, b) => a.date.compareTo(b.date));

    final List<ProductOosSummary> summaries = [];

    for (final product in products) {
      int recordedDays = 0;
      int oosDays = 0;
      int currentStreak = 0;
      DateTime? lastDate;
      SupplierProductDayStatus latestStatus = SupplierProductDayStatus.notRecorded;

      // Filter logs tracking this product
      final trackingLogs = sortedLogs
          .where((l) => l.isProductTracked(product.id) || l.isProductOutOfStock(product.id))
          .toList();

      if (trackingLogs.isNotEmpty) {
        recordedDays = trackingLogs.length;
        oosDays = trackingLogs.where((l) => l.isProductOutOfStock(product.id)).length;
        final lastLog = trackingLogs.last;
        lastDate = lastLog.scanDate;
        latestStatus = lastLog.isProductOutOfStock(product.id)
            ? SupplierProductDayStatus.outOfStock
            : SupplierProductDayStatus.inStock;

        // Calculate current streak backwards from latest log
        for (int i = trackingLogs.length - 1; i >= 0; i--) {
          if (trackingLogs[i].isProductOutOfStock(product.id)) {
            currentStreak++;
          } else {
            break;
          }
        }
      }

      summaries.add(ProductOosSummary(
        product: product,
        isCurrentlyOos: latestStatus == SupplierProductDayStatus.outOfStock,
        currentStreak: currentStreak,
        monthOosDays: oosDays,
        totalRecordedDays: recordedDays,
        lastRecordedDate: lastDate,
        latestStatus: latestStatus,
      ));
    }

    // Sort by SRP ascending, then alphabetically by name (identical to book order page)
    summaries.sort((a, b) => Helperfunctions.compareBySrpAndName(
          nameA: a.product.productName,
          priceA: a.product.sellingPrice,
          nameB: b.product.productName,
          priceB: b.product.sellingPrice,
        ));

    return summaries;
  }

  /// Generates a batch concern message for multiple products to send to the supplier rep.
  String generateBatchConcernMessage({
    required List<ProductOosSummary> oosSummaries,
    required DateTime monthDate,
  }) {
    final monthName = DateFormat('MMMM yyyy').format(monthDate);
    final buffer = StringBuffer();
    buffer.writeln('📋 *Selecta Dealer Out-of-Stock (OOS) Concern Notice*');
    buffer.writeln('Period: $monthName');
    buffer.writeln('Total Products Affected: ${oosSummaries.length}');
    buffer.writeln();
    buffer.writeln('The following Selecta products are currently unavailable from the supplier depot:');
    buffer.writeln();
    for (int i = 0; i < oosSummaries.length; i++) {
      final s = oosSummaries[i];
      final streakStr = s.currentStreak > 1 ? ' (${s.currentStreak} consecutive days)' : '';
      buffer.writeln('${i + 1}. *${s.product.productName}* (SRP ₱${s.product.sellingPrice.toStringAsFixed(2)}) — OOS for ${s.monthOosDays} recorded day(s)$streakStr');
    }
    buffer.writeln();
    buffer.writeln('We have customer demand for these items but cannot replenish due to depot stockout. Kindly advise on replenishment schedule. Thank you!');
    return buffer.toString();
  }
}

/// Lightweight snapshot summary of a single Selecta product for the OOS list.
class ProductOosSummary {
  final SelectaProduct product;
  final bool isCurrentlyOos;
  final int currentStreak;
  final int monthOosDays;
  final int totalRecordedDays;
  final DateTime? lastRecordedDate;
  final SupplierProductDayStatus latestStatus;

  const ProductOosSummary({
    required this.product,
    required this.isCurrentlyOos,
    required this.currentStreak,
    required this.monthOosDays,
    required this.totalRecordedDays,
    this.lastRecordedDate,
    required this.latestStatus,
  });

  double get availabilityRate =>
      totalRecordedDays > 0 ? ((totalRecordedDays - monthOosDays) / totalRecordedDays) * 100 : 0.0;
}
