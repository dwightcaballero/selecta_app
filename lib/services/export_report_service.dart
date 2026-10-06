import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/other_product.dart';
import 'package:selecta_ops/models/proof_of_visit.dart';
import 'package:selecta_ops/models/purchaseorder.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/other_product_service.dart';
import 'package:selecta_ops/services/proof_of_visit_service.dart';
import 'package:selecta_ops/services/purchaseorder_service.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';

enum ExportReportType {
  sales('Sales & Orders Report', 'Daily/weekly customer order amounts, payment methods, and status.'),
  deliveries('Delivery Summary Report', 'Completed, pending, and returned delivery operations with invoices.'),
  creditAging('Credit & AR Aging Report', 'Accounts receivable ledger broken down into aging buckets (0-15d, 16-30d, 31-60d, 60d+).'),
  inventory('Inventory & Stock Sheet', 'Current on-hand stock quantities, wholesale costs, retail SRPs, and valuations.'),
  storeVisits('PJP Store Visits Log', 'Field store visit log with timestamps, agents, notes, and photo references.');

  final String title;
  final String description;
  const ExportReportType(this.title, this.description);
}

class ExportResult {
  final String filePath;
  final String fileName;
  final int rowCount;
  final String csvContent;
  final Map<String, dynamic> summary;

  ExportResult({
    required this.filePath,
    required this.fileName,
    required this.rowCount,
    required this.csvContent,
    required this.summary,
  });
}

/// Service for generating RFC-compliant CSV & Excel export reports for Selecta Ops.
class ExportReportService {
  final FirebaseFirestore _firestore;

  ExportReportService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Escapes CSV cells according to RFC 4180 rules.
  static String escapeCsvCell(dynamic value) {
    if (value == null) return '';
    final original = value.toString();
    final str = original.replaceAll('\r\n', ' ').replaceAll('\n', ' ');
    if (str.contains(',') || str.contains('"') || str.contains(';') || original.contains('\n')) {
      return '"${str.replaceAll('"', '""')}"';
    }
    return str;
  }

  /// Builds a complete CSV string from headers and rows with UTF-8 BOM (`\uFEFF`)
  /// for seamless Excel, Numbers, and Google Sheets compatibility.
  static String buildCsv(List<String> headers, List<List<dynamic>> rows) {
    final buffer = StringBuffer();
    // UTF-8 BOM ensures Excel recognizes UTF-8 encoding (e.g. Peso symbol ₱, accents)
    buffer.write('\uFEFF');

    // Header row
    buffer.writeln(headers.map(escapeCsvCell).join(','));

    // Data rows
    for (final row in rows) {
      buffer.writeln(row.map(escapeCsvCell).join(','));
    }

    return buffer.toString();
  }

