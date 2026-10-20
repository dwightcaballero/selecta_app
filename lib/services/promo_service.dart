import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/promo.dart';

/// The result returned by [PromoService.evaluate].
class PromoEvaluationResult {
  final List<AppliedPromo> appliedPromos;
  final double grossAmount;
  final double discountAmount;
  final double netAmount;
  final List<OrderItem> freeItems;
  final bool isOOSBlocked;
  final List<String> oosItemNames;
  final List<String> hints;
  final Map<String, String> disqualifiedPromos;

  const PromoEvaluationResult({
    required this.appliedPromos,
    required this.grossAmount,
    required this.discountAmount,
    required this.netAmount,
    this.freeItems = const [],
    this.isOOSBlocked = false,
    this.oosItemNames = const [],
    this.hints = const [],
    this.disqualifiedPromos = const {},
  });

  /// True if at least one promotion discount was successfully applied.
  bool get hasPromos => appliedPromos.isNotEmpty;
}

/// Result of evaluating delivery returns against promo bundles (Option B).
class PromoReturnResult {
  final List<OrderItem> items;
  final List<AppliedPromo> retainedPromos;
  final List<AppliedPromo> revokedPromos;
  final double deliveredGrossAmount;
  final double deliveredDiscountAmount;
  final double deliveredNetAmount;
  final double returnAmount;

  const PromoReturnResult({
    required this.items,
    required this.retainedPromos,
    required this.revokedPromos,
    required this.deliveredGrossAmount,
    required this.deliveredDiscountAmount,
    required this.deliveredNetAmount,
    required this.returnAmount,
  });
}

/// Single source of truth for promotional pricing, discount calculation,
/// bundle qualification, stock availability validation, and store usage limits.
class PromoService {
  final FirebaseFirestore? _customFirestore;

  PromoService({FirebaseFirestore? firestore}) : _customFirestore = firestore;

  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;

  // =========================================================================
  // 1. PURE PRICING ENGINE (Unit Testable)
  // =========================================================================

