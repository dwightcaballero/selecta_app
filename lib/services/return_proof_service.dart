import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/return_proof.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/inventory_service.dart';

// ignore: constant_identifier_names
const String RETURN_PROOFS_COLLECTION_REF = 'return_proofs';

class ReturnProofService {
  final FirebaseFirestore _firestore;
  final DeliveryService _deliveryService;
  final InventoryService _inventoryService;
  late final CollectionReference<ReturnProof> _proofsRef;

  ReturnProofService({
    FirebaseFirestore? firestore,
    DeliveryService? deliveryService,
    InventoryService? inventoryService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _deliveryService = deliveryService ?? DeliveryService(),
        _inventoryService = inventoryService ?? InventoryService() {
    _proofsRef = _firestore
        .collection(RETURN_PROOFS_COLLECTION_REF)
        .withConverter<ReturnProof>(
          fromFirestore: (snapshot, _) => ReturnProof.fromSnapshot(snapshot),
          toFirestore: (proof, _) => proof.toJson(),
        );
  }

  /// Builds standardized day key for a date: YYYY-MM-DD
  static String buildDayKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Builds a deterministic document ID for a store and date
  static String buildDocId(String storeName, DateTime date) {
    final sanitizedStore = storeName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    return '${buildDayKey(date)}_$sanitizedStore';
  }

  /// Checks if a delivery has returns (either full return or item-level returns).
  /// Rescheduled or voided deliveries are excluded.
  static bool deliveryHasReturns(Delivery delivery) {
    if (delivery.isRescheduled || delivery.transactionStatus == DeliveryStatus.voided) {
      return false;
    }
    return delivery.transactionStatus == DeliveryStatus.returned ||
        delivery.isReturnIncoming ||
        delivery.hasReturnedItems ||
        delivery.returnAmount > 0;
  }

  /// Determines whether a delivery is subject to the Return Proof Gate.
  /// Backward compatible: returns false if [enabledFrom] is null or delivery date < enabledFrom.
  static bool isDeliverySubjectToGate(Delivery delivery, Timestamp? enabledFrom) {
    if (delivery.returnProofRequired) return true;
    if (enabledFrom == null) return false;

    final targetDate = delivery.deliveryDate ?? delivery.createdDate;
    return targetDate.compareTo(enabledFrom) >= 0;
  }

  /// Extracts return items snapshot from a delivery.
  static List<ReturnProofItem> extractReturnItemsFromDelivery(
    Delivery delivery,
    String deliveryId,
  ) {
    final items = <ReturnProofItem>[];
    final isFullReturn = delivery.transactionStatus == DeliveryStatus.returned;

    for (final item in delivery.items) {
      final retQty = item.returnedQuantity > 0
          ? item.returnedQuantity
          : (isFullReturn ? item.pickedQuantity : 0);

      if (retQty > 0) {
        items.add(ReturnProofItem(
          deliveryId: deliveryId,
          productId: item.productId,
          productName: item.productName,
          returnedQuantity: retQty,
          receivedQuantity: retQty,
          sellingPrice: item.sellingPrice,
          category: item.category,
          productSource: item.productSource,
        ));
      }
    }
    return items;
  }

  /// Retrieves the Return Proof document for a specific store and date.
  Future<ReturnProof?> getProofForStoreAndDate(String storeName, DateTime date) async {
    final docId = buildDocId(storeName, date);
    final doc = await _proofsRef.doc(docId).get();
    if (doc.exists && doc.data() != null) {
      return doc.data();
    }

    // Fallback query by storeName and dayKey
    final dayKey = buildDayKey(date);
    final query = await _proofsRef
        .where('storeName', isEqualTo: storeName.trim())
        .where('dayKey', isEqualTo: dayKey)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return query.docs.first.data();
    }
    return null;
  }

  /// Retrieves all Return Proof documents for a given date.
  Future<List<ReturnProof>> getProofsForDate(DateTime date) async {
    final dayKey = buildDayKey(date);
    final query = await _proofsRef.where('dayKey', isEqualTo: dayKey).get();
    return query.docs.map((d) => d.data()).toList();
  }

  /// Realtime stream of proofs for a given business date.
  Stream<List<ReturnProof>> getProofsByDateStream(DateTime date) {
    final dayKey = buildDayKey(date);
    return _proofsRef
        .where('dayKey', isEqualTo: dayKey)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  /// Realtime stream of pending return proofs awaiting warehouse confirmation.
  Stream<List<ReturnProof>> getPendingProofsStream() {
    return _proofsRef
        .where('status', isEqualTo: ReturnProofStatus.submitted)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => d.data()).toList();
      list.sort((a, b) {
        final dateA = a.submittedDate ?? a.createdAt;
        final dateB = b.submittedDate ?? b.createdAt;
        return dateB.compareTo(dateA);
      });
      return list;
    });
  }

  /// Submits proof of return for a store on a given date.
  /// Exactly 1 photo is required.
  Future<ReturnProof> submitProof({
    required String storeName,
    required DateTime date,
    required List<MapEntry<String, Delivery>> deliveriesWithIds,
    required String imageUrl,
    String notes = '',
    required String submittedBy,
  }) async {
    if (imageUrl.trim().isEmpty) {
      throw ArgumentError('Proof photo is required');
    }

    final dayKey = buildDayKey(date);
    final docId = buildDocId(storeName, date);
    final existingProof = await getProofForStoreAndDate(storeName, date);

    // Aggregate return items across all deliveries for this store
    final allItems = <ReturnProofItem>[];
    final deliveryIds = <String>[];

    for (final entry in deliveriesWithIds) {
      final dId = entry.key;
      final delivery = entry.value;
      deliveryIds.add(dId);
      allItems.addAll(extractReturnItemsFromDelivery(delivery, dId));
    }

    // Maintain versions/history if re-submitting after rejection
    final history = <ReturnProofHistory>[];
    if (existingProof != null) {
      history.addAll(existingProof.history);
      if (existingProof.imageUrl.isNotEmpty) {
        history.add(ReturnProofHistory(
          imageUrl: existingProof.imageUrl,
          notes: existingProof.notes,
          status: existingProof.status,
          actionBy: existingProof.submittedBy.isNotEmpty ? existingProof.submittedBy : submittedBy,
          actionDate: existingProof.submittedDate ?? Timestamp.now(),
          rejectReason: existingProof.rejectReason.isNotEmpty ? existingProof.rejectReason : null,
        ));
      }
    }

    final now = Timestamp.now();
    final newProof = ReturnProof(
      id: docId,
      storeName: storeName.trim(),
      proofDate: Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
      dayKey: dayKey,
      deliveryIds: deliveryIds,
      items: allItems,
      imageUrl: imageUrl.trim(),
      notes: notes.trim(),
      status: ReturnProofStatus.submitted,
      submittedBy: submittedBy.trim(),
      submittedDate: now,
      confirmedBy: '',
      confirmedDate: null,
      rejectReason: '',
      history: history,
      createdAt: existingProof?.createdAt ?? now,
      lastUpdatedDate: now,
    );

    // 1. Write the return_proofs document
    await _proofsRef.doc(docId).set(newProof);

    // 2. Mirror status and proof ID to each affected delivery
    for (final entry in deliveriesWithIds) {
      final dId = entry.key;
      final delivery = entry.value;
      final updatedDelivery = delivery.copyWith(
        returnProofId: docId,
        returnProofStatus: ReturnProofStatus.submitted,
        returnProofUrl: imageUrl.trim(),
        returnProofNotes: notes.trim(),
        returnProofSubmittedBy: submittedBy.trim(),
        returnProofSubmittedDate: now,
        returnProofRejectReason: '',
        lastUpdatedBy: submittedBy.trim(),
        lastupdatedDate: now,
        lastUpdatedPage: AppPages.breakdown,
      );
      await _deliveryService.updateDelivery(dId, updatedDelivery);
    }

    // 3. Log audit entry
    await Helperfunctions.logUpdate(
      '[RETURN PROOF SUBMITTED] $storeName ($dayKey)',
      existingProof?.toJson() ?? {},
      newProof.toJson(),
      page: AppPages.breakdown,
    );

    return newProof;
  }

  /// Warehouse/Dealer confirms receipt of return items.
  /// Supports recording received quantities (variance detection) and auto-restocking returns.
  Future<ReturnProof> confirmProof({
    required String proofId,
    required List<ReturnProofItem> receivedItems,
    required String confirmedBy,
    bool autoRestock = true,
  }) async {
    final doc = await _proofsRef.doc(proofId).get();
    if (!doc.exists || doc.data() == null) {
      throw Exception('Return proof record not found: $proofId');
    }

    final currentProof = doc.data()!;
    final now = Timestamp.now();

    final updatedProof = currentProof.copyWith(
      status: ReturnProofStatus.confirmed,
      confirmedBy: confirmedBy.trim(),
      confirmedDate: now,
      items: receivedItems,
      lastUpdatedDate: now,
    );

    // 1. Save updated proof
    await _proofsRef.doc(proofId).set(updatedProof);

    // 2. Mirror confirmation to associated deliveries
    for (final deliveryId in updatedProof.deliveryIds) {
      final delivery = await _deliveryService.getDeliveryById(deliveryId);
      if (delivery != null) {
        Delivery updatedDelivery = delivery.copyWith(
          returnProofStatus: ReturnProofStatus.confirmed,
          returnProofConfirmedBy: confirmedBy.trim(),
          returnProofConfirmedDate: now,
          lastUpdatedBy: confirmedBy.trim(),
          lastupdatedDate: now,
          lastUpdatedPage: AppPages.returnReceiving,
        );

        // Auto-restock if not already approved by dealer
        if (autoRestock && !delivery.isReturnApprovedByDealer) {
          try {
            await _inventoryService.approveReturnAndReplenishStock(
              delivery: delivery,
              deliveryId: deliveryId,
              disposition: ReturnDisposition.restock,
              dispositionNotes: 'Auto-restocked via Return Proof confirmation ($proofId)',
            );
            updatedDelivery = updatedDelivery.copyWith(
              isReturnApprovedByDealer: true,
              returnApprovedBy: confirmedBy.trim(),
              returnApprovedDate: now,
              isReturnIncoming: false,
            );
          } catch (_) {
            // If inventory restock fails or is already partially handled, still save delivery mirror
          }
        }

        await _deliveryService.updateDelivery(deliveryId, updatedDelivery);
      }
    }

    // 3. Log audit entry
    await Helperfunctions.logUpdate(
      '[RETURN PROOF CONFIRMED] ${currentProof.storeName}',
      currentProof.toJson(),
      updatedProof.toJson(),
      page: AppPages.returnReceiving,
    );

    return updatedProof;
  }

  /// Warehouse/Dealer rejects return proof with a required reason.
  Future<ReturnProof> rejectProof({
    required String proofId,
    required String rejectReason,
    required String rejectedBy,
  }) async {
    if (rejectReason.trim().isEmpty) {
      throw ArgumentError('Rejection reason is required');
    }

    final doc = await _proofsRef.doc(proofId).get();
    if (!doc.exists || doc.data() == null) {
      throw Exception('Return proof record not found: $proofId');
    }

    final currentProof = doc.data()!;
    final now = Timestamp.now();

    final history = List<ReturnProofHistory>.from(currentProof.history);
    history.add(ReturnProofHistory(
      imageUrl: currentProof.imageUrl,
      notes: currentProof.notes,
      status: ReturnProofStatus.rejected,
      actionBy: rejectedBy.trim(),
      actionDate: now,
      rejectReason: rejectReason.trim(),
    ));

    final updatedProof = currentProof.copyWith(
      status: ReturnProofStatus.rejected,
      rejectReason: rejectReason.trim(),
      history: history,
      lastUpdatedDate: now,
    );

    // 1. Save updated proof
    await _proofsRef.doc(proofId).set(updatedProof);

    // 2. Mirror rejection to associated deliveries
    for (final deliveryId in updatedProof.deliveryIds) {
      final delivery = await _deliveryService.getDeliveryById(deliveryId);
      if (delivery != null) {
        final updatedDelivery = delivery.copyWith(
          returnProofStatus: ReturnProofStatus.rejected,
          returnProofRejectReason: rejectReason.trim(),
          lastUpdatedBy: rejectedBy.trim(),
          lastupdatedDate: now,
          lastUpdatedPage: AppPages.returnReceiving,
        );
        await _deliveryService.updateDelivery(deliveryId, updatedDelivery);
      }
    }

    // 3. Log audit entry
    await Helperfunctions.logUpdate(
      '[RETURN PROOF REJECTED] ${currentProof.storeName} - $rejectReason',
      currentProof.toJson(),
      updatedProof.toJson(),
      page: AppPages.returnReceiving,
    );

    return updatedProof;
  }

  /// Dealer emergency override: unlocks the gate for this store with a logged reason.
  Future<ReturnProof> overrideProof({
    required String proofId,
    required String overrideReason,
    required String overriddenBy,
  }) async {
    if (overrideReason.trim().isEmpty) {
      throw ArgumentError('Override reason is required');
    }

    final doc = await _proofsRef.doc(proofId).get();
    if (!doc.exists || doc.data() == null) {
      throw Exception('Return proof record not found: $proofId');
    }

    final currentProof = doc.data()!;
    final now = Timestamp.now();

    final history = List<ReturnProofHistory>.from(currentProof.history);
    history.add(ReturnProofHistory(
      imageUrl: currentProof.imageUrl,
      notes: 'Overridden by dealer: $overrideReason',
      status: ReturnProofStatus.overridden,
      actionBy: overriddenBy.trim(),
      actionDate: now,
      rejectReason: overrideReason.trim(),
    ));

    final updatedProof = currentProof.copyWith(
      status: ReturnProofStatus.overridden,
      overrideBy: overriddenBy.trim(),
      overrideDate: now,
      overrideReason: overrideReason.trim(),
      history: history,
      lastUpdatedDate: now,
    );

    // 1. Save updated proof
    await _proofsRef.doc(proofId).set(updatedProof);

    // 2. Mirror override to associated deliveries
    for (final deliveryId in updatedProof.deliveryIds) {
      final delivery = await _deliveryService.getDeliveryById(deliveryId);
      if (delivery != null) {
        final updatedDelivery = delivery.copyWith(
          returnProofStatus: ReturnProofStatus.overridden,
          lastUpdatedBy: overriddenBy.trim(),
          lastupdatedDate: now,
          lastUpdatedPage: AppPages.returnReceiving,
        );
        await _deliveryService.updateDelivery(deliveryId, updatedDelivery);
      }
    }

    // 3. Log audit entry
    await Helperfunctions.logUpdate(
      '[RETURN PROOF OVERRIDDEN] ${currentProof.storeName} - $overrideReason',
      currentProof.toJson(),
      updatedProof.toJson(),
      page: AppPages.returnReceiving,
    );

    return updatedProof;
  }

  /// Checks if returned items or quantities on deliveries have changed since the proof snapshot.
  /// If changed, invalidates the proof back to 'none' or requires re-submission.
  Future<bool> checkAndInvalidateIfReturnsChanged({
    required ReturnProof proof,
    required List<MapEntry<String, Delivery>> deliveriesWithIds,
  }) async {
    final currentItems = <ReturnProofItem>[];
    for (final entry in deliveriesWithIds) {
      currentItems.addAll(extractReturnItemsFromDelivery(entry.value, entry.key));
    }

    // Compare product counts and quantities
    bool hasChanged = currentItems.length != proof.items.length;
    if (!hasChanged) {
      for (final item in currentItems) {
        final matched = proof.items.where((p) =>
            p.deliveryId == item.deliveryId && p.productId == item.productId);
        if (matched.isEmpty || matched.first.returnedQuantity != item.returnedQuantity) {
          hasChanged = true;
          break;
        }
      }
    }

    if (hasChanged && proof.status != ReturnProofStatus.none) {
      final now = Timestamp.now();
      final invalidated = proof.copyWith(
        status: ReturnProofStatus.none,
        items: currentItems,
        notes: '${proof.notes} (Invalidated: return quantities changed)',
        lastUpdatedDate: now,
      );
      await _proofsRef.doc(proof.id).set(invalidated);

      for (final entry in deliveriesWithIds) {
        final delivery = entry.value;
        final updated = delivery.copyWith(
          returnProofStatus: ReturnProofStatus.none,
          lastUpdatedBy: 'System',
          lastupdatedDate: now,
        );
        await _deliveryService.updateDelivery(entry.key, updated);
      }
      return true;
    }
    return false;
  }
}
