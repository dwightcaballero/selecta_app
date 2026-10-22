import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/admin_selecta_product.dart';
import 'package:selecta_ops/models/breakdown.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/floating_stock.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/other_product.dart';
import 'package:selecta_ops/models/purchaseorder.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/models/placement.dart';
import 'package:selecta_ops/models/van_load.dart';
import 'package:selecta_ops/services/breakdown_service.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/other_product_service.dart';
import 'package:selecta_ops/services/placement_service.dart';
import 'package:selecta_ops/services/purchaseorder_service.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:selecta_ops/models/inventory_pending_adjustment.dart';
import 'package:selecta_ops/models/inventory_snapshot.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:intl/intl.dart';

// ignore: constant_identifier_names
const String INVENTORY_MOVEMENTS_COLLECTION_REF = 'inventory_movements';

/// Container for computed stock mutations, payload, and audit movement.
class StockChangeRecord {
  final InventoryMovement movement;
  final Map<String, dynamic> productUpdates;
  final bool clamped;

  const StockChangeRecord({
    required this.movement,
    required this.productUpdates,
    this.clamped = false,
  });
}

/// Discrepancy finding between ledger records, physical documents, and active product stock.
class StockDiscrepancy {
  final String id;
  final String productId;
  final String productName;
  final String productSource;
  final String discrepancyType; // 'ledger_mismatch', 'chain_broken', 'reserved_mismatch', 'clamped_negative_stock', 'short_pick', 'short_allocation', 'po_short_shipment', 'return_quarantine', 'return_write_off'
  final int expectedValue;
  final int actualValue;
  final String message;
  final DateTime detectedAt;
  final String status; // 'open', 'resolved'
  final String? resolutionNotes;
  final DateTime? resolvedAt;
  final String? resolvedBy;

  const StockDiscrepancy({
    this.id = '',
    required this.productId,
    required this.productName,
    required this.productSource,
    required this.discrepancyType,
    required this.expectedValue,
    required this.actualValue,
    required this.message,
    required this.detectedAt,
    this.status = 'open',
    this.resolutionNotes,
    this.resolvedAt,
    this.resolvedBy,
  });

  factory StockDiscrepancy.fromJson(String id, Map<String, dynamic> json) {
    return StockDiscrepancy(
      id: id,
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      productSource: json['productSource'] as String? ?? 'selecta',
      discrepancyType: json['discrepancyType'] as String? ?? json['type'] as String? ?? 'unknown',
      expectedValue: (json['expectedValue'] as num?)?.toInt() ?? (json['expected'] as num?)?.toInt() ?? 0,
      actualValue: (json['actualValue'] as num?)?.toInt() ?? (json['actual'] as num?)?.toInt() ?? 0,
      message: json['message'] as String? ?? json['details'] as String? ?? '',
      detectedAt: (json['detectedAt'] as Timestamp?)?.toDate() ?? (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: json['status'] as String? ?? 'open',
      resolutionNotes: json['resolutionNotes'] as String?,
      resolvedAt: (json['resolvedAt'] as Timestamp?)?.toDate(),
      resolvedBy: json['resolvedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'productSource': productSource,
        'discrepancyType': discrepancyType,
        'expectedValue': expectedValue,
        'actualValue': actualValue,
        'message': message,
        'detectedAt': Timestamp.fromDate(detectedAt),
        'status': status,
        if (resolutionNotes != null) 'resolutionNotes': resolutionNotes,
        if (resolvedAt != null) 'resolvedAt': Timestamp.fromDate(resolvedAt!),
        if (resolvedBy != null) 'resolvedBy': resolvedBy,
      };
}

/// Audit report containing reconciliation findings across the product catalog.
class StockAuditReport {
  final DateTime auditedAt;
  final int totalProductsAudited;
  final int discrepanciesFound;
  final List<StockDiscrepancy> discrepancies;

  const StockAuditReport({
    required this.auditedAt,
    required this.totalProductsAudited,
    required this.discrepanciesFound,
    required this.discrepancies,
  });
}

/// Exception dashboard metrics bundle summarizing critical inventory discrepancies and KPIs.
class InventoryExceptionDashboardMetrics {
  final int openDiscrepanciesCount;
  final int shortPicksCount;
  final int clampedZeroCount;
  final int manualOverridesCount;
  final int largeAdjustmentsCount;
  final int quarantinedItemsCount;
  final double inventoryAccuracyRate;
  final double pickAccuracyRate;
  final List<StockDiscrepancy> recentDiscrepancies;

  const InventoryExceptionDashboardMetrics({
    required this.openDiscrepanciesCount,
    required this.shortPicksCount,
    required this.clampedZeroCount,
    required this.manualOverridesCount,
    required this.largeAdjustmentsCount,
    required this.quarantinedItemsCount,
    required this.inventoryAccuracyRate,
    required this.pickAccuracyRate,
    this.recentDiscrepancies = const [],
  });
}

/// Service that manages stock levels across both [SelectaProduct] (`selecta_products`)
/// and [OtherProduct] (`other_products`), as well as stock movement audit logs (`inventory_movements`).
class InventoryService {
  final FirebaseFirestore? _customFirestore;
  InventoryService({FirebaseFirestore? firestore}) : _customFirestore = firestore;

  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;

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
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? returnSub;

    List<InventoryItem> selectaItems = [];
    List<InventoryItem> otherItems = [];
    Map<String, String> adminTagMap = {};
    Map<String, String> adminTagByName = {};
    List<AdminSelectaProduct> adminProducts = [];
    Map<String, int> pendingIncomingById = {};
    Map<String, int> pendingIncomingByName = {};
    Map<String, int> pendingReturnById = {};
    Map<String, int> pendingReturnByName = {};
    Map<String, int> pendingPreOrderById = {};
    Map<String, int> pendingPreOrderByName = {};
    Set<String> allLocalSelectaIds = {};
    Set<String> allLocalSelectaNames = {};
    bool selectaLoaded = false;
    bool otherLoaded = false;
    bool poLoaded = false;
    bool returnLoaded = false;

    void emitCombined() {
      if (!selectaLoaded || !otherLoaded || !poLoaded || !returnLoaded) return;
      if (controller.isClosed) return;

      int resolveLiveIncoming(InventoryItem item) {
        final nameKey = item.productName.trim().toLowerCase();
        final poIncoming = pendingIncomingById[item.id] ?? pendingIncomingByName[nameKey] ?? 0;
        final retIncoming = pendingReturnById[item.id] ?? pendingReturnByName[nameKey] ?? 0;
        final liveTotal = poIncoming + retIncoming;
        return liveTotal > 0 ? liveTotal : item.incomingQuantity;
      }

      int resolveLivePreOrder(InventoryItem item) {
        final nameKey = item.productName.trim().toLowerCase();
        return pendingPreOrderById[item.id] ?? pendingPreOrderByName[nameKey] ?? 0;
      }

      final resolvedSelecta = selectaItems.map((item) {
        final nameKey = item.productName.trim().toLowerCase();
        final effectiveIncoming = resolveLiveIncoming(item);
        final livePreOrder = resolveLivePreOrder(item);
        var current = item.copyWith(
          incomingQuantity: effectiveIncoming,
          preOrderQuantity: livePreOrder,
        );

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
          final liveIncoming = (pendingIncomingById[adminProd.id] ?? pendingIncomingByName[nameKey] ?? 0) +
              (pendingReturnById[adminProd.id] ?? pendingReturnByName[nameKey] ?? 0);
          final livePreOrder = pendingPreOrderById[adminProd.id] ?? pendingPreOrderByName[nameKey] ?? 0;
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
              preOrderQuantity: livePreOrder,
              lowStockThreshold: 10,
              source: InventoryProductSource.selecta,
              category: adminProd.category,
              tag: adminProd.tag,
              updatedAt: adminProd.updatedAt,
            ),
          );
        }
      }

      final resolvedOther = otherItems.map((item) {
        final effectiveIncoming = resolveLiveIncoming(item);
        final livePreOrder = resolveLivePreOrder(item);
        return item.copyWith(
          incomingQuantity: effectiveIncoming,
          preOrderQuantity: livePreOrder,
        );
      }).toList();

      final combined = <InventoryItem>[
        ...resolvedSelecta,
        ...resolvedOther,
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

        returnSub = _firestore
            .collection(DELIVERY_COLLECTION_REF)
            .snapshots()
            .listen(
          (snap) {
            final Map<String, int> rById = {};
            final Map<String, int> rByName = {};
            final Map<String, int> preById = {};
            final Map<String, int> preByName = {};

            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);

            for (final doc in snap.docs) {
              final data = doc.data();
              final isApproved = data['isReturnApprovedByDealer'] as bool? ?? false;
              final status = data['transactionStatus'] as String? ?? '';
              final isReturnIncoming = data['isReturnIncoming'] as bool? ?? false;
              final isFullReturn = status == DeliveryStatus.returned;
              final isVoided = status == DeliveryStatus.voided;
              final isSettled = data['isInventorySettled'] as bool? ?? false;
              final isDelivered = status == DeliveryStatus.delivered;

              // 1. Returns calculation
              if (!isApproved && (isFullReturn || isReturnIncoming)) {
                final itemsList = data['items'] as List<dynamic>? ?? [];
                for (final raw in itemsList) {
                  if (raw is Map) {
                    final pid = (raw['productId'] as String? ?? '').trim();
                    final pName = (raw['productName'] as String? ?? '').trim().toLowerCase();
                    final retQty = (raw['returnedQuantity'] as num?)?.toInt() ?? 0;
                    final pickedQty = (raw['pickedQuantity'] as num?)?.toInt() ?? 0;
                    final qty = retQty > 0 ? retQty : (isFullReturn ? pickedQty : 0);
                    if (qty > 0) {
                      if (pid.isNotEmpty) {
                        rById[pid] = (rById[pid] ?? 0) + qty;
                      }
                      if (pName.isNotEmpty) {
                        rByName[pName] = (rByName[pName] ?? 0) + qty;
                      }
                    }
                  }
                }
              }

              // 2. Pre-orders calculation (orders booked for tomorrow or any future dates)
              final deliveryDateTs = data['deliveryDate'] as Timestamp?;
              if (deliveryDateTs != null) {
                final deliveryDate = deliveryDateTs.toDate();
                final deliveryDay = DateTime(deliveryDate.year, deliveryDate.month, deliveryDate.day);
                final isFuture = deliveryDay.isAfter(today);

                if (isFuture && !isVoided && !isFullReturn && !isSettled && !isDelivered) {
                  final itemsList = data['items'] as List<dynamic>? ?? [];
                  for (final raw in itemsList) {
                    if (raw is Map) {
                      final pid = (raw['productId'] as String? ?? '').trim();
                      final pName = (raw['productName'] as String? ?? '').trim().toLowerCase();
                      final orderedQty = (raw['orderedQuantity'] as num?)?.toInt() ?? 0;
                      final pickedQty = (raw['pickedQuantity'] as num?)?.toInt() ?? 0;
                      final qty = pickedQty > 0 ? pickedQty : orderedQty;
                      if (qty > 0) {
                        if (pid.isNotEmpty) {
                          preById[pid] = (preById[pid] ?? 0) + qty;
                        }
                        if (pName.isNotEmpty) {
                          preByName[pName] = (preByName[pName] ?? 0) + qty;
                        }
                      }
                    }
                  }
                }
              }
            }

            pendingReturnById = rById;
            pendingReturnByName = rByName;
            pendingPreOrderById = preById;
            pendingPreOrderByName = preByName;
            returnLoaded = true;
            emitCombined();
          },
          onError: (Object _, StackTrace _) {
            returnLoaded = true;
            emitCombined();
          },
        );
      },
      onCancel: () async {
        await selectaSub?.cancel();
        await adminSub?.cancel();
        await otherSub?.cancel();
        await poSub?.cancel();
        await returnSub?.cancel();
      },
    );

