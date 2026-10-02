import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/badorder.dart';
import 'package:selecta_ops/services/auth_service.dart';
import 'package:selecta_ops/services/badorder_service.dart';
import 'package:selecta_ops/services/hapistore_service.dart';

/// Aggregation and filtering result for bad orders.
class BadOrderFilterResult {
  final List<QueryDocumentSnapshot> filteredDocs;
  final double periodTotalAmount;
  final int thisMonthCount;
  final int allCount;

  const BadOrderFilterResult({
    required this.filteredDocs,
    required this.periodTotalAmount,
    required this.thisMonthCount,
    required this.allCount,
  });
}

/// Controller encapsulating business logic, Firestore CRUD operations,
/// logging, role validation, and filtering for Bad Order records.
class BadOrderController {
  final BadOrderService _badOrderService = BadOrderService();
  final HapiStoreService _hapiStoreService = HapiStoreService();

  /// Real-time stream of all bad order documents.
  Stream<QuerySnapshot> getBadOrdersStream() => _badOrderService.getListBadOrder();

  /// Real-time stream of all active stores for store selection dropdowns.
  Stream<QuerySnapshot> getHapiStoresStream() => _hapiStoreService.getListHapiStoresAsStream();

  /// Checks if the current user possesses the Dealer business role.
  Future<bool> checkIsDealer() => KVariables.getIsDealer();

  /// Returns the display name of the currently authenticated user.
  String getCurrentUserDisplayName() {
    return authService.value.currentUser?.displayName ?? 'Unknown';
  }

  /// Filters and aggregates bad order documents according to period and search query.
  BadOrderFilterResult filterBadOrders({
    required List<QueryDocumentSnapshot> docs,
    required String selectedPeriod,
    required String searchQuery,
    required DateTime now,
  }) {
    int thisMonthCount = 0;
    double periodTotalAmount = 0;
    final List<QueryDocumentSnapshot> filteredDocs = [];
    final cleanQuery = searchQuery.trim().toLowerCase();

    for (final doc in docs) {
      final badorder = doc.data() as BadOrder;
      final date = badorder.badorderDate.toDate();
      final isThisMonth = date.year == now.year && date.month == now.month;

      if (isThisMonth) thisMonthCount++;

      final matchesPeriod = selectedPeriod == 'All' || isThisMonth;
      final matchesSearch = cleanQuery.isEmpty ||
          badorder.hapistore.toLowerCase().contains(cleanQuery) ||
          badorder.description.toLowerCase().contains(cleanQuery);

      if (matchesPeriod) {
        periodTotalAmount += badorder.badorderAmount;
      }

      if (matchesPeriod && matchesSearch) {
        filteredDocs.add(doc);
      }
    }

    return BadOrderFilterResult(
      filteredDocs: filteredDocs,
      periodTotalAmount: periodTotalAmount,
      thisMonthCount: thisMonthCount,
      allCount: docs.length,
    );
  }

  /// Creates a new bad order record and logs the transaction.
  Future<void> createBadOrder({
    required String hapistore,
    required String description,
    required double amount,
    required DateTime selectedDate,
  }) async {
    final user = getCurrentUserDisplayName();
    final newRecord = BadOrder(
      description: description,
      hapistore: hapistore,
      badorderAmount: amount,
      badorderDate: Timestamp.fromDate(selectedDate),
      createdBy: user,
      lastUpdatedBy: user,
      createdDate: Timestamp.now(),
      lastupdatedDate: Timestamp.now(),
      createdPage: AppPages.badOrder,
      lastUpdatedPage: AppPages.badOrder,
    );

    _badOrderService.addBadOrder(newRecord);
    Helperfunctions.logCreate(hapistore, newRecord.toJson(), page: AppPages.badOrder);
  }

  /// Updates an existing bad order record and logs the transaction.
  Future<void> updateBadOrder({
    required String recID,
    required BadOrder existingRecord,
    required String hapistore,
    required String description,
    required double amount,
    required DateTime selectedDate,
  }) async {
    final user = getCurrentUserDisplayName();
    final updatedRecord = existingRecord.copyWith(
      description: description,
      hapistore: hapistore,
      badorderAmount: amount,
      badorderDate: Timestamp.fromDate(selectedDate),
      createdBy: existingRecord.createdBy,
      lastUpdatedBy: user,
      createdDate: existingRecord.createdDate,
      lastupdatedDate: Timestamp.now(),
      createdPage: existingRecord.createdPage,
      lastUpdatedPage: AppPages.badOrder,
    );

    _badOrderService.updateBadOrder(recID, updatedRecord);
    Helperfunctions.logUpdate(
      hapistore,
      existingRecord.toJson(),
      updatedRecord.toJson(),
      page: AppPages.badOrder,
    );
  }

  /// Deletes a bad order record and logs the transaction.
  Future<void> deleteBadOrder({
    required String recID,
    required BadOrder existingRecord,
  }) async {
    _badOrderService.deleteBadOrder(recID);
    Helperfunctions.logDelete(
      existingRecord.hapistore,
      existingRecord.toJson(),
      page: AppPages.badOrder,
    );
  }
}
