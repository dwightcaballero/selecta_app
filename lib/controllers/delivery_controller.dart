import 'dart:io';
import 'package:another_telephony/telephony.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/data.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/placement.dart';
import 'package:selecta_ops/services/auth_service.dart';
import 'package:selecta_ops/services/breakdown_service.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/services/inventory_service.dart';
import 'package:selecta_ops/services/placement_service.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:intl/intl.dart';

/// Aggregated counts by delivery status for summary widgets.
class DeliverySummaryCounts {
  /// Total number of deliveries for the selected date.
  final int all;

  /// Count of orders waiting for picklist completion.
  final int pendingPicklist;

  /// Count of successfully delivered records.
  final int delivered;

  /// Count of records pending delivery (picklist completed, ready for delivery).
  final int pending;

  /// Count of records that were returned.
  final int returned;

  const DeliverySummaryCounts({required this.all, this.pendingPicklist = 0, required this.delivered, required this.pending, required this.returned});
}

/// Container bundling fetched placement document ID and placement items for a store.
class PlacementLoadResult {
  /// Existing placement document ID in Firestore, if any.
  final String placementId;

  /// List of placement items with state populated from the database.
  final List<KPlacement> placements;

  const PlacementLoadResult({required this.placementId, required this.placements});
}

/// Controller managing business logic, computations, validations, and service orchestration
/// for the unified Order -> Picklist -> Delivery workflow.
class DeliveryController {
  final DeliveryService _deliveryService;
  final PlacementService _placementService;
  final BreakdownService _breakdownService;
  final InventoryService _inventoryService;

  DeliveryController({
    DeliveryService? deliveryService,
    PlacementService? placementService,
    BreakdownService? breakdownService,
    InventoryService? inventoryService,
  }) : _deliveryService = deliveryService ?? DeliveryService(),
       _placementService = placementService ?? PlacementService(),
       _breakdownService = breakdownService ?? BreakdownService(),
       _inventoryService = inventoryService ?? InventoryService();

  // ==========================================
  // Shared / Role & Breakdown Queries
  // ==========================================

  /// Verifies whether the currently logged-in user possesses dealer privileges.
  Future<bool> checkIsDealer() async {
    return await KVariables.getIsDealer();
  }

  /// Checks if a cash breakdown has already been recorded for the specified [date].
  ///
  /// When recorded, salesmen are locked from modifying delivery records for that day.
  Future<bool> checkBreakdownStatus(DateTime date) async {
    final String breakdownId = await _breakdownService.getIDofBreakdown(date);
    return breakdownId.isNotEmpty;
  }

  /// Returns whether a breakdown exists and whether it has already been verified by the dealer.
  /// When verified, delivery records for that day are permanently locked for all users (including dealers).
  Future<({bool hasBreakdown, bool isVerified})> checkBreakdownAndVerificationStatus(DateTime date) async {
    final breakdown = await _breakdownService.getDocumentsBySpecificDate(date);
    if (breakdown == null) {
      return (hasBreakdown: false, isVerified: false);
    }
    return (hasBreakdown: true, isVerified: breakdown.isVerifiedByDealer);
  }

  // ==========================================
  // List Operations (DeliveryListPage & PicklistListPage)
  // ==========================================

  /// Returns a real-time stream of delivery records for a specific delivery date.
  Stream<QuerySnapshot<Delivery>> getDeliveriesStream(DateTime date) {
    return _deliveryService.getListDeliveryByDate(date);
  }

  /// Returns a real-time stream of all orders currently in `Pending Picklist` status.
  Stream<QuerySnapshot<Delivery>> getPendingPicklistsStream() {
    return _deliveryService.getPendingPicklistsStream();
  }

  /// Live count stream of orders currently in `Pending Picklist` status for [date] (defaults to current day).
  Stream<int> getPendingPicklistCountStream({DateTime? date}) {
    return _deliveryService.getPendingPicklistCountStream(date: date);
  }

  /// Fetches the count of returned deliveries from past days that need attention/rescheduling.
  Future<int?> getCountReturnedDeliveriesOnOtherDays() async {
    return await DeliveryService.getCountReturnedDeliveriesOnOtherDays();
  }

  /// Real-time stream of the count of returned deliveries requiring dealer action.
  Stream<int> getActiveReturnedDeliveriesCountStream() {
    return _deliveryService.getActiveReturnedDeliveriesCountStream();
  }

  /// Formats the selected date into a friendly navigation label (e.g. "Today, 28 Sep 2026").
  String formatDateLabel(DateTime selectedDate) {
    final today = DateTime.now();
    final selectedDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final currentDay = DateTime(today.year, today.month, today.day);

    if (selectedDay == currentDay) {
      return 'Today, ${DateFormat('d MMM yyyy').format(selectedDate)}';
    }
    if (selectedDay == currentDay.subtract(const Duration(days: 1))) {
      return 'Yesterday, ${DateFormat('d MMM').format(selectedDate)}';
    }
    if (selectedDay == currentDay.add(const Duration(days: 1))) {
      return 'Tomorrow, ${DateFormat('d MMM').format(selectedDate)}';
    }
    return DateFormat('EEE, d MMM yyyy').format(selectedDate);
  }

  /// Computes summary counts across all delivery documents for the interactive status tabs.
  DeliverySummaryCounts computeSummaryCounts(List docs) {
    int pendingPicklist = 0;
    int pending = 0;
    int delivered = 0;
    int returned = 0;

    for (final item in docs) {
      final Delivery delivery = item.data() as Delivery;
      switch (delivery.transactionStatus) {
        case DeliveryStatus.pendingPicklist:
          pendingPicklist++;
          break;
        case DeliveryStatus.pending:
          pending++;
          break;
        case DeliveryStatus.delivered:
          delivered++;
          break;
        case DeliveryStatus.returned:
          returned++;
          break;
      }
    }

    return DeliverySummaryCounts(all: docs.length, pendingPicklist: pendingPicklist, delivered: delivered, pending: pending, returned: returned);
  }

