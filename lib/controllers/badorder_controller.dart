import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/badorder.dart';
import 'package:selecta_ops/models/badorder_batch.dart';
import 'package:selecta_ops/services/auth_service.dart';
import 'package:selecta_ops/services/badorder_batch_service.dart';
import 'package:selecta_ops/services/badorder_service.dart';
import 'package:selecta_ops/services/hapistore_service.dart';

/// Aggregation and filtering result for bad orders.
class BadOrderFilterResult {
  final List<QueryDocumentSnapshot<BadOrder>> filteredDocs;
  final double periodTotalAmount;
  final int thisMonthCount;
  final int allCount;
  final int storeRefundedCount;
  final int storeNotRefundedCount;

  const BadOrderFilterResult({
    required this.filteredDocs,
    required this.periodTotalAmount,
    required this.thisMonthCount,
    required this.allCount,
    required this.storeRefundedCount,
    required this.storeNotRefundedCount,
  });
}

/// Controller encapsulating business logic, Firestore CRUD operations,
/// logging, role validation, and filtering for Bad Order records.
class BadOrderController {
  BadOrderService? _customBadOrderService;
  BadOrderService get _badOrderService => _customBadOrderService ??= BadOrderService();

  HapiStoreService? _customHapiStoreService;
  HapiStoreService get _hapiStoreService => _customHapiStoreService ??= HapiStoreService();

  BadOrderBatchService? _customBadOrderBatchService;
  BadOrderBatchService get _badOrderBatchService =>
      _customBadOrderBatchService ??= BadOrderBatchService();

  BadOrderController({
    BadOrderService? badOrderService,
    HapiStoreService? hapiStoreService,
    BadOrderBatchService? badOrderBatchService,
  })  : _customBadOrderService = badOrderService,
        _customHapiStoreService = hapiStoreService,
        _customBadOrderBatchService = badOrderBatchService;

  /// Real-time stream of all bad order documents.
  Stream<QuerySnapshot<BadOrder>> getBadOrdersStream() =>
      _badOrderService.getListBadOrder();

  /// Real-time stream of all bad order warehouse batches.
  Stream<QuerySnapshot<BadOrderBatch>> getBatchesStream() =>
      _badOrderBatchService.getListBatches();

  /// Real-time stream of all active stores for store selection dropdowns.
  Stream<QuerySnapshot> getHapiStoresStream() =>
      _hapiStoreService.getListHapiStoresAsStream();

  /// Checks if the current user possesses the Dealer business role.
  Future<bool> checkIsDealer() => KVariables.getIsDealer();

  /// Checks if the current user possesses the Admin business role.
  Future<bool> checkIsAdmin() => KVariables.getIsAdmin();

  /// Returns the display name of the currently authenticated user.
  String getCurrentUserDisplayName() {
    return authService.value.currentUser?.displayName ?? 'Unknown';
  }

  /// Filters and aggregates bad order documents according to period, status, refund state, and search query.
  /// Automatically excludes old/legacy records without items.
  BadOrderFilterResult filterBadOrders({
    required List<QueryDocumentSnapshot<BadOrder>> docs,
    required String selectedPeriod,
    required String searchQuery,
    required DateTime now,
    String? statusFilter,
    String? refundFilter,
  }) {
    int thisMonthCount = 0;
    int validTotalCount = 0;
    int storeRefundedCount = 0;
    int storeNotRefundedCount = 0;
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
      if (badorder.isStoreRefunded) {
        storeRefundedCount++;
      } else {
        storeNotRefundedCount++;
      }

      final date = badorder.badorderDate.toDate();
      final isThisMonth = date.year == now.year && date.month == now.month;

      if (isThisMonth) thisMonthCount++;

      final matchesPeriod = selectedPeriod == 'All' || isThisMonth;
      final matchesStatus = statusFilter == null ||
          statusFilter == 'All' ||
          badorder.status.toLowerCase() == statusFilter.toLowerCase();

      final matchesRefund = refundFilter == null ||
          refundFilter == 'All' ||
          (refundFilter == 'Store Refunded' && badorder.isStoreRefunded) ||
          (refundFilter == 'Store Not Refunded' && !badorder.isStoreRefunded);

      final matchesSearch = cleanQuery.isEmpty ||
          badorder.hapistore.toLowerCase().contains(cleanQuery) ||
          badorder.notes.toLowerCase().contains(cleanQuery) ||
          badorder.status.toLowerCase().contains(cleanQuery) ||
          badorder.items.any((item) =>
              item.productName.toLowerCase().contains(cleanQuery));

      if (matchesPeriod) {
        periodTotalAmount += badorder.totalAmount;
      }

      if (matchesPeriod && matchesStatus && matchesRefund && matchesSearch) {
        filteredDocs.add(doc);
      }
    }

