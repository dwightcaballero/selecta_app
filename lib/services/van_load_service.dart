import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/van_load.dart';

// ignore: constant_identifier_names
const String VAN_LOAD_COLLECTION_REF = 'van_loads';

class VanLoadService {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference<VanLoad> _vanLoadsRef;

  VanLoadService() {
    _vanLoadsRef = _firestore
        .collection(VAN_LOAD_COLLECTION_REF)
        .withConverter<VanLoad>(
          fromFirestore: (snapshot, _) => VanLoad.fromJson(snapshot.data()!, snapshot.id),
          toFirestore: (vanLoad, _) => vanLoad.toJson(),
        );
  }

  /// Create a new van load manifest. Returns the new document ID.
  Future<String> addVanLoad(VanLoad vanLoad) async {
    final docRef = await _vanLoadsRef.add(vanLoad);
    return docRef.id;
  }

  /// Update an existing van load.
  Future<void> updateVanLoad(String id, VanLoad vanLoad) async {
    await _vanLoadsRef.doc(id).set(vanLoad, SetOptions(merge: true));
  }

  /// Update specific fields of a van load.
  Future<void> updateVanLoadFields(String id, Map<String, dynamic> data) async {
    await _firestore.collection(VAN_LOAD_COLLECTION_REF).doc(id).update(data);
  }

  /// Get a single van load by document ID.
  Future<VanLoad?> getVanLoad(String id) async {
    final snap = await _vanLoadsRef.doc(id).get();
    return snap.data();
  }

  /// Delete a draft van load (only allowed if not yet deducted).
  Future<void> deleteVanLoad(String id) async {
    await _vanLoadsRef.doc(id).delete();
  }

  /// Stream all van loads sorted by created date descending.
  Stream<List<VanLoad>> streamVanLoads({int limit = 50}) {
    return _vanLoadsRef
        .orderBy('createdDate', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  /// Stream the currently active van load (loaded or in-route).
  Stream<VanLoad?> streamActiveVanLoad() {
    return _vanLoadsRef
        .where('status', whereIn: [VanLoadStatus.loaded, VanLoadStatus.inRoute])
        .orderBy('createdDate', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isNotEmpty ? snap.docs.first.data() : null);
  }

  /// Fetch the current active van load once.
  Future<VanLoad?> getActiveVanLoad() async {
    final snap = await _vanLoadsRef
        .where('status', whereIn: [VanLoadStatus.loaded, VanLoadStatus.inRoute])
        .orderBy('createdDate', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      return snap.docs.first.data();
    }
    return null;
  }

  /// Atomically increments `soldQuantity` on matching items in the van load when a sale occurs.
  Future<void> recordVanSale({
    required String vanLoadId,
    required List<OrderItem> soldItems,
  }) async {
    final vanLoadRef = _firestore.collection(VAN_LOAD_COLLECTION_REF).doc(vanLoadId);

    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(vanLoadRef);
      if (!snap.exists) {
        throw Exception('VanLoad document $vanLoadId does not exist');
      }

      final vanLoad = VanLoad.fromJson(snap.data()!, snap.id);

      // Create a map of productId -> sold quantity for this delivery
      final Map<String, int> saleQtyMap = {};
      for (final item in soldItems) {
        saleQtyMap[item.productId] = (saleQtyMap[item.productId] ?? 0) + item.pickedQuantity;
      }

      // Update matching items in van load
      final updatedItems = vanLoad.items.map((vanItem) {
        final soldInThisSale = saleQtyMap[vanItem.productId] ?? 0;
        if (soldInThisSale > 0) {
          final newSoldQty = vanItem.soldQuantity + soldInThisSale;
          return vanItem.copyWith(soldQuantity: newSoldQty);
        }
        return vanItem;
      }).toList();

      final newTotalSoldAmount = updatedItems.fold<double>(0.0, (acc, item) => acc + item.lineTotalSold);

      transaction.update(vanLoadRef, {
        'items': updatedItems.map((e) => e.toJson()).toList(),
        'totalSoldAmount': newTotalSoldAmount,
        'status': VanLoadStatus.inRoute, // Move to in-route if was loaded
        'lastUpdatedDate': Timestamp.now(),
      });
    });
  }

  /// Reverses a van sale (e.g., if a van sell delivery is voided).
  Future<void> reverseVanSale({
    required String vanLoadId,
    required List<OrderItem> voidedItems,
  }) async {
    final vanLoadRef = _firestore.collection(VAN_LOAD_COLLECTION_REF).doc(vanLoadId);

    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(vanLoadRef);
      if (!snap.exists) return;

      final vanLoad = VanLoad.fromJson(snap.data()!, snap.id);

      final Map<String, int> reverseQtyMap = {};
      for (final item in voidedItems) {
        reverseQtyMap[item.productId] = (reverseQtyMap[item.productId] ?? 0) + item.pickedQuantity;
      }

      final updatedItems = vanLoad.items.map((vanItem) {
        final reverseQty = reverseQtyMap[vanItem.productId] ?? 0;
        if (reverseQty > 0) {
          final newSoldQty = (vanItem.soldQuantity - reverseQty).clamp(0, vanItem.loadedQuantity);
          return vanItem.copyWith(soldQuantity: newSoldQty);
        }
        return vanItem;
      }).toList();

      final newTotalSoldAmount = updatedItems.fold<double>(0.0, (acc, item) => acc + item.lineTotalSold);

      transaction.update(vanLoadRef, {
        'items': updatedItems.map((e) => e.toJson()).toList(),
        'totalSoldAmount': newTotalSoldAmount,
        'lastUpdatedDate': Timestamp.now(),
      });
    });
  }

  /// Get the van load manifest for a specific calendar date (if any exists).
  Future<VanLoad?> getVanLoadForDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);
    final snap = await _vanLoadsRef
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .orderBy('date', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      return snap.docs.first.data();
    }
    return null;
  }
}
