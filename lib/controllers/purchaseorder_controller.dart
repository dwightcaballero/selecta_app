import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/purchaseorder.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/purchaseorder_service.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';

/// Class to hold summary count statistics for purchase orders.
class PurchaseOrderCounts {
  final int total;
  final int pending;
  final int overpayment;
  final int settled;

  const PurchaseOrderCounts({
    required this.total,
    required this.pending,
    required this.overpayment,
    required this.settled,
  });
}

/// Controller managing business logic, filtering, calculation,
/// scanner, and data operations for Purchase Orders.
class PurchaseOrderController {
  final PurchaseOrderService _service = PurchaseOrderService();

  /// Real-time stream of purchase orders from Firestore
  Stream<QuerySnapshot> getPurchaseOrdersStream() {
    return _service.getListPurchaseordersAsStream();
  }

  /// Retrieves unsettled overpayments
  Future<List<QueryDocumentSnapshot<Purchaseorder>>> getUnsettledOverpayments() {
    return _service.getUnsettledOverpayments();
  }

  /// Filters documents by the selected month/year unless viewing all
  List<QueryDocumentSnapshot> filterByMonth({
    required List<QueryDocumentSnapshot> docs,
    required DateTime selectedMonth,
    required bool isAllMonths,
  }) {
    if (isAllMonths) return docs;
    return docs.where((doc) {
      final order = doc.data() as Purchaseorder;
      final orderDate = order.orderDate.toDate();
      return orderDate.year == selectedMonth.year && orderDate.month == selectedMonth.month;
    }).toList();
  }

  /// Calculates status count metrics for a list of purchase orders
  PurchaseOrderCounts calculateCounts(List<QueryDocumentSnapshot> monthDocs) {
    int pendingCount = 0;
    int overpaymentCount = 0;
    int settledCount = 0;

    for (final doc in monthDocs) {
      final order = doc.data() as Purchaseorder;
      final hasInvoice = order.invoiceNumber.trim().isNotEmpty && order.invoiceAmount > 0;
      if (!hasInvoice) {
        pendingCount++;
      } else if (order.isSettled == true) {
        settledCount++;
      } else if (order.overpayment > 0) {
        overpaymentCount++;
      }
    }

    return PurchaseOrderCounts(
      total: monthDocs.length,
      pending: pendingCount,
      overpayment: overpaymentCount,
      settled: settledCount,
    );
  }

  /// Filters and sorts order documents based on chips, query, and sorting selection
  List<QueryDocumentSnapshot> filterAndSortOrders({
    required List<QueryDocumentSnapshot> docs,
    required String selectedFilter,
    required String searchQuery,
    required String sortBy,
  }) {
    final filtered = docs.where((doc) {
      final order = doc.data() as Purchaseorder;
      final hasInvoice = order.invoiceNumber.trim().isNotEmpty && order.invoiceAmount > 0;

      bool matchesFilter = true;
      if (selectedFilter == 'Pending') {
        matchesFilter = !hasInvoice;
      } else if (selectedFilter == 'Overpayment') {
        matchesFilter = order.overpayment > 0 && order.isSettled != true;
      } else if (selectedFilter == 'Settled') {
        matchesFilter = order.isSettled == true;
      }

      final dateStr = Helperfunctions.formatTimestampForDisplay(order.orderDate).toLowerCase();
      final matchesSearch = searchQuery.isEmpty ||
          order.invoiceNumber.toLowerCase().contains(searchQuery) ||
          dateStr.contains(searchQuery);

      return matchesFilter && matchesSearch;
    }).toList();

    filtered.sort((a, b) {
      final orderA = a.data() as Purchaseorder;
      final orderB = b.data() as Purchaseorder;
      switch (sortBy) {
        case 'oldest':
          return orderA.orderDate.compareTo(orderB.orderDate);
        case 'amount_high':
          return orderB.orderAmount.compareTo(orderA.orderAmount);
        case 'amount_low':
          return orderA.orderAmount.compareTo(orderB.orderAmount);
        case 'newest':
        default:
          return orderB.orderDate.compareTo(orderA.orderDate);
      }
    });

    return filtered;
  }

  /// Calculates total deduction amount from selected unsettled overpayments
  double calculateTotalSelectedOverpayments({
    required List<QueryDocumentSnapshot<Purchaseorder>> unsettledDocs,
    required Set<String> selectedIds,
  }) {
    double total = 0;
    for (final doc in unsettledDocs) {
      if (selectedIds.contains(doc.id)) {
        total += doc.data().overpayment;
      }
    }
    return total;
  }

  /// Scans a document via document scanner plugin and returns temporary File
  Future<File?> scanDocument() async {
    final scannedData = await FlutterDocScanner().getScannedDocumentAsImages(page: 1);
    if (scannedData != null && scannedData.images.isNotEmpty) {
      final filePath = scannedData.images.first.replaceFirst('file://', '');
      return File(filePath);
    }
    return null;
  }