  /// Filters delivery document snapshots by selected status tab and search query,
  /// and sorts the stores based on custom delivery sequence or who was processed in picklist first.
  List filterDeliveries({
    required List docs,
    required String selectedStatus,
    required String searchQuery,
    bool ignoreCustomSequence = false,
  }) {
    final query = searchQuery.trim().toLowerCase();
    final filtered = docs.where((doc) {
      final raw = doc.data();
      final Delivery delivery = raw is Delivery ? raw : Delivery.fromJson(raw as Map<String, Object?>);
      if (delivery.transactionStatus == DeliveryStatus.pendingPicklist) {
        return false;
      }
      final matchesStatus = selectedStatus == 'All' || delivery.transactionStatus == selectedStatus;
      final matchesSearch = query.isEmpty || delivery.storeName.toLowerCase().contains(query);
      return matchesStatus && matchesSearch;
    }).toList();

    final hasCustomSequence = !ignoreCustomSequence && filtered.any((d) {
      final raw = d.data();
      final Delivery del = raw is Delivery ? raw : Delivery.fromJson(raw as Map<String, Object?>);
      return del.deliverySequence != null;
    });

    filtered.sort((a, b) {
      final rawA = a.data();
      final rawB = b.data();
      final Delivery delA = rawA is Delivery ? rawA : Delivery.fromJson(rawA as Map<String, Object?>);
      final Delivery delB = rawB is Delivery ? rawB : Delivery.fromJson(rawB as Map<String, Object?>);

      if (hasCustomSequence) {
        final seqA = delA.deliverySequence;
        final seqB = delB.deliverySequence;
        if (seqA != null && seqB != null) {
          final cmp = seqA.compareTo(seqB);
          if (cmp != 0) return cmp;
        } else if (seqA != null) {
          return -1;
        } else if (seqB != null) {
          return 1;
        }
      }

      final timeA = delA.picklistCompletedDate;
      final timeB = delB.picklistCompletedDate;

      // 1. Stores processed in picklist first appear first
      if (timeA != null && timeB != null) {
        final cmp = timeA.compareTo(timeB);
        if (cmp != 0) return cmp;
      } else if (timeA != null) {
        return -1;
      } else if (timeB != null) {
        return 1;
      } else {
        // Fallback for deliveries without picklistCompletedDate:
        // Already processed statuses (pending, delivered, returned) come before pendingPicklist
        final isDelAProcessed = delA.transactionStatus != DeliveryStatus.pendingPicklist;
        final isDelBProcessed = delB.transactionStatus != DeliveryStatus.pendingPicklist;
        if (isDelAProcessed && !isDelBProcessed) return -1;
        if (!isDelAProcessed && isDelBProcessed) return 1;
        if (isDelAProcessed && isDelBProcessed) {
          final cmp = delA.lastupdatedDate.compareTo(delB.lastupdatedDate);
          if (cmp != 0) return cmp;
        }
      }
      return delA.createdDate.compareTo(delB.createdDate);
    });

    return filtered;
  }

  /// Returns the PJP weekday name for the day preceding [selectedDate].
  /// If the previous day is Sunday but no stores have a Sunday schedule, falls back to Saturday.
  String getPreviousPjpDayName(DateTime selectedDate, [Map<String, Hapistore>? storesByName]) {
    final prevDate = selectedDate.subtract(const Duration(days: 1));
    final prevDayName = PjpScheduleDays.all[prevDate.weekday - 1];
    if (prevDate.weekday == DateTime.sunday && storesByName != null) {
      final hasSundayStores = storesByName.values.any((s) => s.pjpSchedule?.trim().toLowerCase() == PjpScheduleDays.sunday.toLowerCase());
      if (!hasSundayStores) {
        return PjpScheduleDays.saturday;
      }
    }
    return prevDayName;
  }

  /// Sorts pending picklist delivery documents based on PJP schedule and sequence for the previous day.
  /// Stores belonging to the previous day's PJP schedule appear first, ordered by their PJP sequence.
  /// Stores not part of the previous day's PJP schedule are placed at the bottom.
  /// If the user has manually edited the order, that order (picklistSequence) is respected.
  List<QueryDocumentSnapshot<Delivery>> sortPendingPicklists({
    required List<QueryDocumentSnapshot<Delivery>> docs,
    required DateTime selectedDate,
    required Map<String, Hapistore> storesByName,
    bool ignoreCustomSequence = false,
  }) {
    final sorted = [...docs];
    final targetPjpDay = getPreviousPjpDayName(selectedDate, storesByName).toLowerCase();

    final hasCustomSequence = !ignoreCustomSequence && sorted.any((d) => d.data().picklistSequence != null);

    sorted.sort((a, b) {
      final delA = a.data();
      final delB = b.data();

      if (hasCustomSequence) {
        final seqA = delA.picklistSequence;
        final seqB = delB.picklistSequence;
        if (seqA != null && seqB != null) {
          final cmp = seqA.compareTo(seqB);
          if (cmp != 0) return cmp;
        } else if (seqA != null) {
          return -1;
        } else if (seqB != null) {
          return 1;
        }
      }

      // Default PJP schedule & sequence logic:
      final storeA = storesByName[delA.storeName.trim().toLowerCase()];
      final storeB = storesByName[delB.storeName.trim().toLowerCase()];

      final isPjpA = storeA?.pjpSchedule?.trim().toLowerCase() == targetPjpDay;
      final isPjpB = storeB?.pjpSchedule?.trim().toLowerCase() == targetPjpDay;

      // PJP stores of previous day come first; non-PJP stores go to the bottom
      if (isPjpA && !isPjpB) return -1;
      if (!isPjpA && isPjpB) return 1;

      if (isPjpA && isPjpB) {
        // Both part of previous day's PJP schedule: sort by pjpSequence
        final pjpSeqA = storeA?.pjpSequence;
        final pjpSeqB = storeB?.pjpSequence;
        if (pjpSeqA != null && pjpSeqB != null) {
          final cmp = pjpSeqA.compareTo(pjpSeqB);
          if (cmp != 0) return cmp;
        } else if (pjpSeqA != null) {
          return -1;
        } else if (pjpSeqB != null) {
          return 1;
        }
        return delA.storeName.toLowerCase().compareTo(delB.storeName.toLowerCase());
      }

      // Neither is part of previous day's PJP schedule: placed at bottom, sorted alphabetically
      return delA.storeName.toLowerCase().compareTo(delB.storeName.toLowerCase());
    });

    return sorted;
  }

