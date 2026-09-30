import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

    final user = FirebaseAuth.instance.currentUser;
    final createdBy = (user?.displayName?.trim().isNotEmpty == true)
        ? user!.displayName!.trim()
        : (user?.email ?? 'Dealer');

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
