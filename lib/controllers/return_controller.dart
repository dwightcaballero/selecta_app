import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/services/auth_service.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/inventory_service.dart';

/// Aggregated return metrics bundle for [ReturnlistPage].
class ReturnListMetrics {
  /// Total cumulative value of all returned orders.
  final double totalAmount;

  /// Total count of returned orders.
  final int totalCount;

  const ReturnListMetrics({
    required this.totalAmount,
    required this.totalCount,
  });
}

/// Controller responsible for managing returned deliveries, rescheduling,
/// and metrics calculation for [ReturnlistPage] and [ReturnPage].
///
/// Keeps presentation decoupled from direct Firebase communication by delegating
/// to [DeliveryService].
class ReturnController {
  final DeliveryService _deliveryService;
  final InventoryService _inventoryService;

  ReturnController({DeliveryService? deliveryService, InventoryService? inventoryService})
      : _deliveryService = deliveryService ?? DeliveryService(),
        _inventoryService = inventoryService ?? InventoryService();

  // ==========================================
  // Shared / Role Methods
  // ==========================================

  /// Checks if the currently active user has dealer privileges.
  Future<bool> checkIsDealer() async {
    return await KVariables.getIsDealer();
  }

  // ==========================================
  // List Operations (ReturnlistPage)
  // ==========================================

  /// Real-time stream of all deliveries with returned transaction status.
  Stream<QuerySnapshot> getReturnsStream() {
    return _deliveryService.getListDeliveryWithReturnStatus();
  }

  /// Calculates total monetary value and count across all active returned delivery documents (excluding rescheduled).
  ReturnListMetrics computeMetrics(List docs) {
    double totalAmount = 0.0;
    int activeCount = 0;
    for (final doc in docs) {
      final Delivery delivery = doc.data() as Delivery;
      if (delivery.isRescheduled) continue;
      final returnAmount = delivery.returnAmount > 0 ? delivery.returnAmount : delivery.orderAmount;
      totalAmount += returnAmount;
      activeCount++;
    }

    return ReturnListMetrics(
      totalAmount: totalAmount,
      totalCount: activeCount,
    );
  }

  /// Filters and sorts returned delivery document snapshots by matching store name or remarks.
  List filterReturns({
    required List docs,
    required String searchQuery,
  }) {
    final list = List.from(docs);
    list.sort((a, b) {
      final da = (a.data() as Delivery).deliveryDate?.toDate() ?? DateTime(2000);
      final db = (b.data() as Delivery).deliveryDate?.toDate() ?? DateTime(2000);
      return db.compareTo(da);
    });

    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return list;

    return list.where((doc) {
      final Delivery delivery = doc.data() as Delivery;
      final nameMatches = delivery.storeName.toLowerCase().contains(query);
      final remarkMatches = delivery.remarks.toLowerCase().contains(query);
      return nameMatches || remarkMatches;
    }).toList();
  }

  // ==========================================
  // Detail Operations (ReturnPage)
  // ==========================================

  /// Dealer approves returned delivery order:
  /// Verifies physical arrival at warehouse, moves returned items from Incoming Stock into Current Stock,
  /// and updates delivery record with approval metadata.
  Future<Delivery> approveReturnedStock({
    required String deliveryId,
    required Delivery delivery,
  }) async {
    final isDealer = await checkIsDealer();
    if (!isDealer) {
      throw Exception('Only dealers are authorized to approve returned stock.');
    }
    if (delivery.isReturnApprovedByDealer) {
      throw Exception('This return has already been approved by the dealer.');
    }

    final currentUserName = authService.value.currentUser?.displayName ??
        authService.value.currentUser?.email ??
        'Dealer';

    // 1. Move returned units from incomingQuantity to physical stockQuantity
    await _inventoryService.approveReturnAndReplenishStock(delivery: delivery);

    // 2. Mark delivery document as dealer approved
    final updatedDelivery = delivery.copyWith(
      isReturnApprovedByDealer: true,
      returnApprovedBy: currentUserName,
      returnApprovedDate: Timestamp.now(),
      isReturnIncoming: false,
      lastUpdatedBy: currentUserName,
      lastupdatedDate: Timestamp.now(),
      lastUpdatedPage: AppPages.returnPage,
    );

    await _deliveryService.updateDelivery(deliveryId, updatedDelivery);

    await Helperfunctions.logUpdate(
      '[RETURN APPROVED] ${delivery.storeName}',
      delivery.toJson(),
      updatedDelivery.toJson(),
      page: AppPages.returnPage,
    );

    return updatedDelivery;
  }