  /// Persists a new store order for pending picklists and synchronizes PJP sequence for previous day's stores.
  Future<void> savePicklistSequenceOrder({
    required List<String> orderedDeliveryIDs,
    required DateTime selectedDate,
    required Map<String, QueryDocumentSnapshot<Delivery>> docsById,
    required Map<String, Hapistore> storesByName,
    required Map<String, String> storeDocIdsByName,
  }) async {
    // 1. Update picklistSequence on deliveries
    await _deliveryService.updatePicklistSequenceOrder(orderedDeliveryIDs);

    // 2. Also synchronize pjpSequence in hapistores for stores that belong to the previous day's PJP
    final targetPjpDay = getPreviousPjpDayName(selectedDate, storesByName);
    final targetPjpStoreDocIDs = <String>[];
    for (final delId in orderedDeliveryIDs) {
      final doc = docsById[delId];
      if (doc == null) continue;
      final storeName = doc.data().storeName.trim().toLowerCase();
      final store = storesByName[storeName];
      final storeDocId = storeDocIdsByName[storeName];
      if (store != null && storeDocId != null && store.pjpSchedule?.trim().toLowerCase() == targetPjpDay.toLowerCase()) {
        if (!targetPjpStoreDocIDs.contains(storeDocId)) {
          targetPjpStoreDocIDs.add(storeDocId);
        }
      }
    }
    if (targetPjpStoreDocIDs.isNotEmpty) {
      final hapiStoreService = HapiStoreService();
      await hapiStoreService.updatePjpSequenceOrder(targetPjpDay, targetPjpStoreDocIDs);
    }

    // 3. Log transaction
    final names = orderedDeliveryIDs.map((id) => docsById[id]?.data().storeName ?? id).join(', ');
    await Helperfunctions.logTransaction(
      'Picklist Resequence - $targetPjpDay (Previous Day)',
      'New order: $names',
      LogAction.update,
      page: AppPages.picklist,
    );
  }

  /// Resets custom picklistSequence on deliveries so order falls back to PJP schedule.
  Future<void> resetPicklistSequenceOrder({required List<String> deliveryIDs}) async {
    await _deliveryService.clearPicklistSequenceOrder(deliveryIDs);
  }

  /// Persists a new store order for deliveries.
  Future<void> saveDeliverySequenceOrder({
    required List<String> orderedDeliveryIDs,
    required DateTime selectedDate,
    required Map<String, QueryDocumentSnapshot<Delivery>> docsById,
  }) async {
    // 1. Update deliverySequence on deliveries
    await _deliveryService.updateDeliverySequenceOrder(orderedDeliveryIDs);

    // 2. Log transaction
    final names = orderedDeliveryIDs.map((id) => docsById[id]?.data().storeName ?? id).join(', ');
    await Helperfunctions.logTransaction(
      'Delivery Resequence - ${formatDateLabel(selectedDate)}',
      'New order: $names',
      LogAction.update,
      page: AppPages.delivery,
    );
  }

  /// Resets custom deliverySequence on deliveries so order falls back to default sequence.
  Future<void> resetDeliverySequenceOrder({required List<String> deliveryIDs}) async {
    await _deliveryService.clearDeliverySequenceOrder(deliveryIDs);
  }

  // ==========================================
  // Step 1: Book Order Operations (BookOrderPage)
  // ==========================================

  /// Computes total order amount from a list of [OrderItem]s.
  double computeItemsOrderAmount(List<OrderItem> items) {
    Decimal total = Decimal.zero;
    for (final item in items) {
      total += Decimal.parse(item.lineTotal.toStringAsFixed(2));
    }
    return total.toDouble();
  }

  /// Creates a new Booked Order (`Pending Picklist`) in the unified `delivery` collection,
  /// temporarily reserves floating stock (`reservedQuantity`), and writes an audit log.
  Future<({String id, Delivery delivery})> createBookedOrder({
    required String storeName,
    required DateTime selectedDate,
    required List<OrderItem> items,
    String remarks = '',
  }) async {
    final status = await checkBreakdownAndVerificationStatus(selectedDate);
    if (status.isVerified) {
      throw Exception('Cannot book order: Daily cash breakdown for this date has already been verified and closed.');
    }

    final cleanItems = items.where((i) => i.pickedQuantity > 0).toList();
    final double orderAmount = computeItemsOrderAmount(cleanItems);
    final currentUserName = authService.value.currentUser?.displayName ?? 'Admin';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final deliveryDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final isTomorrowOrFuture = deliveryDay.isAfter(today);
    final shouldReserve = !isTomorrowOrFuture;

    final newRecord = Delivery(
      storeName: storeName,
      remarks: remarks.trim(),
      transactionStatus: DeliveryStatus.pendingPicklist,
      imagePath: '',
      orderAmount: orderAmount,
      returnAmount: 0,
      creditAmount: 0,
      cashAmount: 0,
      onlineAmount: 0,
      deliveryDate: Timestamp.fromDate(selectedDate),
      creditStatus: CreditStatus.unpaid,
      createdBy: currentUserName,
      lastUpdatedBy: currentUserName,
      createdDate: Timestamp.now(),
      lastupdatedDate: Timestamp.now(),
      createdPage: AppPages.bookOrder,
      lastUpdatedPage: AppPages.bookOrder,
      items: cleanItems,
      isInventoryReserved: shouldReserve,
      isInventoryDeducted: false,
    );

    // 1. Reserve floating inventory only if delivery is for today (so today's actual stock is not blocked by advance orders)
    if (shouldReserve) {
      await _inventoryService.reserveStockForOrder(storeName: storeName, items: cleanItems);
    }

    // 2. Persist unified transaction in `delivery` collection
    final String newId = await _deliveryService.addDelivery(newRecord);

    // 3. Write audit log
    await Helperfunctions.logCreate(storeName, newRecord.toJson(), page: AppPages.bookOrder);

    return (id: newId, delivery: newRecord);
  }