    return BadOrderFilterResult(
      filteredDocs: filteredDocs,
      periodTotalAmount: periodTotalAmount,
      thisMonthCount: thisMonthCount,
      allCount: validTotalCount,
      storeRefundedCount: storeRefundedCount,
      storeNotRefundedCount: storeNotRefundedCount,
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
    bool isStoreRefunded = false,
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
      isStoreRefunded: isStoreRefunded,
      storeRefundedDate: isStoreRefunded ? Timestamp.now() : null,
      storeRefundedBy: isStoreRefunded ? user : null,
    );

    final id = await _badOrderService.addBadOrder(newRecord);
    Helperfunctions.logCreate(hapistore, newRecord.toJson(), page: page);
    return id;
  }

  /// Updates an entire bad order record (Dealer only).
  Future<void> updateBadOrder({
    required String recID,
    required BadOrder updatedRecord,
    required BadOrder existingRecord,
    String page = AppPages.badOrder,
  }) async {
    final isDealer = await checkIsDealer();
    if (!isDealer) {
      throw Exception('Only dealers can edit bad order records.');
    }
    final isAdmin = await checkIsAdmin();
    if (!isAdmin && existingRecord.status != BadOrderStatus.storePullout) {
      throw Exception(
        'Cannot edit bad order once status is "${existingRecord.status}" in order to maintain data accuracy.',
      );
    }
    final user = getCurrentUserDisplayName();
    final toSave = updatedRecord.copyWith(
      lastUpdatedBy: user,
      lastupdatedDate: Timestamp.now(),
      lastUpdatedPage: page,
    );
    await _badOrderService.updateBadOrder(recID, toSave);
    Helperfunctions.logUpdate(
      existingRecord.hapistore,
      existingRecord.toJson(),
      toSave.toJson(),
      page: page,
    );
  }

  /// Toggles whether the store has been refunded / credited for this bad order (Dealer only).
  Future<void> toggleStoreRefunded({
    required String recID,
    required BadOrder existingRecord,
    required bool isRefunded,
    String page = AppPages.badOrder,
  }) async {
    final isDealer = await checkIsDealer();
    if (!isDealer) {
      throw Exception('Only dealers can update store refund status.');
    }
    final user = getCurrentUserDisplayName();
    await _badOrderService.updateBadOrderStoreRefunded(
      recID,
      isRefunded,
      updatedBy: user,
      page: page,
    );
    Helperfunctions.logUpdate(
      existingRecord.hapistore,
      existingRecord.toJson(),
      {...existingRecord.toJson(), 'isStoreRefunded': isRefunded},
      page: page,
    );
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

  /// Deletes a bad order record and logs the transaction (Dealer only).
  Future<void> deleteBadOrder({
    required String recID,
    required BadOrder existingRecord,
  }) async {
    final isDealer = await checkIsDealer();
    if (!isDealer) {
      throw Exception('Only dealers can delete bad order records.');
    }
    final isAdmin = await checkIsAdmin();
    if (!isAdmin && existingRecord.status != BadOrderStatus.storePullout) {
      throw Exception(
        'Cannot delete bad order once status is "${existingRecord.status}" in order to maintain data accuracy.',
      );
    }
    await _badOrderService.deleteBadOrder(recID);
    Helperfunctions.logDelete(
      existingRecord.hapistore,
      existingRecord.toJson(),
      page: AppPages.badOrder,
    );
  }

  /// Generates a default batch number e.g. "BO-202610-001" based on existing batch count.
  String generateDefaultBatchNumber(int existingBatchCount) {
    final monthStr = DateFormat('yyyyMM').format(DateTime.now());
    final seq = (existingBatchCount + 1).toString().padLeft(3, '0');
    return 'BO-$monthStr-$seq';
  }

  /// Creates a new warehouse pullout batch and updates member bad orders (Dealer only).
  Future<String> createWarehouseBatch({
    required String batchNumber,
    required String supplierRefNo,
    required DateTime pulloutDate,
    required List<QueryDocumentSnapshot<BadOrder>> selectedBadOrders,
    String notes = '',
  }) async {
    final isDealer = await checkIsDealer();
    if (!isDealer) {
      throw Exception('Only dealers can create warehouse pullout batches.');
    }
    final user = getCurrentUserDisplayName();
    final now = Timestamp.now();

    final badOrderIds = selectedBadOrders.map((d) => d.id).toList();
    final storeNames = selectedBadOrders.map((d) => d.data().hapistore).toSet().toList();
    final totalAmount = selectedBadOrders.fold<double>(0.0, (acc, d) => acc + d.data().totalAmount);
    final totalItems = selectedBadOrders.fold<int>(0, (acc, d) => acc + d.data().items.length);

    final newBatch = BadOrderBatch(
      batchNumber: batchNumber.trim(),
      supplierRefNo: supplierRefNo.trim(),
      pulloutDate: Timestamp.fromDate(pulloutDate),
      badOrderIds: badOrderIds,
      storeNames: storeNames,
      totalBatchAmount: totalAmount,
      totalItemsCount: totalItems,
      status: BadOrderStatus.warehousePullout,
      notes: notes.trim(),
      createdBy: user,
      createdDate: now,
      lastUpdatedBy: user,
      lastupdatedDate: now,
    );

    final batchId = await _badOrderBatchService.createBatch(newBatch);
    Helperfunctions.logCreate(
      'Batch: $batchNumber',
      newBatch.toJson(),
      page: AppPages.badOrder,
    );
    return batchId;
  }

  /// Settles a warehouse batch with supplier Credit Memo / Refund details (Dealer only).
  Future<void> settleWarehouseBatch({
    required String batchId,
    required BadOrderBatch existingBatch,
    required double supplierRefundAmount,
    required String supplierCreditMemoNo,
    required DateTime supplierRefundDate,
    String adjustmentReason = '',
  }) async {
    final isDealer = await checkIsDealer();
    if (!isDealer) {
      throw Exception('Only dealers can settle warehouse batches.');
    }
    final user = getCurrentUserDisplayName();

    await _badOrderBatchService.settleBatch(
      batchId: batchId,
      existingBatch: existingBatch,
      supplierRefundAmount: supplierRefundAmount,
      supplierCreditMemoNo: supplierCreditMemoNo.trim(),
      supplierRefundDate: supplierRefundDate,
      adjustmentReason: adjustmentReason.trim(),
      user: user,
    );

    Helperfunctions.logUpdate(
      'Batch: ${existingBatch.batchNumber}',
      existingBatch.toJson(),
      {
        ...existingBatch.toJson(),
        'status': BadOrderStatus.settled,
        'isSupplierRefunded': true,
        'supplierRefundAmount': supplierRefundAmount,
        'supplierCreditMemoNo': supplierCreditMemoNo.trim(),
      },
      page: AppPages.badOrder,
    );
  }

  /// Deletes/cancels an unsettled warehouse batch and reverts bad orders back to 'Store Pullout' (Dealer only).
  Future<void> deleteWarehouseBatch({
    required String batchId,
    required BadOrderBatch existingBatch,
  }) async {
    final isDealer = await checkIsDealer();
    if (!isDealer) {
      throw Exception('Only dealers can delete warehouse batches.');
    }
    final user = getCurrentUserDisplayName();

    await _badOrderBatchService.deleteBatch(
      batchId: batchId,
      existingBatch: existingBatch,
      user: user,
    );

    Helperfunctions.logDelete(
      'Batch: ${existingBatch.batchNumber}',
      existingBatch.toJson(),
      page: AppPages.badOrder,
    );
  }
}