  /// Generates and saves an export report for the selected report type and date range.
  Future<ExportResult> generateReport({
    required ExportReportType type,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    final dateOnly = DateFormat('yyyy-MM-dd');
    final fileTimestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

    List<String> headers = [];
    List<List<dynamic>> rows = [];
    Map<String, dynamic> summary = {};
    String baseFileName = '';

    // Adjust endDate to include the entire day
    final effectiveEndDate = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    final effectiveStartDate = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);

    switch (type) {
      // ═════════════════════════════════════════════════════════════════════
      // 1. SALES & ORDERS REPORT
      // ═════════════════════════════════════════════════════════════════════
      case ExportReportType.sales:
        baseFileName = 'Selecta_Sales_Report_$fileTimestamp.csv';
        headers = [
          'Order Date',
          'PO / Invoice #',
          'Created By',
          'Order Amount (PHP)',
          'Invoice Amount (PHP)',
          'Settlement Status',
          'PO Status',
          'Item Count',
        ];

        final snapshot = await _firestore
            .collection(PURCHASEORDER_COLLECTION_REF)
            .where('orderDate', isGreaterThanOrEqualTo: Timestamp.fromDate(effectiveStartDate))
            .where('orderDate', isLessThanOrEqualTo: Timestamp.fromDate(effectiveEndDate))
            .get();

        double totalSales = 0.0;
        int paidCount = 0;

        for (final doc in snapshot.docs) {
          final data = doc.data();
          final po = Purchaseorder.fromJson(data);
          final orderDt = po.orderDate.toDate();
          final amount = po.orderAmount > 0 ? po.orderAmount : po.invoiceAmount;
          totalSales += amount;
          if (po.isSettled == true) paidCount++;

          rows.add([
            dateFormat.format(orderDt),
            po.invoiceNumber.isNotEmpty ? po.invoiceNumber : (po.poNumber.isNotEmpty ? po.poNumber : doc.id),
            po.createdBy,
            po.orderAmount.toStringAsFixed(2),
            po.invoiceAmount.toStringAsFixed(2),
            po.isSettled == true ? 'Settled' : 'Unsettled',
            po.status,
            po.items.length,
          ]);
        }

        summary = {
          'Total Revenue (PHP)': totalSales.toStringAsFixed(2),
          'Total Orders': rows.length,
          'Paid Orders': paidCount,
          'Date Range': '${dateOnly.format(effectiveStartDate)} to ${dateOnly.format(effectiveEndDate)}',
        };
        break;

      // ═════════════════════════════════════════════════════════════════════
      // 2. DELIVERY SUMMARY REPORT
      // ═════════════════════════════════════════════════════════════════════
      case ExportReportType.deliveries:
        baseFileName = 'Selecta_Deliveries_Report_$fileTimestamp.csv';
        headers = [
          'Delivery Date',
          'Delivery ID',
          'Store Name',
          'Delivery Status',
          'Invoiced Amount (PHP)',
          'Cash Collected (PHP)',
          'Credit Amount (PHP)',
          'Credit Status',
          'Delivered Timestamp',
          'Items Count',
          'Notes',
        ];

        final snapshot = await _firestore
            .collection(DELIVERY_COLLECTION_REF)
            .where('createdDate', isGreaterThanOrEqualTo: Timestamp.fromDate(effectiveStartDate))
            .where('createdDate', isLessThanOrEqualTo: Timestamp.fromDate(effectiveEndDate))
            .get();

        double totalInvoiced = 0.0;
        double totalCash = 0.0;
        double totalCredit = 0.0;
        int deliveredCount = 0;

        for (final doc in snapshot.docs) {
          final data = doc.data();
          final d = Delivery.fromJson(data);
          final createdDt = d.createdDate.toDate();
          final invoicedAmt = d.orderAmount;
          final cashAmt = d.cashAmount + d.onlineAmount;
          final creditAmt = d.creditAmount;

          totalInvoiced += invoicedAmt;
          totalCash += cashAmt;
          totalCredit += creditAmt;
          if (d.transactionStatus.toLowerCase().contains('deliver')) deliveredCount++;

          rows.add([
            dateFormat.format(createdDt),
            doc.id,
            d.storeName,
            d.transactionStatus,
            invoicedAmt.toStringAsFixed(2),
            cashAmt.toStringAsFixed(2),
            creditAmt.toStringAsFixed(2),
            d.creditStatus,
            d.deliveryDate != null ? dateFormat.format(d.deliveryDate!.toDate()) : 'Pending',
            d.items.length,
            d.remarks,
          ]);
        }

        summary = {
          'Total Invoiced (PHP)': totalInvoiced.toStringAsFixed(2),
          'Cash Collected (PHP)': totalCash.toStringAsFixed(2),
          'Credit Incurred (PHP)': totalCredit.toStringAsFixed(2),
          'Total Deliveries': rows.length,
          'Completed Deliveries': deliveredCount,
        };
        break;

      // ═════════════════════════════════════════════════════════════════════
      // 3. CREDIT & AR AGING REPORT
      // ═════════════════════════════════════════════════════════════════════
      case ExportReportType.creditAging:
        baseFileName = 'Selecta_Credit_Aging_Report_$fileTimestamp.csv';
        headers = [
          'Delivery Date',
          'Store Name',
          'Delivery ID',
          'Days Overdue',
          'Aging Bucket',
          'Credit Amount (PHP)',
          'Credit Status',
          'Delivery Status',
          'Remarks',
        ];

        final snapshot = await _firestore.collection(DELIVERY_COLLECTION_REF).get();
        final now = DateTime.now();

        double totalOverdue = 0.0;
        double bucket0To15 = 0.0;
        double bucket16To30 = 0.0;
        double bucket31To60 = 0.0;
        double bucket60Plus = 0.0;

        for (final doc in snapshot.docs) {
          final data = doc.data();
          final d = Delivery.fromJson(data);

          // Only unpaid credit
          final isUnpaid = d.creditStatus.toLowerCase() == 'unpaid' || d.creditStatus.toLowerCase() == 'overdue';
          if (!isUnpaid || d.creditAmount <= 0) continue;

          final refDate = d.deliveryDate?.toDate() ?? d.createdDate.toDate();
          final daysOverdue = now.difference(refDate).inDays;

          String bucket;
          if (daysOverdue <= 15) {
            bucket = '0-15 Days (Current)';
            bucket0To15 += d.creditAmount;
          } else if (daysOverdue <= 30) {
            bucket = '16-30 Days';
            bucket16To30 += d.creditAmount;
          } else if (daysOverdue <= 60) {
            bucket = '31-60 Days';
            bucket31To60 += d.creditAmount;
          } else {
            bucket = '60+ Days (Critical)';
            bucket60Plus += d.creditAmount;
          }

          totalOverdue += d.creditAmount;

          rows.add([
            dateOnly.format(refDate),
            d.storeName,
            doc.id,
            daysOverdue,
            bucket,
            d.creditAmount.toStringAsFixed(2),
            d.creditStatus,
            d.transactionStatus,
            d.remarks,
          ]);
        }

        // Sort by days overdue descending
        rows.sort((a, b) => (b[3] as int).compareTo(a[3] as int));

        summary = {
          'Total Unpaid AR (PHP)': totalOverdue.toStringAsFixed(2),
          '0-15 Days Bucket': bucket0To15.toStringAsFixed(2),
          '16-30 Days Bucket': bucket16To30.toStringAsFixed(2),
          '31-60 Days Bucket': bucket31To60.toStringAsFixed(2),
          '60+ Days Critical': bucket60Plus.toStringAsFixed(2),
          'Total Delinquent Accounts': rows.length,
        };
        break;

      // ═════════════════════════════════════════════════════════════════════
      // 4. INVENTORY & STOCK SHEET
      // ═════════════════════════════════════════════════════════════════════
      case ExportReportType.inventory:
        baseFileName = 'Selecta_Stock_Sheet_$fileTimestamp.csv';
        headers = [
          'Brand / Catalog',
          'Item Code / SKU',
          'Product Name',
          'Category',
          'Physical Stock',
          'Reserved Stock',
          'Available Stock',
          'Dealer Cost (PHP)',
          'Retail SRP (PHP)',
          'Profit Margin (%)',
          'Total Valuation Cost (PHP)',
          'Total Valuation SRP (PHP)',
          'Stock Status',
        ];

        final selectaSnap = await _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).get();
        final otherSnap = await _firestore.collection(OTHER_PRODUCTS_COLLECTION_REF).get();

        int totalUnits = 0;
        double totalCostValuation = 0.0;
        double totalRetailValuation = 0.0;

        for (final doc in selectaSnap.docs) {
          final p = SelectaProduct.fromSnapshot(doc);
          if (!p.isActive) continue;

          totalUnits += p.stockQuantity;
          totalCostValuation += p.stockCostValue;
          totalRetailValuation += p.stockRetailValue;

          rows.add([
            'Selecta',
            p.itemCode,
            p.productName,
            p.category,
            p.stockQuantity,
            p.reservedQuantity,
            p.availableQuantity,
            p.buyingPrice.toStringAsFixed(2),
            p.sellingPrice.toStringAsFixed(2),
            p.marginPercent.toStringAsFixed(1),
            p.stockCostValue.toStringAsFixed(2),
            p.stockRetailValue.toStringAsFixed(2),
            p.isOutOfStock ? 'Out of Stock' : (p.isLowStock ? 'Low Stock' : 'Good'),
          ]);
        }

        for (final doc in otherSnap.docs) {
          final p = OtherProduct.fromJson(doc.data());
          if (!p.isActive) continue;

          final costVal = p.stockQuantity * p.buyingPrice;
          final retailVal = p.stockQuantity * p.sellingPrice;
          final marginPct = p.buyingPrice > 0 ? ((p.sellingPrice - p.buyingPrice) / p.buyingPrice) * 100 : 0.0;

          totalUnits += p.stockQuantity;
          totalCostValuation += costVal;
          totalRetailValuation += retailVal;

          rows.add([
            'Other Product',
            doc.id,
            p.productName,
            'Other',
            p.stockQuantity,
            p.reservedQuantity,
            (p.stockQuantity - p.reservedQuantity).clamp(0, 999999),
            p.buyingPrice.toStringAsFixed(2),
            p.sellingPrice.toStringAsFixed(2),
            marginPct.toStringAsFixed(1),
            costVal.toStringAsFixed(2),
            retailVal.toStringAsFixed(2),
            p.isOutOfStock ? 'Out of Stock' : (p.isLowStock ? 'Low Stock' : 'Good'),
          ]);
        }

        summary = {
          'Total Physical Units': totalUnits,
          'Total Valuation Cost (PHP)': totalCostValuation.toStringAsFixed(2),
          'Total Valuation Retail (PHP)': totalRetailValuation.toStringAsFixed(2),
          'Active Catalog Items': rows.length,
        };
        break;

      // ═════════════════════════════════════════════════════════════════════
      // 5. PJP STORE VISITS LOG
      // ═════════════════════════════════════════════════════════════════════
      case ExportReportType.storeVisits:
        baseFileName = 'Selecta_PJP_Visits_Report_$fileTimestamp.csv';
        headers = [
          'Visit Date & Time',
          'Store Name',
          'Field Agent / Taken By',
          'Photo Attached',
          'Photo URL',
          'Visit Notes',
        ];

        final snapshot = await _firestore
            .collection(PROOF_OF_VISIT_COLLECTION)
            .where('visitDate', isGreaterThanOrEqualTo: Timestamp.fromDate(effectiveStartDate))
            .where('visitDate', isLessThanOrEqualTo: Timestamp.fromDate(effectiveEndDate))
            .get();

        for (final doc in snapshot.docs) {
          final visit = ProofOfVisit.fromJson(doc.data(), id: doc.id);
          final visitDt = visit.visitDate.toDate();

          rows.add([
            dateFormat.format(visitDt),
            visit.storeName,
            visit.takenBy.isNotEmpty ? visit.takenBy : 'Salesman',
            visit.imageUrl.isNotEmpty ? 'YES' : 'NO',
            visit.imageUrl,
            visit.notes,
          ]);
        }

        final uniqueStores = rows.map((r) => r[1]).toSet().length;
        summary = {
          'Total Visits Recorded': rows.length,
          'Unique Stores Visited': uniqueStores,
          'Date Range': '${dateOnly.format(effectiveStartDate)} to ${dateOnly.format(effectiveEndDate)}',
        };
        break;
    }

    final csvContent = buildCsv(headers, rows);

    // Save to temp / documents directory
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$baseFileName');
    await file.writeAsString(csvContent);

    return ExportResult(
      filePath: file.path,
      fileName: baseFileName,
      rowCount: rows.length,
      csvContent: csvContent,
      summary: summary,
    );
  }

  /// Opens the exported report file in Microsoft Excel or Google Sheets.
  Future<OpenResult> openExportedFile(String filePath) async {
    return await OpenFilex.open(filePath);
  }
}
