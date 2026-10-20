import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/models/promo.dart';

void main() {
  group('Promo Model & Admin Setup Tests', () {
    test('PromoReward getters identify reward types correctly', () {
      const fixedReward = PromoReward(type: 'fixed', amount: 50.0);
      expect(fixedReward.isFixed, isTrue);
      expect(fixedReward.isPercentage, isFalse);
      expect(fixedReward.isFreeReward, isFalse);

      const percentReward = PromoReward(type: 'percent', percent: 15.0);
      expect(percentReward.isPercentage, isTrue);
      expect(percentReward.isFixed, isFalse);

      const freeReward = PromoReward(
        type: 'freeItem',
        freeItems: [
          PromoFreeItem(
            productId: 'free_p1',
            productName: 'Free Cornetto',
            quantity: 1,
            imageUrl: 'https://example.com/cone.png',
          ),
        ],
      );
      expect(freeReward.isFreeReward, isTrue);
      expect(freeReward.freeItems.first.imageUrl, 'https://example.com/cone.png');
    });

    test('AppliedPromo promoTitle alias matches name', () {
      const applied = AppliedPromo(
        promoId: 'promo_101',
        name: 'Magnum Summer Festival',
        timesApplied: 2,
        discountAmount: 100.0,
        reward: PromoReward(type: 'fixed', amount: 50.0),
      );
      expect(applied.promoTitle, 'Magnum Summer Festival');
      expect(applied.name, 'Magnum Summer Festival');
    });

    test('Promo serialization and copyWith works cleanly', () {
      final promo = Promo(
        id: 'p_1',
        name: 'Buy 2 Selecta Take 1 Other',
        rules: const [
          PromoRule(productId: 'sel_1', productName: 'Cornetto', requiredQty: 2),
        ],
        reward: const PromoReward(
          type: 'freeItem',
          freeItems: [
            PromoFreeItem(productId: 'oth_1', productName: 'Free Wafer', quantity: 1),
          ],
        ),
        limitPerStore: 1,
        fundedBy: 'supplier',
        supplierName: 'Unilever',
        supplierRefundable: true,
        createdDate: Timestamp.now(),
        lastUpdatedDate: Timestamp.now(),
      );

      final json = promo.toJson();
      expect(json['name'], 'Buy 2 Selecta Take 1 Other');
      expect(json['fundedBy'], 'supplier');
      expect(json['supplierRefundable'], isTrue);
      expect(json['limitPerStore'], 1);

      final restored = Promo.fromJson(json, 'p_1');
      expect(restored.id, 'p_1');
      expect(restored.rules.length, 1);
      expect(restored.rules.first.requiredQty, 2);
      expect(restored.reward.freeItems.first.productName, 'Free Wafer');
    });
  });
}