    return controller.stream;
  }

  String _collectionForSource(String productSource) {
    return productSource == 'other'
        ? OTHER_PRODUCTS_COLLECTION_REF
        : SELECTA_PRODUCTS_COLLECTION_REF;
  }

  static String? _cachedAppVersion;

  static Future<String> _resolveAppVersion() async {
    if (_cachedAppVersion != null) return _cachedAppVersion!;
    try {
      final info = await PackageInfo.fromPlatform();
      _cachedAppVersion = '${info.version}+${info.buildNumber}';
      return _cachedAppVersion!;
    } catch (_) {
      return '1.0.0+51';
    }
  }

  /// Executes a Firestore transaction with offline error handling and retry limits.
  Future<T> _runInventoryTransaction<T>(
    String operationName,
    Future<T> Function(Transaction transaction) updateFunction,
  ) async {
    try {
      return await _firestore.runTransaction<T>(
        updateFunction,
        maxAttempts: 5,
      );
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable' ||
          e.code == 'deadline-exceeded' ||
          e.message?.toLowerCase().contains('offline') == true) {
        throw StateError(
          'Inventory operation "$operationName" requires an active internet connection. Please verify your connection and try again.',
        );
      }
      rethrow;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('offline') || msg.contains('failed to get document because the client is offline')) {
        throw StateError(
          'Inventory operation "$operationName" requires an active internet connection. Please verify your connection and try again.',
        );
      }
      rethrow;
    }
  }

  Future<int> _resolveUnitApprovalThreshold() async {
    try {
      final config = await ConfigurationService().getConfiguration();
      return config.unitApprovalThreshold;
    } catch (_) {
      return 10;
    }
  }

  Future<({String uid, String role, String name})> _resolveActor() async {
    try {
      final authUser = FirebaseAuth.instance.currentUser;
      final cachedUser = await KVariables.getUser();
      final uid = authUser?.uid ?? '';
      final role = cachedUser?.role ?? 'Unknown';
      final name = (authUser?.displayName?.trim().isNotEmpty == true)
          ? authUser!.displayName!.trim()
          : ((cachedUser?.username.trim().isNotEmpty ?? false)
              ? cachedUser!.username.trim()
              : (authUser?.email?.trim().isNotEmpty == true ? authUser!.email!.trim() : 'Unknown'));
      return (uid: uid, role: role, name: name);
    } catch (_) {
      return (uid: '', role: 'Unknown', name: 'Unknown');
    }
  }


  static List<List<T>> _chunk<T>(List<T> items, int chunkSize) {
    final chunks = <List<T>>[];
    for (var i = 0; i < items.length; i += chunkSize) {
      chunks.add(items.sublist(i, (i + chunkSize < items.length) ? i + chunkSize : items.length));
    }
    return chunks;
  }

  /// Central logic for computing stock mutations, enforcing non-negative floors,
  /// tracking clamping, and creating rich [InventoryMovement] audit records.
  StockChangeRecord _computeStockChange({
    required DocumentReference<Map<String, dynamic>> productRef,
    required DocumentSnapshot<Map<String, dynamic>> productSnap,
    int stockDelta = 0,
    int reservedDelta = 0,
    int incomingDelta = 0,
    required MovementType movementType,
    ReasonCode? reasonCode,
    ReferenceType? referenceType,
    String? referenceId,
    String? referenceLabel,
    String? reason,
    String notes = '',
    bool allowClamping = true,
    String? batchId,
    String? actorUid,
    String? actorRole,
    String? actorName,
    String? appVersion,
    String? deviceId,
    Timestamp? timestamp,
    // Phase 8 parameters
    String? correlationId,
    String? idempotencyKey,
    String? sourceLocation,
    String? targetLocation,
    bool isOverride = false,
    String? overrideReason,
    double? costPrice,
    double? sellingPrice,
    ReturnDisposition? disposition,
    ShortPickReason? shortPickReason,
    bool isBlind = false,
    int countRound = 1,
    int? systemQuantityAtStart,
  }) {
    final data = productSnap.data() ?? {};
    final currentStock = (data['stockQuantity'] as num?)?.toInt() ?? 0;
    final currentReserved = (data['reservedQuantity'] as num?)?.toInt() ?? 0;
    final currentIncoming = (data['incomingQuantity'] as num?)?.toInt() ?? 0;

    int nextStock = currentStock;
    bool clamped = false;
    int? requestedQuantity;

    if (stockDelta != 0) {
      final target = currentStock + stockDelta;
      if (target < 0) {
        if (!allowClamping) {
          throw ArgumentError(
            'Stock cannot be reduced below zero (requested: $target, current: $currentStock).',
          );
        }
        clamped = true;
        requestedQuantity = stockDelta.abs();
        nextStock = 0;
      } else {
        nextStock = target;
      }
    }

    final targetReserved = currentReserved + reservedDelta;
    final nextReserved = targetReserved < 0 ? 0 : targetReserved;

    final targetIncoming = currentIncoming + incomingDelta;
    final nextIncoming = targetIncoming < 0 ? 0 : targetIncoming;

    final effectiveDelta = nextStock - currentStock;
    final now = timestamp ?? Timestamp.now();

    final productUpdates = <String, dynamic>{
      if (stockDelta != 0 || clamped) 'stockQuantity': nextStock,
      if (reservedDelta != 0) 'reservedQuantity': nextReserved,
      if (incomingDelta != 0) 'incomingQuantity': nextIncoming,
      'updatedAt': now,
    };

    final resolvedMovementId = (idempotencyKey != null && idempotencyKey.isNotEmpty)
        ? idempotencyKey.replaceAll('/', '_')
        : _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc().id;
    final productName = (data['productName'] as String?) ??
        (data['name'] as String?) ??
        'Product';
    final productSource = (data['productSource'] as String?) ??
        (productRef.parent.id == OTHER_PRODUCTS_COLLECTION_REF ? 'other' : 'selecta');

    final resolvedCostPrice = costPrice ?? (data['buyingPrice'] as num?)?.toDouble();
    final resolvedSellingPrice = sellingPrice ?? (data['sellingPrice'] as num?)?.toDouble();

    final movement = InventoryMovement(
      id: resolvedMovementId,
      productId: productRef.id,
      productName: productName,
      productSource: productSource,
      previousStock: currentStock,
      newStock: nextStock,
      delta: effectiveDelta,
      reason: reason ?? movementType.label,
      notes: notes,
      createdBy: actorName ?? 'System',
      createdAt: now,
      movementType: movementType,
      reasonCode: reasonCode,
      referenceType: referenceType,
      referenceId: referenceId,
      referenceLabel: referenceLabel,
      previousReserved: reservedDelta != 0 ? currentReserved : null,
      newReserved: reservedDelta != 0 ? nextReserved : null,
      previousIncoming: incomingDelta != 0 ? currentIncoming : null,
      newIncoming: incomingDelta != 0 ? nextIncoming : null,
      requestedQuantity: clamped ? requestedQuantity : null,
      clamped: clamped,
      actorUid: actorUid,
      actorRole: actorRole,
      actorName: actorName,
      source: 'app',
      deviceId: deviceId,
      appVersion: appVersion,
      batchId: batchId,
      correlationId: correlationId,
      idempotencyKey: idempotencyKey,
      sourceLocation: sourceLocation,
      targetLocation: targetLocation,
      isOverride: isOverride,
      overrideReason: overrideReason,
      costPrice: resolvedCostPrice,
      sellingPrice: resolvedSellingPrice,
      disposition: disposition,
      shortPickReason: shortPickReason,
      isBlind: isBlind,
      countRound: countRound,
      systemQuantityAtStart: systemQuantityAtStart,
    );

    return StockChangeRecord(
      movement: movement,
      productUpdates: productUpdates,
      clamped: clamped,
    );
  }

  /// Logs a discrepancy into `inventory_discrepancies` collection.
  Future<void> _recordDiscrepancy({
    required String productId,
    required String productName,
    required String productSource,
    required String type,
    required int expected,
    required int actual,
    required String details,
    String? movementId,
    String? batchId,
  }) async {
    try {
      await _firestore.collection('inventory_discrepancies').add({
        'productId': productId,
        'productName': productName,
        'productSource': productSource,
        'discrepancyType': type,
        'type': type,
        'expectedValue': expected,
        'expected': expected,
        'actualValue': actual,
        'actual': actual,
        'message': details,
        'details': details,
        'movementId': movementId,
        'batchId': batchId,
        'status': 'open',
        'detectedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error recording inventory discrepancy: $e');
    }
  }

  /// Temporarily reserves floating stock (`reservedQuantity`) when a new order is booked
  /// (`Pending Picklist`), preventing over-ordering before the picklist is completed.
  /// Logs an [InventoryMovement] audit entry with [MovementType.reserve].
  Future<void> reserveStockForOrder({
    required String storeName,
    required List<OrderItem> items,
    String? orderId,
  }) async {
    final validItems = items.where((i) => i.productId.isNotEmpty && i.pickedQuantity > 0).toList();
    if (validItems.isEmpty) return;
    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();
    final correlationId = 'order_${orderId ?? storeName}_${now.millisecondsSinceEpoch}';

    for (final chunk in _chunk(validItems, 100)) {
      final List<({String productId, String productName, String productSource, int requested, int available})> shortAllocations = [];

      await _runInventoryTransaction('reserveStockForOrder', (transaction) async {
        final productRefs = chunk.map((item) {
          final collectionName = _collectionForSource(item.productSource);
          return _firestore.collection(collectionName).doc(item.productId);
        }).toList();
        final movRefs = chunk.map((item) {
          final idKey = 'order_reserve_${orderId ?? storeName}_${item.productId}'.replaceAll('/', '_');
          return _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(idKey);
        }).toList();

        final productSnaps = await Future.wait(productRefs.map((r) => transaction.get(r)));
        final movSnaps = await Future.wait(movRefs.map((r) => transaction.get(r)));

        for (int i = 0; i < chunk.length; i++) {
          final snap = productSnaps[i];
          final movSnap = movSnaps[i];
          if (!snap.exists) continue;
          if (movSnap.exists) continue; // Idempotency check

          final item = chunk[i];
          final currentStock = (snap.data()?['stockQuantity'] as num?)?.toInt() ?? 0;
          final currentReserved = (snap.data()?['reservedQuantity'] as num?)?.toInt() ?? 0;
          final availableAtMoment = currentStock - currentReserved;

          final isShort = availableAtMoment < item.pickedQuantity;
          if (isShort) {
            shortAllocations.add((
              productId: snap.id,
              productName: (snap.data()?['productName'] as String?) ?? item.productName,
              productSource: item.productSource,
              requested: item.pickedQuantity,
              available: availableAtMoment > 0 ? availableAtMoment : 0,
            ));
          }

          final change = _computeStockChange(
            productRef: snap.reference,
            productSnap: snap,
            stockDelta: 0,
            reservedDelta: item.pickedQuantity,
            movementType: MovementType.reserve,
            referenceType: ReferenceType.order,
            referenceId: orderId,
            referenceLabel: storeName,
            correlationId: correlationId,
            idempotencyKey: movRefs[i].id,
            sourceLocation: 'warehouse',
            targetLocation: 'reserved',
            reason: 'Order Booked (Reserved Stock)',
            notes: 'Store: $storeName (Reserved: +${item.pickedQuantity}${isShort ? " [Short Allocation: Avail $availableAtMoment]" : ""})',
            actorUid: actor.uid,
            actorRole: actor.role,
            actorName: actor.name,
            appVersion: appVersion,
            timestamp: now,
          );

          transaction.update(snap.reference, change.productUpdates);
          transaction.set(movRefs[i], change.movement.toJson());
        }
      });

      for (final s in shortAllocations) {
        _recordDiscrepancy(
          productId: s.productId,
          productName: s.productName,
          productSource: s.productSource,
          type: 'short_allocation',
          expected: s.requested,
          actual: s.available,
          details: 'Order booking short allocation for $storeName: requested ${s.requested}, available ${s.available}.',
        );
      }
    }
  }

  /// Adjusts floating stock (`reservedQuantity`) when an order in `Pending Picklist`
  /// has its quantities or items updated prior to picklist completion.
  /// Logs an [InventoryMovement] audit entry.
  Future<void> adjustReservedStockForOrderUpdate({
    required String storeName,
    required List<OrderItem> oldItems,
    required List<OrderItem> newItems,
    String? orderId,
  }) async {
    final Map<String, ({String source, String productId, int delta})> deltas = {};

    for (final oldItem in oldItems) {
      if (oldItem.productId.isEmpty) continue;
      final key = '${oldItem.productSource}:${oldItem.productId}';
      final prev = deltas[key];
      deltas[key] = (
        source: oldItem.productSource,
        productId: oldItem.productId,
        delta: (prev?.delta ?? 0) - oldItem.pickedQuantity,
      );
    }

    for (final newItem in newItems) {
      if (newItem.productId.isEmpty) continue;
      final key = '${newItem.productSource}:${newItem.productId}';
      final prev = deltas[key];
      deltas[key] = (
        source: newItem.productSource,
        productId: newItem.productId,
        delta: (prev?.delta ?? 0) + newItem.pickedQuantity,
      );
    }

    final activeEntries = deltas.values.where((e) => e.delta != 0).toList();
    if (activeEntries.isEmpty) return;

    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();

    for (final chunk in _chunk(activeEntries, 100)) {
      await _runInventoryTransaction('adjustReservedStockForOrderUpdate', (transaction) async {
        final productRefs = chunk.map((entry) {
          final collectionName = _collectionForSource(entry.source);
          return _firestore.collection(collectionName).doc(entry.productId);
        }).toList();
        final movRefs = chunk.map((entry) {
          final idKey = 'order_adj_reserve_${orderId ?? storeName}_${entry.productId}_${now.millisecondsSinceEpoch}'.replaceAll('/', '_');
          return _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(idKey);
        }).toList();

        final productSnaps = await Future.wait(productRefs.map((r) => transaction.get(r)));
        final movSnaps = await Future.wait(movRefs.map((r) => transaction.get(r)));

        for (int i = 0; i < chunk.length; i++) {
          final snap = productSnaps[i];
          final movSnap = movSnaps[i];
          if (!snap.exists) continue;
          if (movSnap.exists) continue;

          final entry = chunk[i];
          final delta = entry.delta;

          final change = _computeStockChange(
            productRef: snap.reference,
            productSnap: snap,
            stockDelta: 0,
            reservedDelta: delta,
            movementType: delta > 0 ? MovementType.reserve : MovementType.release,
            referenceType: ReferenceType.order,
            referenceId: orderId,
            referenceLabel: storeName,
            idempotencyKey: movRefs[i].id,
            reason: delta > 0
                ? 'Order Updated (Reserved Stock Increased)'
                : 'Order Updated (Reserved Stock Released)',
            notes: 'Store: $storeName (${delta > 0 ? "+$delta" : "$delta"} reserved)',
            actorUid: actor.uid,
            actorRole: actor.role,
            actorName: actor.name,
            appVersion: appVersion,
            timestamp: now,
          );

          transaction.update(snap.reference, change.productUpdates);
          transaction.set(movRefs[i], change.movement.toJson());
        }
      });
    }
  }

  /// Releases floating stock (`reservedQuantity`) when a `Pending Picklist` order is deleted/cancelled.
  /// Logs an [InventoryMovement] audit entry with [MovementType.release].
  Future<void> releaseReservedStockForOrder({
    required String storeName,
    required List<OrderItem> items,
    String? orderId,
  }) async {
    final validItems = items.where((i) => i.productId.isNotEmpty && i.pickedQuantity > 0).toList();
    if (validItems.isEmpty) return;
    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();

    for (final chunk in _chunk(validItems, 100)) {
      await _runInventoryTransaction('releaseReservedStockForOrder', (transaction) async {
        final productRefs = chunk.map((item) {
          final collectionName = _collectionForSource(item.productSource);
          return _firestore.collection(collectionName).doc(item.productId);
        }).toList();
        final movRefs = chunk.map((item) {
          final idKey = 'order_release_${orderId ?? storeName}_${item.productId}'.replaceAll('/', '_');
          return _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(idKey);
        }).toList();

        final productSnaps = await Future.wait(productRefs.map((r) => transaction.get(r)));
        final movSnaps = await Future.wait(movRefs.map((r) => transaction.get(r)));

        for (int i = 0; i < chunk.length; i++) {
          final snap = productSnaps[i];
          final movSnap = movSnaps[i];
          if (!snap.exists) continue;
          if (movSnap.exists) continue;

          final item = chunk[i];

          final change = _computeStockChange(
            productRef: snap.reference,
            productSnap: snap,
            stockDelta: 0,
            reservedDelta: -item.pickedQuantity,
            movementType: MovementType.release,
            referenceType: ReferenceType.order,
            referenceId: orderId,
            referenceLabel: storeName,
            idempotencyKey: movRefs[i].id,
            reason: 'Order Cancelled (Reservation Released)',
            notes: 'Store: $storeName (Released: -${item.pickedQuantity})',
            actorUid: actor.uid,
            actorRole: actor.role,
            actorName: actor.name,
            appVersion: appVersion,
            timestamp: now,
          );

          transaction.update(snap.reference, change.productUpdates);
          transaction.set(movRefs[i], change.movement.toJson());
        }
      });
    }
  }

  /// Reverses stock deductions and/or releases floating stock when an order is deleted.
  /// Used by Admin test deletions to ensure warehouse inventory balances are restored cleanly.
  Future<void> reverseStockForDeletedOrder({
    required String storeName,
    required List<OrderItem> items,
    required bool wasDeducted,
    required bool wasReserved,
    String? orderId,
  }) async {
    final validItems = items.where((i) => i.productId.isNotEmpty).toList();
    if (validItems.isEmpty) return;
    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();

    for (final chunk in _chunk(validItems, 100)) {
      await _runInventoryTransaction('reverseStockForDeletedOrder', (transaction) async {
        final productRefs = chunk.map((item) {
          final collectionName = _collectionForSource(item.productSource);
          return _firestore.collection(collectionName).doc(item.productId);
        }).toList();
        final movRefs = chunk.map((item) {
          final idKey = 'order_delete_rev_${orderId ?? storeName}_${item.productId}'.replaceAll('/', '_');
          return _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(idKey);
        }).toList();

        final productSnaps = await Future.wait(productRefs.map((r) => transaction.get(r)));
        final movSnaps = await Future.wait(movRefs.map((r) => transaction.get(r)));

        for (int i = 0; i < chunk.length; i++) {
          final snap = productSnaps[i];
          final movSnap = movSnaps[i];
          if (!snap.exists) continue;
          if (movSnap.exists) continue;

          final item = chunk[i];
          final orderedQty = item.effectiveQuantity;
          final diff = orderedQty - item.returnedQuantity;
          final int netDeductedQty = diff < 0 ? 0 : diff;

          final stockDelta = (wasDeducted && netDeductedQty > 0) ? netDeductedQty : 0;
          final reservedDelta = (wasReserved && !wasDeducted && orderedQty > 0) ? -orderedQty : 0;

          if (stockDelta == 0 && reservedDelta == 0) continue;

          final change = _computeStockChange(
            productRef: snap.reference,
            productSnap: snap,
            stockDelta: stockDelta,
            reservedDelta: reservedDelta,
            movementType: MovementType.reversal,
            referenceType: ReferenceType.order,
            referenceId: orderId,
            referenceLabel: storeName,
            idempotencyKey: movRefs[i].id,
            reason: 'Admin Delete Order Reversal',
            notes: 'Restored stock for deleted order [$storeName]',
            actorUid: actor.uid,
            actorRole: actor.role,
            actorName: actor.name,
            appVersion: appVersion,
            timestamp: now,
          );

          transaction.update(snap.reference, change.productUpdates);
          transaction.set(movRefs[i], change.movement.toJson());
        }
      });
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
    String? deliveryId,
  }) async {
    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();
    final List<StockChangeRecord> clampedRecords = [];

    final Map<String, ({String source, String productId, int reservedQty, int pickedQty})> itemMap = {};
    if (wasReserved) {
      for (final r in reservedItems) {
        if (r.productId.isEmpty) continue;
        final key = '${r.productSource}:${r.productId}';
        final prev = itemMap[key];
        itemMap[key] = (
          source: r.productSource,
          productId: r.productId,
          reservedQty: (prev?.reservedQty ?? 0) + r.pickedQuantity,
          pickedQty: prev?.pickedQty ?? 0,
        );
      }
    }

    for (final p in pickedItems) {
      if (p.productId.isEmpty) continue;
      final key = '${p.productSource}:${p.productId}';
      final prev = itemMap[key];
      itemMap[key] = (
        source: p.productSource,
        productId: p.productId,
        reservedQty: prev?.reservedQty ?? 0,
        pickedQty: (prev?.pickedQty ?? 0) + p.pickedQuantity,
      );
    }

    final activeEntries = itemMap.values.where((e) => e.reservedQty > 0 || e.pickedQty > 0).toList();
    if (activeEntries.isEmpty) return;

    for (final chunk in _chunk(activeEntries, 100)) {
      await _runInventoryTransaction('confirmPicklistAndDeductStock', (transaction) async {
        final productRefs = chunk.map((entry) {
          final collectionName = _collectionForSource(entry.source);
          return _firestore.collection(collectionName).doc(entry.productId);
        }).toList();
        final movRefs = chunk.map((entry) {
          final idKey = 'picklist_deduct_${deliveryId ?? storeName}_${entry.productId}'.replaceAll('/', '_');
          return _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(idKey);
        }).toList();

        final productSnaps = await Future.wait(productRefs.map((r) => transaction.get(r)));
        final movSnaps = await Future.wait(movRefs.map((r) => transaction.get(r)));

        for (int i = 0; i < chunk.length; i++) {
          final snap = productSnaps[i];
          final movSnap = movSnaps[i];
          if (!snap.exists) continue;
          if (movSnap.exists) continue;

          final entry = chunk[i];

          final change = _computeStockChange(
            productRef: snap.reference,
            productSnap: snap,
            stockDelta: -entry.pickedQty,
            reservedDelta: -entry.reservedQty,
            movementType: MovementType.pick,
            referenceType: ReferenceType.picklist,
            referenceId: deliveryId,
            referenceLabel: storeName,
            idempotencyKey: movRefs[i].id,
            reason: 'Picklist Completed (For Delivery)',
            notes: 'Store: $storeName (Picked: ${entry.pickedQty})',
            allowClamping: true,
            actorUid: actor.uid,
            actorRole: actor.role,
            actorName: actor.name,
            appVersion: appVersion,
            timestamp: now,
          );

          transaction.update(snap.reference, change.productUpdates);
          transaction.set(movRefs[i], change.movement.toJson());

          if (change.clamped) {
            clampedRecords.add(change);
          }
        }
      });
    }

    for (final rec in clampedRecords) {
      _recordDiscrepancy(
        productId: rec.movement.productId,
        productName: rec.movement.productName,
        productSource: rec.movement.productSource,
        type: 'clamped_negative_stock',
        expected: rec.movement.previousStock,
        actual: 0,
        details: 'Picklist stock deduction clamped to 0. Requested: ${rec.movement.requestedQuantity}, available: ${rec.movement.previousStock}. Store: $storeName',
        movementId: rec.movement.id,
      );
    }
  }

  /// Deducts warehouse stock when dealer confirms a Van Load manifest.
  /// Logs an [InventoryMovement] audit entry with reason 'Van Load'.
  Future<void> deductVanLoadInventory({
    required String vanLoadId,
    required List<VanLoadItem> items,
    String? driverName,
  }) async {
    final validItems = items.where((i) => i.productId.isNotEmpty && i.loadedQuantity > 0).toList();
    if (validItems.isEmpty) return;
    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();
    final List<StockChangeRecord> clampedRecords = [];

    for (final chunk in _chunk(validItems, 100)) {
      await _runInventoryTransaction('deductVanLoadInventory', (transaction) async {
        final productRefs = chunk.map((item) {
          final collectionName = _collectionForSource(item.productSource);
          return _firestore.collection(collectionName).doc(item.productId);
        }).toList();
        final movRefs = chunk.map((item) {
          final idKey = 'van_load_deduct_${vanLoadId}_${item.productId}'.replaceAll('/', '_');
          return _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(idKey);
        }).toList();

        final productSnaps = await Future.wait(productRefs.map((r) => transaction.get(r)));
        final movSnaps = await Future.wait(movRefs.map((r) => transaction.get(r)));

        for (int i = 0; i < chunk.length; i++) {
          final snap = productSnaps[i];
          final movSnap = movSnaps[i];
          if (!snap.exists) continue;
          if (movSnap.exists) continue;

          final item = chunk[i];

          final change = _computeStockChange(
            productRef: snap.reference,
            productSnap: snap,
            stockDelta: -item.loadedQuantity,
            movementType: MovementType.van_load,
            referenceType: ReferenceType.van_load,
            referenceId: vanLoadId,
            referenceLabel: driverName != null ? 'Van Load: $driverName' : 'Van Load #$vanLoadId',
            idempotencyKey: movRefs[i].id,
            reason: 'Van Load',
            notes: 'Van Load #$vanLoadId${driverName != null ? ' ($driverName)' : ''}',
            allowClamping: true,
            actorUid: actor.uid,
            actorRole: actor.role,
            actorName: actor.name,
            appVersion: appVersion,
            timestamp: now,
          );

          transaction.update(snap.reference, change.productUpdates);
          transaction.set(movRefs[i], change.movement.toJson());

          if (change.clamped) {
            clampedRecords.add(change);
          }
        }
      });
    }

    for (final rec in clampedRecords) {
      _recordDiscrepancy(
        productId: rec.movement.productId,
        productName: rec.movement.productName,
        productSource: rec.movement.productSource,
        type: 'clamped_negative_stock',
        expected: rec.movement.previousStock,
        actual: 0,
        details: 'Van load deduction clamped to 0. Requested: ${rec.movement.requestedQuantity}, available: ${rec.movement.previousStock}. Van Load: $vanLoadId',
        movementId: rec.movement.id,
      );
    }
  }

  /// Replenishes warehouse stock when unsold items from a Van Load are returned at EOD.
  /// Logs an [InventoryMovement] audit entry with reason 'Van Return'.
  Future<void> returnVanLoadInventory({
    required String vanLoadId,
    required List<VanLoadItem> returnedItems,
    String? driverName,
  }) async {
    final validItems = returnedItems.where((i) => i.productId.isNotEmpty && i.returnedQuantity > 0).toList();
    if (validItems.isEmpty) return;
    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();

    for (final chunk in _chunk(validItems, 100)) {
      await _runInventoryTransaction('returnVanLoadInventory', (transaction) async {
        final productRefs = chunk.map((item) {
          final collectionName = _collectionForSource(item.productSource);
          return _firestore.collection(collectionName).doc(item.productId);
        }).toList();
        final movRefs = chunk.map((item) {
          final idKey = 'van_return_${vanLoadId}_${item.productId}'.replaceAll('/', '_');
          return _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(idKey);
        }).toList();

        final productSnaps = await Future.wait(productRefs.map((r) => transaction.get(r)));
        final movSnaps = await Future.wait(movRefs.map((r) => transaction.get(r)));

        for (int i = 0; i < chunk.length; i++) {
          final snap = productSnaps[i];
          final movSnap = movSnaps[i];
          if (!snap.exists) continue;
          if (movSnap.exists) continue;

          final item = chunk[i];

          final change = _computeStockChange(
            productRef: snap.reference,
            productSnap: snap,
            stockDelta: item.returnedQuantity,
            movementType: MovementType.van_return,
            referenceType: ReferenceType.van_load,
            referenceId: vanLoadId,
            referenceLabel: driverName != null ? 'Van Return: $driverName' : 'Van Return #$vanLoadId',
            idempotencyKey: movRefs[i].id,
            reason: 'Van Return',
            notes: 'Returned from Van Load #$vanLoadId',
            actorUid: actor.uid,
            actorRole: actor.role,
            actorName: actor.name,
            appVersion: appVersion,
            timestamp: now,
          );

          transaction.update(snap.reference, change.productUpdates);
          transaction.set(movRefs[i], change.movement.toJson());
        }
      });
    }
  }

  /// Atomically completes a picklist inside a Firestore transaction:
  /// 1. Idempotency Check: Verifies the delivery record is still in `picklist` status and `isInventoryDeducted == false`.
  ///    If already processed or deducted, throws an Exception to prevent double-processing.
  /// 2. Reads all affected product documents.
  /// 3. Deducts physical `stockQuantity` and releases `reservedQuantity` for each picked product.
  /// 4. Creates `InventoryMovement` audit log records.
  /// 5. Updates the `deliveries` document to `DeliveryStatus.pending` with `isInventoryDeducted = true`.
  /// 6. Saves placement record if provided.
  ///
  /// Everything is executed inside `_firestore.runTransaction` — All or Nothing.
  Future<void> completePicklistAtomicTransaction({
    required String deliveryId,
    required Delivery updatedDelivery,
    required List<OrderItem> reservedItems,
    required List<OrderItem> pickedItems,
    required bool wasReserved,
    Placement? placement,
    Map<String, ShortPickReason>? shortPickReasons,
  }) async {
    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();
    final correlationId = 'picklist_$deliveryId';

    await _firestore.runTransaction((transaction) async {
      // 1. Idempotency & Concurrency check: read latest delivery document
      final deliveryRef = _firestore.collection(DELIVERY_COLLECTION_REF).doc(deliveryId);
      final deliverySnap = await transaction.get(deliveryRef);
      if (!deliverySnap.exists) {
        throw Exception('Delivery record "$deliveryId" not found.');
      }
      final deliveryData = deliverySnap.data() ?? {};
      final isDeducted = deliveryData['isInventoryDeducted'] as bool? ?? false;
      final status = deliveryData['transactionStatus'] as String? ?? '';
      if (isDeducted || status == DeliveryStatus.pending || status == DeliveryStatus.delivered) {
        throw Exception('This picklist has already been processed or marked For Delivery.');
      }

      // Map reserved and picked quantities by product
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

      // 2. Read all affected product docs (Firestore transactions require all reads before writes)
      final Map<String, DocumentSnapshot<Map<String, dynamic>>> productSnaps = {};
      for (final item in merged.values) {
        final collectionName = _collectionForSource(item.source);
        final productRef = _firestore.collection(collectionName).doc(item.id);
        final snap = await transaction.get(productRef);
        productSnaps['${item.source}:${item.id}'] = snap;
      }

      // 3. Stage product stock updates and movement logs
      final List<StockChangeRecord> clampedRecords = [];
      final List<({String id, String name, String source, int req, int picked, ShortPickReason reason})> shortPicks = [];

      for (final item in merged.values) {
        final key = '${item.source}:${item.id}';
        final snap = productSnaps[key];
        if (snap == null || !snap.exists) continue;

        final isShort = wasReserved && item.reservedQty > 0 && item.pickedQty < item.reservedQty;
        final ShortPickReason? spr = isShort ? (shortPickReasons?[item.id] ?? ShortPickReason.out_of_stock) : null;

        if (isShort) {
          shortPicks.add((
            id: item.id,
            name: item.name,
            source: item.source,
            req: item.reservedQty,
            picked: item.pickedQty,
            reason: spr ?? ShortPickReason.out_of_stock,
          ));
        }

        final change = _computeStockChange(
          productRef: snap.reference,
          productSnap: snap,
          stockDelta: -item.pickedQty,
          reservedDelta: -item.reservedQty,
          movementType: MovementType.pick,
          referenceType: ReferenceType.picklist,
          referenceId: deliveryId,
          referenceLabel: updatedDelivery.storeName,
          correlationId: correlationId,
          idempotencyKey: 'picklist_${deliveryId}_${item.id}',
          sourceLocation: 'warehouse',
          targetLocation: 'van',
          shortPickReason: spr,
          reason: isShort ? 'Picklist Short-Pick (${spr?.label ?? "Short"})' : 'Picklist Completed (For Delivery)',
          notes: 'Store: ${updatedDelivery.storeName} (Picked: ${item.pickedQty}${isShort ? ", Short: ${item.reservedQty - item.pickedQty} [${spr?.label}]" : ""})',
          allowClamping: true,
          actorUid: actor.uid,
          actorRole: actor.role,
          actorName: actor.name,
          appVersion: appVersion,
          timestamp: now,
        );

        transaction.update(snap.reference, change.productUpdates);

        if (item.pickedQty > 0 || change.clamped || isShort) {
          final movRef = _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(change.movement.id);
          transaction.set(movRef, change.movement.toJson());
        }

        if (change.clamped) {
          clampedRecords.add(change);
        }
      }

      // 4. Stage delivery document update
      transaction.update(deliveryRef, updatedDelivery.toJson());

      // 5. Stage placement update if provided
      if (placement != null) {
        final pId = placement.id.isNotEmpty ? placement.id : deliveryId;
        final placementRef = _firestore.collection(PLACEMENT_COLLECTION_REF).doc(pId);
        transaction.set(placementRef, placement.toJson(), SetOptions(merge: true));
      }

      // 6. Record discrepancies if any clamped deductions occurred
      for (final rec in clampedRecords) {
        _recordDiscrepancy(
          productId: rec.movement.productId,
          productName: rec.movement.productName,
          productSource: rec.movement.productSource,
          type: 'clamped_negative_stock',
          expected: rec.movement.previousStock,
          actual: 0,
          details: 'Picklist stock deduction clamped to 0 for delivery $deliveryId (${updatedDelivery.storeName}). Requested: ${rec.movement.requestedQuantity}, available: ${rec.movement.previousStock}.',
          movementId: rec.movement.id,
        );
      }

      // 7. Record short pick discrepancies & flag for cycle count
      for (final sp in shortPicks) {
        _recordDiscrepancy(
          productId: sp.id,
          productName: sp.name,
          productSource: sp.source,
          type: 'short_pick',
          expected: sp.req,
          actual: sp.picked,
          details: 'Short-pick on picklist for ${updatedDelivery.storeName}: required ${sp.req}, picked ${sp.picked} (Reason: ${sp.reason.label}). Flagged for physical count.',
        );
      }
    });
  }

  /// Updates the stock quantity (and optionally lowStockThreshold and maxStock) of a product
  /// and records an [InventoryMovement] entry in `inventory_movements`.
  /// Manual adjustments that would result in negative stock are rejected with an [ArgumentError].
  /// Updates the stock quantity (and optionally lowStockThreshold and maxStock) of a product
  /// and records an [InventoryMovement] entry in `inventory_movements`.
  /// Manual adjustments that would result in negative stock are rejected with an [ArgumentError].
  /// Adjustments above the configured unit approval threshold require dealer approval.
  Future<InventoryPendingAdjustment?> updateStock({
    required InventoryItem item,
    required int newStockQuantity,
    int? newLowStockThreshold,
    int? newMaxStock,
    required String reason,
    String notes = '',
    ReasonCode? reasonCode,
    ReferenceType? referenceType,
    String? referenceId,
    bool bypassThreshold = false,
  }) async {
    if (newStockQuantity < 0) {
      throw ArgumentError('Stock cannot be set to a negative value ($newStockQuantity).');
    }

    final actor = await _resolveActor();
    if (actor.role.toLowerCase() != 'dealer' && actor.role.toLowerCase() != 'superadmin') {
      throw StateError('Unauthorized: Only users with Dealer privileges may perform manual inventory adjustments.');
    }

    final currentStock = item.stockQuantity;
    final stockDelta = newStockQuantity - currentStock;
    final threshold = await _resolveUnitApprovalThreshold();

    if (!bypassThreshold && stockDelta.abs() > threshold) {
      return await submitPendingAdjustment(
        item: item,
        requestedStock: newStockQuantity,
        previousStock: currentStock,
        delta: stockDelta,
        reason: reason,
        notes: notes,
        reasonCode: reasonCode,
        actor: actor,
      );
    }

    final thresholdVal = (newLowStockThreshold ?? item.lowStockThreshold) < 0
        ? 0
        : (newLowStockThreshold ?? item.lowStockThreshold);
    final maxStockVal = (newMaxStock ?? item.maxStock) < 0
        ? 0
        : (newMaxStock ?? item.maxStock);

    final collectionName = item.source == InventoryProductSource.selecta
        ? SELECTA_PRODUCTS_COLLECTION_REF
        : OTHER_PRODUCTS_COLLECTION_REF;

    final appVersion = await _resolveAppVersion();
    final now = Timestamp.now();

    await _runInventoryTransaction('updateStock', (transaction) async {
      final productRef = _firestore.collection(collectionName).doc(item.id);
      final snap = await transaction.get(productRef);
      if (!snap.exists) {
        throw Exception('Product "${item.productName}" not found.');
      }

      final data = snap.data() ?? {};
      final latestStock = (data['stockQuantity'] as num?)?.toInt() ?? 0;
      final effectiveDelta = newStockQuantity - latestStock;

      final change = _computeStockChange(
        productRef: productRef,
        productSnap: snap,
        stockDelta: effectiveDelta,
        movementType: MovementType.adjustment,
        reasonCode: reasonCode,
        referenceType: referenceType ?? ReferenceType.manual,
        referenceId: referenceId,
        reason: reason.trim().isEmpty ? 'Manual Adjustment' : reason.trim(),
        notes: notes.trim(),
        allowClamping: false,
        actorUid: actor.uid,
        actorRole: actor.role,
        actorName: actor.name,
        appVersion: appVersion,
        timestamp: now,
      );

      final payload = Map<String, dynamic>.from(change.productUpdates);
      payload['lowStockThreshold'] = thresholdVal;
      if (item.source == InventoryProductSource.selecta) {
        payload['maxStock'] = maxStockVal;
      }

      transaction.update(productRef, payload);

      if (effectiveDelta != 0) {
        final movRef = _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(change.movement.id);
        transaction.set(movRef, change.movement.toJson());
      }
    });

    return null;
  }

  /// Submits an adjustment request that exceeds the threshold to `inventory_pending_adjustments`.
  Future<InventoryPendingAdjustment> submitPendingAdjustment({
    required InventoryItem item,
    required int requestedStock,
    required int previousStock,
    required int delta,
    required String reason,
    String notes = '',
    ReasonCode? reasonCode,
    ({String uid, String role, String name})? actor,
  }) async {
    final effectiveActor = actor ?? await _resolveActor();
    final docRef = _firestore.collection('inventory_pending_adjustments').doc();
    final pending = InventoryPendingAdjustment(
      id: docRef.id,
      productId: item.id,
      productName: item.productName,
      productSource: item.productSource,
      previousStock: previousStock,
      requestedStock: requestedStock,
      delta: delta,
      reason: reason,
      notes: notes,
      reasonCode: reasonCode,
      requestedByUid: effectiveActor.uid,
      requestedByName: effectiveActor.name,
      requestedAt: DateTime.now(),
      status: 'pending',
    );
    await docRef.set(pending.toJson());
    return pending;
  }

  /// Real-time stream of all pending adjustments awaiting dealer authorization.
  Stream<List<InventoryPendingAdjustment>> getPendingAdjustmentsStream() {
    return _firestore
        .collection('inventory_pending_adjustments')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.map((d) => InventoryPendingAdjustment.fromJson(d.id, d.data())).toList());
  }

  /// Approves a pending adjustment, applies the physical stock delta, and logs an audited movement.
  Future<void> approvePendingAdjustment(String adjustmentId) async {
    final actor = await _resolveActor();
    if (actor.role.toLowerCase() != 'dealer' && actor.role.toLowerCase() != 'superadmin') {
      throw StateError('Unauthorized: Only dealers may approve pending adjustments.');
    }

    final adjRef = _firestore.collection('inventory_pending_adjustments').doc(adjustmentId);
    final adjSnap = await adjRef.get();
    if (!adjSnap.exists) {
      throw Exception('Pending adjustment #$adjustmentId not found.');
    }
    final pending = InventoryPendingAdjustment.fromJson(adjSnap.id, adjSnap.data()!);
    if (!pending.isPending) {
      throw Exception('Pending adjustment #$adjustmentId is already ${pending.status}.');
    }

    final collectionName = pending.productSource == 'other'
        ? OTHER_PRODUCTS_COLLECTION_REF
        : SELECTA_PRODUCTS_COLLECTION_REF;
    final productRef = _firestore.collection(collectionName).doc(pending.productId);

    await _runInventoryTransaction('approvePendingAdjustment', (transaction) async {
      final pSnap = await transaction.get(productRef);
      if (!pSnap.exists) throw Exception('Product "${pending.productName}" not found.');
      final currentStock = (pSnap.data()?['stockQuantity'] as num?)?.toInt() ?? 0;
      final targetDelta = pending.requestedStock - currentStock;

      final change = _computeStockChange(
        productRef: productRef,
        productSnap: pSnap,
        stockDelta: targetDelta,
        movementType: MovementType.adjustment,
        reasonCode: pending.reasonCode,
        referenceType: ReferenceType.manual,
        referenceId: pending.id,
        referenceLabel: 'Approved Pending Adj #${pending.id.substring(0, 8.clamp(0, pending.id.length))}',
        reason: 'Approved Adjustment: ${pending.reason}',
        notes: '${pending.notes} (Approved by ${actor.name})',
        isOverride: true,
        overrideReason: 'Large adjustment approved by dealer',
        actorUid: actor.uid,
        actorRole: actor.role,
        actorName: actor.name,
      );

      transaction.update(productRef, change.productUpdates);
      final movRef = _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(change.movement.id);
      transaction.set(movRef, change.movement.toJson());
      transaction.update(adjRef, {
        'status': 'approved',
        'reviewedByUid': actor.uid,
        'reviewedByName': actor.name,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Rejects a pending adjustment.
  Future<void> rejectPendingAdjustment(String adjustmentId, {String? reason}) async {
    final actor = await _resolveActor();
    if (actor.role.toLowerCase() != 'dealer' && actor.role.toLowerCase() != 'superadmin') {
      throw StateError('Unauthorized: Only dealers may reject pending adjustments.');
    }
    await _firestore.collection('inventory_pending_adjustments').doc(adjustmentId).update({
      'status': 'rejected',
      'reviewedByUid': actor.uid,
      'reviewedByName': actor.name,
      'reviewedAt': FieldValue.serverTimestamp(),
      if (reason != null) 'rejectionReason': reason.trim(),
    });
  }

  /// Quick adjustment helper that applies a positive or negative delta to an item's stock.
  /// Rejects any change that would cause stock to go below zero.
  Future<void> adjustStockByDelta({
    required InventoryItem item,
    required int delta,
    String reason = 'Manual Adjustment',
    ReasonCode reasonCode = ReasonCode.count_correction,
    String notes = '',
  }) async {
    final collectionName = item.source == InventoryProductSource.selecta
        ? SELECTA_PRODUCTS_COLLECTION_REF
        : OTHER_PRODUCTS_COLLECTION_REF;

    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();
    final now = Timestamp.now();

    await _firestore.runTransaction((transaction) async {
      final productRef = _firestore.collection(collectionName).doc(item.id);
      final snap = await transaction.get(productRef);
      if (!snap.exists) {
        throw Exception('Product "${item.productName}" not found.');
      }

      final change = _computeStockChange(
        productRef: productRef,
        productSnap: snap,
        stockDelta: delta,
        movementType: MovementType.adjustment,
        reasonCode: reasonCode,
        referenceType: ReferenceType.manual,
        reason: reason,
        notes: notes,
        allowClamping: false,
        actorUid: actor.uid,
        actorRole: actor.role,
        actorName: actor.name,
        appVersion: appVersion,
        timestamp: now,
      );

      transaction.update(productRef, change.productUpdates);

      if (change.movement.hasPhysicalStockChange) {
        final movRef = _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(change.movement.id);
        transaction.set(movRef, change.movement.toJson());
      }
    });
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
        .snapshots()
        .map((snap) {
          final list = snap.docs.map(InventoryMovement.fromSnapshot).toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          if (limit > 0 && list.length > limit) {
            return list.sublist(0, limit);
          }
          return list;
        });
  }

  /// Replenishes inventory stock for items received in a Purchase Order.
  /// Increments physical `stockQuantity` and logs an [InventoryMovement] audit entry for each product.
  Future<void> replenishStockForPurchaseOrder({
    required String invoiceNumber,
    required DateTime orderDate,
    required List<OrderItem> items,
    String? poId,
  }) async {
    final validItems = items.where((i) => i.productId.isNotEmpty && i.effectiveQuantity > 0).toList();
    if (validItems.isEmpty) return;
    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();
    final invoiceRef = invoiceNumber.trim().isNotEmpty
        ? invoiceNumber.trim()
        : 'PO-${DateFormat('yyyyMMdd').format(orderDate)}';

    for (final chunk in _chunk(validItems, 100)) {
      await _runInventoryTransaction('replenishStockForPurchaseOrder', (transaction) async {
        final productRefs = chunk.map((item) {
          final collectionName = _collectionForSource(item.productSource);
          return _firestore.collection(collectionName).doc(item.productId);
        }).toList();
        final movRefs = chunk.map((item) {
          final idKey = 'po_replenish_${poId ?? invoiceRef}_${item.productId}'.replaceAll('/', '_');
          return _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(idKey);
        }).toList();

        final productSnaps = await Future.wait(productRefs.map((r) => transaction.get(r)));
        final movSnaps = await Future.wait(movRefs.map((r) => transaction.get(r)));

        for (int i = 0; i < chunk.length; i++) {
          final snap = productSnaps[i];
          final movSnap = movSnaps[i];
          if (!snap.exists) continue;
          if (movSnap.exists) continue;

          final item = chunk[i];
          final qty = item.effectiveQuantity;

          final change = _computeStockChange(
            productRef: snap.reference,
            productSnap: snap,
            stockDelta: qty,
            movementType: MovementType.receipt,
            referenceType: ReferenceType.purchase_order,
            referenceId: poId ?? invoiceRef,
            referenceLabel: invoiceRef,
            idempotencyKey: movRefs[i].id,
            reason: 'Purchase Order Replenishment',
            notes: 'PO Ref: $invoiceRef (Qty: +$qty)',
            actorUid: actor.uid,
            actorRole: actor.role,
            actorName: actor.name,
            appVersion: appVersion,
            timestamp: now,
          );

          transaction.update(snap.reference, change.productUpdates);
          transaction.set(movRefs[i], change.movement.toJson());
        }
      });
    }
  }

  /// Adjusts stock when an already-replenished Purchase Order is edited.
  Future<void> adjustReplenishedStockForPurchaseOrder({
    required String invoiceNumber,
    required DateTime orderDate,
    required List<OrderItem> oldItems,
    required List<OrderItem> newItems,
    String? poId,
  }) async {
    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();
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
    final List<({String source, String productId, int delta})> diffs = [];

    for (final key in allKeys) {
      final parts = key.split(':');
      if (parts.length != 2) continue;
      final source = parts[0];
      final productId = parts[1];

      final oldQty = oldQtyByKey[key] ?? 0;
      final newQty = newQtyByKey[key] ?? 0;
      final delta = newQty - oldQty;
      if (delta != 0) {
        diffs.add((source: source, productId: productId, delta: delta));
      }
    }

    if (diffs.isEmpty) return;

    for (final chunk in _chunk(diffs, 100)) {
      await _runInventoryTransaction('adjustReplenishedStockForPurchaseOrder', (transaction) async {
        final productRefs = chunk.map((entry) {
          final collectionName = _collectionForSource(entry.source);
          return _firestore.collection(collectionName).doc(entry.productId);
        }).toList();
        final movRefs = chunk.map((entry) {
          final idKey = 'po_adj_replenish_${poId ?? invoiceRef}_${entry.productId}_${now.millisecondsSinceEpoch}'.replaceAll('/', '_');
          return _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(idKey);
        }).toList();

        final productSnaps = await Future.wait(productRefs.map((r) => transaction.get(r)));
        final movSnaps = await Future.wait(movRefs.map((r) => transaction.get(r)));

        for (int i = 0; i < chunk.length; i++) {
          final snap = productSnaps[i];
          final movSnap = movSnaps[i];
          if (!snap.exists) continue;
          if (movSnap.exists) continue;

          final entry = chunk[i];
          final delta = entry.delta;

          final change = _computeStockChange(
            productRef: snap.reference,
            productSnap: snap,
            stockDelta: delta,
            movementType: MovementType.receipt,
            referenceType: ReferenceType.purchase_order,
            referenceId: poId ?? invoiceRef,
            referenceLabel: invoiceRef,
            idempotencyKey: movRefs[i].id,
            reason: 'Purchase Order Adjustment',
            notes: 'PO Ref: $invoiceRef (${delta > 0 ? "+$delta" : "$delta"})',
            actorUid: actor.uid,
            actorRole: actor.role,
            actorName: actor.name,
            appVersion: appVersion,
            timestamp: now,
          );

          transaction.update(snap.reference, change.productUpdates);
          transaction.set(movRefs[i], change.movement.toJson());
        }
      });
    }
  }

  /// Reverts replenished stock if a purchase order is deleted.
  Future<void> revertReplenishedStockForPurchaseOrder({
    required String invoiceNumber,
    required List<OrderItem> items,
    String? poId,
  }) async {
    final validItems = items.where((i) => i.productId.isNotEmpty && i.effectiveQuantity > 0).toList();
    if (validItems.isEmpty) return;
    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();

    for (final chunk in _chunk(validItems, 100)) {
      await _runInventoryTransaction('revertReplenishedStockForPurchaseOrder', (transaction) async {
        final productRefs = chunk.map((item) {
          final collectionName = _collectionForSource(item.productSource);
          return _firestore.collection(collectionName).doc(item.productId);
        }).toList();
        final movRefs = chunk.map((item) {
          final idKey = 'po_revert_${poId ?? invoiceNumber}_${item.productId}'.replaceAll('/', '_');
          return _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(idKey);
        }).toList();

        final productSnaps = await Future.wait(productRefs.map((r) => transaction.get(r)));
        final movSnaps = await Future.wait(movRefs.map((r) => transaction.get(r)));

        for (int i = 0; i < chunk.length; i++) {
          final snap = productSnaps[i];
          final movSnap = movSnaps[i];
          if (!snap.exists) continue;
          if (movSnap.exists) continue;

          final item = chunk[i];
          final qty = item.effectiveQuantity;

          final change = _computeStockChange(
            productRef: snap.reference,
            productSnap: snap,
            stockDelta: -qty,
            movementType: MovementType.reversal,
            referenceType: ReferenceType.purchase_order,
            referenceId: poId ?? invoiceNumber,
            referenceLabel: invoiceNumber,
            idempotencyKey: movRefs[i].id,
            reason: 'Purchase Order Deleted (Stock Reverted)',
            notes: 'PO Ref: $invoiceNumber (Reverted: -$qty)',
            actorUid: actor.uid,
            actorRole: actor.role,
            actorName: actor.name,
            appVersion: appVersion,
            timestamp: now,
          );

          transaction.update(snap.reference, change.productUpdates);
          transaction.set(movRefs[i], change.movement.toJson());
        }
      });
    }
  }

  /// Adds floating incoming stock (`incomingQuantity`) when a new Purchase Order is created
  /// with status `'pending'`, and logs an [InventoryMovement] audit entry with [MovementType.incoming_added].
  /// Note: On-hand physical stock delta remains 0.
  Future<void> addIncomingStockForPurchaseOrder({
    required List<OrderItem> items,
    String poNumber = '',
    String? poId,
  }) async {
    final validItems = items.where((i) => i.productId.isNotEmpty && i.effectiveQuantity > 0).toList();
    if (validItems.isEmpty) return;
    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();

    for (final chunk in _chunk(validItems, 100)) {
      await _runInventoryTransaction('addIncomingStockForPurchaseOrder', (transaction) async {
        final productRefs = chunk.map((item) {
          final collectionName = _collectionForSource(item.productSource);
          return _firestore.collection(collectionName).doc(item.productId);
        }).toList();
        final movRefs = chunk.map((item) {
          final idKey = 'po_incoming_add_${poId ?? poNumber}_${item.productId}'.replaceAll('/', '_');
          return _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(idKey);
        }).toList();

        final productSnaps = await Future.wait(productRefs.map((r) => transaction.get(r)));
        final movSnaps = await Future.wait(movRefs.map((r) => transaction.get(r)));

        for (int i = 0; i < chunk.length; i++) {
          final snap = productSnaps[i];
          final movSnap = movSnaps[i];
          if (!snap.exists) continue;
          if (movSnap.exists) continue;

          final item = chunk[i];
          final qty = item.effectiveQuantity;

          final change = _computeStockChange(
            productRef: snap.reference,
            productSnap: snap,
            stockDelta: 0,
            incomingDelta: qty,
            movementType: MovementType.incoming_added,
            referenceType: ReferenceType.purchase_order,
            referenceId: poId ?? poNumber,
            referenceLabel: poNumber,
            idempotencyKey: movRefs[i].id,
            reason: 'PO Placed (Incoming Stock Added)',
            notes: poNumber.isNotEmpty ? 'PO Ref: $poNumber (Incoming: +$qty)' : 'Incoming: +$qty',
            actorUid: actor.uid,
            actorRole: actor.role,
            actorName: actor.name,
            appVersion: appVersion,
            timestamp: now,
          );

          transaction.update(snap.reference, change.productUpdates);
          transaction.set(movRefs[i], change.movement.toJson());
        }
      });
    }
  }

  /// Adjusts floating incoming stock (`incomingQuantity`) when an existing pending Purchase Order
  /// has its items or quantities updated prior to official invoice confirmation.
  Future<void> adjustIncomingStockForPurchaseOrder({
    required List<OrderItem> oldItems,
    required List<OrderItem> newItems,
    String poNumber = '',
    String? poId,
  }) async {
    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();

    final Map<String, int> oldQtyByKey = {
      for (final item in oldItems) '${item.productSource}:${item.productId}': item.effectiveQuantity
    };
    final Map<String, int> newQtyByKey = {
      for (final item in newItems) '${item.productSource}:${item.productId}': item.effectiveQuantity
    };

    final allKeys = {...oldQtyByKey.keys, ...newQtyByKey.keys};
    final List<({String source, String productId, int delta})> diffs = [];

    for (final key in allKeys) {
      final parts = key.split(':');
      if (parts.length != 2) continue;
      final source = parts[0];
      final productId = parts[1];

      final oldQty = oldQtyByKey[key] ?? 0;
      final newQty = newQtyByKey[key] ?? 0;
      final delta = newQty - oldQty;
      if (delta != 0) {
        diffs.add((source: source, productId: productId, delta: delta));
      }
    }

    if (diffs.isEmpty) return;

    for (final chunk in _chunk(diffs, 100)) {
      await _runInventoryTransaction('adjustIncomingStockForPurchaseOrder', (transaction) async {
        final productRefs = chunk.map((entry) {
          final collectionName = _collectionForSource(entry.source);
          return _firestore.collection(collectionName).doc(entry.productId);
        }).toList();
        final movRefs = chunk.map((entry) {
          final idKey = 'po_incoming_adj_${poId ?? poNumber}_${entry.productId}_${now.millisecondsSinceEpoch}'.replaceAll('/', '_');
          return _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(idKey);
        }).toList();

        final productSnaps = await Future.wait(productRefs.map((r) => transaction.get(r)));
        final movSnaps = await Future.wait(movRefs.map((r) => transaction.get(r)));

        for (int i = 0; i < chunk.length; i++) {
          final snap = productSnaps[i];
          final movSnap = movSnaps[i];
          if (!snap.exists) continue;
          if (movSnap.exists) continue;

          final entry = chunk[i];
          final delta = entry.delta;

          final change = _computeStockChange(
            productRef: snap.reference,
            productSnap: snap,
            stockDelta: 0,
            incomingDelta: delta,
            movementType: MovementType.incoming_adjusted,
            referenceType: ReferenceType.purchase_order,
            referenceId: poId ?? poNumber,
            referenceLabel: poNumber,
            idempotencyKey: movRefs[i].id,
            reason: 'PO Adjusted (Incoming Stock)',
            notes: poNumber.isNotEmpty
                ? 'PO Ref: $poNumber (Incoming: ${delta > 0 ? "+$delta" : "$delta"})'
                : 'Incoming: ${delta > 0 ? "+$delta" : "$delta"}',
            actorUid: actor.uid,
            actorRole: actor.role,
            actorName: actor.name,
            appVersion: appVersion,
            timestamp: now,
          );

          transaction.update(snap.reference, change.productUpdates);
          transaction.set(movRefs[i], change.movement.toJson());
        }
      });
    }
  }

  /// Removes floating incoming stock (`incomingQuantity`) when a pending Purchase Order is deleted/cancelled.
  Future<void> removeIncomingStockForPurchaseOrder({
    required List<OrderItem> items,
    String poNumber = '',
    String? poId,
  }) async {
    final validItems = items.where((i) => i.productId.isNotEmpty && i.effectiveQuantity > 0).toList();
    if (validItems.isEmpty) return;
    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();

    for (final chunk in _chunk(validItems, 100)) {
      await _runInventoryTransaction('removeIncomingStockForPurchaseOrder', (transaction) async {
        final productRefs = chunk.map((item) {
          final collectionName = _collectionForSource(item.productSource);
          return _firestore.collection(collectionName).doc(item.productId);
        }).toList();
        final movRefs = chunk.map((item) {
          final idKey = 'po_incoming_rem_${poId ?? poNumber}_${item.productId}'.replaceAll('/', '_');
          return _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(idKey);
        }).toList();

        final productSnaps = await Future.wait(productRefs.map((r) => transaction.get(r)));
        final movSnaps = await Future.wait(movRefs.map((r) => transaction.get(r)));

        for (int i = 0; i < chunk.length; i++) {
          final snap = productSnaps[i];
          final movSnap = movSnaps[i];
          if (!snap.exists) continue;
          if (movSnap.exists) continue;

          final item = chunk[i];
          final qty = item.effectiveQuantity;

          final change = _computeStockChange(
            productRef: snap.reference,
            productSnap: snap,
            stockDelta: 0,
            incomingDelta: -qty,
            movementType: MovementType.incoming_removed,
            referenceType: ReferenceType.purchase_order,
            referenceId: poId ?? poNumber,
            referenceLabel: poNumber,
            idempotencyKey: movRefs[i].id,
            reason: 'PO Cancelled (Incoming Removed)',
            notes: poNumber.isNotEmpty ? 'PO Ref: $poNumber (Cancelled: -$qty)' : 'Cancelled: -$qty',
            actorUid: actor.uid,
            actorRole: actor.role,
            actorName: actor.name,
            appVersion: appVersion,
            timestamp: now,
          );

          transaction.update(snap.reference, change.productUpdates);
          transaction.set(movRefs[i], change.movement.toJson());
        }
      });
    }
  }

  /// Replenishes physical `stockQuantity` for confirmed items and simultaneously
  /// clears floating `incomingQuantity` from the original Purchase Order items.
  Future<void> replenishAndClearIncomingStockForPurchaseOrder({
    required String invoiceNumber,
    required DateTime orderDate,
    required List<OrderItem> originalPoItems,
    required List<OrderItem> confirmedItems,
    String? poId,
  }) async {
    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();
    final invoiceRef = invoiceNumber.trim().isNotEmpty
        ? invoiceNumber.trim()
        : 'PO-${DateFormat('yyyyMMdd').format(orderDate)}';

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

    final activeEntries = merged.values.where((e) => e.stockAdd > 0 || e.incomingDeduct > 0).toList();
    if (activeEntries.isEmpty) return;

    final correlationId = 'po_$invoiceRef';
    final List<({String id, String name, String source, int expected, int actual})> shortShipments = [];

    for (final chunk in _chunk(activeEntries, 100)) {
      await _runInventoryTransaction('replenishAndClearIncomingStockForPurchaseOrder', (transaction) async {
        final productRefs = chunk.map((entry) {
          final collectionName = _collectionForSource(entry.source);
          return _firestore.collection(collectionName).doc(entry.id);
        }).toList();
        final movRefs = chunk.map((entry) {
          final idKey = 'po_rcpt_${invoiceRef}_${entry.id}'.replaceAll('/', '_');
          return _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(idKey);
        }).toList();

        final productSnaps = await Future.wait(productRefs.map((r) => transaction.get(r)));
        final movSnaps = await Future.wait(movRefs.map((r) => transaction.get(r)));

        for (int i = 0; i < chunk.length; i++) {
          final snap = productSnaps[i];
          final movSnap = movSnaps[i];
          if (!snap.exists) continue;
          if (movSnap.exists) continue;

          final entry = chunk[i];

          // 8.5: Track PO receiving variance (short shipment)
          if (entry.incomingDeduct > entry.stockAdd) {
            shortShipments.add((
              id: entry.id,
              name: entry.name,
              source: entry.source,
              expected: entry.incomingDeduct,
              actual: entry.stockAdd,
            ));
          }

          final change = _computeStockChange(
            productRef: snap.reference,
            productSnap: snap,
            stockDelta: entry.stockAdd,
            incomingDelta: -entry.incomingDeduct,
            movementType: MovementType.receipt,
            referenceType: ReferenceType.purchase_order,
            referenceId: poId ?? invoiceRef,
            referenceLabel: invoiceRef,
            correlationId: correlationId,
            idempotencyKey: movRefs[i].id,
            sourceLocation: 'supplier',
            targetLocation: 'warehouse',
            reason: 'Purchase Order Replenishment',
            notes: 'PO Ref: $invoiceRef (Received: +${entry.stockAdd}, Cleared: -${entry.incomingDeduct})',
            actorUid: actor.uid,
            actorRole: actor.role,
            actorName: actor.name,
            appVersion: appVersion,
            timestamp: now,
          );

          transaction.update(snap.reference, change.productUpdates);

          if (entry.stockAdd > 0 || entry.incomingDeduct > 0) {
            transaction.set(movRefs[i], change.movement.toJson());
          }
        }
      });
    }

    for (final s in shortShipments) {
      final shortQty = s.expected - s.actual;
      _recordDiscrepancy(
        productId: s.id,
        productName: s.name,
        productSource: s.source,
        type: 'po_short_shipment',
        expected: s.expected,
        actual: s.actual,
        details: 'PO $invoiceRef short-shipment: expected ${s.expected}, received ${s.actual} (short: $shortQty).',
      );
    }
  }

  /// Adds returned items into incoming stock (`incomingQuantity`) when a delivery order
  /// has returns recorded or is tagged as returned, awaiting physical arrival and dealer inspection.
  /// Also logs an [InventoryMovement] audit record for each returned item.
  Future<void> addIncomingStockForReturn({
    required String storeName,
    required List<OrderItem> returnedItems,
    String? deliveryId,
  }) async {
    final validItems = returnedItems.where((i) {
      final qty = i.returnedQuantity > 0 ? i.returnedQuantity : i.pickedQuantity;
      return i.productId.isNotEmpty && qty > 0;
    }).toList();
    if (validItems.isEmpty) return;
    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();

    for (final chunk in _chunk(validItems, 100)) {
      await _runInventoryTransaction('addIncomingStockForReturn', (transaction) async {
        final productRefs = chunk.map((item) {
          final collectionName = _collectionForSource(item.productSource);
          return _firestore.collection(collectionName).doc(item.productId);
        }).toList();
        final movRefs = chunk.map((item) {
          final idKey = 'return_incoming_${deliveryId ?? storeName}_${item.productId}'.replaceAll('/', '_');
          return _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(idKey);
        }).toList();

        final productSnaps = await Future.wait(productRefs.map((r) => transaction.get(r)));
        final movSnaps = await Future.wait(movRefs.map((r) => transaction.get(r)));

        for (int i = 0; i < chunk.length; i++) {
          final snap = productSnaps[i];
          final movSnap = movSnaps[i];
          if (!snap.exists) continue;
          if (movSnap.exists) continue;

          final item = chunk[i];
          final qty = item.returnedQuantity > 0 ? item.returnedQuantity : item.pickedQuantity;

          final change = _computeStockChange(
            productRef: snap.reference,
            productSnap: snap,
            stockDelta: 0,
            incomingDelta: qty,
            movementType: MovementType.incoming_added,
            referenceType: ReferenceType.return_doc,
            referenceId: deliveryId,
            referenceLabel: storeName,
            correlationId: 'return_${deliveryId ?? storeName}',
            idempotencyKey: movRefs[i].id,
            sourceLocation: 'customer',
            targetLocation: 'incoming',
            reason: 'Return Received (Incoming to Warehouse)',
            notes: 'Store: $storeName (Incoming Return: +$qty, Pending Inspection)',
            actorUid: actor.uid,
            actorRole: actor.role,
            actorName: actor.name,
            appVersion: appVersion,
            timestamp: now,
          );

          transaction.update(snap.reference, change.productUpdates);
          transaction.set(movRefs[i], change.movement.toJson());
        }
      });
    }
  }

  /// Called when the dealer approves returned items in the Return page.
  /// Supports explicit [ReturnDisposition]:
  /// - [ReturnDisposition.restock]: Adds returned units to physical warehouse stock.
  /// - [ReturnDisposition.quarantine]: Retains units in quarantine for inspection (does not enter saleable stock).
  /// - [ReturnDisposition.write_off]: Scraps/writes off damaged units (does not enter saleable stock).
  /// Always clears units from incoming stock and logs an immutable [InventoryMovement].
  Future<void> approveReturnAndReplenishStock({
    required Delivery delivery,
    String? deliveryId,
    ReturnDisposition disposition = ReturnDisposition.restock,
    String? dispositionNotes,
  }) async {
    if (delivery.items.isEmpty) return;
    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();
    final correlationId = 'return_approve_${deliveryId ?? delivery.storeName}_${now.millisecondsSinceEpoch}';

    final isFullReturn = delivery.transactionStatus == DeliveryStatus.returned;
    final returnItems = delivery.items.where((i) {
      final qty = i.returnedQuantity > 0 ? i.returnedQuantity : (isFullReturn ? i.pickedQuantity : 0);
      return i.productId.isNotEmpty && qty > 0;
    }).toList();
    if (returnItems.isEmpty) return;

    final List<({String productId, String productName, String productSource, String type, int qty, String details})> discrepancies = [];

    for (final chunk in _chunk(returnItems, 100)) {
      await _runInventoryTransaction('approveReturnAndReplenishStock', (transaction) async {
        final productRefs = chunk.map((item) {
          final collectionName = _collectionForSource(item.productSource);
          return _firestore.collection(collectionName).doc(item.productId);
        }).toList();
        final movRefs = chunk.map((item) {
          final idKey = 'return_appr_${deliveryId ?? delivery.storeName}_${item.productId}_${disposition.key}'.replaceAll('/', '_');
          return _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(idKey);
        }).toList();

        final productSnaps = await Future.wait(productRefs.map((r) => transaction.get(r)));
        final movSnaps = await Future.wait(movRefs.map((r) => transaction.get(r)));

        for (int i = 0; i < chunk.length; i++) {
          final snap = productSnaps[i];
          final movSnap = movSnaps[i];
          if (!snap.exists) continue;
          if (movSnap.exists) continue;

          final item = chunk[i];
          final retQty = item.returnedQuantity > 0 ? item.returnedQuantity : (isFullReturn ? item.pickedQuantity : 0);
          if (retQty <= 0) continue;

          final int stockDelta;
          final String targetLoc;
          final String reasonText;
          final ReasonCode? rc;

          switch (disposition) {
            case ReturnDisposition.restock:
              stockDelta = retQty;
              targetLoc = 'warehouse';
              reasonText = 'Return Approved & Restocked';
              rc = null;
              break;
            case ReturnDisposition.quarantine:
              stockDelta = 0;
              targetLoc = 'quarantine';
              reasonText = 'Return Quarantined for Inspection';
              rc = ReasonCode.damaged;
              discrepancies.add((
                productId: item.productId,
                productName: item.productName,
                productSource: item.productSource,
                type: 'return_quarantine',
                qty: retQty,
                details: 'Returned goods quarantined from ${delivery.storeName}: $retQty units. ${dispositionNotes ?? ""}',
              ));
              break;
            case ReturnDisposition.write_off:
              stockDelta = 0;
              targetLoc = 'scrap';
              reasonText = 'Return Written-Off (Scrapped)';
              rc = ReasonCode.damaged;
              discrepancies.add((
                productId: item.productId,
                productName: item.productName,
                productSource: item.productSource,
                type: 'return_write_off',
                qty: retQty,
                details: 'Returned goods written off from ${delivery.storeName}: $retQty units scrapped. ${dispositionNotes ?? ""}',
              ));
              break;
          }

          final change = _computeStockChange(
            productRef: snap.reference,
            productSnap: snap,
            stockDelta: stockDelta,
            incomingDelta: -retQty,
            movementType: MovementType.customer_return,
            reasonCode: rc,
            referenceType: ReferenceType.return_doc,
            referenceId: deliveryId,
            referenceLabel: delivery.storeName,
            correlationId: correlationId,
            idempotencyKey: movRefs[i].id,
            sourceLocation: 'incoming',
            targetLocation: targetLoc,
            disposition: disposition,
            reason: reasonText,
            notes: 'Store: ${delivery.storeName} (${disposition.label}: $retQty)${dispositionNotes != null && dispositionNotes.isNotEmpty ? " Note: $dispositionNotes" : ""}',
            actorUid: actor.uid,
            actorRole: actor.role,
            actorName: actor.name,
            appVersion: appVersion,
            timestamp: now,
          );

          transaction.update(snap.reference, change.productUpdates);
          transaction.set(movRefs[i], change.movement.toJson());
        }
      });
    }

    for (final d in discrepancies) {
      _recordDiscrepancy(
        productId: d.productId,
        productName: d.productName,
        productSource: d.productSource,
        type: d.type,
        expected: 0,
        actual: d.qty,
        details: d.details,
      );
    }
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
    bool allowReconciliation = false,
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
    if (allowReconciliation && plan.settledDeliveryIds.isEmpty) {
      return;
    }

    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();
    final actorName = actor.name;

    await _firestore.runTransaction((transaction) async {
      // 1. Check breakdown doc to prevent double-verification unless in reconciliation mode
      if (breakdownId.isNotEmpty && !allowReconciliation) {
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

      // 3. Update products and stage movement logs
      final List<StockChangeRecord> clampedRecords = [];
      for (final delta in plan.productDeltas.values) {
        final key = '${delta.productSource}:${delta.productId}';
        final pSnap = productSnaps[key];
        if (pSnap == null || !pSnap.exists) continue;

        final collectionName = _collectionForSource(delta.productSource);
        final pRef = _firestore.collection(collectionName).doc(delta.productId);

        final change = _computeStockChange(
          productRef: pRef,
          productSnap: pSnap,
          stockDelta: delta.stockDelta,
          reservedDelta: delta.reservedDelta,
          movementType: MovementType.settlement,
          referenceType: ReferenceType.delivery,
          referenceId: breakdownId.isNotEmpty ? breakdownId : null,
          referenceLabel: 'Daily Settlement (${DateFormat('yyyy-MM-dd').format(date)})',
          reason: allowReconciliation
              ? 'Delivery Settled (Reconciled Past Breakdown)'
              : 'Daily Delivery Settlement',
          notes: 'Settled deliveries for ${DateFormat('yyyy-MM-dd').format(date)}',
          allowClamping: true,
          actorUid: actor.uid,
          actorRole: actor.role,
          actorName: actor.name,
          appVersion: appVersion,
          timestamp: now,
        );

        transaction.update(pRef, change.productUpdates);

        if (delta.stockDelta != 0 || delta.reservedDelta != 0 || change.clamped) {
          final movRef = _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(change.movement.id);
          transaction.set(movRef, change.movement.toJson());
        }

        if (change.clamped) {
          clampedRecords.add(change);
        }
      }

      // 4. Mark all affected deliveries as settled
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

      // 5. Update breakdown doc
      if (breakdownId.isNotEmpty) {
        final bRef = _firestore.collection(BREAKDOWN_COLLECTION_REF).doc(breakdownId);
        transaction.update(bRef, {
          'isVerifiedByDealer': true,
          'verifiedBy': actorName,
          'verifiedDate': breakdown.verifiedDate ?? now,
          'inventorySettledDate': now,
          'lastupdatedDate': now,
          'lastUpdatedBy': actorName,
        });
      }

      // 6. Record discrepancies if clamped
      for (final rec in clampedRecords) {
        _recordDiscrepancy(
          productId: rec.movement.productId,
          productName: rec.movement.productName,
          productSource: rec.movement.productSource,
          type: 'clamped_negative_stock',
          expected: rec.movement.previousStock,
          actual: 0,
          details: 'Settlement stock deduction clamped to 0 for date ${DateFormat('yyyy-MM-dd').format(date)}. Requested: ${rec.movement.requestedQuantity}, available: ${rec.movement.previousStock}.',
          movementId: rec.movement.id,
        );
      }
    });
  }

  /// Manually settles or reconciles an individual delivery whose inventory was left floating / unsettled.
  Future<void> settleSingleDelivery(String deliveryId) async {
    final dRef = _firestore.collection(DELIVERY_COLLECTION_REF).doc(deliveryId);
    final dSnap = await dRef.get();
    if (!dSnap.exists) throw Exception('Delivery document not found.');

    final data = dSnap.data()!;
    final delivery = Delivery.fromJson(data);
    final isSettled = data[DeliveryModelString.isInventorySettled] as bool? ?? false;
    if (isSettled) {
      throw Exception('This delivery is already inventory settled.');
    }

    final plan = computeSettlement([(id: deliveryId, delivery: delivery)]);
    final now = Timestamp.now();
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();
    final actorName = actor.name;

    if (plan.settledDeliveryIds.isEmpty) {
      // If not delivered or returned (e.g., cancelled or rescheduled), release any held reserved stock
      if (delivery.isInventoryReserved) {
        await releaseReservedStockForOrder(
          storeName: delivery.storeName,
          items: delivery.items,
          orderId: deliveryId,
        );
      }
      await dRef.update({
        DeliveryModelString.isInventoryReserved: false,
        DeliveryModelString.isInventorySettled: true,
        DeliveryModelString.inventorySettledDate: now,
        DeliveryModelString.inventorySettledBy: actorName,
        DeliveryModelString.lastupdatedDate: now,
        DeliveryModelString.lastUpdatedBy: actorName,
      });
      return;
    }

    await _firestore.runTransaction((transaction) async {
      // 1. Read product docs
      final Map<String, DocumentSnapshot<Map<String, dynamic>>> productSnaps = {};
      for (final delta in plan.productDeltas.values) {
        final collectionName = _collectionForSource(delta.productSource);
        final pRef = _firestore.collection(collectionName).doc(delta.productId);
        final pSnap = await transaction.get(pRef);
        productSnaps['${delta.productSource}:${delta.productId}'] = pSnap;
      }

      // 2. Update products and movement logs
      final List<StockChangeRecord> clampedRecords = [];
      for (final delta in plan.productDeltas.values) {
        final key = '${delta.productSource}:${delta.productId}';
        final pSnap = productSnaps[key];
        if (pSnap == null || !pSnap.exists) continue;

        final collectionName = _collectionForSource(delta.productSource);
        final pRef = _firestore.collection(collectionName).doc(delta.productId);

        final change = _computeStockChange(
          productRef: pRef,
          productSnap: pSnap,
          stockDelta: delta.stockDelta,
          reservedDelta: delta.reservedDelta,
          movementType: MovementType.settlement,
          referenceType: ReferenceType.delivery,
          referenceId: deliveryId,
          referenceLabel: delivery.storeName,
          reason: 'Manual Delivery Settlement (Reconciliation)',
          notes: 'Store: ${delivery.storeName}',
          allowClamping: true,
          actorUid: actor.uid,
          actorRole: actor.role,
          actorName: actor.name,
          appVersion: appVersion,
          timestamp: now,
        );

        transaction.update(pRef, change.productUpdates);

        if (delta.stockDelta != 0 || delta.reservedDelta != 0 || change.clamped) {
          final movRef = _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(change.movement.id);
          transaction.set(movRef, change.movement.toJson());
        }

        if (change.clamped) {
          clampedRecords.add(change);
        }
      }

      // 3. Mark delivery settled
      transaction.update(dRef, {
        DeliveryModelString.isInventorySettled: true,
        DeliveryModelString.isInventoryDeducted: true,
        DeliveryModelString.isInventoryReserved: false,
        DeliveryModelString.inventorySettledDate: now,
        DeliveryModelString.inventorySettledBy: actorName,
        DeliveryModelString.lastupdatedDate: now,
        DeliveryModelString.lastUpdatedBy: actorName,
      });

      // 4. Record discrepancies if clamped
      for (final rec in clampedRecords) {
        _recordDiscrepancy(
          productId: rec.movement.productId,
          productName: rec.movement.productName,
          productSource: rec.movement.productSource,
          type: 'clamped_negative_stock',
          expected: rec.movement.previousStock,
          actual: 0,
          details: 'Delivery settlement stock deduction clamped to 0 for delivery $deliveryId (${delivery.storeName}). Requested: ${rec.movement.requestedQuantity}, available: ${rec.movement.previousStock}.',
          movementId: rec.movement.id,
        );
      }
    });
  }

  /// Re-reserves floating inventory (`reservedQuantity`) for an order created when rescheduling
  /// a verified returned delivery.
  Future<void> reReserveForRescheduledOrder(List<OrderItem> items) async {
    await reserveStockForOrder(storeName: 'Rescheduled Order', items: items);
  }

  /// Retrieves paginated inventory movements with optional multi-attribute filters.
  Future<({List<InventoryMovement> movements, DocumentSnapshot? lastDoc, bool hasMore})> getMovementsPaginated({
    String? productId,
    MovementType? movementType,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
    ReferenceType? referenceType,
    int limit = 40,
    DocumentSnapshot? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection(INVENTORY_MOVEMENTS_COLLECTION_REF)
        .orderBy('createdAt', descending: true);

    if (productId != null && productId.isNotEmpty) {
      query = query.where('productId', isEqualTo: productId);
    }
    if (movementType != null) {
      query = query.where('movementType', isEqualTo: movementType.key);
    }
    if (referenceType != null) {
      query = query.where('referenceType', isEqualTo: referenceType.key);
    }
    if (startDate != null) {
      query = query.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
    }
    if (endDate != null) {
      final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
      query = query.where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay));
    }

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    query = query.limit(limit + 1);

    final snapshot = await query.get();
    final docs = snapshot.docs;
    final hasMore = docs.length > limit;
    final returnDocs = hasMore ? docs.sublist(0, limit) : docs;

    List<InventoryMovement> results = returnDocs.map(InventoryMovement.fromSnapshot).toList();

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      results = results.where((m) {
        return m.displayActor.toLowerCase().contains(q) ||
            m.notes.toLowerCase().contains(q) ||
            (m.referenceLabel?.toLowerCase().contains(q) ?? false) ||
            m.productName.toLowerCase().contains(q) ||
            m.reason.toLowerCase().contains(q);
      }).toList();
    }

    return (
      movements: results,
      lastDoc: returnDocs.isNotEmpty ? returnDocs.last : null,
      hasMore: hasMore,
    );
  }

  /// Fetches all active inventory items across Selecta and Other products.
  Future<List<InventoryItem>> getAllInventoryItems() async {
    final List<InventoryItem> items = [];
    final selectaSnaps = await _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).get();
    for (final doc in selectaSnaps.docs) {
      items.add(InventoryItem.fromSelectaProduct(SelectaProduct.fromSnapshot(doc)));
    }
    final otherSnaps = await _firestore.collection(OTHER_PRODUCTS_COLLECTION_REF).get();
    for (final doc in otherSnaps.docs) {
      items.add(InventoryItem.fromOtherProduct(doc.id, OtherProduct.fromJson(doc.data())));
    }
    return items;
  }

  /// Fetches recent movements with optional limit and date filter.
  Future<List<InventoryMovement>> getMovements({
    int limit = 1000,
    DateTime? startDate,
  }) async {
    Query<Map<String, dynamic>> query = _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF);
    if (startDate != null) {
      query = query.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
    }
    query = query.orderBy('createdAt', descending: true).limit(limit);
    try {
      final snap = await query.get();
      return snap.docs.map((d) => InventoryMovement.fromSnapshot(d)).toList();
    } catch (_) {
      final snap = await _firestore
          .collection(INVENTORY_MOVEMENTS_COLLECTION_REF)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      var list = snap.docs.map((d) => InventoryMovement.fromSnapshot(d)).toList();
      if (startDate != null) {
        list = list.where((m) => m.createdAt.toDate().isAfter(startDate) || m.createdAt.toDate().isAtSameMomentAs(startDate)).toList();
      }
      return list;
    }
  }

  /// Generates CSV formatted text for a list of [InventoryMovement] audit records.
  static String exportMovementsToCsv(List<InventoryMovement> movements) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Movement ID,Date Time,Product ID,Product Name,Source,Movement Type,Reason Code,Reference Type,Reference ID,Reference Label,Previous Stock,New Stock,Delta,Previous Reserved,New Reserved,Previous Incoming,New Incoming,Requested Qty,Clamped,Actor Name,Actor Role,Device ID,App Version,Correlation ID,Idempotency Key,Source Location,Target Location,Override,Override Reason,Unit Cost,Selling Price,Disposition,Short Pick Reason,Notes',
    );

    for (final m in movements) {
      final dt = DateFormat('yyyy-MM-dd HH:mm:ss').format(m.createdAt.toDate());
      final row = [
        _escapeCsv(m.id),
        _escapeCsv(dt),
        _escapeCsv(m.productId),
        _escapeCsv(m.productName),
        _escapeCsv(m.productSource),
        _escapeCsv(m.movementType.label),
        _escapeCsv(m.reasonCode?.label ?? ''),
        _escapeCsv(m.referenceType?.label ?? ''),
        _escapeCsv(m.referenceId ?? ''),
        _escapeCsv(m.referenceLabel ?? ''),
        m.previousStock,
        m.newStock,
        m.delta,
        m.previousReserved ?? '',
        m.newReserved ?? '',
        m.previousIncoming ?? '',
        m.newIncoming ?? '',
        m.requestedQuantity ?? '',
        m.clamped ? 'YES' : 'NO',
        _escapeCsv(m.displayActor),
        _escapeCsv(m.actorRole ?? ''),
        _escapeCsv(m.deviceId ?? ''),
        _escapeCsv(m.appVersion ?? ''),
        _escapeCsv(m.correlationId ?? ''),
        _escapeCsv(m.idempotencyKey ?? ''),
        _escapeCsv(m.sourceLocation ?? ''),
        _escapeCsv(m.targetLocation ?? ''),
        m.isOverride ? 'YES' : 'NO',
        _escapeCsv(m.overrideReason ?? ''),
        m.costPrice != null ? m.costPrice!.toStringAsFixed(2) : '',
        m.sellingPrice != null ? m.sellingPrice!.toStringAsFixed(2) : '',
        _escapeCsv(m.disposition?.label ?? ''),
        _escapeCsv(m.shortPickReason?.label ?? ''),
        _escapeCsv(m.notes),
      ];
      buffer.writeln(row.join(','));
    }
    return buffer.toString();
  }

  static String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Performs an in-app stock audit and reconciliation across all products or a single product.
  Future<StockAuditReport> runStockAudit({String? targetProductId}) async {
    final now = DateTime.now();
    final List<StockDiscrepancy> findings = [];

    // 1. Gather products to audit
    List<InventoryItem> items = [];
    if (targetProductId != null && targetProductId.isNotEmpty) {
      final selectaDoc = await _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).doc(targetProductId).get();
      if (selectaDoc.exists) {
        items.add(InventoryItem.fromSelectaProduct(SelectaProduct.fromSnapshot(selectaDoc)));
      } else {
        final otherDoc = await _firestore.collection(OTHER_PRODUCTS_COLLECTION_REF).doc(targetProductId).get();
        if (otherDoc.exists) {
          items.add(InventoryItem.fromOtherProduct(otherDoc.id, OtherProduct.fromJson(otherDoc.data() ?? {})));
        }
      }
    } else {
      final selectaSnaps = await _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).get();
      for (final doc in selectaSnaps.docs) {
        items.add(InventoryItem.fromSelectaProduct(SelectaProduct.fromSnapshot(doc)));
      }
      final otherSnaps = await _firestore.collection(OTHER_PRODUCTS_COLLECTION_REF).get();
      for (final doc in otherSnaps.docs) {
        items.add(InventoryItem.fromOtherProduct(doc.id, OtherProduct.fromJson(doc.data())));
      }
    }

    // 2. Fetch pending picklist deliveries to compute actual expected reservedQuantity
    final pendingDeliveriesSnap = await _firestore
        .collection(DELIVERY_COLLECTION_REF)
        .where('transactionStatus', isEqualTo: DeliveryStatus.pendingPicklist)
        .where('isInventoryDeducted', isEqualTo: false)
        .get();

    final Map<String, int> actualReservedPerProduct = {};
    for (final doc in pendingDeliveriesSnap.docs) {
      final d = Delivery.fromJson(doc.data());
      for (final item in d.items) {
        if (item.productId.isEmpty) continue;
        final key = item.productId;
        actualReservedPerProduct[key] = (actualReservedPerProduct[key] ?? 0) + item.pickedQuantity;
      }
    }

    // 3. Audit each product
    for (final item in items) {
      final expectedReserved = actualReservedPerProduct[item.id] ?? 0;
      if (item.reservedQuantity != expectedReserved) {
        findings.add(StockDiscrepancy(
          productId: item.id,
          productName: item.productName,
          productSource: item.productSource,
          discrepancyType: 'reserved_mismatch',
          expectedValue: expectedReserved,
          actualValue: item.reservedQuantity,
          message: 'Reserved stock on product doc (${item.reservedQuantity}) does not match open picklist sum ($expectedReserved).',
          detectedAt: now,
        ));
      }

      final movementsSnap = await _firestore
          .collection(INVENTORY_MOVEMENTS_COLLECTION_REF)
          .where('productId', isEqualTo: item.id)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

      final movements = movementsSnap.docs.map(InventoryMovement.fromSnapshot).toList();
      if (movements.isNotEmpty) {
        final latest = movements.first;
        if (latest.newStock != item.stockQuantity) {
          findings.add(StockDiscrepancy(
            productId: item.id,
            productName: item.productName,
            productSource: item.productSource,
            discrepancyType: 'ledger_mismatch',
            expectedValue: latest.newStock,
            actualValue: item.stockQuantity,
            message: 'Direct product document modification detected: Current stock (${item.stockQuantity}) differs from latest recorded movement (${latest.newStock}).',
            detectedAt: now,
          ));
        }

        for (int i = 0; i < movements.length - 1; i++) {
          final newer = movements[i];
          final older = movements[i + 1];
          if (newer.previousStock != older.newStock) {
            findings.add(StockDiscrepancy(
              productId: item.id,
              productName: item.productName,
              productSource: item.productSource,
              discrepancyType: 'chain_broken',
              expectedValue: older.newStock,
              actualValue: newer.previousStock,
              message: 'Movement ledger sequence break: Movement at ${newer.createdAt.toDate()} has previous stock ${newer.previousStock}, but prior movement ended with ${older.newStock}.',
              detectedAt: now,
            ));
            break;
          }
        }
      }
    }

    // 4. Save findings to inventory_discrepancies collection
    if (findings.isNotEmpty) {
      final batch = _firestore.batch();
      for (final f in findings) {
        final docRef = _firestore.collection('inventory_discrepancies').doc();
        batch.set(docRef, f.toJson());
      }
      final auditRef = _firestore.collection('inventory_audit_runs').doc();
      batch.set(auditRef, {
        'auditedAt': Timestamp.fromDate(now),
        'totalProductsAudited': items.length,
        'discrepanciesFound': findings.length,
      });
      await batch.commit();
    }

    return StockAuditReport(
      auditedAt: now,
      totalProductsAudited: items.length,
      discrepanciesFound: findings.length,
      discrepancies: findings,
    );
  }

  /// Records a physical cycle count entry for a product.
  /// Immediately adjusts physical stock and logs a [MovementType.count_correction]
  /// with [ReasonCode.count_correction].
  Future<InventoryMovement> submitCycleCount({
    required InventoryItem item,
    required int countedQuantity,
    String notes = '',
    bool isBlind = false,
    int countRound = 1,
    int? systemQuantityAtStart,
  }) async {
    final variance = countedQuantity - item.stockQuantity;
    final actor = await _resolveActor();
    final appVersion = await _resolveAppVersion();
    final now = Timestamp.now();

    final collectionName = item.source == InventoryProductSource.selecta
        ? SELECTA_PRODUCTS_COLLECTION_REF
        : OTHER_PRODUCTS_COLLECTION_REF;

    InventoryMovement? resultingMovement;

    await _runInventoryTransaction('submitCycleCount', (transaction) async {
      final productRef = _firestore.collection(collectionName).doc(item.id);
      final snap = await transaction.get(productRef);
      if (!snap.exists) {
        throw Exception('Product "${item.productName}" not found.');
      }

      final change = _computeStockChange(
        productRef: productRef,
        productSnap: snap,
        stockDelta: variance,
        movementType: MovementType.count_correction,
        reasonCode: ReasonCode.count_correction,
        referenceType: ReferenceType.manual,
        reason: 'Physical Cycle Count Correction',
        notes: notes.isNotEmpty
            ? notes
            : 'Cycle count adjusted by ${variance >= 0 ? "+$variance" : "$variance"} (Counted: $countedQuantity)',
        allowClamping: false,
        actorUid: actor.uid,
        actorRole: actor.role,
        actorName: actor.name,
        appVersion: appVersion,
        timestamp: now,
        isBlind: isBlind,
        countRound: countRound,
        systemQuantityAtStart: systemQuantityAtStart ?? item.stockQuantity,
      );

      transaction.update(productRef, change.productUpdates);
      final movRef = _firestore.collection(INVENTORY_MOVEMENTS_COLLECTION_REF).doc(change.movement.id);
      transaction.set(movRef, change.movement.toJson());
      resultingMovement = change.movement;
    });

    try {
      await _firestore.collection('cycle_counts').add({
        'productId': item.id,
        'productName': item.productName,
        'productSource': item.productSource,
        'systemStock': item.stockQuantity,
        'countedStock': countedQuantity,
        'variance': variance,
        'notes': notes,
        'countedBy': actor.name,
        'countedByUid': actor.uid,
        'countedAt': now,
        'isBlind': isBlind,
        'countRound': countRound,
      });
    } catch (e) {
      debugPrint('Error recording cycle count: $e');
    }

    return resultingMovement!;
  }

  /// Captures an end-of-day stock snapshot across all active products into `inventory_snapshots/{dateId}`
  /// and subcollection `items/{productId}`. Reconciles daily movements against opening/closing balances.
  Future<InventorySnapshot> captureDailyStockSnapshot([DateTime? date]) async {
    final targetDate = date ?? DateTime.now();
    final dateId = DateFormat('yyyy-MM-dd').format(targetDate);
    final startOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day, 0, 0, 0);
    final endOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day, 23, 59, 59, 999);

    final selectaSnaps = await _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).get();
    final otherSnaps = await _firestore.collection(OTHER_PRODUCTS_COLLECTION_REF).get();

    final List<InventoryItem> items = [
      ...selectaSnaps.docs.map((d) => InventoryItem.fromSelectaProduct(SelectaProduct.fromSnapshot(d))),
      ...otherSnaps.docs.map((d) => InventoryItem.fromOtherProduct(d.id, OtherProduct.fromJson(d.data()))),
    ];

    final movementsSnap = await _firestore
        .collection(INVENTORY_MOVEMENTS_COLLECTION_REF)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .get();

    final Map<String, int> totalInPerProduct = {};
    final Map<String, int> totalOutPerProduct = {};

    for (final doc in movementsSnap.docs) {
      final mov = InventoryMovement.fromSnapshot(doc);
      if (mov.delta > 0) {
        totalInPerProduct[mov.productId] = (totalInPerProduct[mov.productId] ?? 0) + mov.delta;
      } else if (mov.delta < 0) {
        totalOutPerProduct[mov.productId] = (totalOutPerProduct[mov.productId] ?? 0) + mov.delta.abs();
      }
    }

    final List<InventorySnapshotItem> snapshotItems = [];
    int totalStock = 0;
    int totalReserved = 0;
    int totalIncoming = 0;
    bool hasDiscrepancy = false;

    for (final item in items) {
      final closing = item.stockQuantity;
      final totalIn = totalInPerProduct[item.id] ?? 0;
      final totalOut = totalOutPerProduct[item.id] ?? 0;
      final net = totalIn - totalOut;
      final opening = closing - net < 0 ? 0 : closing - net;
      final reconciled = (opening + totalIn - totalOut == closing);

      if (!reconciled) {
        hasDiscrepancy = true;
        _recordDiscrepancy(
          productId: item.id,
          productName: item.productName,
          productSource: item.productSource,
          type: 'snapshot_mismatch',
          expected: opening + totalIn - totalOut,
          actual: closing,
          details: 'Daily stock snapshot mismatch on $dateId for ${item.productName}: opening $opening + in $totalIn - out $totalOut != closing $closing.',
        );
      }

      totalStock += closing;
      totalReserved += item.reservedQuantity;
      totalIncoming += item.incomingQuantity;

      snapshotItems.add(InventorySnapshotItem(
        productId: item.id,
        productName: item.productName,
        productSource: item.productSource,
        openingStock: opening,
        closingStock: closing,
        totalIn: totalIn,
        totalOut: totalOut,
        reserved: item.reservedQuantity,
        reconciled: reconciled,
      ));
    }

    final snapshot = InventorySnapshot(
      dateKey: dateId,
      id: dateId,
      date: dateId,
      snapshotAt: targetDate,
      totalProducts: items.length,
      totalStockQuantity: totalStock,
      totalReservedQuantity: totalReserved,
      totalIncomingQuantity: totalIncoming,
      status: hasDiscrepancy ? 'discrepancy' : 'captured',
      items: snapshotItems,
    );

    await _firestore.collection('inventory_snapshots').doc(dateId).set(snapshot.toJson());

    for (final chunk in _chunk(snapshotItems, 400)) {
      final batch = _firestore.batch();
      for (final sItem in chunk) {
        final itemRef = _firestore
            .collection('inventory_snapshots')
            .doc(dateId)
            .collection('items')
            .doc(sItem.productId);
        batch.set(itemRef, sItem.toJson());
      }
      await batch.commit();
    }

    return snapshot;
  }

  /// Ensures yesterday's end-of-day snapshot was captured, backfilling it if missing.
  Future<void> ensureYesterdaySnapshotCaptured() async {
    try {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final dateId = DateFormat('yyyy-MM-dd').format(yesterday);
      final doc = await _firestore.collection('inventory_snapshots').doc(dateId).get();
      if (!doc.exists) {
        await captureDailyStockSnapshot(yesterday);
      }
    } catch (e) {
      debugPrint('ensureYesterdaySnapshotCaptured error: $e');
    }
  }

  /// Reconciles daily stock snapshots over a date range.
  Future<List<InventorySnapshot>> reconcileDailySnapshots({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final List<InventorySnapshot> snapshots = [];
    DateTime current = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);

    while (!current.isAfter(end)) {
      final dateId = DateFormat('yyyy-MM-dd').format(current);
      final doc = await _firestore.collection('inventory_snapshots').doc(dateId).get();
      if (doc.exists) {
        final itemsSnap = await doc.reference.collection('items').get();
        final items = itemsSnap.docs.map(InventorySnapshotItem.fromSnapshot).toList();
        final snapshot = InventorySnapshot.fromSnapshot(doc, items: items);
        snapshots.add(snapshot);
      } else {
        final captured = await captureDailyStockSnapshot(current);
        snapshots.add(captured);
      }
      current = current.add(const Duration(days: 1));
    }

    return snapshots;
  }

  /// Retrieves closing stock for a product as of a given date.
  Future<int?> getStockAsOfDate(DateTime date, String productId) async {
    final dateId = DateFormat('yyyy-MM-dd').format(date);
    final itemDoc = await _firestore
        .collection('inventory_snapshots')
        .doc(dateId)
        .collection('items')
        .doc(productId)
        .get();
    if (itemDoc.exists) {
      return (itemDoc.data()?['closingStock'] as num?)?.toInt();
    }
    return null;
  }

  /// Checks if 24 hours have elapsed since the last stock audit and runs one automatically if due.
  Future<StockAuditReport?> checkAndRunScheduledAudit() async {
    try {
      final config = await ConfigurationService().getConfiguration();
      final lastAudit = config.lastStockAuditAt?.toDate();
      final now = DateTime.now();

      if (lastAudit == null || now.difference(lastAudit).inHours >= 24) {
        final report = await runStockAudit();
        await ConfigurationService().saveConfiguration(
          config.copyWith(lastStockAuditAt: Timestamp.fromDate(now)),
        );
        return report;
      }
    } catch (e) {
      debugPrint('checkAndRunScheduledAudit error: $e');
    }
    return null;
  }

  /// Realtime stream of open discrepancy count.
  Stream<int> getOpenDiscrepanciesCountStream() {
    return _firestore
        .collection('inventory_discrepancies')
        .where('status', isEqualTo: 'open')
        .snapshots()
        .map((s) => s.docs.length);
  }

  /// Realtime stream providing unified floating stock details across active Purchase Orders
  /// (Going In) and active reserved Deliveries/Orders (Going Out).
  Stream<FloatingStockData> getFloatingStockStream() {
    late StreamController<FloatingStockData> controller;
    StreamSubscription? inventorySub;
    StreamSubscription? poSub;
    StreamSubscription? deliverySub;

    List<InventoryItem> currentInventory = [];
    List<FloatingTransaction> currentIncoming = [];
    List<FloatingTransaction> currentOutgoing = [];
    bool invLoaded = false;
    bool poLoaded = false;
    bool delLoaded = false;

    void emit() {
      if (!invLoaded || !poLoaded || !delLoaded || controller.isClosed) return;

      int totalIn = 0;
      int totalOut = 0;

      // Map product IDs/names to incoming and outgoing source references
      final Map<String, List<FloatingSourceRef>> incomingByProduct = {};
      final Map<String, List<FloatingSourceRef>> outgoingByProduct = {};

      for (final tx in currentIncoming) {
        for (final item in tx.items) {
          final qty = item.pickedQuantity > 0 ? item.pickedQuantity : item.orderedQuantity;
          if (qty <= 0) continue;
          totalIn += qty;

          final ref = FloatingSourceRef(
            transactionId: tx.id,
            title: tx.title,
            subtitle: tx.subtitle,
            status: tx.status,
            date: tx.date,
            quantity: qty,
            isIncoming: true,
          );

          if (item.productId.isNotEmpty) {
            incomingByProduct.putIfAbsent(item.productId, () => []).add(ref);
          }
          final nameKey = item.productName.trim().toLowerCase();
          if (nameKey.isNotEmpty) {
            incomingByProduct.putIfAbsent(nameKey, () => []).add(ref);
          }
        }
      }

      for (final tx in currentOutgoing) {
        for (final item in tx.items) {
          final qty = item.pickedQuantity > 0 ? item.pickedQuantity : item.orderedQuantity;
          if (qty <= 0) continue;
          totalOut += qty;

          final ref = FloatingSourceRef(
            transactionId: tx.id,
            title: tx.title,
            subtitle: tx.subtitle,
            status: tx.status,
            date: tx.date,
            quantity: qty,
            isIncoming: false,
          );

          if (item.productId.isNotEmpty) {
            outgoingByProduct.putIfAbsent(item.productId, () => []).add(ref);
          }
          final nameKey = item.productName.trim().toLowerCase();
          if (nameKey.isNotEmpty) {
            outgoingByProduct.putIfAbsent(nameKey, () => []).add(ref);
          }
        }
      }

      // Build product list
      final List<FloatingProductItem> products = [];
      for (final item in currentInventory) {
        final nameKey = item.productName.trim().toLowerCase();
        final inSources = incomingByProduct[item.id] ?? incomingByProduct[nameKey] ?? [];
        final outSources = outgoingByProduct[item.id] ?? outgoingByProduct[nameKey] ?? [];

        final inQty = inSources.isNotEmpty
            ? inSources.fold<int>(0, (acc, s) => acc + s.quantity)
            : item.incomingQuantity;
        final outQty = outSources.isNotEmpty
            ? outSources.fold<int>(0, (acc, s) => acc + s.quantity)
            : item.reservedQuantity;

        if (inQty > 0 || outQty > 0 || inSources.isNotEmpty || outSources.isNotEmpty) {
          products.add(
            FloatingProductItem(
              productId: item.id,
              productName: item.productName,
              imageUrl: item.imageUrl,
              productSource: item.source == InventoryProductSource.selecta ? 'selecta' : 'other',
              category: item.category,
              buyingPrice: item.buyingPrice,
              sellingPrice: item.sellingPrice,
              stockQuantity: item.stockQuantity,
              incomingQuantity: inQty,
              reservedQuantity: outQty,
              incomingSources: inSources,
              outgoingSources: outSources,
            ),
          );
        }
      }

      products.sort((a, b) => a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));

      controller.add(
        FloatingStockData(
          products: products,
          incomingTransactions: currentIncoming,
          outgoingTransactions: currentOutgoing,
          totalIncomingUnits: totalIn,
          totalReservedUnits: totalOut,
        ),
      );
    }

    controller = StreamController<FloatingStockData>.broadcast(
      onListen: () {
        inventorySub = getActiveInventoryStream().listen((inv) {
          currentInventory = inv;
          invLoaded = true;
          emit();
        }, onError: (e, s) {
          if (!controller.isClosed) controller.addError(e, s);
        });

        poSub = _firestore.collection(PURCHASEORDER_COLLECTION_REF).snapshots().listen((snap) {
          final List<FloatingTransaction> incoming = [];
          for (final doc in snap.docs) {
            final data = doc.data();
            final isReplenished = data['isInventoryReplenished'] as bool? ?? false;
            final status = (data['status'] as String? ?? 'pending').toLowerCase();
            if (!isReplenished && status != 'cancelled') {
              final po = Purchaseorder.fromSnapshot(doc);
              final totalUnits = po.items.fold<int>(
                0,
                (acc, i) => acc + (i.pickedQuantity > 0 ? i.pickedQuantity : i.orderedQuantity),
              );
              incoming.add(
                FloatingTransaction(
                  id: doc.id,
                  type: FloatingTransactionType.incoming,
                  title: po.poNumber.isNotEmpty ? 'PO #${po.poNumber}' : 'Purchase Order',
                  subtitle: 'Supplier: Selecta Unilever',
                  status: po.status.isNotEmpty ? po.status : 'Pending',
                  date: po.orderDate.toDate(),
                  totalUnits: totalUnits,
                  items: po.items,
                ),
              );
            }
          }
          currentIncoming = incoming..sort((a, b) => b.date.compareTo(a.date));
          poLoaded = true;
          emit();
        }, onError: (e, s) {
          if (!controller.isClosed) controller.addError(e, s);
        });

        deliverySub = _firestore
            .collection(DELIVERY_COLLECTION_REF)
            .where(DeliveryModelString.isInventoryReserved, isEqualTo: true)
            .snapshots()
            .listen((snap) {
          final List<FloatingTransaction> outgoing = [];
          for (final doc in snap.docs) {
            final data = doc.data();
            final isSettled = data[DeliveryModelString.isInventorySettled] as bool? ?? false;
            final status = (data['transactionStatus'] as String? ?? '').toLowerCase();
            if (!isSettled && status != 'cancelled') {
              final del = Delivery.fromJson(data);
              final totalUnits = del.items.fold<int>(
                0,
                (acc, i) => acc + (i.pickedQuantity > 0 ? i.pickedQuantity : i.orderedQuantity),
              );
              outgoing.add(
                FloatingTransaction(
                  id: doc.id,
                  type: FloatingTransactionType.outgoing,
                  title: del.storeName.isNotEmpty ? del.storeName : 'Store Order',
                  subtitle: '${del.transactionStatus} • ${del.createdBy.isNotEmpty ? del.createdBy : "Dealer"}',
                  status: del.transactionStatus.isNotEmpty ? del.transactionStatus : 'Reserved',
                  date: del.deliveryDate?.toDate() ?? del.createdDate.toDate(),
                  totalUnits: totalUnits,
                  items: del.items,
                ),
              );
            }
          }
          currentOutgoing = outgoing..sort((a, b) => b.date.compareTo(a.date));
          delLoaded = true;
          emit();
        }, onError: (e, s) {
          if (!controller.isClosed) controller.addError(e, s);
        });
      },
      onCancel: () {
        inventorySub?.cancel();
        poSub?.cancel();
        deliverySub?.cancel();
      },
    );

    return controller.stream;
  }

  /// Checks if an inventory movement with the given [idempotencyKey] has already been recorded.
  Future<bool> hasMovementWithIdempotencyKey(String idempotencyKey) async {
    final snap = await _firestore
        .collection(INVENTORY_MOVEMENTS_COLLECTION_REF)
        .where('idempotencyKey', isEqualTo: idempotencyKey)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// Fetches exception metrics, KPI summary, and open discrepancies for the Dealer Exception Dashboard.
  Future<InventoryExceptionDashboardMetrics> fetchExceptionDashboardMetrics() async {
    // 1. Fetch open discrepancies
    final discSnap = await _firestore
        .collection('inventory_discrepancies')
        .where('status', isEqualTo: 'open')
        .get();

    final discrepancies = discSnap.docs.map((d) {
      return StockDiscrepancy.fromJson(d.id, d.data());
    }).toList();

    int shortPicks = 0;
    int clampedZero = 0;
    int quarantined = 0;

    for (final d in discrepancies) {
      if (d.discrepancyType == 'short_pick') shortPicks++;
      if (d.discrepancyType == 'clamped_negative_stock') clampedZero++;
      if (d.discrepancyType == 'return_quarantine') quarantined++;
    }

    // 2. Fetch movements in last 30 days to compute manual overrides and large adjustments
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    final movSnap = await _firestore
        .collection(INVENTORY_MOVEMENTS_COLLECTION_REF)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
        .get();

    int manualOverrides = 0;
    int largeAdjustments = 0;
    int pickCount = 0;

    for (final doc in movSnap.docs) {
      final m = InventoryMovement.fromSnapshot(doc);
      if (m.isOverride) manualOverrides++;
      if (m.movementType == MovementType.adjustment && m.delta.abs() >= 10) {
        largeAdjustments++;
      }
      if (m.movementType == MovementType.pick) {
        pickCount++;
      }
    }

    // 3. Accuracy calculations
    final totalDiscrepancies = discrepancies.length;
    final selectaCount = (await _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).count().get()).count ?? 1;
    final otherCount = (await _firestore.collection(OTHER_PRODUCTS_COLLECTION_REF).count().get()).count ?? 0;
    final totalProducts = (selectaCount + otherCount) > 0 ? (selectaCount + otherCount) : 1;
    final affectedProducts = discrepancies.map((d) => d.productId).toSet().length;
    final inventoryAccuracy = ((totalProducts - affectedProducts) / totalProducts * 100).clamp(0.0, 100.0);

    final totalPicksAttempted = pickCount + shortPicks;
    final pickAccuracy = totalPicksAttempted > 0
        ? ((pickCount / totalPicksAttempted) * 100).clamp(0.0, 100.0)
        : 100.0;

    discrepancies.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));

    return InventoryExceptionDashboardMetrics(
      openDiscrepanciesCount: totalDiscrepancies,
      shortPicksCount: shortPicks,
      clampedZeroCount: clampedZero,
      manualOverridesCount: manualOverrides,
      largeAdjustmentsCount: largeAdjustments,
      quarantinedItemsCount: quarantined,
      inventoryAccuracyRate: inventoryAccuracy,
      pickAccuracyRate: pickAccuracy,
      recentDiscrepancies: discrepancies.take(50).toList(),
    );
  }

  /// Resolves an open stock discrepancy with dealer resolution notes.
  Future<void> resolveDiscrepancy({
    required String discrepancyId,
    required String resolutionNotes,
  }) async {
    final actor = await _resolveActor();
    await _firestore.collection('inventory_discrepancies').doc(discrepancyId).update({
      'status': 'resolved',
      'resolutionNotes': resolutionNotes,
      'resolvedBy': actor.name,
      'resolvedAt': FieldValue.serverTimestamp(),
    });
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
