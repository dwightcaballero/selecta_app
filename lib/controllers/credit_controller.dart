import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/services/auth_service.dart';
import 'package:selecta_ops/services/delivery_service.dart';

/// Available sorting options for outstanding credit records.
enum CreditSort {
  highestAmount('Highest Credit', Icons.arrow_downward),
  lowestAmount('Lowest Credit', Icons.arrow_upward),
  oldest('Oldest First (Aging)', Icons.history),
  newest('Newest First', Icons.calendar_today);

  const CreditSort(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Filter options based on credit aging buckets.
enum CreditAgingFilter {
  all('All'),
  current('0–15d (Current)'),
  dueSoon('16–30d (Due Soon)'),
  overdue('31d+ (Overdue)');

  const CreditAgingFilter(this.label);
  final String label;
}

/// Strongly typed container binding a Firestore document ID to its [Delivery] model.
class CreditRecord {
  /// The Firestore document identifier.
  final String id;

  /// The parsed delivery object containing credit and payment metrics.
  final Delivery delivery;

  const CreditRecord({required this.id, required this.delivery});

  /// Days elapsed since delivery date (or created date if delivery date is missing).
  int get agingDays {
    final date = delivery.deliveryDate?.toDate() ?? delivery.createdDate.toDate();
    final days = DateTime.now().difference(date).inDays;
    return days < 0 ? 0 : days;
  }

  /// Whether this record matches the given aging filter.
  bool matchesAgingFilter(CreditAgingFilter filter) {
    switch (filter) {
      case CreditAgingFilter.all:
        return true;
      case CreditAgingFilter.current:
        return agingDays <= 15;
      case CreditAgingFilter.dueSoon:
        return agingDays >= 16 && agingDays <= 30;
      case CreditAgingFilter.overdue:
        return agingDays >= 31;
    }
  }
}

/// Calculated metrics and filtered records bundle for the credit list view.
class CreditListMetrics {
  /// The list of credit records after applying search filters and sorting.
  final List<CreditRecord> filteredRecords;

  /// Total cumulative credit across all stores before filtering.
  final double totalCredit;

  /// Total number of accounts with outstanding credits before filtering.
  final int totalAccounts;

  /// Total credit amount for stores matching the current search filter.
  final double filteredCredit;

  /// Number of accounts matching the current search filter.
  final int filteredCount;

  /// Count of accounts in 0-15d bucket.
  final int countCurrent;

  /// Count of accounts in 16-30d bucket.
  final int countDueSoon;

  /// Count of accounts in 31d+ bucket.
  final int countOverdue;

  const CreditListMetrics({
    required this.filteredRecords,
    required this.totalCredit,
    required this.totalAccounts,
    required this.filteredCredit,
    required this.filteredCount,
    required this.countCurrent,
    required this.countDueSoon,
    required this.countOverdue,
  });

  /// Indicates if an active search filter has altered the visible results.
  bool get isFiltered => filteredCount != totalAccounts;
}

/// Controller managing business logic, computations, and data transformations
/// for both [CreditlistPage] and [CreditPage].
///
/// By centralizing credit domain logic here:
/// - Firebase/Firestore operations are strictly delegated to [DeliveryService].
/// - Audit logging and delivery model mutations are isolated from UI widgets.
/// - Filtering, sorting, and aggregate calculations remain fully testable.
class CreditController {
  DeliveryService? _deliveryService;
  DeliveryService get _effectiveDeliveryService => _deliveryService ??= DeliveryService();

  CreditController({DeliveryService? deliveryService})
    // ignore: prefer_initializing_formals
    : _deliveryService = deliveryService;

  // ==========================================
  // List Operations (CreditlistPage)
  // ==========================================

  /// Returns a real-time stream of delivery records that have unpaid credit.
  Stream<QuerySnapshot> getCreditDeliveriesStream() {
    return _effectiveDeliveryService.getListDeliveryWithCredit();
  }

  /// Verifies whether the currently logged-in user possesses dealer privileges.
  Future<bool> checkIsDealer() async {
    return await KVariables.getIsDealer();
  }

  /// Transforms raw Firestore document snapshots into typed [CreditListMetrics],
  /// applying the active search query, aging filter, and selected sort order.
  CreditListMetrics computeMetrics({
    required List<QueryDocumentSnapshot> docs,
    required String searchQuery,
    required CreditSort sort,
    CreditAgingFilter agingFilter = CreditAgingFilter.all,
  }) {
    // 1. Map raw documents to strongly typed CreditRecord wrappers
    final allRecords = docs.map((doc) {
      return CreditRecord(id: doc.id, delivery: doc.data() as Delivery);
    }).toList();

    // 2. Compute aggregate total outstanding credit & aging bucket counts
    final totalCredit = allRecords.fold<double>(0.0, (runningTotal, record) => runningTotal + record.delivery.creditAmount);

    int countCurrent = 0;
    int countDueSoon = 0;
    int countOverdue = 0;

    for (final record in allRecords) {
      if (record.agingDays <= 15) {
        countCurrent++;
      } else if (record.agingDays <= 30) {
        countDueSoon++;
      } else {
        countOverdue++;
      }
    }

    // 3. Filter by store name and aging bucket
    final trimmedQuery = searchQuery.trim().toLowerCase();
    final filtered = allRecords.where((record) {
      final matchesSearch = trimmedQuery.isEmpty || record.delivery.storeName.toLowerCase().contains(trimmedQuery);
      final matchesAging = record.matchesAgingFilter(agingFilter);
      return matchesSearch && matchesAging;
    }).toList();

    // 4. Sort according to selected criteria
    filtered.sort((a, b) => compareCreditRecords(a, b, sort));

    // 5. Compute filtered outstanding credit amount
    final filteredCredit = filtered.fold<double>(0.0, (runningTotal, record) => runningTotal + record.delivery.creditAmount);

    return CreditListMetrics(
      filteredRecords: filtered,
      totalCredit: totalCredit,
      totalAccounts: allRecords.length,
      filteredCredit: filteredCredit,
      filteredCount: filtered.length,
      countCurrent: countCurrent,
      countDueSoon: countDueSoon,
      countOverdue: countOverdue,
    );
  }

  /// Comparator logic to order two [CreditRecord] items based on the given [CreditSort].
  int compareCreditRecords(CreditRecord a, CreditRecord b, CreditSort sort) {
    switch (sort) {
      case CreditSort.highestAmount:
        return b.delivery.creditAmount.compareTo(a.delivery.creditAmount);
      case CreditSort.lowestAmount:
        return a.delivery.creditAmount.compareTo(b.delivery.creditAmount);
      case CreditSort.oldest:
        final dateA = a.delivery.deliveryDate?.toDate() ?? DateTime(1970);
        final dateB = b.delivery.deliveryDate?.toDate() ?? DateTime(1970);
        return dateA.compareTo(dateB);
      case CreditSort.newest:
        final dateA = a.delivery.deliveryDate?.toDate() ?? DateTime(1970);
        final dateB = b.delivery.deliveryDate?.toDate() ?? DateTime(1970);
        return dateB.compareTo(dateA);
    }
  }

  // ==========================================
  // Detail & Settlement Operations (CreditPage)
  // ==========================================

  /// Checks if the selected credit status matches the record's current status.
  bool isStatusUnchanged({required String currentStatus, required String selectedStatus}) {
    return currentStatus == selectedStatus;
  }

  /// Resolves the initial status for a delivery record, defaulting to unpaid if empty.
  String resolveInitialStatus(Delivery delivery) {
    return delivery.creditStatus.isNotEmpty ? delivery.creditStatus : CreditStatus.unpaid;
  }

  /// Updates the credit settlement status of a delivery in Firestore via [DeliveryService]
  /// and writes an audit log trail using [Helperfunctions.logUpdate].
  ///
  /// Returns the updated [Delivery] instance.
  Future<Delivery> updateCreditStatus({required String deliveryId, required Delivery currentDelivery, required String newCreditStatus}) async {
    final currentUserName = authService.value.currentUser?.displayName ?? 'Admin';

    // Construct immutable updated delivery model
    final updatedDelivery = currentDelivery.copyWith(
      storeName: currentDelivery.storeName,
      remarks: currentDelivery.remarks,
      transactionStatus: currentDelivery.transactionStatus,
      orderAmount: currentDelivery.orderAmount,
      returnAmount: currentDelivery.returnAmount,
      creditAmount: currentDelivery.creditAmount,
      cashAmount: currentDelivery.cashAmount,
      onlineAmount: currentDelivery.onlineAmount,
      deliveryDate: currentDelivery.deliveryDate,
      creditStatus: newCreditStatus,
      createdBy: currentDelivery.createdBy,
      lastUpdatedBy: currentUserName,
      createdDate: currentDelivery.createdDate,
      lastupdatedDate: Timestamp.now(),
      createdPage: currentDelivery.createdPage,
      lastUpdatedPage: AppPages.credit,
    );

    // Persist changes to Firestore via the Service layer
    await _effectiveDeliveryService.updateDelivery(deliveryId, updatedDelivery);

    // Record audit trail entry
    Helperfunctions.logUpdate(updatedDelivery.storeName, currentDelivery.toJson(), updatedDelivery.toJson(), page: AppPages.credit);

    return updatedDelivery;
  }
}
