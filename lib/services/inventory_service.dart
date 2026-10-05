import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/admin_selecta_product.dart';
import 'package:selecta_ops/models/breakdown.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/other_product.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/services/breakdown_service.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/other_product_service.dart';
import 'package:selecta_ops/services/purchaseorder_service.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:intl/intl.dart';

// ignore: constant_identifier_names
const String INVENTORY_MOVEMENTS_COLLECTION_REF = 'inventory_movements';

/// Service that manages stock levels across both [SelectaProduct] (`selecta_products`)
/// and [OtherProduct] (`other_products`), as well as stock movement audit logs (`inventory_movements`).
class InventoryService {
  final _firestore = FirebaseFirestore.instance;

  /// Combines real-time streams of active [SelectaProduct] and active [OtherProduct]
  /// into a single unified stream of [InventoryItem]s sorted alphabetically by product name.
  /// Seamlessly resolves tags from `admin_selecta_products` if empty on local product records,
  /// and surfaces any newly added Admin products even before manual sync.
  Stream<List<InventoryItem>> getActiveInventoryStream() {
    late StreamController<List<InventoryItem>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? selectaSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? adminSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? otherSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? poSub;

    List<InventoryItem> selectaItems = [];
    List<InventoryItem> otherItems = [];
    Map<String, String> adminTagMap = {};
    Map<String, String> adminTagByName = {};
    List<AdminSelectaProduct> adminProducts = [];
    Map<String, int> pendingIncomingById = {};
    Map<String, int> pendingIncomingByName = {};
    Set<String> allLocalSelectaIds = {};
    Set<String> allLocalSelectaNames = {};
    bool selectaLoaded = false;
    bool otherLoaded = false;
    bool poLoaded = false;

    void emitCombined() {
      if (!selectaLoaded || !otherLoaded || !poLoaded) return;
      if (controller.isClosed) return;

      final resolvedSelecta = selectaItems.map((item) {
        final nameKey = item.productName.trim().toLowerCase();

        final liveIncoming = pendingIncomingById[item.id] ?? pendingIncomingByName[nameKey] ?? 0;
        final effectiveIncoming = liveIncoming > 0 ? liveIncoming : item.incomingQuantity;
        var current = item.copyWith(incomingQuantity: effectiveIncoming);

        if (current.tag.isNotEmpty) return current;
        final fallbackTag = adminTagMap[item.id] ?? adminTagByName[nameKey] ?? '';
        if (fallbackTag.isNotEmpty) {
          return current.copyWith(tag: fallbackTag);
        }
        return current;
      }).toList();

      // Include newly added Admin products that are not yet in dealer's local selecta_products
      for (final adminProd in adminProducts) {
        final nameKey = adminProd.productName.trim().toLowerCase();
        if (adminProd.productName.isNotEmpty &&
            !allLocalSelectaIds.contains(adminProd.id) &&
            !allLocalSelectaNames.contains(nameKey)) {
          final liveIncoming = pendingIncomingById[adminProd.id] ?? pendingIncomingByName[nameKey] ?? 0;
          resolvedSelecta.add(
            InventoryItem(
              id: adminProd.id,
              productName: adminProd.productName,
              imageUrl: adminProd.imageUrl,
              buyingPrice: adminProd.buyingPrice,
              sellingPrice: adminProd.sellingPrice,
              isActive: true,
              stockQuantity: 0,
              incomingQuantity: liveIncoming,
              reservedQuantity: 0,
              lowStockThreshold: 10,
              source: InventoryProductSource.selecta,
              category: adminProd.category,
              tag: adminProd.tag,
              updatedAt: adminProd.updatedAt,
            ),
          );
        }
      }

      final combined = <InventoryItem>[
        ...resolvedSelecta,
        ...otherItems,
      ].where((item) => item.isActive).toList()
        ..sort((a, b) => a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));
      controller.add(combined);
    }