  /// Evaluates the list of cart [items] against [activePromos] for the specified
  /// [storeName] and [date].
  ///
  /// - Non-stacking at item/unit level (Option B): each item unit can only participate in 1 promo.
  /// - Automatically injects free reward products with sellingPrice = 0.
  /// - Enforces [limitPerStore] using [usedCounts].
  /// - Enforces OOS checks if [availableStock] is provided.
  PromoEvaluationResult evaluate({
    required List<OrderItem> items,
    required String storeName,
    required DateTime date,
    required List<Promo> activePromos,
    Map<String, int> usedCounts = const {},
    Map<String, int>? availableStock,
    Map<String, double>? productBuyingPrices,
  }) {
    // 1. Separate regular items from any existing injected free rewards
    final regularItems = items.where((i) => !i.isFreeReward && i.effectiveQuantity > 0).toList();

    // Compute gross total of regular items
    Decimal grossDecimal = Decimal.zero;
    for (final item in regularItems) {
      grossDecimal += Decimal.parse(item.lineTotal.toStringAsFixed(2));
    }
    final double grossAmount = grossDecimal.toDouble();

    // Map remaining unallocated units per product
    final Map<String, int> remainingQuantities = {};
    final Map<String, double> productPrices = {};
    final Map<String, String> productNames = {};
    final Map<String, String> productSources = {};
    final Map<String, String> productCategories = {};

    for (final item in regularItems) {
      remainingQuantities[item.productId] = (remainingQuantities[item.productId] ?? 0) + item.effectiveQuantity;
      productPrices[item.productId] = item.sellingPrice;
      productNames[item.productId] = item.productName;
      productSources[item.productId] = item.productSource;
      productCategories[item.productId] = item.category;
    }

    // Filter valid promos by active state and date window
    final eligiblePromos = activePromos.where((p) => p.isValidAt(date)).toList();

    // Sort by priority descending (higher priority evaluates first), then ID
    eligiblePromos.sort((a, b) {
      final pComp = b.priority.compareTo(a.priority);
      if (pComp != 0) return pComp;
      return a.id.compareTo(b.id);
    });

    final List<AppliedPromo> appliedPromos = [];
    final List<OrderItem> freeItems = [];
    final List<String> hints = [];
    final List<String> oosItemNames = [];
    final Map<String, String> disqualifiedPromos = {};
    Decimal totalDiscount = Decimal.zero;
    bool isOOSBlocked = false;

    for (final promo in eligiblePromos) {
      // 2. Check store lifetime limit
      if (promo.limitPerStore != null) {
        final used = usedCounts[promo.id] ?? 0;
        final remainingLifetime = promo.limitPerStore! - used;
        if (remainingLifetime <= 0) {
          disqualifiedPromos[promo.id] = 'Store reached purchase limit (${promo.limitPerStore}x)';
          continue;
        }
      }

      final used = usedCounts[promo.id] ?? 0;
      final remainingLifetime = promo.limitPerStore != null ? (promo.limitPerStore! - used) : 999999;

      if (promo.rules.isEmpty) continue;

      // 3. Check rule fulfillment
      int maxPossibleSets = 999999;
      int satisfiedRulesCount = 0;
      String? almostQualifyingHint;

      for (final rule in promo.rules) {
        final available = remainingQuantities[rule.productId] ?? 0;
        final ruleName = rule.productName.isNotEmpty ? rule.productName : (productNames[rule.productId] ?? rule.productId);

        // Check if store lacks enough stock in available inventory (Warehouse OOS)
        if (availableStock != null) {
          final warehouseStock = availableStock[rule.productId] ?? 0;
          if (warehouseStock < rule.requiredQty) {
            isOOSBlocked = true;
            if (!oosItemNames.contains(ruleName)) {
              oosItemNames.add(ruleName);
            }
          }
        }

        if (available >= rule.requiredQty) {
          satisfiedRulesCount++;
          final sets = available ~/ rule.requiredQty;
          if (sets < maxPossibleSets) {
            maxPossibleSets = sets;
          }
        } else {
          maxPossibleSets = 0;
          // Generate hints if store has some items or is just 1 step away
          final missingQty = rule.requiredQty - available;
          if (missingQty <= 2) {
            almostQualifyingHint = 'Add $missingQty more $ruleName to get ${promo.name}';
          }
        }
      }

      // If not fully satisfied, check if we should show an almost-qualifying hint
      if (maxPossibleSets <= 0 || satisfiedRulesCount < promo.rules.length) {
        if (almostQualifyingHint != null && satisfiedRulesCount > 0) {
          hints.add(almostQualifyingHint);
        }
        continue;
      }

      // 4. Calculate applications
      int applications = promo.repeatPerSet && (promo.limitPerStore != 1) ? maxPossibleSets : 1;
      if (promo.maxApplicationsPerOrder != null) {
        applications = min(applications, promo.maxApplicationsPerOrder!);
      }
      applications = min(applications, remainingLifetime);

      if (applications <= 0) continue;

      // 5. Check if required stock for the full application is available
      if (availableStock != null) {
        for (final rule in promo.rules) {
          final totalNeeded = rule.requiredQty * applications;
          final warehouseStock = availableStock[rule.productId] ?? 0;
          if (warehouseStock < totalNeeded) {
            isOOSBlocked = true;
            final ruleName = rule.productName.isNotEmpty ? rule.productName : (productNames[rule.productId] ?? rule.productId);
            if (!oosItemNames.contains(ruleName)) {
              oosItemNames.add(ruleName);
            }
          }
        }
      }

      // 6. Deduct units from remainingQuantities (Non-stacking Option B)
      for (final rule in promo.rules) {
        final usedUnits = rule.requiredQty * applications;
        remainingQuantities[rule.productId] = (remainingQuantities[rule.productId] ?? 0) - usedUnits;
      }

      // 7. Calculate discount / inject free items
      Decimal promoDiscount = Decimal.zero;
      final List<String> freeItemProductIds = [];

      if (promo.reward.type == 'fixed') {
        final amount = promo.reward.amount ?? 0.0;
        promoDiscount = Decimal.parse((amount * applications).toStringAsFixed(2));
      } else if (promo.reward.type == 'percent') {
        final percent = promo.reward.percent ?? 0.0;
        // Calculate the base cost of qualifying products
        Decimal bundleBaseCost = Decimal.zero;
        for (final rule in promo.rules) {
          final unitPrice = productPrices[rule.productId] ?? 0.0;
          bundleBaseCost += Decimal.parse((unitPrice * rule.requiredQty).toStringAsFixed(2));
        }
        final discountPerSet = bundleBaseCost * Decimal.parse((percent / 100.0).toStringAsFixed(4));
        promoDiscount = Decimal.parse((discountPerSet.toDouble() * applications).toStringAsFixed(2));
      } else if (promo.reward.type == 'freeItem') {
        // Free item reward
        for (final freeDef in promo.reward.freeItems) {
          final totalFreeQty = freeDef.quantity * applications;
          freeItemProductIds.add(freeDef.productId);

          // Check warehouse stock for free item
          if (availableStock != null) {
            final warehouseStock = availableStock[freeDef.productId] ?? 0;
            if (warehouseStock < totalFreeQty) {
              isOOSBlocked = true;
              if (!oosItemNames.contains(freeDef.productName)) {
                oosItemNames.add(freeDef.productName);
              }
            }
          }

          final buyingCost = freeDef.buyingPrice > 0
              ? freeDef.buyingPrice
              : (productBuyingPrices?[freeDef.productId] ?? 0.0);

          freeItems.add(OrderItem(
            productId: freeDef.productId,
            productName: freeDef.productName,
            productSource: freeDef.productSource,
            category: freeDef.category,
            sellingPrice: 0.0,
            buyingPrice: buyingCost,
            orderedQuantity: totalFreeQty,
            pickedQuantity: totalFreeQty,
            isFreeReward: true,
            promoId: promo.id,
            isPicked: false,
          ));
        }
      }

      totalDiscount += promoDiscount;

      appliedPromos.add(AppliedPromo(
        promoId: promo.id,
        name: promo.name,
        timesApplied: applications,
        discountAmount: promoDiscount.toDouble(),
        fundedBy: promo.fundedBy,
        supplierName: promo.supplierName,
        supplierRefundable: promo.supplierRefundable,
        rules: promo.rules,
        reward: promo.reward,
        freeItemProductIds: freeItemProductIds,
      ));
    }

    final double discountAmount = totalDiscount.toDouble();
    final double netAmount = max(0.0, grossAmount - discountAmount);

    return PromoEvaluationResult(
      appliedPromos: appliedPromos,
      grossAmount: grossAmount,
      discountAmount: discountAmount,
      netAmount: netAmount,
      freeItems: freeItems,
      isOOSBlocked: isOOSBlocked,
      oosItemNames: oosItemNames,
      hints: hints,
      disqualifiedPromos: disqualifiedPromos,
    );
  }

