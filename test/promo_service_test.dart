import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/promo.dart';
import 'package:selecta_ops/services/promo_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PromoService Pricing Engine Tests', () {
    late PromoService promoService;
    final now = DateTime(2026, 10, 19, 10, 0);

    setUp(() {
      promoService = PromoService();
    });

    final p1 = const OrderItem(
      productId: 'prod_1',
      productName: 'Cornetto Chocolate',
      sellingPrice: 30.0,
      orderedQuantity: 2,
    );

    final p2 = const OrderItem(
      productId: 'prod_2',
      productName: 'Cornetto Vanilla',
      sellingPrice: 30.0,
      orderedQuantity: 2,
    );

    final p3 = const OrderItem(
      productId: 'prod_3',
      productName: 'Selecta Pint Vanilla',
      sellingPrice: 150.0,
      orderedQuantity: 1,
    );

    test('Fixed discount applies for qualifying bundle and calculates net amount', () {
      final promo = Promo(
        id: 'promo_combo_1',
        name: 'Cornetto Duo Saver',
        rules: const [
          PromoRule(productId: 'prod_1', requiredQty: 1),
          PromoRule(productId: 'prod_2', requiredQty: 1),
        ],
        reward: const PromoReward(type: 'fixed', amount: 15.0),
        repeatPerSet: true,
        createdDate: Timestamp.now(),
        lastUpdatedDate: Timestamp.now(),
      );

      final result = promoService.evaluate(
        items: [p1, p2],
        storeName: 'Store Alpha',
        date: now,
        activePromos: [promo],
      );

      // 2 sets of P1 + P2 = 2 * 15 = 30.0 discount
      // Gross: (2 * 30) + (2 * 30) = 120.0
      // Net: 120 - 30 = 90.0
      expect(result.hasPromos, isTrue);
      expect(result.appliedPromos.length, 1);
      expect(result.appliedPromos.first.timesApplied, 2);
      expect(result.grossAmount, 120.0);
      expect(result.discountAmount, 30.0);
      expect(result.netAmount, 90.0);
    });

    test('repeatPerSet: false caps discount application to 1 set', () {
      final promo = Promo(
        id: 'promo_once_per_order',
        name: 'Single Set Deal',
        rules: const [
          PromoRule(productId: 'prod_1', requiredQty: 1),
          PromoRule(productId: 'prod_2', requiredQty: 1),
        ],
        reward: const PromoReward(type: 'fixed', amount: 20.0),
        repeatPerSet: false,
        createdDate: Timestamp.now(),
        lastUpdatedDate: Timestamp.now(),
      );

      final result = promoService.evaluate(
        items: [p1, p2], // 2 of each
        storeName: 'Store Alpha',
        date: now,
        activePromos: [promo],
      );

      expect(result.appliedPromos.first.timesApplied, 1);
      expect(result.discountAmount, 20.0);
      expect(result.netAmount, 100.0);
    });

    test('limitPerStore: 1 forces single application and is blocked if already availed', () {
      final promo = Promo(
        id: 'promo_supplier_once',
        name: 'Supplier Welcome Promo',
        rules: const [
          PromoRule(productId: 'prod_1', requiredQty: 1),
          PromoRule(productId: 'prod_2', requiredQty: 1),
        ],
        reward: const PromoReward(type: 'fixed', amount: 25.0),
        limitPerStore: 1,
        createdDate: Timestamp.now(),
        lastUpdatedDate: Timestamp.now(),
      );

      // 1st time (not yet availed)
      final result1 = promoService.evaluate(
        items: [p1, p2],
        storeName: 'Store Alpha',
        date: now,
        activePromos: [promo],
        usedCounts: {'promo_supplier_once': 0},
      );
      expect(result1.appliedPromos.first.timesApplied, 1);
      expect(result1.discountAmount, 25.0);

      // 2nd time (already used 1 time)
      final result2 = promoService.evaluate(
        items: [p1, p2],
        storeName: 'Store Alpha',
        date: now,
        activePromos: [promo],
        usedCounts: {'promo_supplier_once': 1},
      );
      expect(result2.hasPromos, isFalse);
      expect(result2.discountAmount, 0.0);
      expect(result2.disqualifiedPromos.containsKey('promo_supplier_once'), isTrue);
    });

    test('Item-level non-stacking (Option B): Each product unit only participates in 1 promo', () {
      // Promo A: 1x P1 + 1x P2 -> PHP 20 off (Priority 10)
      final promoA = Promo(
        id: 'promo_a',
        name: 'Promo A',
        priority: 10,
        rules: const [
          PromoRule(productId: 'prod_1', requiredQty: 1),
          PromoRule(productId: 'prod_2', requiredQty: 1),
        ],
        reward: const PromoReward(type: 'fixed', amount: 20.0),
        createdDate: Timestamp.now(),
        lastUpdatedDate: Timestamp.now(),
      );

      // Promo B: 1x P1 + 1x P3 -> PHP 30 off (Priority 5)
      final promoB = Promo(
        id: 'promo_b',
        name: 'Promo B',
        priority: 5,
        rules: const [
          PromoRule(productId: 'prod_1', requiredQty: 1),
          PromoRule(productId: 'prod_3', requiredQty: 1),
        ],
        reward: const PromoReward(type: 'fixed', amount: 30.0),
        createdDate: Timestamp.now(),
        lastUpdatedDate: Timestamp.now(),
      );

      // Cart only has 1 unit of P1, 1 of P2, 1 of P3
      final singleP1 = const OrderItem(productId: 'prod_1', productName: 'P1', sellingPrice: 30.0, orderedQuantity: 1);
      final singleP2 = const OrderItem(productId: 'prod_2', productName: 'P2', sellingPrice: 30.0, orderedQuantity: 1);
      final singleP3 = const OrderItem(productId: 'prod_3', productName: 'P3', sellingPrice: 150.0, orderedQuantity: 1);

      final result = promoService.evaluate(
        items: [singleP1, singleP2, singleP3],
        storeName: 'Store Alpha',
        date: now,
        activePromos: [promoA, promoB],
      );

      // Promo A has higher priority, consumes singleP1 and singleP2.
      // Remaining P1 is 0, so Promo B cannot apply!
      expect(result.appliedPromos.length, 1);
      expect(result.appliedPromos.first.promoId, 'promo_a');
      expect(result.discountAmount, 20.0);
    });

    test('Percentage reward computes discount correctly based on qualifying bundle items', () {
      final promo = Promo(
        id: 'promo_percent',
        name: '10% Bundle Discount',
        rules: const [
          PromoRule(productId: 'prod_1', requiredQty: 1), // 30
          PromoRule(productId: 'prod_3', requiredQty: 1), // 150
        ],
        reward: const PromoReward(type: 'percent', percent: 10.0),
        createdDate: Timestamp.now(),
        lastUpdatedDate: Timestamp.now(),
      );

      final result = promoService.evaluate(
        items: [p1, p3], // 2x P1, 1x P3 -> 1 set
        storeName: 'Store Alpha',
        date: now,
        activePromos: [promo],
      );

      // Base bundle cost: 30 + 150 = 180. 10% of 180 = 18.00
      expect(result.appliedPromos.first.timesApplied, 1);
      expect(result.discountAmount, 18.0);
      // Gross: (2 * 30) + 150 = 210. Net: 210 - 18 = 192.0
      expect(result.grossAmount, 210.0);
      expect(result.netAmount, 192.0);
    });

    test('Free item reward automatically injects item with sellingPrice: 0', () {
      final promo = Promo(
        id: 'promo_free_magnum',
        name: 'Buy 2 Cornetto Get 1 Free Pint',
        rules: const [
          PromoRule(productId: 'prod_1', requiredQty: 2),
        ],
        reward: const PromoReward(
          type: 'freeItem',
          freeItems: [
            PromoFreeItem(
              productId: 'prod_free_pint',
              productName: 'Free Selecta Pint',
              quantity: 1,
              buyingPrice: 100.0,
            ),
          ],
        ),
        createdDate: Timestamp.now(),
        lastUpdatedDate: Timestamp.now(),
      );

      final result = promoService.evaluate(
        items: [p1], // orderedQuantity: 2
        storeName: 'Store Alpha',
        date: now,
        activePromos: [promo],
      );

      expect(result.appliedPromos.length, 1);
      expect(result.freeItems.length, 1);
      final freeItem = result.freeItems.first;
      expect(freeItem.productId, 'prod_free_pint');
      expect(freeItem.sellingPrice, 0.0);
      expect(freeItem.buyingPrice, 100.0);
      expect(freeItem.orderedQuantity, 1);
      expect(freeItem.isFreeReward, isTrue);
      expect(freeItem.promoId, 'promo_free_magnum');
    });

    test('OOS stock validation blocks promo when warehouse stock is insufficient', () {
      final promo = Promo(
        id: 'promo_oos_test',
        name: 'OOS Combo',
        rules: const [
          PromoRule(productId: 'prod_1', requiredQty: 5),
        ],
        reward: const PromoReward(type: 'fixed', amount: 50.0),
        createdDate: Timestamp.now(),
        lastUpdatedDate: Timestamp.now(),
      );

      final result = promoService.evaluate(
        items: [const OrderItem(productId: 'prod_1', productName: 'Cornetto', sellingPrice: 30.0, orderedQuantity: 5)],
        storeName: 'Store Alpha',
        date: now,
        activePromos: [promo],
        availableStock: {
          'prod_1': 3, // only 3 in stock, but 5 needed
        },
      );

      expect(result.isOOSBlocked, isTrue);
      expect(result.oosItemNames, contains('Cornetto'));
    });

    test('Almost-qualifying hint is generated when missing 1 unit', () {
      final promo = Promo(
        id: 'promo_hint',
        name: 'Summer Saver',
        rules: const [
          PromoRule(productId: 'prod_1', productName: 'Cornetto Choc', requiredQty: 2),
          PromoRule(productId: 'prod_2', productName: 'Cornetto Van', requiredQty: 2),
        ],
        reward: const PromoReward(type: 'fixed', amount: 20.0),
        createdDate: Timestamp.now(),
        lastUpdatedDate: Timestamp.now(),
      );

      // Cart has 2 of P1, but only 1 of P2
      final result = promoService.evaluate(
        items: [
          const OrderItem(productId: 'prod_1', productName: 'Cornetto Choc', sellingPrice: 30.0, orderedQuantity: 2),
          const OrderItem(productId: 'prod_2', productName: 'Cornetto Van', sellingPrice: 30.0, orderedQuantity: 1),
        ],
        storeName: 'Store Alpha',
        date: now,
        activePromos: [promo],
      );

      expect(result.hasPromos, isFalse);
      expect(result.hints.isNotEmpty, isTrue);
      expect(result.hints.first, contains('Add 1 more Cornetto Van'));
    });

    test('Promo outside date window is ignored', () {
      final expiredPromo = Promo(
        id: 'promo_expired',
        name: 'Expired Promo',
        startDate: Timestamp.fromDate(DateTime(2026, 1, 1)),
        endDate: Timestamp.fromDate(DateTime(2026, 1, 31)),
        rules: const [PromoRule(productId: 'prod_1', requiredQty: 1)],
        reward: const PromoReward(type: 'fixed', amount: 10.0),
        createdDate: Timestamp.now(),
        lastUpdatedDate: Timestamp.now(),
      );

      final result = promoService.evaluate(
        items: [p1],
        storeName: 'Store Alpha',
        date: now, // 2026-10-19
        activePromos: [expiredPromo],
      );

      expect(result.hasPromos, isFalse);
      expect(result.discountAmount, 0.0);
    });

    test('Option B Returns: Returning even 1 item in a promo bundle returns the whole promo line and discount', () {
      final promo = Promo(
        id: 'promo_bundle_1',
        name: 'Buy 2 Tubs Save ₱100',
        rules: const [
          PromoRule(productId: 'prod_tub', productName: 'Tub Vanilla', requiredQty: 2),
        ],
        reward: const PromoReward(type: 'fixed', amount: 100.0),
        createdDate: Timestamp.now(),
        lastUpdatedDate: Timestamp.now(),
      );

      final delivery = Delivery.empty().copyWith(
        orderAmount: 700.0,
        originalOrderAmount: 700.0,
        grossAmount: 800.0,
        discountAmount: 100.0,
        appliedPromos: [
          AppliedPromo(
            promoId: 'promo_bundle_1',
            name: 'Buy 2 Tubs Save ₱100',
            timesApplied: 1,
            discountAmount: 100.0,
            rules: promo.rules,
            reward: promo.reward,
          ),
        ],
        items: const [
          OrderItem(
            productId: 'prod_tub',
            productName: 'Tub Vanilla',
            sellingPrice: 400.0,
            orderedQuantity: 2,
            pickedQuantity: 2,
            returnedQuantity: 0,
          ),
          OrderItem(
            productId: 'prod_cone',
            productName: 'Cornetto Vanilla',
            sellingPrice: 50.0,
            orderedQuantity: 1,
            pickedQuantity: 1,
            returnedQuantity: 0,
          ),
        ],
      );

      // Customer returns 1 Tub Vanilla
      final itemsWithReturns = [
        delivery.items[0].copyWith(returnedQuantity: 1),
        delivery.items[1],
      ];

      final returnResult = promoService.recalculateReturnsWithPromos(
        delivery: delivery,
        itemsWithReturns: itemsWithReturns,
      );

      // Under Option B:
      // The entire promo line (both Tubs) must be returned
      final returnedTub = returnResult.items.firstWhere((i) => i.productId == 'prod_tub');
      expect(returnedTub.returnedQuantity, 2); // whole promo line returned!

      // Promo discount is revoked
      expect(returnResult.revokedPromos.length, 1);
      expect(returnResult.retainedPromos.isEmpty, isTrue);
      expect(returnResult.deliveredDiscountAmount, 0.0);

      // Only Cornetto delivered: 1 * 50 = 50.0
      expect(returnResult.deliveredGrossAmount, 50.0);
      expect(returnResult.deliveredNetAmount, 50.0);
      // Return amount: 700 - 50 = 650.0 (Customer pays 50 for the cone, gets 650 back)
      expect(returnResult.returnAmount, 650.0);
    });

    test('Option B Returns: Returning promo item also returns injected free reward product', () {
      final delivery = Delivery.empty().copyWith(
        orderAmount: 800.0,
        originalOrderAmount: 800.0,
        grossAmount: 800.0,
        discountAmount: 0.0,
        appliedPromos: const [
          AppliedPromo(
            promoId: 'promo_free_cone',
            name: 'Buy 2 Tubs Get Free Cone',
            timesApplied: 1,
            discountAmount: 0.0,
            rules: [PromoRule(productId: 'prod_tub', requiredQty: 2)],
            reward: PromoReward(type: 'free_item', amount: 0.0),
            freeItemProductIds: ['prod_free_cone'],
          ),
        ],
        items: const [
          OrderItem(
            productId: 'prod_tub',
            productName: 'Tub Vanilla',
            sellingPrice: 400.0,
            orderedQuantity: 2,
            pickedQuantity: 2,
            returnedQuantity: 0,
          ),
          OrderItem(
            productId: 'prod_free_cone',
            productName: 'Free Cornetto',
            sellingPrice: 0.0,
            buyingPrice: 30.0,
            orderedQuantity: 1,
            pickedQuantity: 1,
            returnedQuantity: 0,
            isFreeReward: true,
            promoId: 'promo_free_cone',
          ),
        ],
      );

      // Customer returns 1 Tub
      final itemsWithReturns = [
        delivery.items[0].copyWith(returnedQuantity: 1),
        delivery.items[1],
      ];

      final returnResult = promoService.recalculateReturnsWithPromos(
        delivery: delivery,
        itemsWithReturns: itemsWithReturns,
      );

      // Under Option B, both Tub and free cone must be returned
      final returnedTub = returnResult.items.firstWhere((i) => i.productId == 'prod_tub');
      final returnedFreeCone = returnResult.items.firstWhere((i) => i.productId == 'prod_free_cone');
      expect(returnedTub.returnedQuantity, 2);
      expect(returnedFreeCone.returnedQuantity, 1);
      expect(returnResult.revokedPromos.length, 1);
      expect(returnResult.deliveredNetAmount, 0.0);
      expect(returnResult.returnAmount, 800.0);
    });
  });
}
