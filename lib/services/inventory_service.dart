import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/models/inventory_movement.dart';
import 'package:flutter_app/models/other_product.dart';
import 'package:flutter_app/models/selecta_product.dart';
import 'package:flutter_app/services/other_product_service.dart';
import 'package:flutter_app/services/selecta_product_service.dart';

// ignore: constant_identifier_names
const String INVENTORY_MOVEMENTS_COLLECTION_REF = 'inventory_movements';

/// Service that manages stock levels across both [SelectaProduct] (`selecta_products`)
/// and [OtherProduct] (`other_products`), as well as stock movement audit logs (`inventory_movements`).
class InventoryService {
  final _firestore = FirebaseFirestore.instance;

  /// Combines real-time streams of active [SelectaProduct] and active [OtherProduct]
  /// into a single unified stream of [InventoryItem]s sorted alphabetically by product name.
  Stream<List<InventoryItem>> getActiveInventoryStream() {
    late StreamController<List<InventoryItem>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? selectaSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? otherSub;

    List<InventoryItem> selectaItems = [];
    List<InventoryItem> otherItems = [];
    bool selectaLoaded = false;
    bool otherLoaded = false;

    void emitCombined() {
      if (!selectaLoaded || !otherLoaded) return;
      if (controller.isClosed) return;
      final combined = <InventoryItem>[
        ...selectaItems,
        ...otherItems,
      ]..sort((a, b) => a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));
      controller.add(combined);
    }

    controller = StreamController<List<InventoryItem>>.broadcast(
      onListen: () {
        selectaSub = _firestore
            .collection(SELECTA_PRODUCTS_COLLECTION_REF)
            .snapshots()
            .listen(
          (snap) {
            selectaItems = snap.docs
                .map((doc) => SelectaProduct.fromSnapshot(doc))
                .where((p) => p.isActive && p.productName.isNotEmpty)
                .map(InventoryItem.fromSelectaProduct)
                .toList();
            selectaLoaded = true;
            emitCombined();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          },
        );

        otherSub = _firestore
            .collection(OTHER_PRODUCTS_COLLECTION_REF)
            .snapshots()
            .listen(
          (snap) {
            otherItems = snap.docs
                .map((doc) => (id: doc.id, product: OtherProduct.fromSnapshot(doc)))
                .where((entry) => entry.product.isActive && entry.product.productName.isNotEmpty)
                .map((entry) => InventoryItem.fromOtherProduct(entry.id, entry.product))
                .toList();
            otherLoaded = true;
            emitCombined();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          },
        );
      },
      onCancel: () async {
        await selectaSub?.cancel();
        await otherSub?.cancel();
      },
    );