  // =========================================================================
  // 2. FIRESTORE USAGE COUNTING & QUERIES
  // =========================================================================

  /// Calculates the lifetime used counts for all promos availed by [storeName].
  ///
  /// Bounded query: only queries orders starting from [afterDate] (if provided),
  /// filtering out cancelled/voided orders. If [excludeDeliveryId] is passed (such
  /// as during order edit), that order's usage is omitted.
  Future<Map<String, int>> getStorePromoUsage(
    String storeName, {
    DateTime? afterDate,
    String? excludeDeliveryId,
  }) async {
    final Map<String, int> usage = {};
    if (storeName.trim().isEmpty) return usage;

    Query<Map<String, dynamic>> query = _firestore
        .collection('delivery')
        .where('storeName', isEqualTo: storeName.trim());

    if (afterDate != null) {
      query = query.where('deliveryDate', isGreaterThanOrEqualTo: Timestamp.fromDate(afterDate));
    }

    final snapshot = await query.get();

    for (final doc in snapshot.docs) {
      if (excludeDeliveryId != null && doc.id == excludeDeliveryId) {
        continue;
      }

      final data = doc.data();
      final status = data['transactionStatus']?.toString().toLowerCase() ?? '';
      if (status == DeliveryStatus.voided.toLowerCase() ||
          status == 'cancelled' ||
          status == 'voided') {
        continue;
      }

      final rawPromos = data['appliedPromos'] as List<dynamic>?;
      if (rawPromos == null || rawPromos.isEmpty) continue;

      for (final raw in rawPromos) {
        if (raw is Map) {
          final promoId = raw['promoId']?.toString();
          final times = (raw['timesApplied'] as num?)?.toInt() ?? 1;
          if (promoId != null && promoId.isNotEmpty) {
            usage[promoId] = (usage[promoId] ?? 0) + times;
          }
        }
      }
    }

    return usage;
  }