  /// Updates an existing Booked Order while it is still in `Pending Picklist` status,
  /// adjusting floating stock reservations (`reservedQuantity`) accordingly.
  Future<Delivery> updateBookedOrder({
    required String deliveryId,
    required Delivery currentDelivery,
    required String storeName,
    required DateTime selectedDate,
    required List<OrderItem> items,
    String? remarks,
  }) async {
    final cleanItems = items.where((i) => i.pickedQuantity > 0).toList();
    final double orderAmount = computeItemsOrderAmount(cleanItems);
    final currentUserName = authService.value.currentUser?.displayName ?? 'Admin';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final deliveryDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final isTomorrowOrFuture = deliveryDay.isAfter(today);

    if (isTomorrowOrFuture) {
      // If order previously reserved inventory, release it since it is now an advance order
      if (currentDelivery.isInventoryReserved && !currentDelivery.isInventoryDeducted) {
        await _inventoryService.releaseReservedStockForOrder(storeName: storeName, items: currentDelivery.items);
      }
    } else {
      // If delivery is for today/same-day:
      if (currentDelivery.isInventoryReserved && !currentDelivery.isInventoryDeducted) {
        await _inventoryService.adjustReservedStockForOrderUpdate(storeName: storeName, oldItems: currentDelivery.items, newItems: cleanItems);
      } else if (!currentDelivery.isInventoryReserved && !currentDelivery.isInventoryDeducted) {
        await _inventoryService.reserveStockForOrder(storeName: storeName, items: cleanItems);
      }
    }

    final updated = currentDelivery.copyWith(
      storeName: storeName,
      remarks: remarks ?? currentDelivery.remarks,
      deliveryDate: Timestamp.fromDate(selectedDate),
      orderAmount: orderAmount,
      items: cleanItems,
      isInventoryReserved: !isTomorrowOrFuture && !currentDelivery.isInventoryDeducted,
      lastUpdatedBy: currentUserName,
      lastupdatedDate: Timestamp.now(),
      lastUpdatedPage: AppPages.bookOrder,
    );

    await _deliveryService.updateDelivery(deliveryId, updated);
    await Helperfunctions.logUpdate(storeName, currentDelivery.toJson(), updated.toJson(), page: AppPages.bookOrder);

    return updated;
  }

  // ==========================================
  // Step 2: Picklist Operations (PicklistPage)
  // ==========================================

  /// Saves intermediate picklist progress (checked items, adjusted quantities, receipt, placement)
  /// while keeping status as `Pending Picklist` and updating floating stock reservation.
  Future<Delivery> savePicklistProgress({
    required BuildContext context,
    required String deliveryId,
    required Delivery currentDelivery,
    required String storeName,
    required List<OrderItem> items,
    required File? imageFile,
    required String networkImagePath,
    required List<KPlacement> placements,
    required String placementId,
    String? remarks,
  }) async {
    final cleanItems = items.where((i) => i.pickedQuantity > 0).toList();
    final double orderAmount = computeItemsOrderAmount(cleanItems);
    final currentUserName = authService.value.currentUser?.displayName ?? 'Admin';

    if (currentDelivery.isInventoryReserved && !currentDelivery.isInventoryDeducted) {
      await _inventoryService.adjustReservedStockForOrderUpdate(storeName: storeName, oldItems: currentDelivery.items, newItems: cleanItems);
    }

    String imageFilePath = currentDelivery.imagePath;
    if (context.mounted) {
      imageFilePath = await Helperfunctions.updateImage(context, imageFile, networkImagePath, currentDelivery.imagePath);
    }

    final updated = currentDelivery.copyWith(
      storeName: storeName,
      remarks: remarks ?? currentDelivery.remarks,
      imagePath: imageFilePath,
      orderAmount: orderAmount,
      items: cleanItems,
      lastUpdatedBy: currentUserName,
      lastupdatedDate: Timestamp.now(),
      lastUpdatedPage: AppPages.picklist,
    );

    await _deliveryService.updateDelivery(deliveryId, updated);

    if (placements.isNotEmpty && updated.deliveryDate != null) {
      final placement = Placement.fromFlags(
        storeName: updated.storeName,
        deliveryDate: updated.deliveryDate!,
        flags: placements.map((p) => p.isPlaced).toList(),
        id: placementId,
      );
      placement.progressCount = placements.where((p) => p.isPlaced).length;
      placement.isFinished = placement.progressCount == 12;
      await _placementService.savePlacement(placement);
    }

    await Helperfunctions.logUpdate(storeName, currentDelivery.toJson(), updated.toJson(), page: AppPages.picklist);

    return updated;
  }

  final Set<String> _inFlightPicklistDeliveries = {};