  /// Saves a new purchase order, settles selected overpayments, and logs audit entries
  Future<void> savePurchaseOrder({
    required BuildContext context,
    required double orderAmount,
    required DateTime selectedOrderDate,
    required DateTime selectedInvoiceDate,
    required File? pickedImage,
    required Set<String> selectedOverpaymentIds,
    required List<QueryDocumentSnapshot<Purchaseorder>> unsettledOverpayments,
  }) async {
    String imageFilePath = '';
    if (pickedImage != null) {
      imageFilePath = await Helperfunctions.saveImage(context, pickedImage);
    }

    final currentUserDisplayName = authService.value.currentUser?.displayName ?? 'User';

    final newPurchaseorder = Purchaseorder(
      invoiceNumber: '',
      orderAmount: orderAmount,
      orderDate: Timestamp.fromDate(selectedOrderDate),
      overpayment: 0,
      isSettled: null,
      createdBy: currentUserDisplayName,
      lastUpdatedBy: currentUserDisplayName,
      createdDate: Timestamp.now(),
      lastupdatedDate: Timestamp.now(),
      invoiceAmount: 0,
      imagePath: imageFilePath,
      invoiceDate: Timestamp.fromDate(selectedInvoiceDate),
      createdPage: AppPages.purchaseOrder,
      lastUpdatedPage: AppPages.purchaseOrder,
    );

    _service.addPurchaseorder(newPurchaseorder);
    await Helperfunctions.logCreate(
      Helperfunctions.formatTimestampForDisplay(newPurchaseorder.orderDate),
      newPurchaseorder.toJson(),
      page: AppPages.purchaseOrder,
    );

    // Settle selected overpayments
    if (selectedOverpaymentIds.isNotEmpty) {
      for (final doc in unsettledOverpayments) {
        if (selectedOverpaymentIds.contains(doc.id)) {
          final order = doc.data();
          final prevJson = order.toJson();
          order.isSettled = true;
          order.lastUpdatedBy = currentUserDisplayName;
          order.lastupdatedDate = Timestamp.now();
          order.lastUpdatedPage = AppPages.purchaseOrder;
          _service.updatePurchaseorder(doc.id, order);
          await Helperfunctions.logUpdate(
            order.invoiceNumber.isNotEmpty ? order.invoiceNumber : Helperfunctions.formatTimestampForDisplay(order.orderDate),
            prevJson,
            order.toJson(),
            page: AppPages.purchaseOrder,
          );
        }
      }
    }
  }

  /// Updates existing purchase order with invoice information and audit logging
  Future<void> updatePurchaseOrder({
    required BuildContext context,
    required String purchaseOrderId,
    required Purchaseorder currentOrder,
    required String invoiceNumber,
    required double invoiceAmount,
    required DateTime selectedOrderDate,
    required DateTime selectedInvoiceDate,
    required File? pickedImage,
    required String networkImagePath,
  }) async {
    if (invoiceAmount > currentOrder.orderAmount) {
      throw Exception('Invoice amount cannot exceed the order amount.');
    }

    final double overpayment = currentOrder.orderAmount - invoiceAmount;
    final String imageFilePath = await Helperfunctions.updateImage(
      context,
      pickedImage,
      networkImagePath,
      currentOrder.imagePath,
    );

    final currentUserDisplayName = authService.value.currentUser?.displayName ?? 'User';

    final updatedPurchaseorder = Purchaseorder(
      invoiceNumber: invoiceNumber.trim().toUpperCase(),
      orderAmount: currentOrder.orderAmount,
      orderDate: Timestamp.fromDate(selectedOrderDate),
      overpayment: overpayment > 0 ? overpayment : 0,
      isSettled: overpayment > 0 ? (currentOrder.isSettled ?? false) : null,
      createdBy: currentOrder.createdBy,
      lastUpdatedBy: currentUserDisplayName,
      createdDate: currentOrder.createdDate,
      lastupdatedDate: Timestamp.now(),
      invoiceAmount: invoiceAmount,
      imagePath: imageFilePath,
      invoiceDate: Timestamp.fromDate(selectedInvoiceDate),
      createdPage: currentOrder.createdPage,
      lastUpdatedPage: AppPages.purchaseOrder,
    );

    _service.updatePurchaseorder(purchaseOrderId, updatedPurchaseorder);
    await Helperfunctions.logUpdate(
      updatedPurchaseorder.invoiceNumber.isNotEmpty
          ? updatedPurchaseorder.invoiceNumber
          : Helperfunctions.formatTimestampForDisplay(updatedPurchaseorder.orderDate),
      currentOrder.toJson(),
      updatedPurchaseorder.toJson(),
      page: AppPages.purchaseOrder,
    );
  }

  /// Deletes a purchase order, removes image if present, and logs deletion
  Future<void> deletePurchaseOrder({
    required BuildContext context,
    required String purchaseOrderId,
    required Purchaseorder order,
  }) async {
    if (order.imagePath.isNotEmpty) {
      await Helperfunctions.deleteImage(context, order.imagePath);
    }

    _service.deletePurchaseorder(purchaseOrderId);
    await Helperfunctions.logDelete(
      order.invoiceNumber.isNotEmpty
          ? order.invoiceNumber
          : Helperfunctions.formatTimestampForDisplay(order.orderDate),
      order.toJson(),
      page: AppPages.purchaseOrder,
    );
  }
}
