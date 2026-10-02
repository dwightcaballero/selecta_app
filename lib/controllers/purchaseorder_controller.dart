import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/purchaseorder.dart';
import 'package:selecta_ops/services/auth_service.dart';
import 'package:selecta_ops/services/gemini_ai_service.dart';
import 'package:selecta_ops/services/inventory_service.dart';
import 'package:selecta_ops/services/purchaseorder_service.dart';
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
///
/// ## Workflow (3 Phases):
/// - **Phase 1 — Create PO (Floating):** Scan digital invoice → AI extracts items →
///   Save PO with `status='pending'`, quantities are floating, NO inventory replenishment.
///   Stocks haven't arrived yet.
/// - **Phase 2 — Confirm Official Invoice:** Stocks arrive with paper invoice →
///   AI compares official invoice vs original PO → shows confirmed/missing items →
///   User confirms → inventory permanently replenished for confirmed items,
///   missing items deleted, overpayment computed → `status='confirmed'`.
/// - **Phase 3 — Settled:** If any overpayment remains, it can be applied to the
///   next PO. Once settled, `isSettled = true`.
class PurchaseOrderController {
  final PurchaseOrderService _service = PurchaseOrderService();
  final InventoryService _inventoryService = InventoryService();

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
      // "Pending" = PO created but not yet confirmed with official invoice
      if (order.status == 'pending') {
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
      final isPending = order.status == 'pending';

      bool matchesFilter = true;
      if (selectedFilter == 'Pending') {
        matchesFilter = isPending;
      } else if (selectedFilter == 'Overpayment') {
        matchesFilter = order.overpayment > 0 && order.isSettled != true;
      } else if (selectedFilter == 'Settled') {
        matchesFilter = order.isSettled == true;
      }

      final dateStr = Helperfunctions.formatTimestampForDisplay(order.orderDate).toLowerCase();
      final matchesSearch = searchQuery.isEmpty ||
          order.poNumber.toLowerCase().contains(searchQuery) ||
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

  // ============================================================
  // PHASE 1: Create PO (floating quantities, NO inventory replenishment)
  // ============================================================

  /// Saves a new purchase order as **PENDING** (floating quantities).
  /// Inventory is NOT replenished yet — stocks have not arrived.
  /// At creation time, the official invoice has not arrived yet.
  Future<void> savePurchaseOrder({
    required BuildContext context,
    required double orderAmount,
    required DateTime selectedOrderDate,
    required File? pickedImage,
    required Set<String> selectedOverpaymentIds,
    required List<QueryDocumentSnapshot<Purchaseorder>> unsettledOverpayments,
    List<OrderItem> items = const [],
    String poNumber = '',
  }) async {
    String imageFilePath = '';
    if (pickedImage != null) {
      imageFilePath = await Helperfunctions.saveImage(context, pickedImage);
    }

    final currentUserDisplayName = authService.value.currentUser?.displayName ?? 'User';
    final cleanItems = items.where((i) => i.effectiveQuantity > 0).toList();

    // Compute effective orderAmount from items cost if not provided
    double effectiveOrderAmount = orderAmount;
    if (cleanItems.isNotEmpty && effectiveOrderAmount <= 0) {
      effectiveOrderAmount = cleanItems.fold(0.0, (acc, item) => acc + (item.effectiveQuantity * item.buyingPrice));
    }

    final cleanPoNumber = poNumber.trim().toUpperCase();

    // Phase 1: Create PO with status='pending', isInventoryReplenished=false
    // Inventory is NOT touched yet — stocks haven't arrived.
    // Invoice number and amount remain empty/0 until invoice is attached.
    final newPurchaseorder = Purchaseorder(
      poNumber: cleanPoNumber,
      invoiceNumber: '',
      orderAmount: effectiveOrderAmount,
      orderDate: Timestamp.fromDate(selectedOrderDate),
      overpayment: 0,
      isSettled: null,
      createdBy: currentUserDisplayName,
      lastUpdatedBy: currentUserDisplayName,
      createdDate: Timestamp.now(),
      lastupdatedDate: Timestamp.now(),
      invoiceAmount: 0.0,
      imagePath: imageFilePath,
      invoiceDate: Timestamp.fromDate(selectedOrderDate),
      createdPage: AppPages.purchaseOrder,
      lastUpdatedPage: AppPages.purchaseOrder,
      items: cleanItems,
      isInventoryReplenished: false,
      status: 'pending',
    );

    // Persist purchase order record
    _service.addPurchaseorder(newPurchaseorder);

    // Create floating incoming inventory for products in the purchase order
    if (cleanItems.isNotEmpty) {
      await _inventoryService.addIncomingStockForPurchaseOrder(items: cleanItems);
    }

    await Helperfunctions.logCreate(
      newPurchaseorder.poNumber.isNotEmpty
          ? newPurchaseorder.poNumber
          : Helperfunctions.formatTimestampForDisplay(newPurchaseorder.orderDate),
      newPurchaseorder.toJson(),
      page: AppPages.purchaseOrder,
    );

    // Settle selected overpayments if any were selected as deductions
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

  // ============================================================
  // PHASE 2: Attach Official Invoice (permanent inventory replenishment)
  // ============================================================

  /// Attaches and confirms the official paper invoice for an existing pending PO.
  ///
  /// - Replenishes inventory **only** for confirmed items (items that arrived).
  /// - Missing items (out of stock from supplier) are removed from the PO.
  /// - Overpayment = original order amount − confirmed invoice total.
  /// - Updates PO status to `'invoiced'`, sets `isInventoryReplenished = true`.
  Future<void> confirmOfficialInvoice({
    required BuildContext context,
    required String purchaseOrderId,
    required Purchaseorder currentOrder,
    required List<ConfirmedInvoiceItem> confirmedItems,
    required List<OrderItem> missingItems,
    required String officialInvoiceNumber,
    required double officialInvoiceAmount,
    required DateTime officialInvoiceDate,
    required File? pickedImage,
  }) async {
    if (confirmedItems.isEmpty) {
      throw Exception('No confirmed items. Please scan the official invoice and verify at least one delivered product.');
    }

    final currentUserDisplayName = authService.value.currentUser?.displayName ?? 'User';

    // Save official invoice image (overwrites digital invoice image)
    final String imageFilePath = await Helperfunctions.updateImage(
      context,
      pickedImage,
      '', // no existing network path for replacement
      currentOrder.imagePath,
    );

    // Build OrderItems from confirmed items (isPicked = true, permanent)
    final List<OrderItem> confirmedOrderItems = confirmedItems.map((ci) {
      return OrderItem(
        productId: ci.productId,
        productName: ci.productName,
        imageUrl: ci.imageUrl,
        productSource: ci.productSource,
        category: ci.category,
        tag: ci.tag,
        buyingPrice: ci.unitCost,
        sellingPrice: ci.sellingPrice,
        orderedQuantity: ci.orderedQuantity,
        pickedQuantity: ci.deliveredQuantity,
        isPicked: true,
      );
    }).toList();

    // Compute final invoice amount
    final double finalInvoiceAmount = officialInvoiceAmount > 0
        ? officialInvoiceAmount
        : confirmedItems.fold(0.0, (acc, i) => acc + i.lineTotal);

    // Overpayment = original order amount − actual invoice amount (if positive)
    final double rawOverpayment = currentOrder.orderAmount - finalInvoiceAmount;
    final double overpayment = rawOverpayment > 0.009
        ? double.parse(rawOverpayment.toStringAsFixed(2))
        : 0.0;

    // Replenish inventory permanently for confirmed items and clear floating incoming stock from original PO
    await _inventoryService.replenishAndClearIncomingStockForPurchaseOrder(
      invoiceNumber: officialInvoiceNumber.isNotEmpty
          ? officialInvoiceNumber
          : currentOrder.invoiceNumber,
      orderDate: officialInvoiceDate,
      originalPoItems: currentOrder.items,
      confirmedItems: confirmedOrderItems,
    );

    // Update PO to invoiced state
    final resolvedInvoiceNumber = officialInvoiceNumber.trim().isNotEmpty
        ? officialInvoiceNumber.trim().toUpperCase()
        : currentOrder.invoiceNumber;

    final updatedPurchaseorder = Purchaseorder(
      poNumber: currentOrder.poNumber.isNotEmpty ? currentOrder.poNumber : currentOrder.invoiceNumber,
      invoiceNumber: resolvedInvoiceNumber,
      orderAmount: currentOrder.orderAmount,
      orderDate: currentOrder.orderDate,
      overpayment: overpayment,
      isSettled: overpayment > 0 ? false : null,
      createdBy: currentOrder.createdBy,
      lastUpdatedBy: currentUserDisplayName,
      createdDate: currentOrder.createdDate,
      lastupdatedDate: Timestamp.now(),
      invoiceAmount: finalInvoiceAmount,
      imagePath: imageFilePath.isNotEmpty ? imageFilePath : currentOrder.imagePath,
      invoiceDate: Timestamp.fromDate(officialInvoiceDate),
      createdPage: currentOrder.createdPage,
      lastUpdatedPage: AppPages.purchaseOrder,
      items: confirmedOrderItems,
      isInventoryReplenished: true,
      status: 'invoiced',
    );

    final prevJson = currentOrder.toJson();
    _service.updatePurchaseorder(purchaseOrderId, updatedPurchaseorder);
    await Helperfunctions.logUpdate(
      resolvedInvoiceNumber.isNotEmpty
          ? resolvedInvoiceNumber
          : Helperfunctions.formatTimestampForDisplay(updatedPurchaseorder.orderDate),
      prevJson,
      updatedPurchaseorder.toJson(),
      page: AppPages.purchaseOrder,
    );
  }

  // ============================================================
  // UPDATE (edit existing pending PO before confirmation)
  // ============================================================

  /// Updates an existing **pending** purchase order (before official invoice confirmation).
  /// Synchronizes floating incoming stock to reflect new item quantities.
  Future<void> updatePendingPurchaseOrder({
    required BuildContext context,
    required String purchaseOrderId,
    required Purchaseorder currentOrder,
    required String poNumber,
    required DateTime selectedOrderDate,
    required File? pickedImage,
    required String networkImagePath,
    List<OrderItem> items = const [],
    double? updatedOrderAmount,
  }) async {
    final cleanItems = items.where((i) => i.effectiveQuantity > 0).toList();
    final effectiveOrderAmount = updatedOrderAmount ?? currentOrder.orderAmount;

    final String imageFilePath = await Helperfunctions.updateImage(
      context,
      pickedImage,
      networkImagePath,
      currentOrder.imagePath,
    );

    final currentUserDisplayName = authService.value.currentUser?.displayName ?? 'User';

    final updatedPurchaseorder = Purchaseorder(
      poNumber: poNumber.trim().toUpperCase(),
      invoiceNumber: currentOrder.invoiceNumber,
      orderAmount: effectiveOrderAmount,
      orderDate: Timestamp.fromDate(selectedOrderDate),
      overpayment: 0,
      isSettled: null,
      createdBy: currentOrder.createdBy,
      lastUpdatedBy: currentUserDisplayName,
      createdDate: currentOrder.createdDate,
      lastupdatedDate: Timestamp.now(),
      invoiceAmount: currentOrder.invoiceAmount,
      imagePath: imageFilePath,
      invoiceDate: currentOrder.invoiceDate,
      createdPage: currentOrder.createdPage,
      lastUpdatedPage: AppPages.purchaseOrder,
      items: cleanItems.isNotEmpty ? cleanItems : currentOrder.items,
      isInventoryReplenished: false,
      status: 'pending',
    );

    // Adjust incoming stock if items/quantities were edited in pending status
    if (currentOrder.status == 'pending') {
      await _inventoryService.adjustIncomingStockForPurchaseOrder(
        oldItems: currentOrder.items,
        newItems: cleanItems.isNotEmpty ? cleanItems : currentOrder.items,
      );
    }

    _service.updatePurchaseorder(purchaseOrderId, updatedPurchaseorder);
    await Helperfunctions.logUpdate(
      updatedPurchaseorder.poNumber.isNotEmpty
          ? updatedPurchaseorder.poNumber
          : (updatedPurchaseorder.invoiceNumber.isNotEmpty
              ? updatedPurchaseorder.invoiceNumber
              : Helperfunctions.formatTimestampForDisplay(updatedPurchaseorder.orderDate)),
      currentOrder.toJson(),
      updatedPurchaseorder.toJson(),
      page: AppPages.purchaseOrder,
    );
  }

  // ============================================================
  // DELETE
  // ============================================================

  /// Deletes a purchase order, reverts replenished stock if confirmed, removes incoming stock if pending, removes image, and logs deletion.
  Future<void> deletePurchaseOrder({
    required BuildContext context,
    required String purchaseOrderId,
    required Purchaseorder order,
  }) async {
    // Only revert stock if already confirmed (Phase 2 complete)
    if (order.isInventoryReplenished && order.items.isNotEmpty) {
      await _inventoryService.revertReplenishedStockForPurchaseOrder(
        invoiceNumber: order.invoiceNumber,
        items: order.items,
      );
    } else if (order.status == 'pending' && order.items.isNotEmpty) {
      // Release floating incoming stock
      await _inventoryService.removeIncomingStockForPurchaseOrder(
        items: order.items,
      );
    }

    if (order.imagePath.isNotEmpty) {
      if (context.mounted) {
        await Helperfunctions.deleteImage(context, order.imagePath);
      }
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