  /// Completes the Picklist:
  /// 1. Verifies the daily cash breakdown is not already locked.
  /// 2. Uploads/updates receipt image FIRST (so image failures never corrupt database state).
  /// 3. Atomically deducts inventory stock, releases reserved stock, records movements,
  ///    updates the delivery status to `DeliveryStatus.pending` ("For Delivery"), and saves placement
  ///    in a single Firestore transaction (All or Nothing).
  /// 4. Logs audit trail and optionally sends customer SMS.
  Future<Delivery> completePicklist({
    required BuildContext context,
    required String deliveryId,
    required Delivery currentDelivery,
    required String storeName,
    required List<OrderItem> pickedItems,
    required File? imageFile,
    required String networkImagePath,
    required List<KPlacement> placements,
    required String placementId,
    required bool sendText,
    required String smsMessage,
    String? remarks,
    void Function(String step)? onProgress,
  }) async {
    if (_inFlightPicklistDeliveries.contains(deliveryId)) {
      throw Exception('This picklist is already being processed. Please wait.');
    }
    _inFlightPicklistDeliveries.add(deliveryId);

    try {
      final cleanItems = pickedItems.where((i) => i.pickedQuantity > 0).toList();
      final double orderAmount = computeItemsOrderAmount(cleanItems);
      final currentUserName = authService.value.currentUser?.displayName ?? 'Admin';

      final deliveryDate = currentDelivery.deliveryDate?.toDate() ?? DateTime.now();
      final status = await checkBreakdownAndVerificationStatus(deliveryDate);
      if (status.isVerified) {
        throw Exception('Cannot process for delivery: The daily cash breakdown for this date has already been verified and closed by the dealer.');
      }

      // 1. Upload/update receipt image FIRST (outside DB transaction with timeout protection)
      String imageFilePath = currentDelivery.imagePath;
      if (context.mounted && (imageFile != null || networkImagePath.isEmpty)) {
        onProgress?.call('Uploading proof photo...');
        imageFilePath = await Helperfunctions.updateImage(
          context,
          imageFile,
          networkImagePath,
          currentDelivery.imagePath,
        );
      }

      // 2. Prepare updated delivery model
      final updated = currentDelivery.copyWith(
        storeName: storeName,
        remarks: remarks ?? currentDelivery.remarks,
        transactionStatus: DeliveryStatus.pending,
        imagePath: imageFilePath,
        orderAmount: orderAmount,
        items: cleanItems.map((i) => i.copyWith(isPicked: true)).toList(),
        isInventoryReserved: false,
        isInventoryDeducted: true,
        picklistCompletedDate: Timestamp.now(),
        picklistCompletedBy: currentUserName,
        lastUpdatedBy: currentUserName,
        lastupdatedDate: Timestamp.now(),
        lastUpdatedPage: AppPages.picklist,
      );

      // 3. Prepare placement model if present
      Placement? placement;
      if (placements.isNotEmpty && updated.deliveryDate != null) {
        placement = Placement.fromFlags(
          storeName: updated.storeName,
          deliveryDate: updated.deliveryDate!,
          flags: placements.map((p) => p.isPlaced).toList(),
          id: placementId,
        );
        placement.progressCount = placements.where((p) => p.isPlaced).length;
        placement.isFinished = placement.progressCount == 12;
      }

      // 4. ATOMIC DATABASE TRANSACTION (All or Nothing: Stock + Movements + Delivery + Placement)
      onProgress?.call('Verifying stock & marking for delivery...');
      await _inventoryService.completePicklistAtomicTransaction(
        deliveryId: deliveryId,
        updatedDelivery: updated,
        reservedItems: currentDelivery.items,
        pickedItems: cleanItems,
        wasReserved: currentDelivery.isInventoryReserved,
        placement: placement,
      );

      // 5. Write audit trail
      await Helperfunctions.logUpdate(storeName, currentDelivery.toJson(), updated.toJson(), page: AppPages.picklist);

      // 6. Optional SMS notification
      if (sendText && smsMessage.isNotEmpty) {
        await sendDeliverySms(storeName: storeName, message: smsMessage);
      }

      return updated;
    } finally {
      _inFlightPicklistDeliveries.remove(deliveryId);
    }
  }

  // ==========================================
  // Step 3: Delivery & Payment Operations (DeliveryPage)
  // ==========================================

  /// Computes payment discrepancy (total received payments minus the required order amount).
  ///
  /// Returns `0.0` if balanced, positive if overpaid, negative if underpaid.
  /// When [withItemReturns] is true, the orderAmount is already adjusted to exclude returned items,
  /// so returnAmount is excluded from the collected payments to prevent double-counting.
  double computeDiscrepancy({
    required double orderAmount,
    required String cash,
    required String online,
    required String credit,
    required String returnAmount,
    bool withItemReturns = false,
  }) {
    final Decimal cashAmount = Helperfunctions.formatStringAmountToDecimal(cash);
    final Decimal onlineAmount = Helperfunctions.formatStringAmountToDecimal(online);
    final Decimal creditAmount = Helperfunctions.formatStringAmountToDecimal(credit);
    final Decimal returnAmt = withItemReturns ? Decimal.zero : Helperfunctions.formatStringAmountToDecimal(returnAmount);

    final Decimal totalAmount = cashAmount + onlineAmount + creditAmount + returnAmt;
    final Decimal orderAmt = Decimal.parse(orderAmount.toStringAsFixed(2));

    return (totalAmount - orderAmt).toDouble();
  }

  /// Calculates total collected payments across cash, online, credit, and return fields.
  double computeTotalCollected({
    required String cash,
    required String online,
    required String credit,
    required String returnAmount,
    bool withItemReturns = false,
  }) {
    final Decimal cashAmount = Helperfunctions.formatStringAmountToDecimal(cash);
    final Decimal onlineAmount = Helperfunctions.formatStringAmountToDecimal(online);
    final Decimal creditAmount = Helperfunctions.formatStringAmountToDecimal(credit);
    final Decimal returnAmt = withItemReturns ? Decimal.zero : Helperfunctions.formatStringAmountToDecimal(returnAmount);

    return (cashAmount + onlineAmount + creditAmount + returnAmt).toDouble();
  }

  /// Validates delivery payment breakdown and return remarks before updating.
  ///
  /// Returns a list of validation error messages, or an empty list if valid.
  List<String> validateDeliveryForm({
    required String status,
    required double orderAmount,
    required String cash,
    required String online,
    required String credit,
    required String returnAmount,
    required String remarks,
    bool withItemReturns = false,
    bool hasReturnsRecorded = false,
  }) {
    final List<String> listError = [];
    final Decimal cashAmount = Helperfunctions.formatStringAmountToDecimal(cash);
    final Decimal onlineAmount = Helperfunctions.formatStringAmountToDecimal(online);
    final Decimal creditAmount = Helperfunctions.formatStringAmountToDecimal(credit);
    final Decimal returnAmt = withItemReturns ? Decimal.zero : Helperfunctions.formatStringAmountToDecimal(returnAmount);

    final Decimal totalAmount = cashAmount + onlineAmount + creditAmount + returnAmt;
    final Decimal orderAmt = Decimal.parse(orderAmount.toStringAsFixed(2));

    if (status == DeliveryStatus.delivered && totalAmount != orderAmt) {
      listError.add('Total amount does not match the order amount!');
    }
    if ((returnAmt != Decimal.zero || hasReturnsRecorded || status == DeliveryStatus.returned) && remarks.trim().isEmpty) {
      listError.add('Please enter a remark for return details!');
    }

    return listError;
  }

  /// Generates the standard customer confirmation SMS notification body.
  String generateSmsMessage({required String storeName, required String formattedOrderAmount}) {
    return '[SELECTA DELIVERY]\n\n'
        'Good day $storeName! This is to confirm that your order worth ($formattedOrderAmount) is now pending for delivery.\n\n'
        'Please expect your stocks to arrive in a few hours. Thank you for choosing Selecta Ice Cream. Have a sweet day!';
  }