  /// Streams all active promotions from the `promos` collection.
  Stream<List<Promo>> streamActivePromos() {
    return _firestore
        .collection('promos')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Promo.fromJson(doc.data(), doc.id)).toList();
    });
  }

  /// Fetches a one-time list of all active promotions.
  Future<List<Promo>> getActivePromos() async {
    final snapshot = await _firestore
        .collection('promos')
        .where('isActive', isEqualTo: true)
        .get();
    return snapshot.docs.map((doc) => Promo.fromJson(doc.data(), doc.id)).toList();
  }

  /// Saves or updates a promotion in the `promos` collection.
  Future<void> savePromo(Promo promo) async {
    final collection = _firestore.collection('promos');
    final docRef = promo.id.isEmpty ? collection.doc() : collection.doc(promo.id);
    final data = promo.copyWith(id: docRef.id).toJson();
    await docRef.set(data, SetOptions(merge: true));
  }

  /// Soft deactivates a promotion.
  Future<void> deactivatePromo(String promoId) async {
    await _firestore.collection('promos').doc(promoId).update({
      'isActive': false,
      'lastUpdatedDate': Timestamp.now(),
    });
  }

  /// Permanently deletes a promotion from Firestore.
  Future<void> deletePromo(String promoId) async {
    await _firestore.collection('promos').doc(promoId).delete();
  }

  /// Evaluates returns on an existing [delivery] based on industry Decision Q3 (Option B):
  /// "Promos are considered 1 product line. If the customer returns even 1 item in the
  /// promo, then the whole promo line together with the discount is returned back to warehouse."
  PromoReturnResult recalculateReturnsWithPromos({
    required Delivery delivery,
    required List<OrderItem> itemsWithReturns,
  }) {
    // If no promos were applied, standard return calculation applies.
    if (delivery.appliedPromos.isEmpty) {
      final double totalDelivered = itemsWithReturns.fold<double>(
        0.0,
        (acc, i) => acc + (i.isFreeReward ? 0.0 : i.deliveredLineTotal),
      );
      final double totalReturned = itemsWithReturns.fold<double>(
        0.0,
        (acc, i) => acc + (i.isFreeReward ? 0.0 : i.returnedLineTotal),
      );
      return PromoReturnResult(
        items: itemsWithReturns,
        retainedPromos: const [],
        revokedPromos: const [],
        deliveredGrossAmount: totalDelivered,
        deliveredDiscountAmount: 0.0,
        deliveredNetAmount: totalDelivered,
        returnAmount: totalReturned,
      );
    }

    final List<OrderItem> updatedItems = List.from(itemsWithReturns);
    final List<AppliedPromo> retainedPromos = [];
    final List<AppliedPromo> revokedPromos = [];

    // Check each applied promo to see if any of its constituent items has returnedQuantity > 0
    for (final promo in delivery.appliedPromos) {
      final promoProductIds = {
        ...promo.rules.map((r) => r.productId),
        ...promo.freeItemProductIds,
      };

      bool promoHasReturnedItem = false;
      for (final item in updatedItems) {
        final matches = (item.promoId == promo.promoId) || promoProductIds.contains(item.productId);
        if (matches && item.returnedQuantity > 0) {
          promoHasReturnedItem = true;
          break;
        }
      }

      if (promoHasReturnedItem) {
        revokedPromos.add(promo);
        // Under Option B, if even 1 item in the promo is returned, the whole promo line is returned:
        // Set returnedQuantity = pickedQuantity for all items belonging to this promo
        for (int i = 0; i < updatedItems.length; i++) {
          final item = updatedItems[i];
          final matches = (item.promoId == promo.promoId) || promoProductIds.contains(item.productId);
          if (matches) {
            updatedItems[i] = item.copyWith(returnedQuantity: item.pickedQuantity);
          }
        }
      } else {
        retainedPromos.add(promo);
      }
    }

    // Compute delivered gross (for regular items)
    Decimal deliveredGrossDec = Decimal.zero;
    for (final item in updatedItems) {
      if (!item.isFreeReward) {
        final deliveredUnits = (item.pickedQuantity - item.returnedQuantity).clamp(0, item.pickedQuantity);
        final lineDelivered = Decimal.parse((deliveredUnits * item.sellingPrice).toStringAsFixed(2));
        deliveredGrossDec += lineDelivered;
      }
    }
    final double deliveredGross = deliveredGrossDec.toDouble();

    // Compute delivered discounts from retained promos
    Decimal deliveredDiscountDec = Decimal.zero;
    for (final promo in retainedPromos) {
      deliveredDiscountDec += Decimal.parse(promo.discountAmount.toStringAsFixed(2));
    }
    final double deliveredDiscount = deliveredDiscountDec.toDouble();

    final double deliveredNet = max(0.0, (deliveredGrossDec - deliveredDiscountDec).toDouble());
    final originalAmount = delivery.originalOrderAmount ?? delivery.orderAmount;
    final double returnAmount = max(0.0, (Decimal.parse(originalAmount.toStringAsFixed(2)) - Decimal.parse(deliveredNet.toStringAsFixed(2))).toDouble());

    return PromoReturnResult(
      items: updatedItems,
      retainedPromos: retainedPromos,
      revokedPromos: revokedPromos,
      deliveredGrossAmount: deliveredGross,
      deliveredDiscountAmount: deliveredDiscount,
      deliveredNetAmount: deliveredNet,
      returnAmount: returnAmount,
    );
  }
}
