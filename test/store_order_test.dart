import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/controllers/store_cart_controller.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/models/store_order.dart';
import 'package:selecta_ops/services/store_auth_service.dart';

void main() {
  group('StoreOrderItem Tests', () {
    test('Calculates lineTotal, totalPrice, and effectivePrice correctly', () {
      const item = StoreOrderItem(
        productId: 'prod_1',
        name: 'Cornetto Chocolate',
        uom: 'piece',
        qty: 10,
        unitPrice: 30.0,
        qtyApproved: 8,
      );

      expect(item.productName, 'Cornetto Chocolate');
      expect(item.packaging, 'piece');
      expect(item.qtyOrdered, 10);
      expect(item.qtyApproved, 8);
      expect(item.effectiveQty, 8);
      expect(item.totalPrice, 300.0);
      expect(item.effectivePrice, 240.0);
    });

    test('StoreOrderItem serialization and deserialization roundtrip', () {
      const item = StoreOrderItem(
        productId: 'prod_2',
        name: 'Magnum Classic',
        uom: 'piece',
        qty: 5,
        unitPrice: 65.0,
        qtyApproved: 5,
        category: 'Ice Cream',
        flavor: 'Vanilla Chocolate',
        imageUrl: 'https://example.com/magnum.png',
      );

      final json = item.toJson();
      final restored = StoreOrderItem.fromJson(json);

      expect(restored.productId, 'prod_2');
      expect(restored.productName, 'Magnum Classic');
      expect(restored.qtyOrdered, 5);
      expect(restored.unitPrice, 65.0);
      expect(restored.lineTotal, 325.0);
      expect(restored.qtyApproved, 5);
    });
  });

  group('StoreOrder Model & Lifecycle Tests', () {
    test('Lifecycle status helpers report correct state', () {
      final now = Timestamp.now();
      final orderSubmitted = StoreOrder(
        id: 'so_1',
        orderNo: 'SO-20261024-0001',
        storeId: 'store_123',
        storeName: 'Aling Nena Tindahan',
        status: StoreOrderStatus.submitted,
        items: const [],
        totalAmount: 500.0,
        createdBy: 'user_1',
        createdAt: now,
        updatedAt: now,
      );

      expect(orderSubmitted.isSubmitted, isTrue);
      expect(orderSubmitted.isApproved, isFalse);
      expect(orderSubmitted.isOutForDelivery, isFalse);
      expect(orderSubmitted.isDelivered, isFalse);
      expect(orderSubmitted.isCancelled, isFalse);
      expect(orderSubmitted.isRejected, isFalse);

      final orderApproved = orderSubmitted.copyWith(
        status: StoreOrderStatus.approved,
        approvedAmount: 480.0,
        deliveryId: 'del_999',
      );

      expect(orderApproved.isSubmitted, isFalse);
      expect(orderApproved.isApproved, isTrue);
      expect(orderApproved.effectiveAmount, 480.0);
      expect(orderApproved.deliveryId, 'del_999');

      final orderDelivered = orderApproved.copyWith(
        status: StoreOrderStatus.delivered,
      );
      expect(orderDelivered.isDelivered, isTrue);
    });

    test('StoreOrder JSON serialization roundtrip with status history', () {
      final now = Timestamp.now();
      final order = StoreOrder(
        id: 'so_2',
        orderNo: 'SO-20261024-0002',
        storeId: 'store_456',
        storeName: 'Barangay Corner Store',
        status: StoreOrderStatus.approved,
        items: const [
          StoreOrderItem(
            productId: 'p1',
            name: 'Pint Vanilla',
            qty: 4,
            unitPrice: 120.0,
            qtyApproved: 3,
          ),
        ],
        totalAmount: 480.0,
        approvedAmount: 360.0,
        deliveryDate: now,
        remarks: 'Please deliver morning',
        source: 'store',
        deliveryId: 'delivery_456',
        statusHistory: [
          StoreOrderStatusHistory(
            status: StoreOrderStatus.submitted,
            at: now,
            byUid: 'store_user',
            byName: 'Store Owner',
          ),
          StoreOrderStatusHistory(
            status: StoreOrderStatus.approved,
            at: now,
            byUid: 'dealer_user',
            byName: 'Dealer Manager',
          ),
        ],
        createdBy: 'store_user',
        createdAt: now,
        updatedAt: now,
      );

      final json = order.toJson();
      final restored = StoreOrder.fromJson(json, id: 'so_2');

      expect(restored.id, 'so_2');
      expect(restored.orderNo, 'SO-20261024-0002');
      expect(restored.storeName, 'Barangay Corner Store');
      expect(restored.status, StoreOrderStatus.approved);
      expect(restored.items.length, 1);
      expect(restored.items.first.productName, 'Pint Vanilla');
      expect(restored.totalAmount, 480.0);
      expect(restored.approvedAmount, 360.0);
      expect(restored.effectiveAmount, 360.0);
      expect(restored.statusHistory.length, 2);
      expect(restored.statusHistory.first.status, StoreOrderStatus.submitted);
      expect(restored.statusHistory.last.status, StoreOrderStatus.approved);
    });
  });

  group('StoreCartController Tests', () {
    test('Manages items, quantities, and computes subtotal accurately', () {
      final cart = StoreCartController();
      cart.clearCart();

      final product1 = SelectaProduct(
        id: 'sp_1',
        itemCode: 'SP001',
        productName: 'Paddle Pop Rainbow',
        category: 'Stick',
        sellingPrice: 20.0,
        imageUrl: 'https://example.com/paddlepop.png',
      );

      final product2 = SelectaProduct(
        id: 'sp_2',
        itemCode: 'SP002',
        productName: 'Cornetto Disc',
        category: 'Cone',
        sellingPrice: 35.0,
        imageUrl: 'https://example.com/cornetto.png',
      );

      // Add 2 pieces of Product 1
      cart.addItem(product1, 'Piece', quantity: 2);
      expect(cart.itemCount, 2);
      expect(cart.subtotal, 40.0);

      // Add 1 case of Product 1 (using case packaging)
      cart.addItem(product1, 'Case', quantity: 1);
      expect(cart.itemCount, 3);
      expect(cart.subtotal, 40.0 + 20.0); // 1 piece default piecesPerCase = 1 * 20

      // Add 3 pieces of Product 2
      cart.addItem(product2, 'Piece', quantity: 3);
      expect(cart.subtotal, 60.0 + (3 * 35.0)); // 165.0

      // Update quantity
      cart.setQuantity(product1.id, 'Piece', 5);
      expect(cart.subtotal, (5 * 20.0) + 20.0 + (3 * 35.0)); // 100 + 20 + 105 = 225.0

      // Remove item
      cart.removeItem(product2.id, 'Piece');
      expect(cart.items.any((i) => i.product.id == product2.id), isFalse);
      expect(cart.subtotal, 120.0);

      cart.clearCart();
      expect(cart.isEmpty, isTrue);
      expect(cart.subtotal, 0.0);
    });

    test('1-Click Reorder loads previous store order into cart', () {
      final cart = StoreCartController();
      cart.clearCart();

      final previousOrder = StoreOrder(
        id: 'so_old',
        orderNo: 'SO-OLD-01',
        storeId: 'store_1',
        storeName: 'Test Store',
        status: StoreOrderStatus.delivered,
        items: const [
          StoreOrderItem(
            productId: 'p_reorder_1',
            name: 'Pint Double Dutch',
            uom: 'piece',
            qty: 2,
            unitPrice: 150.0,
          ),
          StoreOrderItem(
            productId: 'p_reorder_2',
            name: 'Twin Pops',
            uom: 'piece',
            qty: 5,
            unitPrice: 15.0,
          ),
        ],
        totalAmount: 375.0,
        createdBy: 'user',
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      );

      cart.loadFromStoreOrder(previousOrder);

      expect(cart.items.length, 2);
      expect(cart.subtotal, (2 * 150.0) + (5 * 15.0)); // 375.0
      expect(cart.items.first.product.productName, 'Pint Double Dutch');
      expect(cart.items.first.quantity, 2);
      expect(cart.items.last.product.productName, 'Twin Pops');
      expect(cart.items.last.quantity, 5);

      cart.clearCart();
    });
  });

  group('StoreAuthService Username Validation Rules', () {
    test('Accepts valid usernames', () {
      expect(StoreAuthService.validateUsername('store123'), isNull);
      expect(StoreAuthService.validateUsername('aling.nena'), isNull);
      expect(StoreAuthService.validateUsername('sari_sari-store'), isNull);
      expect(StoreAuthService.validateUsername('abcd'), isNull); // min 4 chars
      expect(StoreAuthService.validateUsername('twenty_characters_01'), isNull); // 20 chars
    });

    test('Rejects invalid usernames with helpful error messages', () {
      // Too short
      expect(StoreAuthService.validateUsername('abc'), isNotNull);

      // Too long (> 20 chars)
      expect(StoreAuthService.validateUsername('this_username_is_way_too_long_for_store'), isNotNull);

      // Invalid special characters
      expect(StoreAuthService.validateUsername('store@123'), isNotNull);
      expect(StoreAuthService.validateUsername('store#name'), isNotNull);
      expect(StoreAuthService.validateUsername('store name'), isNotNull);
      expect(StoreAuthService.validateUsername('store!'), isNotNull);
    });
  });

  group('Configuration Cut-Off Time & Minimum Order Value Tests', () {
    test('Identifies cut-off time transitions', () {
      final config = Configuration.empty().copyWith(
        storeMinimumOrderValue: 1000.0,
        storeCutoffTime: '17:00', // 5:00 PM
      );

      expect(config.hasStoreMinimumOrderValue, isTrue);
      expect(config.hasStoreCutoffTime, isTrue);

      final beforeCutoff = DateTime(2026, 10, 24, 16, 30); // 4:30 PM
      expect(config.isAfterCutoff(beforeCutoff), isFalse);

      final afterCutoff = DateTime(2026, 10, 24, 17, 15); // 5:15 PM
      expect(config.isAfterCutoff(afterCutoff), isTrue);

      final exactlyAtCutoff = DateTime(2026, 10, 24, 17, 0); // 5:00 PM
      expect(config.isAfterCutoff(exactlyAtCutoff), isFalse);
    });
  });
}