    return controller.stream;
  }

  String _collectionForSource(String productSource) {
    return productSource == 'other'
        ? OTHER_PRODUCTS_COLLECTION_REF
        : SELECTA_PRODUCTS_COLLECTION_REF;
  }

  String _currentActorName() {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.displayName?.trim().isNotEmpty == true) {
      return user!.displayName!.trim();
    }
    return user?.email ?? 'Dealer';
  }

  /// Temporarily reserves floating stock (`reservedQuantity`) when a new order is booked
  /// (`Pending Picklist`), preventing over-ordering before the picklist is completed.
  Future<void> reserveStockForOrder({
    required String storeName,
    required List<OrderItem> items,
  }) async {
    if (items.isEmpty) return;
    final now = Timestamp.now();
    final batch = _firestore.batch();

    for (final item in items) {
      if (item.productId.isEmpty || item.pickedQuantity <= 0) continue;
      final collectionName = _collectionForSource(item.productSource);
      final productRef = _firestore.collection(collectionName).doc(item.productId);
      final snap = await productRef.get();
      if (!snap.exists) continue;
      final data = snap.data() ?? {};
      final currentReserved = (data['reservedQuantity'] as num?)?.toInt() ?? 0;
      final newReserved = currentReserved + item.pickedQuantity;

      batch.update(productRef, {
        'reservedQuantity': newReserved < 0 ? 0 : newReserved,
        'updatedAt': now,
      });
    }

    await batch.commit();
  }

  /// Adjusts floating stock (`reservedQuantity`) when an order in `Pending Picklist`
  /// has its quantities or items updated prior to picklist completion.
  Future<void> adjustReservedStockForOrderUpdate({
    required String storeName,
    required List<OrderItem> oldItems,
    required List<OrderItem> newItems,
  }) async {
    final Map<String, ({String source, int delta})> deltas = {};

    for (final oldItem in oldItems) {
      if (oldItem.productId.isEmpty) continue;
      final key = '${oldItem.productSource}:${oldItem.productId}';
      final prev = deltas[key];
      deltas[key] = (
        source: oldItem.productSource,
        delta: (prev?.delta ?? 0) - oldItem.pickedQuantity,
      );
    }

    for (final newItem in newItems) {
      if (newItem.productId.isEmpty) continue;
      final key = '${newItem.productSource}:${newItem.productId}';
      final prev = deltas[key];
      deltas[key] = (
        source: newItem.productSource,
        delta: (prev?.delta ?? 0) + newItem.pickedQuantity,
      );
    }

    final now = Timestamp.now();
    final batch = _firestore.batch();
    bool hasChanges = false;

    for (final entry in deltas.entries) {
      if (entry.value.delta == 0) continue;
      final parts = entry.key.split(':');
      if (parts.length < 2) continue;
      final productId = parts.sublist(1).join(':');
      final collectionName = _collectionForSource(entry.value.source);
      final productRef = _firestore.collection(collectionName).doc(productId);
      final snap = await productRef.get();
      if (!snap.exists) continue;
      final data = snap.data() ?? {};
      final currentReserved = (data['reservedQuantity'] as num?)?.toInt() ?? 0;
      final nextReserved = (currentReserved + entry.value.delta);

      batch.update(productRef, {
        'reservedQuantity': nextReserved < 0 ? 0 : nextReserved,
        'updatedAt': now,
      });
      hasChanges = true;
    }

    if (hasChanges) {
      await batch.commit();
    }
  }

  /// Releases floating stock (`reservedQuantity`) when a `Pending Picklist` order is deleted/cancelled.
  Future<void> releaseReservedStockForOrder({
    required String storeName,
    required List<OrderItem> items,
  }) async {
    if (items.isEmpty) return;
    final now = Timestamp.now();
    final batch = _firestore.batch();
    bool hasChanges = false;

    for (final item in items) {
      if (item.productId.isEmpty || item.pickedQuantity <= 0) continue;
      final collectionName = _collectionForSource(item.productSource);
      final productRef = _firestore.collection(collectionName).doc(item.productId);
      final snap = await productRef.get();
      if (!snap.exists) continue;
      final data = snap.data() ?? {};
      final currentReserved = (data['reservedQuantity'] as num?)?.toInt() ?? 0;
      final nextReserved = currentReserved - item.pickedQuantity;

      batch.update(productRef, {
        'reservedQuantity': nextReserved < 0 ? 0 : nextReserved,
        'updatedAt': now,
      });
      hasChanges = true;
    }

    if (hasChanges) {
      await batch.commit();
    }
  }

  /// Permanently deducts picked quantities from physical `stockQuantity` and releases
  /// floating `reservedQuantity` when a Picklist is completed and marked For Delivery.
  /// Also records an [InventoryMovement] audit entry for each deducted item.
  Future<void> confirmPicklistAndDeductStock({
    required String storeName,
    required List<OrderItem> reservedItems,
    required List<OrderItem> pickedItems,
    required bool wasReserved,
  }) async {
    final now = Timestamp.now();
    final createdBy = _currentActorName();
    final batch = _firestore.batch();

    // Map reserved quantities by key so we release exact reserved amounts even if items were edited
    final Map<String, ({String source, String id, String name, int reservedQty, int pickedQty})> merged = {};

    if (wasReserved) {
      for (final r in reservedItems) {
        if (r.productId.isEmpty) continue;
        final key = '${r.productSource}:${r.productId}';
        final existing = merged[key];
        merged[key] = (
          source: r.productSource,
          id: r.productId,
          name: r.productName,
          reservedQty: (existing?.reservedQty ?? 0) + r.pickedQuantity,
          pickedQty: existing?.pickedQty ?? 0,
        );
      }
    }

    for (final p in pickedItems) {
      if (p.productId.isEmpty) continue;
      final key = '${p.productSource}:${p.productId}';
      final existing = merged[key];
      merged[key] = (
        source: p.productSource,
        id: p.productId,
        name: p.productName,
        reservedQty: existing?.reservedQty ?? 0,
        pickedQty: (existing?.pickedQty ?? 0) + p.pickedQuantity,
      );
    }

    for (final item in merged.values) {
      final collectionName = _collectionForSource(item.source);
      final productRef = _firestore.collection(collectionName).doc(item.id);
      final snap = await productRef.get();
      if (!snap.exists) continue;
      final data = snap.data() ?? {};

      final currentStock = (data['stockQuantity'] as num?)?.toInt() ?? 0;
      final currentReserved = (data['reservedQuantity'] as num?)?.toInt() ?? 0;

      final nextStock = (currentStock - item.pickedQty) < 0 ? 0 : (currentStock - item.pickedQty);
      final nextReserved = (currentReserved - item.reservedQty) < 0 ? 0 : (currentReserved - item.reservedQty);
      final delta = nextStock - currentStock;

      batch.update(productRef, {
        'stockQuantity': nextStock,
        'reservedQuantity': nextReserved,
        'updatedAt': now,
      });

      if (item.pickedQty > 0) {
        final movementRef = _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc();
        final movement = InventoryMovement(
          id: movementRef.id,
          productId: item.id,
          productName: item.name,
          productSource: item.source,
          previousStock: currentStock,
          newStock: nextStock,
          delta: delta != 0 ? delta : -item.pickedQty,
          reason: 'Picklist Completed (For Delivery)',
          notes: 'Store: $storeName (Picked: ${item.pickedQty})',
          createdBy: createdBy,
          createdAt: now,
        );
        batch.set(movementRef, movement.toJson());
      }
    }

    await batch.commit();
  }

  /// Updates the stock quantity (and optionally lowStockThreshold) of a product
  /// and records an [InventoryMovement] entry in `inventory_movements`.
  Future<void> updateStock({
    required InventoryItem item,
    required int newStockQuantity,
    int? newLowStockThreshold,
    required String reason,
    String notes = '',
  }) async {
    final clampedNewStock = newStockQuantity < 0 ? 0 : newStockQuantity;
    final threshold = (newLowStockThreshold ?? item.lowStockThreshold) < 0
        ? 0
        : (newLowStockThreshold ?? item.lowStockThreshold);
    final delta = clampedNewStock - item.stockQuantity;
    final now = Timestamp.now();

    final collectionName = item.source == InventoryProductSource.selecta
        ? SELECTA_PRODUCTS_COLLECTION_REF
        : OTHER_PRODUCTS_COLLECTION_REF;

    final createdBy = _currentActorName();

    final batch = _firestore.batch();
    final productRef = _firestore.collection(collectionName).doc(item.id);

    batch.update(productRef, {
      'stockQuantity': clampedNewStock,
      'lowStockThreshold': threshold,
      'updatedAt': now,
    });

    if (delta != 0) {
      final movementRef = _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc();
      final movement = InventoryMovement(
        id: movementRef.id,
        productId: item.id,
        productName: item.productName,
        productSource: item.source.key,
        previousStock: item.stockQuantity,
        newStock: clampedNewStock,
        delta: delta,
        reason: reason.trim().isEmpty ? 'Manual Adjustment' : reason.trim(),
        notes: notes.trim(),
        createdBy: createdBy,
        createdAt: now,
      );
      batch.set(movementRef, movement.toJson());
    }

    await batch.commit();
  }

  /// Streams recent inventory movements ordered by newest first.
  Stream<List<InventoryMovement>> getRecentMovementsStream({int limit = 50}) {
    return _firestore
        .collection(INVENTORY_MOVEMENTS_COLLECTION_REF)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(InventoryMovement.fromSnapshot).toList());
  }

  /// Streams recent inventory movements for a specific product.
  Stream<List<InventoryMovement>> getProductMovementsStream(String productId, {int limit = 25}) {
    return _firestore
        .collection(INVENTORY_MOVEMENTS_COLLECTION_REF)
        .where('productId', isEqualTo: productId)
        .limit(limit)
        .snapshots()
        .map((snap) {
          final list = snap.docs.map(InventoryMovement.fromSnapshot).toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }
}