  /// Sends an SMS notification to the customer store using Telephony.
  Future<void> sendDeliverySms({required String storeName, required String message}) async {
    try {
      String storeContact = await HapiStoreService.getContactByStoreName(storeName);
      storeContact = storeContact.replaceFirst('09', '+639');

      final Telephony telephony = Telephony.instance;
      final bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;

      if (permissionsGranted ?? false) {
        telephony.sendSms(to: storeContact, message: message, isMultipart: true);
      }
    } catch (_) {
      // SMS failures should not block successful transaction persistence
    }
  }

  /// Fetches saved placement data for a store in the current month and maps it to placement items based on Best Sellers.
  Future<PlacementLoadResult> loadPlacementsForStore(String storeName) async {
    final selectaService = SelectaProductService();
    final bestSellers = await selectaService.getBestSellerProducts();

    List<KPlacement> listPlacement;
    if (bestSellers.isNotEmpty) {
      listPlacement = bestSellers
          .map(
            (prod) => KPlacement(
              itemName: prod.productName,
              itemCode: prod.id,
              isPlaced: false,
              isPlacedFromDB: false,
              itemImagePath: prod.imageUrl.isNotEmpty ? prod.imageUrl : 'assets/images/placement/watermelon.png',
            ),
          )
          .toList();
    } else {
      listPlacement = KData.getListPlacement();
    }

    String placementId = '';

    if (storeName.isNotEmpty) {
      final savedPlacement = await _placementService.getPlacementByStoreAndDate(storeName, DateTime.now());
      if (savedPlacement != null) {
        placementId = savedPlacement.id;
        final placedLowerNames = savedPlacement.placedProductNames.map((n) => n.trim().toLowerCase()).toSet();

        // Also check legacy cotc flags
        final flags = [
          savedPlacement.cotc1,
          savedPlacement.cotc2,
          savedPlacement.cotc3,
          savedPlacement.cotc4,
          savedPlacement.cotc5,
          savedPlacement.cotc6,
          savedPlacement.cotc7,
          savedPlacement.cotc8,
          savedPlacement.cotc9,
          savedPlacement.cotc10,
          savedPlacement.cotc11,
          savedPlacement.cotc12,
        ];
        final legacyList = KData.getListPlacement();
        for (int i = 0; i < legacyList.length && i < flags.length; i++) {
          if (flags[i]) {
            placedLowerNames.add(legacyList[i].itemName.trim().toLowerCase());
          }
        }

        for (final item in listPlacement) {
          if (placedLowerNames.contains(item.itemName.trim().toLowerCase())) {
            item.isPlaced = true;
            item.isPlacedFromDB = true;
          }
        }
      }
    }

    return PlacementLoadResult(placementId: placementId, placements: listPlacement);
  }

  /// Creates a new delivery record directly (legacy helper).
  Future<Delivery> createDelivery({
    required BuildContext context,
    required String storeName,
    required String orderAmountText,
    required DateTime selectedDate,
    required File? imageFile,
    required List<KPlacement> placements,
    required String placementId,
    required bool sendText,
    required String smsMessage,
  }) async {
    final status = await checkBreakdownAndVerificationStatus(selectedDate);
    if (status.isVerified) {
      throw Exception('Cannot create delivery: Daily cash breakdown for this date has already been verified and closed.');
    }

    String imageFilePath = '';
    if (imageFile != null && context.mounted) {
      imageFilePath = await Helperfunctions.saveImage(context, imageFile);
    }

    final double orderAmount = Helperfunctions.formatStringAmountToDouble(orderAmountText);
    final currentUserName = authService.value.currentUser?.displayName ?? 'Admin';

    final newRecord = Delivery(
      storeName: storeName,
      remarks: '',
      transactionStatus: DeliveryStatus.pending,
      imagePath: imageFilePath,
      orderAmount: orderAmount,
      returnAmount: 0,
      creditAmount: 0,
      cashAmount: 0,
      onlineAmount: 0,
      deliveryDate: Timestamp.fromDate(selectedDate),
      creditStatus: CreditStatus.unpaid,
      createdBy: currentUserName,
      lastUpdatedBy: currentUserName,
      createdDate: Timestamp.now(),
      lastupdatedDate: Timestamp.now(),
      createdPage: AppPages.delivery,
      lastUpdatedPage: AppPages.delivery,
    );

    await _deliveryService.addDelivery(newRecord);

    final placement = Placement.fromFlags(
      storeName: newRecord.storeName,
      deliveryDate: newRecord.deliveryDate!,
      flags: placements.map((placement) => placement.isPlaced).toList(),
      id: placementId,
    );
    placement.progressCount = placements.where((placement) => placement.isPlaced).length;
    placement.isFinished = placement.progressCount == 12;
    await _placementService.savePlacement(placement);

    await Helperfunctions.logCreate(storeName, newRecord.toJson(), page: AppPages.delivery);

    if (sendText && smsMessage.isNotEmpty) {
      await sendDeliverySms(storeName: storeName, message: smsMessage);
    }

    return newRecord;
  }

  Future<Delivery?> getDeliveryById(String deliveryId) async {
    return _deliveryService.getDeliveryById(deliveryId);
  }