  /// Reschedules a returned delivery (Option A: creates a new delivery in [DeliveryStatus.pendingPicklist]
  /// on the target date, re-reserves stock, and marks the original delivery as rescheduled).
  /// Requires dealer approval of returned stock before rescheduling.
  Future<Delivery> rescheduleDelivery({
    required String deliveryId,
    required Delivery delivery,
    DateTime? rescheduleDate,
  }) async {
    if (!delivery.isReturnApprovedByDealer) {
      throw Exception('Dealer approval is required before rescheduling. Please approve the returned stock into warehouse inventory first.');
    }

    final targetDate = rescheduleDate != null
        ? Timestamp.fromDate(rescheduleDate)
        : Timestamp.now();
    final currentUserName = authService.value.currentUser?.displayName ??
        authService.value.currentUser?.email ??
        'Admin';

    // 1. Build item list for the new delivery
    final newItems = delivery.items.map((item) {
      final qty = delivery.hasReturnedItems
          ? item.returnedQuantity
          : item.pickedQuantity;
      return item.copyWith(
        orderedQuantity: qty,
        pickedQuantity: 0,
        returnedQuantity: 0,
        isPicked: false,
      );
    }).where((item) => item.orderedQuantity > 0).toList();

    final double newOrderAmount = newItems.isNotEmpty
        ? newItems.fold<double>(0.0, (acc, i) => acc + (i.orderedQuantity * i.sellingPrice))
        : (delivery.returnAmount > 0 ? delivery.returnAmount : delivery.orderAmount);

    final String origDateStr = delivery.deliveryDate != null
        ? Helperfunctions.formatTimestampForDisplay(delivery.deliveryDate!)
        : '';

    // 2. Create the new Delivery record in Pending Picklist
    final newDelivery = Delivery.empty().copyWith(
      storeName: delivery.storeName,
      remarks: delivery.remarks.isNotEmpty
          ? 'Rescheduled: ${delivery.remarks}'
          : 'Rescheduled from ${delivery.storeName}${origDateStr.isNotEmpty ? ' ($origDateStr)' : ''}',
      transactionStatus: DeliveryStatus.pendingPicklist,
      orderAmount: newOrderAmount,
      originalOrderAmount: newOrderAmount,
      returnAmount: 0,
      creditAmount: 0,
      cashAmount: 0,
      onlineAmount: 0,
      deliveryDate: targetDate,
      creditStatus: '',
      items: newItems,
      isInventoryReserved: newItems.isNotEmpty,
      isInventoryDeducted: false,
      isInventorySettled: false,
      createdBy: currentUserName,
      lastUpdatedBy: currentUserName,
      createdDate: Timestamp.now(),
      lastupdatedDate: Timestamp.now(),
      createdPage: AppPages.returnPage,
      lastUpdatedPage: AppPages.returnPage,
    );

    final newDeliveryId = await _deliveryService.addDelivery(newDelivery);

    // 3. Re-reserve floating inventory for the rescheduled items
    if (newItems.isNotEmpty) {
      await _inventoryService.reReserveForRescheduledOrder(newItems);
    }

    // 4. Update original delivery as rescheduled
    final updatedDelivery = delivery.copyWith(
      isRescheduled: true,
      rescheduledToDeliveryId: newDeliveryId,
      rescheduledDate: targetDate,
      lastUpdatedBy: currentUserName,
      lastupdatedDate: Timestamp.now(),
      lastUpdatedPage: AppPages.returnPage,
    );

    await _deliveryService.updateDelivery(deliveryId, updatedDelivery);

    await Helperfunctions.logUpdate(
      '[RESCHEDULE RETURN] ${delivery.storeName} -> New Order: $newDeliveryId',
      delivery.toJson(),
      updatedDelivery.toJson(),
      page: AppPages.returnPage,
    );

    return updatedDelivery;
  }

  /// Deletes a returned delivery record and removes its uploaded receipt/document image.
  /// If the return has not been settled yet and has reserved stock, releases the reservation.
  Future<void> deleteReturn({
    required BuildContext context,
    required String deliveryId,
    required Delivery delivery,
  }) async {
    if (delivery.isReturnApprovedByDealer) {
      throw Exception('Cannot delete a return record after it has already been approved by the dealer.');
    }
    if (delivery.isInventorySettled) {
      throw Exception('Cannot delete a return record after the daily breakdown has been verified and settled.');
    }

    if (delivery.imagePath.isNotEmpty) {
      await Helperfunctions.deleteImage(context, delivery.imagePath);
    }

    // Release floating stock reservation if still reserved and not settled
    if (delivery.isInventoryReserved && delivery.items.isNotEmpty) {
      await _inventoryService.releaseReservedStockForOrder(
        items: delivery.items,
        storeName: delivery.storeName,
      );
    }

    _deliveryService.deleteDelivery(deliveryId);

    await Helperfunctions.logDelete(
      delivery.storeName,
      delivery.toJson(),
      page: AppPages.returnPage,
    );
  }
}
