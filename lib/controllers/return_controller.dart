import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/delivery_service.dart';

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

  ReturnController({DeliveryService? deliveryService})
      : _deliveryService = deliveryService ?? DeliveryService();

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

  /// Calculates total monetary value and count across all returned delivery documents.
  ReturnListMetrics computeMetrics(List docs) {
    double totalAmount = 0.0;
    for (final doc in docs) {
      final Delivery delivery = doc.data() as Delivery;
      final returnAmount = delivery.returnAmount > 0 ? delivery.returnAmount : delivery.orderAmount;
      totalAmount += returnAmount;
    }

    return ReturnListMetrics(
      totalAmount: totalAmount,
      totalCount: docs.length,
    );
  }

  /// Filters returned delivery document snapshots by matching store name or remarks.
  List filterReturns({
    required List docs,
    required String searchQuery,
  }) {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return docs;

    return docs.where((doc) {
      final Delivery delivery = doc.data() as Delivery;
      final nameMatches = delivery.storeName.toLowerCase().contains(query);
      final remarkMatches = delivery.remarks.toLowerCase().contains(query);
      return nameMatches || remarkMatches;
    }).toList();
  }

  // ==========================================
  // Detail Operations (ReturnPage)
  // ==========================================

  /// Reschedules a returned delivery, transitioning its status back to [DeliveryStatus.pending].
  ///
  /// Updates the delivery in Firestore via [DeliveryService] and logs an audit trail.
  Future<Delivery> rescheduleDelivery({
    required String deliveryId,
    required Delivery delivery,
    DateTime? rescheduleDate,
  }) async {
    final targetDate = rescheduleDate != null
        ? Timestamp.fromDate(rescheduleDate)
        : Timestamp.now();
    final currentUserName = authService.value.currentUser?.displayName ??
        authService.value.currentUser?.email ??
        'Admin';

    final updatedDelivery = delivery.copyWith(
      storeName: delivery.storeName,
      remarks: '',
      transactionStatus: DeliveryStatus.pending,
      orderAmount: delivery.orderAmount,
      returnAmount: 0,
      creditAmount: delivery.creditAmount,
      cashAmount: delivery.cashAmount,
      onlineAmount: delivery.onlineAmount,
      deliveryDate: targetDate,
      creditStatus: '',
      createdBy: delivery.createdBy,
      lastUpdatedBy: currentUserName,
      createdDate: delivery.createdDate,
      lastupdatedDate: Timestamp.now(),
      createdPage: delivery.createdPage,
      lastUpdatedPage: AppPages.returnPage,
    );

    await _deliveryService.updateDelivery(deliveryId, updatedDelivery);

    await Helperfunctions.logUpdate(
      '[REDELIVER] ${delivery.storeName}',
      delivery.toJson(),
      updatedDelivery.toJson(),
      page: AppPages.returnPage,
    );

    return updatedDelivery;
  }

  /// Deletes a returned delivery record and removes its uploaded receipt/document image.
  Future<void> deleteReturn({
    required BuildContext context,
    required String deliveryId,
    required Delivery delivery,
  }) async {
    if (delivery.imagePath.isNotEmpty) {
      await Helperfunctions.deleteImage(context, delivery.imagePath);
    }
    _deliveryService.deleteDelivery(deliveryId);

    await Helperfunctions.logDelete(
      delivery.storeName,
      delivery.toJson(),
      page: AppPages.returnPage,
    );
  }
}