  /// Updates an existing delivery record with new amounts, status, and remarks.
  ///
  /// Uploads/updates receipt images, persists changes through [DeliveryService],
  /// and writes an update audit log trail.
  Future<Delivery> updateDelivery({
    required BuildContext context,
    required String deliveryId,
    required Delivery currentDelivery,
    required String storeName,
    required String status,
    required String remarks,
    required String orderAmountText,
    required String cashAmountText,
    required String onlineAmountText,
    required String creditAmountText,
    required String returnAmountText,
    required File? imageFile,
    required String networkImagePath,
    DateTime? selectedDate,
    List<KPlacement>? placements,
    String? placementId,
    List<OrderItem>? itemsWithReturns,
  }) async {
    if (currentDelivery.isReturnApprovedByDealer) {
      throw Exception('This delivery order has already been approved by the dealer and cannot be modified.');
    }
    if (currentDelivery.isInventorySettled) {
      throw Exception('This delivery order has already been verified and locked.');
    }

    double returnAmount = 0;
    double creditAmount = 0;
    double onlineAmount = 0;
    double cashAmount = 0;
    String finalRemarks = remarks;
    double finalOrderAmount = currentDelivery.orderAmount;
    double? finalOriginalOrderAmount = currentDelivery.originalOrderAmount;
    List<OrderItem> finalItems = currentDelivery.items;

    switch (status) {
      case DeliveryStatus.pendingPicklist:
      case DeliveryStatus.pending:
        finalOrderAmount = Helperfunctions.formatStringAmountToDouble(orderAmountText);
        finalRemarks = '';
        returnAmount = 0;
        finalItems = currentDelivery.items.map((i) => i.copyWith(returnedQuantity: 0)).toList();
        finalOriginalOrderAmount = null;
        break;

      case DeliveryStatus.delivered:
        creditAmount = Helperfunctions.formatStringAmountToDouble(creditAmountText);
        onlineAmount = Helperfunctions.formatStringAmountToDouble(onlineAmountText);
        cashAmount = Helperfunctions.formatStringAmountToDouble(cashAmountText);

        if (itemsWithReturns != null) {
          finalItems = itemsWithReturns;
          final double totalDelivered = itemsWithReturns.fold<double>(0.0, (acc, i) => acc + i.deliveredLineTotal);
          final double totalReturned = itemsWithReturns.fold<double>(0.0, (acc, i) => acc + i.returnedLineTotal);
          final bool hasReturns = itemsWithReturns.any((i) => i.returnedQuantity > 0);

          if (hasReturns) {
            finalOriginalOrderAmount = currentDelivery.originalOrderAmount ?? currentDelivery.orderAmount;
            finalOrderAmount = totalDelivered;
            returnAmount = totalReturned;
          } else {
            finalOrderAmount = currentDelivery.originalOrderAmount ?? Helperfunctions.formatStringAmountToDouble(orderAmountText);
            returnAmount = 0;
            finalOriginalOrderAmount = null;
          }
        } else {
          returnAmount = Helperfunctions.formatStringAmountToDouble(returnAmountText);
          finalOrderAmount = Helperfunctions.formatStringAmountToDouble(orderAmountText);
        }
        break;

      case DeliveryStatus.returned:
        finalOriginalOrderAmount = currentDelivery.originalOrderAmount ?? currentDelivery.orderAmount;
        finalOrderAmount = finalOriginalOrderAmount;
        returnAmount = finalOrderAmount;
        finalItems = currentDelivery.items.map((i) => i.copyWith(returnedQuantity: i.pickedQuantity)).toList();
        break;
      default:
    }

    // Returned Stock Tracking:
    // When an order is marked returned or has partial returns, and physical stock had already left the warehouse,
    // the returned goods are now incoming stock heading back to the warehouse.
    final returnedItems = finalItems.where((i) => i.returnedQuantity > 0).toList();
    bool markReturnIncoming = currentDelivery.isReturnIncoming;
    if (returnedItems.isNotEmpty && !currentDelivery.isReturnIncoming && currentDelivery.isInventoryDeducted) {
      await _inventoryService.addIncomingStockForReturn(
        storeName: storeName,
        returnedItems: returnedItems,
      );
      markReturnIncoming = true;
    }

    // Update image
    String imageFilePath = currentDelivery.imagePath;
    if (context.mounted) {
      imageFilePath = await Helperfunctions.updateImage(context, imageFile, networkImagePath, currentDelivery.imagePath);
    }

    final currentUserName = authService.value.currentUser?.displayName ?? 'Admin';

    final updatedDelivery = currentDelivery.copyWith(
      storeName: storeName,
      remarks: finalRemarks,
      transactionStatus: status,
      imagePath: imageFilePath,
      orderAmount: finalOrderAmount,
      originalOrderAmount: finalOriginalOrderAmount,
      returnAmount: returnAmount,
      creditAmount: creditAmount,
      cashAmount: cashAmount,
      onlineAmount: onlineAmount,
      items: finalItems,
      isReturnIncoming: markReturnIncoming,
      isReturnApprovedByDealer: false,
      deliveryDate: selectedDate != null ? Timestamp.fromDate(selectedDate) : currentDelivery.deliveryDate,
      createdBy: currentDelivery.createdBy,
      lastUpdatedBy: currentUserName,
      createdDate: currentDelivery.createdDate,
      lastupdatedDate: Timestamp.now(),
      createdPage: currentDelivery.createdPage,
      lastUpdatedPage: AppPages.delivery,
    );

    // Persist via Service
    await _deliveryService.updateDelivery(deliveryId, updatedDelivery);

    if (status == DeliveryStatus.delivered) {
      await reflectBestSellerPlacementsForDelivery(updatedDelivery);
    }

    if (placements != null && placements.isNotEmpty && updatedDelivery.deliveryDate != null) {
      final placedNames = placements.where((p) => p.isPlaced).map((p) => p.itemName).toList();
      final totalBestSellers = await SelectaProductService().getBestSellerProducts();
      final totalExpected = totalBestSellers.isNotEmpty ? totalBestSellers.length : placements.length;
      final isFinished = totalExpected > 0 && placedNames.length >= totalExpected;

      final placement = Placement(
        id: placementId ?? '',
        storeName: updatedDelivery.storeName,
        deliveryDate: updatedDelivery.deliveryDate!,
        placedProductNames: placedNames,
        cotc1: placements.isNotEmpty ? placements[0].isPlaced : false,
        cotc2: placements.length > 1 ? placements[1].isPlaced : false,
        cotc3: placements.length > 2 ? placements[2].isPlaced : false,
        cotc4: placements.length > 3 ? placements[3].isPlaced : false,
        cotc5: placements.length > 4 ? placements[4].isPlaced : false,
        cotc6: placements.length > 5 ? placements[5].isPlaced : false,
        cotc7: placements.length > 6 ? placements[6].isPlaced : false,
        cotc8: placements.length > 7 ? placements[7].isPlaced : false,
        cotc9: placements.length > 8 ? placements[8].isPlaced : false,
        cotc10: placements.length > 9 ? placements[9].isPlaced : false,
        cotc11: placements.length > 10 ? placements[10].isPlaced : false,
        cotc12: placements.length > 11 ? placements[11].isPlaced : false,
        isFinished: isFinished,
        progressCount: placedNames.length,
      );
      await _placementService.savePlacement(placement);
    }

    // Audit log
    await Helperfunctions.logUpdate(storeName, currentDelivery.toJson(), updatedDelivery.toJson(), page: AppPages.delivery);

    return updatedDelivery;
  }

