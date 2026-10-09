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
  final List<QueryDocumentSnapshot<BadOrder>> filteredDocs;
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
  final BadOrderService _badOrderService;
  final HapiStoreService _hapiStoreService;

  BadOrderController({
    BadOrderService? badOrderService,
    HapiStoreService? hapiStoreService,
  })  : _badOrderService = badOrderService ?? BadOrderService(),
        _hapiStoreService = hapiStoreService ?? HapiStoreService();

  /// Real-time stream of all bad order documents.
  Stream<QuerySnapshot<BadOrder>> getBadOrdersStream() =>
      _badOrderService.getListBadOrder();

  /// Real-time stream of all active stores for store selection dropdowns.
  Stream<QuerySnapshot> getHapiStoresStream() =>
      _hapiStoreService.getListHapiStoresAsStream();

  /// Checks if the current user possesses the Dealer business role.
  Future<bool> checkIsDealer() => KVariables.getIsDealer();

  /// Returns the display name of the currently authenticated user.
  String getCurrentUserDisplayName() {
    return authService.value.currentUser?.displayName ?? 'Unknown';
  }

  /// Filters and aggregates bad order documents according to period, status, and search query.
  /// Automatically excludes old/legacy records without items.
  BadOrderFilterResult filterBadOrders({
    required List<QueryDocumentSnapshot<BadOrder>> docs,
    required String selectedPeriod,
    required String searchQuery,
    required DateTime now,
    String? statusFilter,
  }) {
    int thisMonthCount = 0;
    int validTotalCount = 0;
    double periodTotalAmount = 0;
    final List<QueryDocumentSnapshot<BadOrder>> filteredDocs = [];
    final cleanQuery = searchQuery.trim().toLowerCase();

    for (final doc in docs) {
      final badorder = doc.data();

      // Rule: Do not show old bad order records without items
      if (!badorder.isNewRecord || badorder.items.isEmpty) {
        continue;
      }

      validTotalCount++;
      final date = badorder.badorderDate.toDate();
      final isThisMonth = date.year == now.year && date.month == now.month;

      if (isThisMonth) thisMonthCount++;

      final matchesPeriod = selectedPeriod == 'All' || isThisMonth;
      final matchesStatus = statusFilter == null ||
          statusFilter == 'All' ||
          badorder.status.toLowerCase() == statusFilter.toLowerCase();

      final matchesSearch = cleanQuery.isEmpty ||
          badorder.hapistore.toLowerCase().contains(cleanQuery) ||
          badorder.notes.toLowerCase().contains(cleanQuery) ||
          badorder.status.toLowerCase().contains(cleanQuery) ||
          badorder.items.any((item) =>
              item.productName.toLowerCase().contains(cleanQuery));

      if (matchesPeriod) {
        periodTotalAmount += badorder.totalAmount;
      }

      if (matchesPeriod && matchesStatus && matchesSearch) {
        filteredDocs.add(doc);
      }
    }

    return BadOrderFilterResult(
      filteredDocs: filteredDocs,
      periodTotalAmount: periodTotalAmount,
      thisMonthCount: thisMonthCount,
      allCount: validTotalCount,
    );
  }

  /// Creates a new bad order record and logs the transaction.
  Future<String> createBadOrder({
    required String hapistore,
    required DateTime selectedDate,
    required String imagePath,
    required List<BadOrderItem> items,
    String notes = '',
    String page = AppPages.delivery,
  }) async {
    final user = getCurrentUserDisplayName();
    final newRecord = BadOrder(
      hapistore: hapistore,
      badorderDate: Timestamp.fromDate(selectedDate),
      imagePath: imagePath,
      status: BadOrderStatus.storePullout,
      notes: notes,
      items: items,
      schemaVersion: 2,
      createdBy: user,
      lastUpdatedBy: user,
      createdDate: Timestamp.now(),
      lastupdatedDate: Timestamp.now(),
      createdPage: page,
      lastUpdatedPage: page,
    );

    final id = await _badOrderService.addBadOrder(newRecord);
    Helperfunctions.logCreate(hapistore, newRecord.toJson(), page: page);
    return id;
  }

  /// Updates the status of an existing bad order record (Dealer only).
  Future<void> updateStatus({
    required String recID,
    required BadOrder existingRecord,
    required String newStatus,
    String page = AppPages.badOrder,
  }) async {
    final isDealer = await checkIsDealer();
    if (!isDealer) {
      throw Exception('Only dealers can update bad order status.');
    }
    final user = getCurrentUserDisplayName();
    await _badOrderService.updateBadOrderStatus(
      recID,
      newStatus,
      updatedBy: user,
      page: page,
    );
    Helperfunctions.logUpdate(
      existingRecord.hapistore,
      existingRecord.toJson(),
      {...existingRecord.toJson(), 'status': newStatus},
      page: page,
    );
  }

  /// Deletes a bad order record and logs the transaction.
  Future<void> deleteBadOrder({
    required String recID,
    required BadOrder existingRecord,
  }) async {
    await _badOrderService.deleteBadOrder(recID);
    Helperfunctions.logDelete(
      existingRecord.hapistore,
      existingRecord.toJson(),
      page: AppPages.badOrder,
    );
  }
}