    controller = StreamController<List<InventoryItem>>.broadcast(
      onListen: () {
        selectaSub = _firestore
            .collection(SELECTA_PRODUCTS_COLLECTION_REF)
            .snapshots()
            .listen(
          (snap) {
            allLocalSelectaIds = snap.docs.map((d) => d.id).toSet();
            allLocalSelectaNames = snap.docs
                .map((d) => (d.data()['productName'] as String? ?? '').trim().toLowerCase())
                .where((name) => name.isNotEmpty)
                .toSet();

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

        adminSub = _firestore
            .collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF)
            .snapshots()
            .listen(
          (snap) {
            adminProducts = snap.docs
                .map((doc) => AdminSelectaProduct.fromSnapshot(doc))
                .where((p) => p.productName.isNotEmpty)
                .toList();
            adminTagMap = {
              for (final p in adminProducts)
                if (p.tag.isNotEmpty) p.id: p.tag,
            };
            adminTagByName = {
              for (final p in adminProducts)
                if (p.tag.isNotEmpty) p.productName.trim().toLowerCase(): p.tag,
            };
            emitCombined();
          },
          onError: (Object _, StackTrace _) {
            // Non-critical fallback; dealer can continue with local selecta products
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

        poSub = _firestore
            .collection(PURCHASEORDER_COLLECTION_REF)
            .snapshots()
            .listen(
          (snap) {
            final Map<String, int> byId = {};
            final Map<String, int> byName = {};

            for (final doc in snap.docs) {
              final data = doc.data();
              final isReplenished = data['isInventoryReplenished'] as bool? ?? false;
              final status = (data['status'] as String? ?? 'pending').toLowerCase();
              final hasInvoice = (data['invoiceNumber'] as String? ?? '').trim().isNotEmpty &&
                  ((data['invoiceAmount'] as num?)?.toDouble() ?? 0.0) > 0;

              // Consider pending if not marked replenished AND (status is pending OR no confirmed invoice yet)
              if (!isReplenished && (status == 'pending' || !hasInvoice)) {
                final itemsList = data['items'] as List<dynamic>? ?? [];
                for (final raw in itemsList) {
                  if (raw is Map) {
                    final pid = (raw['productId'] as String? ?? '').trim();
                    final pName = (raw['productName'] as String? ?? '').trim().toLowerCase();
                    final qty = (raw['pickedQuantity'] as num?)?.toInt() ??
                        ((raw['orderedQuantity'] as num?)?.toInt() ?? 0);
                    if (qty > 0) {
                      if (pid.isNotEmpty) {
                        byId[pid] = (byId[pid] ?? 0) + qty;
                      }
                      if (pName.isNotEmpty) {
                        byName[pName] = (byName[pName] ?? 0) + qty;
                      }
                    }
                  }
                }
              }
            }

            pendingIncomingById = byId;
            pendingIncomingByName = byName;
            poLoaded = true;
            emitCombined();
          },
          onError: (Object _, StackTrace _) {
            poLoaded = true;
            emitCombined();
          },
        );
      },
      onCancel: () async {
        await selectaSub?.cancel();
        await adminSub?.cancel();
        await otherSub?.cancel();
        await poSub?.cancel();
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

  /// Replenishes inventory stock for items received in a Purchase Order.
  /// Increments `stockQuantity` and logs an [InventoryMovement] audit entry for each product.
  Future<void> replenishStockForPurchaseOrder({
    required String invoiceNumber,
    required DateTime orderDate,
    required List<OrderItem> items,
  }) async {
    if (items.isEmpty) return;
    final now = Timestamp.now();
    final createdBy = _currentActorName();
    final batch = _firestore.batch();
    final invoiceRef = invoiceNumber.trim().isNotEmpty
        ? invoiceNumber.trim()
        : 'PO-${DateFormat('yyyyMMdd').format(orderDate)}';

    for (final item in items) {
      final qty = item.effectiveQuantity;
      if (item.productId.isEmpty || qty <= 0) continue;
      final collectionName = _collectionForSource(item.productSource);
      final productRef = _firestore.collection(collectionName).doc(item.productId);
      final snap = await productRef.get();
      if (!snap.exists) continue;
      final data = snap.data() ?? {};

      final currentStock = (data['stockQuantity'] as num?)?.toInt() ?? 0;
      final nextStock = currentStock + qty;

      batch.update(productRef, {
        'stockQuantity': nextStock,
        'updatedAt': now,
      });

      final movementRef = _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc();
      final movement = InventoryMovement(
        id: movementRef.id,
        productId: item.productId,
        productName: item.productName,
        productSource: item.productSource,
        previousStock: currentStock,
        newStock: nextStock,
        delta: qty,
        reason: 'Purchase Order Replenishment',
        notes: 'PO Ref: $invoiceRef',
        createdBy: createdBy,
        createdAt: now,
      );
      batch.set(movementRef, movement.toJson());
    }

    await batch.commit();
  }

  /// Adjusts stock when an already-replenished Purchase Order is edited.
  Future<void> adjustReplenishedStockForPurchaseOrder({
    required String invoiceNumber,
    required DateTime orderDate,
    required List<OrderItem> oldItems,
    required List<OrderItem> newItems,
  }) async {
    final now = Timestamp.now();
    final createdBy = _currentActorName();
    final batch = _firestore.batch();
    final invoiceRef = invoiceNumber.trim().isNotEmpty
        ? invoiceNumber.trim()
        : 'PO-${DateFormat('yyyyMMdd').format(orderDate)}';

    final Map<String, int> oldQtyByKey = {
      for (final item in oldItems) '${item.productSource}:${item.productId}': item.effectiveQuantity
    };
    final Map<String, int> newQtyByKey = {
      for (final item in newItems) '${item.productSource}:${item.productId}': item.effectiveQuantity
    };

    final allKeys = {...oldQtyByKey.keys, ...newQtyByKey.keys};
    bool hasChanges = false;

    for (final key in allKeys) {
      final parts = key.split(':');
      if (parts.length != 2) continue;
      final source = parts[0];
      final productId = parts[1];

      final oldQty = oldQtyByKey[key] ?? 0;
      final newQty = newQtyByKey[key] ?? 0;
      final delta = newQty - oldQty;
      if (delta == 0) continue;

      final collectionName = _collectionForSource(source);
      final productRef = _firestore.collection(collectionName).doc(productId);
      final snap = await productRef.get();
      if (!snap.exists) continue;
      final data = snap.data() ?? {};

      final currentStock = (data['stockQuantity'] as num?)?.toInt() ?? 0;
      final nextStock = (currentStock + delta) < 0 ? 0 : (currentStock + delta);

      batch.update(productRef, {
        'stockQuantity': nextStock,
        'updatedAt': now,
      });

      final itemSample = newItems.firstWhere(
        (i) => '${i.productSource}:${i.productId}' == key,
        orElse: () => oldItems.firstWhere((i) => '${i.productSource}:${i.productId}' == key),
      );

      final movementRef = _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc();
      final movement = InventoryMovement(
        id: movementRef.id,
        productId: productId,
        productName: itemSample.productName,
        productSource: source,
        previousStock: currentStock,
        newStock: nextStock,
        delta: delta,
        reason: 'Purchase Order Adjustment',
        notes: 'PO Ref: $invoiceRef (${delta > 0 ? "+$delta" : "$delta"})',
        createdBy: createdBy,
        createdAt: now,
      );
      batch.set(movementRef, movement.toJson());
      hasChanges = true;
    }

    if (hasChanges) {
      await batch.commit();
    }
  }

  /// Reverts replenished stock if a purchase order is deleted.
  Future<void> revertReplenishedStockForPurchaseOrder({
    required String invoiceNumber,
    required List<OrderItem> items,
  }) async {
    if (items.isEmpty) return;
    final now = Timestamp.now();
    final createdBy = _currentActorName();
    final batch = _firestore.batch();

    for (final item in items) {
      final qty = item.effectiveQuantity;
      if (item.productId.isEmpty || qty <= 0) continue;
      final collectionName = _collectionForSource(item.productSource);
      final productRef = _firestore.collection(collectionName).doc(item.productId);
      final snap = await productRef.get();
      if (!snap.exists) continue;
      final data = snap.data() ?? {};

      final currentStock = (data['stockQuantity'] as num?)?.toInt() ?? 0;
      final nextStock = (currentStock - qty) < 0 ? 0 : (currentStock - qty);

      batch.update(productRef, {
        'stockQuantity': nextStock,
        'updatedAt': now,
      });

      final movementRef = _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc();
      final movement = InventoryMovement(
        id: movementRef.id,
        productId: item.productId,
        productName: item.productName,
        productSource: item.productSource,
        previousStock: currentStock,
        newStock: nextStock,
        delta: -qty,
        reason: 'Purchase Order Deleted (Stock Reverted)',
        notes: 'PO Ref: $invoiceNumber',
        createdBy: createdBy,
        createdAt: now,
      );
      batch.set(movementRef, movement.toJson());
    }

    await batch.commit();
  }

  /// Adds floating incoming stock (`incomingQuantity`) when a new Purchase Order is created
  /// with status `'pending'`.
  Future<void> addIncomingStockForPurchaseOrder({
    required List<OrderItem> items,
  }) async {
    if (items.isEmpty) return;
    final now = Timestamp.now();
    final batch = _firestore.batch();
    bool hasUpdates = false;

    for (final item in items) {
      final qty = item.effectiveQuantity;
      if (item.productId.isEmpty || qty <= 0) continue;
      final collectionName = _collectionForSource(item.productSource);
      final productRef = _firestore.collection(collectionName).doc(item.productId);
      final snap = await productRef.get();
      if (!snap.exists) continue;
      final data = snap.data() ?? {};

      final currentIncoming = (data['incomingQuantity'] as num?)?.toInt() ?? 0;
      final nextIncoming = currentIncoming + qty;

      batch.update(productRef, {
        'incomingQuantity': nextIncoming,
        'updatedAt': now,
      });
      hasUpdates = true;
    }

    if (hasUpdates) {
      await batch.commit();
    }
  }

  /// Adjusts floating incoming stock (`incomingQuantity`) when an existing pending Purchase Order
  /// has its items or quantities updated prior to official invoice confirmation.
  Future<void> adjustIncomingStockForPurchaseOrder({
    required List<OrderItem> oldItems,
    required List<OrderItem> newItems,
  }) async {
    final now = Timestamp.now();
    final batch = _firestore.batch();

    final Map<String, ({String source, int delta})> deltas = {};

    for (final oldItem in oldItems) {
      if (oldItem.productId.isEmpty) continue;
      final key = '${oldItem.productSource}:${oldItem.productId}';
      final prev = deltas[key];
      deltas[key] = (
        source: oldItem.productSource,
        delta: (prev?.delta ?? 0) - oldItem.effectiveQuantity,
      );
    }

    for (final newItem in newItems) {
      if (newItem.productId.isEmpty) continue;
      final key = '${newItem.productSource}:${newItem.productId}';
      final prev = deltas[key];
      deltas[key] = (
        source: newItem.productSource,
        delta: (prev?.delta ?? 0) + newItem.effectiveQuantity,
      );
    }

    bool hasUpdates = false;
    for (final entry in deltas.entries) {
      if (entry.value.delta == 0) continue;
      final parts = entry.key.split(':');
      if (parts.length != 2) continue;
      final productId = parts[1];

      final collectionName = _collectionForSource(entry.value.source);
      final productRef = _firestore.collection(collectionName).doc(productId);
      final snap = await productRef.get();
      if (!snap.exists) continue;
      final data = snap.data() ?? {};

      final currentIncoming = (data['incomingQuantity'] as num?)?.toInt() ?? 0;
      final nextIncoming = currentIncoming + entry.value.delta;

      batch.update(productRef, {
        'incomingQuantity': nextIncoming < 0 ? 0 : nextIncoming,
        'updatedAt': now,
      });
      hasUpdates = true;
    }

    if (hasUpdates) {
      await batch.commit();
    }
  }

  /// Removes floating incoming stock (`incomingQuantity`) when a pending Purchase Order is deleted/cancelled.
  Future<void> removeIncomingStockForPurchaseOrder({
    required List<OrderItem> items,
  }) async {
    if (items.isEmpty) return;
    final now = Timestamp.now();
    final batch = _firestore.batch();
    bool hasUpdates = false;

    for (final item in items) {
      final qty = item.effectiveQuantity;
      if (item.productId.isEmpty || qty <= 0) continue;
      final collectionName = _collectionForSource(item.productSource);
      final productRef = _firestore.collection(collectionName).doc(item.productId);
      final snap = await productRef.get();
      if (!snap.exists) continue;
      final data = snap.data() ?? {};

      final currentIncoming = (data['incomingQuantity'] as num?)?.toInt() ?? 0;
      final nextIncoming = currentIncoming - qty;

      batch.update(productRef, {
        'incomingQuantity': nextIncoming < 0 ? 0 : nextIncoming,
        'updatedAt': now,
      });
      hasUpdates = true;
    }

    if (hasUpdates) {
      await batch.commit();
    }
  }

  /// Replenishes physical `stockQuantity` for confirmed items and simultaneously
  /// clears floating `incomingQuantity` from the original Purchase Order items.
  Future<void> replenishAndClearIncomingStockForPurchaseOrder({
    required String invoiceNumber,
    required DateTime orderDate,
    required List<OrderItem> originalPoItems,
    required List<OrderItem> confirmedItems,
  }) async {
    final now = Timestamp.now();
    final createdBy = _currentActorName();
    final batch = _firestore.batch();
    final invoiceRef = invoiceNumber.trim().isNotEmpty
        ? invoiceNumber.trim()
        : 'PO-${DateFormat('yyyyMMdd').format(orderDate)}';

    // Map all involved product IDs: source + id -> { incomingDelta, physicalDelta, name }
    final Map<String, ({String source, String id, String name, int incomingDeduct, int stockAdd})> merged = {};

    for (final item in originalPoItems) {
      if (item.productId.isEmpty) continue;
      final key = '${item.productSource}:${item.productId}';
      final existing = merged[key];
      merged[key] = (
        source: item.productSource,
        id: item.productId,
        name: item.productName,
        incomingDeduct: (existing?.incomingDeduct ?? 0) + item.effectiveQuantity,
        stockAdd: existing?.stockAdd ?? 0,
      );
    }

    for (final item in confirmedItems) {
      if (item.productId.isEmpty) continue;
      final key = '${item.productSource}:${item.productId}';
      final existing = merged[key];
      merged[key] = (
        source: item.productSource,
        id: item.productId,
        name: item.productName,
        incomingDeduct: existing?.incomingDeduct ?? 0,
        stockAdd: (existing?.stockAdd ?? 0) + item.effectiveQuantity,
      );
    }

    for (final entry in merged.values) {
      final collectionName = _collectionForSource(entry.source);
      final productRef = _firestore.collection(collectionName).doc(entry.id);
      final snap = await productRef.get();
      if (!snap.exists) continue;
      final data = snap.data() ?? {};

      final currentStock = (data['stockQuantity'] as num?)?.toInt() ?? 0;
      final currentIncoming = (data['incomingQuantity'] as num?)?.toInt() ?? 0;

      final nextStock = currentStock + entry.stockAdd;
      final nextIncoming = currentIncoming - entry.incomingDeduct;

      batch.update(productRef, {
        'stockQuantity': nextStock,
        'incomingQuantity': nextIncoming < 0 ? 0 : nextIncoming,
        'updatedAt': now,
      });

      if (entry.stockAdd > 0) {
        final movementRef = _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc();
        final movement = InventoryMovement(
          id: movementRef.id,
          productId: entry.id,
          productName: entry.name,
          productSource: entry.source,
          previousStock: currentStock,
          newStock: nextStock,
          delta: entry.stockAdd,
          reason: 'Purchase Order Replenishment',
          notes: 'PO Ref: $invoiceRef',
          createdBy: createdBy,
          createdAt: now,
        );
        batch.set(movementRef, movement.toJson());
      }
    }

    await batch.commit();
  }

  /// Calculates net stock and reserved adjustments for verified deliveries without writing to Firestore.
  /// Pure function suitable for unit tests and verification preview modals.
  static SettlementPlan computeSettlement(List<({String id, Delivery delivery})> deliveries) {
    final Map<String, ProductSettlementDelta> deltas = {};
    final List<SettlementMovementPlan> movements = [];
    final List<String> settledIds = [];

    int totalDeliveredUnits = 0;
    int totalReturnedUnits = 0;
    int totalLegacyRestockedUnits = 0;
    int orderCount = 0;
    int deliveredOrderCount = 0;
    int returnedOrderCount = 0;

    void addDelta({
      required String source,
      required String productId,
      required String productName,
      int stockDelta = 0,
      int reservedDelta = 0,
    }) {
      if (productId.isEmpty || (stockDelta == 0 && reservedDelta == 0)) return;
      final key = '$source:$productId';
      final current = deltas[key];
      if (current == null) {
        deltas[key] = ProductSettlementDelta(
          productId: productId,
          productName: productName,
          productSource: source,
          stockDelta: stockDelta,
          reservedDelta: reservedDelta,
        );
      } else {
        deltas[key] = current.copyWith(
          stockDelta: current.stockDelta + stockDelta,
          reservedDelta: current.reservedDelta + reservedDelta,
        );
      }
    }

    for (final entry in deliveries) {
      final id = entry.id;
      final d = entry.delivery;

      // Skip orders that are already settled or not yet eligible
      if (d.isInventorySettled) continue;
      if (d.transactionStatus == DeliveryStatus.pendingPicklist) continue;
      if (d.transactionStatus == DeliveryStatus.pending) continue;

      bool orderProcessed = false;

      if (d.transactionStatus == DeliveryStatus.delivered) {
        orderProcessed = true;
        deliveredOrderCount++;
        settledIds.add(id);

        for (final item in d.items) {
          if (item.productId.isEmpty) continue;
          final dQty = item.deliveredQuantity;
          final rQty = item.returnedQuantity;

          if (!d.isInventoryDeducted) {
            // New workflow: physical stock was never deducted, but was held in reservedQuantity
            totalDeliveredUnits += dQty;
            totalReturnedUnits += rQty;

            // Deduct delivered units from stock & reserved; release returned units from reserved
            addDelta(
              source: item.productSource,
              productId: item.productId,
              productName: item.productName,
              stockDelta: -dQty,
              reservedDelta: -(dQty + rQty),
            );

            if (dQty > 0) {
              movements.add(SettlementMovementPlan(
                productId: item.productId,
                productName: item.productName,
                productSource: item.productSource,
                delta: -dQty,
                reason: 'Delivery Settled (Breakdown Verified)',
                notes: 'Store: ${d.storeName} (Delivered: $dQty${rQty > 0 ? ", Returned: $rQty" : ""})',
              ));
            }
          } else {
            // Legacy workflow: stock was already deducted at picklist completion
            totalReturnedUnits += rQty;
            if (rQty > 0) {
              totalLegacyRestockedUnits += rQty;
              addDelta(
                source: item.productSource,
                productId: item.productId,
                productName: item.productName,
                stockDelta: rQty,
                reservedDelta: 0,
              );
              movements.add(SettlementMovementPlan(
                productId: item.productId,
                productName: item.productName,
                productSource: item.productSource,
                delta: rQty,
                reason: 'Return Restocked (Legacy Order)',
                notes: 'Store: ${d.storeName} (Restocked: $rQty)',
              ));
            }
          }
        }
      } else if (d.transactionStatus == DeliveryStatus.returned) {
        orderProcessed = true;
        returnedOrderCount++;
        settledIds.add(id);

        for (final item in d.items) {
          if (item.productId.isEmpty) continue;
          final pickedQty = item.pickedQuantity > 0 ? item.pickedQuantity : item.orderedQuantity;
          totalReturnedUnits += pickedQty;

          if (!d.isInventoryDeducted) {
            // New workflow: physical stock was never deducted, but was held in reservedQuantity
            // Upon breakdown verification, return is verified: release floating reservation
            addDelta(
              source: item.productSource,
              productId: item.productId,
              productName: item.productName,
              stockDelta: 0,
              reservedDelta: -pickedQty,
            );
          } else {
            // Legacy workflow: stock was already deducted at picklist! We must restock physical stock
            totalLegacyRestockedUnits += pickedQty;
            addDelta(
              source: item.productSource,
              productId: item.productId,
              productName: item.productName,
              stockDelta: pickedQty,
              reservedDelta: 0,
            );
            movements.add(SettlementMovementPlan(
              productId: item.productId,
              productName: item.productName,
              productSource: item.productSource,
              delta: pickedQty,
              reason: 'Return Restocked (Legacy Order)',
              notes: 'Store: ${d.storeName} (Restocked: $pickedQty)',
            ));
          }
        }
      }

      if (orderProcessed) {
        orderCount++;
      }
    }

    return SettlementPlan(
      productDeltas: deltas,
      movements: movements,
      settledDeliveryIds: settledIds,
      totalDeliveredUnits: totalDeliveredUnits,
      totalReturnedUnits: totalReturnedUnits,
      totalLegacyRestockedUnits: totalLegacyRestockedUnits,
      affectedProductCount: deltas.length,
      affectedOrderCount: orderCount,
      deliveredCount: deliveredOrderCount,
      returnedCount: returnedOrderCount,
    );
  }

  /// Queries all deliveries for [date] and computes the pending settlement plan for preview.
  Future<SettlementPlan> previewSettlementForDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    final snapshot = await _firestore
        .collection(DELIVERY_COLLECTION_REF)
        .where(DeliveryModelString.deliveryDate, isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where(DeliveryModelString.deliveryDate, isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .get();

    final deliveries = snapshot.docs.map((doc) {
      return (id: doc.id, delivery: Delivery.fromJson(doc.data()));
    }).toList();

    return computeSettlement(deliveries);
  }

  /// Atomically settles inventory for all delivered and returned orders on [date]
  /// inside a Firestore transaction.
  ///
  /// Permanently updates physical stock, releases floating reservations, creates audit
  /// movements, marks deliveries as settled, and verifies the breakdown.
  Future<void> settleDeliveriesForDate({
    required DateTime date,
    required String breakdownId,
    required Breakdown breakdown,
  }) async {
    final startOfDay = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    final deliverySnapshot = await _firestore
        .collection(DELIVERY_COLLECTION_REF)
        .where(DeliveryModelString.deliveryDate, isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where(DeliveryModelString.deliveryDate, isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .get();

    final deliveries = deliverySnapshot.docs.map((doc) {
      return (id: doc.id, delivery: Delivery.fromJson(doc.data()));
    }).toList();

    final plan = computeSettlement(deliveries);
    final now = Timestamp.now();
    final actorName = _currentActorName();

    await _firestore.runTransaction((transaction) async {
      // 1. Check breakdown doc to prevent double-verification
      if (breakdownId.isNotEmpty) {
        final bRef = _firestore.collection(BREAKDOWN_COLLECTION_REF).doc(breakdownId);
        final bSnap = await transaction.get(bRef);
        if (bSnap.exists && (bSnap.data()?['isVerifiedByDealer'] as bool? ?? false)) {
          throw Exception('This cash breakdown is already verified.');
        }
      }

      // 2. Read all affected product docs
      final Map<String, DocumentSnapshot<Map<String, dynamic>>> productSnaps = {};
      for (final delta in plan.productDeltas.values) {
        final collectionName = _collectionForSource(delta.productSource);
        final pRef = _firestore.collection(collectionName).doc(delta.productId);
        final pSnap = await transaction.get(pRef);
        productSnaps['${delta.productSource}:${delta.productId}'] = pSnap;
      }

      // 3. Update products
      for (final delta in plan.productDeltas.values) {
        final key = '${delta.productSource}:${delta.productId}';
        final pSnap = productSnaps[key];
        if (pSnap == null || !pSnap.exists) continue;

        final data = pSnap.data() ?? {};
        final currentStock = (data['stockQuantity'] as num?)?.toInt() ?? 0;
        final currentReserved = (data['reservedQuantity'] as num?)?.toInt() ?? 0;

        final nextStock = (currentStock + delta.stockDelta).clamp(0, 99999999);
        final nextReserved = (currentReserved + delta.reservedDelta).clamp(0, 99999999);

        final collectionName = _collectionForSource(delta.productSource);
        final pRef = _firestore.collection(collectionName).doc(delta.productId);

        transaction.update(pRef, {
          'stockQuantity': nextStock,
          'reservedQuantity': nextReserved,
          'updatedAt': now,
        });
      }

      // 4. Record stock movement logs
      for (final mov in plan.movements) {
        final key = '${mov.productSource}:${mov.productId}';
        final pSnap = productSnaps[key];
        final currentStock = ((pSnap?.data()?['stockQuantity'] as num?)?.toInt() ?? 0);
        final nextStock = (currentStock + mov.delta).clamp(0, 99999999);

        final movementRef = _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc();
        final movement = InventoryMovement(
          id: movementRef.id,
          productId: mov.productId,
          productName: mov.productName,
          productSource: mov.productSource,
          previousStock: currentStock,
          newStock: nextStock,
          delta: mov.delta,
          reason: mov.reason,
          notes: mov.notes,
          createdBy: actorName,
          createdAt: now,
        );
        transaction.set(movementRef, movement.toJson());
      }

      // 5. Mark all affected deliveries as settled
      for (final deliveryId in plan.settledDeliveryIds) {
        final dRef = _firestore.collection(DELIVERY_COLLECTION_REF).doc(deliveryId);
        transaction.update(dRef, {
          DeliveryModelString.isInventorySettled: true,
          DeliveryModelString.isInventoryDeducted: true,
          DeliveryModelString.isInventoryReserved: false,
          DeliveryModelString.inventorySettledDate: now,
          DeliveryModelString.inventorySettledBy: actorName,
          DeliveryModelString.lastupdatedDate: now,
          DeliveryModelString.lastUpdatedBy: actorName,
        });
      }

      // 6. Update breakdown doc
      if (breakdownId.isNotEmpty) {
        final bRef = _firestore.collection(BREAKDOWN_COLLECTION_REF).doc(breakdownId);
        transaction.update(bRef, {
          'isVerifiedByDealer': true,
          'verifiedBy': actorName,
          'verifiedDate': now,
          'inventorySettledDate': now,
          'lastupdatedDate': now,
          'lastUpdatedBy': actorName,
        });
      }
    });
  }

  /// Re-reserves floating inventory (`reservedQuantity`) for an order created when rescheduling
  /// a verified returned delivery.
  Future<void> reReserveForRescheduledOrder(List<OrderItem> items) async {
    await reserveStockForOrder(storeName: 'Rescheduled Order', items: items);
  }
}

/// Represents the calculated net changes to be applied to a product during settlement.
class ProductSettlementDelta {
  final String productId;
  final String productName;
  final String productSource;
  final int stockDelta;
  final int reservedDelta;

  const ProductSettlementDelta({
    required this.productId,
    required this.productName,
    required this.productSource,
    required this.stockDelta,
    required this.reservedDelta,
  });

  ProductSettlementDelta copyWith({
    String? productId,
    String? productName,
    String? productSource,
    int? stockDelta,
    int? reservedDelta,
  }) {
    return ProductSettlementDelta(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSource: productSource ?? this.productSource,
      stockDelta: stockDelta ?? this.stockDelta,
      reservedDelta: reservedDelta ?? this.reservedDelta,
    );
  }
}

/// Represents an audit movement to be written during settlement.
class SettlementMovementPlan {
  final String productId;
  final String productName;
  final String productSource;
  final int delta;
  final String reason;
  final String notes;

  const SettlementMovementPlan({
    required this.productId,
    required this.productName,
    required this.productSource,
    required this.delta,
    required this.reason,
    required this.notes,
  });
}

/// Aggregated settlement outcome bundling per-product deltas, movement plans, and summary metrics.
class SettlementPlan {
  final Map<String, ProductSettlementDelta> productDeltas;
  final List<SettlementMovementPlan> movements;
  final List<String> settledDeliveryIds;
  final int totalDeliveredUnits;
  final int totalReturnedUnits;
  final int totalLegacyRestockedUnits;
  final int affectedProductCount;
  final int affectedOrderCount;
  final int deliveredCount;
  final int returnedCount;

  int get totalDeliveriesToSettle => affectedOrderCount;
  Map<String, ProductSettlementDelta> get deltas => productDeltas;

  ProductSettlementDelta? getDelta(String productId) {
    if (productDeltas.containsKey(productId)) return productDeltas[productId];
    for (final entry in productDeltas.entries) {
      if (entry.value.productId == productId) return entry.value;
    }
    return null;
  }

  const SettlementPlan({
    required this.productDeltas,
    required this.movements,
    required this.settledDeliveryIds,
    required this.totalDeliveredUnits,
    required this.totalReturnedUnits,
    required this.totalLegacyRestockedUnits,
    required this.affectedProductCount,
    required this.affectedOrderCount,
    this.deliveredCount = 0,
    this.returnedCount = 0,
  });

  static const empty = SettlementPlan(
    productDeltas: {},
    movements: [],
    settledDeliveryIds: [],
    totalDeliveredUnits: 0,
    totalReturnedUnits: 0,
    totalLegacyRestockedUnits: 0,
    affectedProductCount: 0,
    affectedOrderCount: 0,
    deliveredCount: 0,
    returnedCount: 0,
  );
}