  /// Automatically reflects any ordered Best Seller products in the store's monthly Placement record
  /// when a delivery has been successfully delivered.
  Future<void> reflectBestSellerPlacementsForDelivery(Delivery delivery) async {
    if (delivery.storeName.trim().isEmpty || delivery.deliveryDate == null) return;

    // 1. Identify all delivered products with positive quantities
    final Set<String> deliveredBestSellerNames = {};
    for (final item in delivery.items) {
      final effectiveQty = item.deliveredQuantity;
      if (effectiveQty > 0 && ProductTag.isBestSeller(item.tag)) {
        deliveredBestSellerNames.add(item.productName.trim());
      }
    }

    // Also match against active catalog Best Sellers (in case tag wasn't set on older OrderItem snapshots)
    final allBestSellers = await SelectaProductService().getBestSellerProducts();
    final bestSellerNameMap = {for (final p in allBestSellers) p.productName.trim().toLowerCase(): p.productName.trim()};

    for (final item in delivery.items) {
      final effectiveQty = item.deliveredQuantity;
      if (effectiveQty > 0) {
        final match = bestSellerNameMap[item.productName.trim().toLowerCase()];
        if (match != null) {
          deliveredBestSellerNames.add(match);
        }
      }
    }

    if (deliveredBestSellerNames.isEmpty) return;

    // 2. Fetch existing placement record for this store & month
    final deliveryDateTime = delivery.deliveryDate!.toDate();
    final existingPlacement = await _placementService.getPlacementByStoreAndDate(delivery.storeName, deliveryDateTime);

    final placement = existingPlacement ?? Placement.empty().copyWith(storeName: delivery.storeName, deliveryDate: delivery.deliveryDate!);

    // 3. Union existing placed product names with newly delivered Best Sellers
    final currentPlaced = Set<String>.from(placement.placedProductNames);
    currentPlaced.addAll(deliveredBestSellerNames);
    placement.placedProductNames = currentPlaced.toList();

    // Map to legacy cotc flags if any matching names exist
    final legacyList = KData.getListPlacement();
    final legacyMap = <String, bool>{};
    for (int i = 0; i < legacyList.length; i++) {
      final code = 'cotc${i + 1}';
      final match = placement.placedProductNames.any((pName) => pName.trim().toLowerCase() == legacyList[i].itemName.trim().toLowerCase());
      legacyMap[code] = match;
    }
    placement.cotc1 = legacyMap['cotc1'] ?? placement.cotc1;
    placement.cotc2 = legacyMap['cotc2'] ?? placement.cotc2;
    placement.cotc3 = legacyMap['cotc3'] ?? placement.cotc3;
    placement.cotc4 = legacyMap['cotc4'] ?? placement.cotc4;
    placement.cotc5 = legacyMap['cotc5'] ?? placement.cotc5;
    placement.cotc6 = legacyMap['cotc6'] ?? placement.cotc6;
    placement.cotc7 = legacyMap['cotc7'] ?? placement.cotc7;
    placement.cotc8 = legacyMap['cotc8'] ?? placement.cotc8;
    placement.cotc9 = legacyMap['cotc9'] ?? placement.cotc9;
    placement.cotc10 = legacyMap['cotc10'] ?? placement.cotc10;
    placement.cotc11 = legacyMap['cotc11'] ?? placement.cotc11;
    placement.cotc12 = legacyMap['cotc12'] ?? placement.cotc12;

    final totalBestSellerCount = allBestSellers.isNotEmpty ? allBestSellers.length : 12;
    placement.progressCount = placement.placedProductNames.length;
    placement.isFinished = totalBestSellerCount > 0 && placement.progressCount >= totalBestSellerCount;

    // 4. Persist to Firestore
    await _placementService.savePlacement(placement);
  }

  /// Deletes a delivery record, releases any floating reserved inventory if still in
  /// `Pending Picklist`, and removes its associated uploaded image from storage.
  Future<void> deleteDelivery({required BuildContext context, required String deliveryId, required Delivery delivery}) async {
    if (delivery.isReturnApprovedByDealer) {
      throw Exception('Cannot delete a delivery record that has already been approved by dealer.');
    }
    if (delivery.isInventorySettled) {
      throw Exception('Cannot delete a delivery record for a date that has already been verified and locked.');
    }
    if (delivery.isInventoryReserved && !delivery.isInventoryDeducted && delivery.items.isNotEmpty) {
      await _inventoryService.releaseReservedStockForOrder(storeName: delivery.storeName, items: delivery.items);
    }
    if (delivery.imagePath.isNotEmpty && context.mounted) {
      await Helperfunctions.deleteImage(context, delivery.imagePath);
    }
    await _deliveryService.deleteDelivery(deliveryId);

    await Helperfunctions.logDelete(delivery.storeName, delivery.toJson(), page: AppPages.delivery);
  }

  /// Voids a pending picklist order, releases its floating stock reservation,
  /// and stores the mandatory reason without deleting the document from Firestore.
  Future<void> voidDelivery({
    required BuildContext context,
    required String deliveryId,
    required Delivery delivery,
    required String reason,
  }) async {
    if (delivery.isReturnApprovedByDealer) {
      throw Exception('Cannot void an order that has already been approved by dealer.');
    }
    if (delivery.isInventorySettled) {
      throw Exception('Cannot void an order for a date that has already been verified and locked.');
    }
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw Exception('A reason is required to void this order.');
    }

    final currentUser = authService.value.currentUser?.displayName ?? 'Dealer';

    // Release floating stock reservation
    if (delivery.isInventoryReserved && !delivery.isInventoryDeducted && delivery.items.isNotEmpty) {
      await _inventoryService.releaseReservedStockForOrder(
        storeName: delivery.storeName,
        items: delivery.items,
      );
    }

    await _deliveryService.voidDelivery(
      deliveryID: deliveryId,
      reason: trimmedReason,
      voidedBy: currentUser,
    );

    await Helperfunctions.logTransaction(
      'Void Order - ${delivery.storeName}',
      'Voided picklist order. Reason: $trimmedReason',
      LogAction.update,
      page: AppPages.picklist,
    );
  }

  /// Settles inventory movements for an individual delivery that was completed after daily verification.
  Future<void> settleSingleDelivery(String deliveryId) async {
    await _inventoryService.settleSingleDelivery(deliveryId);
  }
}
