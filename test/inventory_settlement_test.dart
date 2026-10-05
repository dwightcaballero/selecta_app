import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/services/inventory_service.dart';

void main() {
  group('Inventory Settlement Calculation Tests', () {
    test('Delivered order without returns deducts physical stock and releases reserved floating stock', () {
      final item = const OrderItem(
        productId: 'prod_1',
        productName: 'Cornetto Chocolate',
        sellingPrice: 30.0,
        orderedQuantity: 10,
        pickedQuantity: 10,
        returnedQuantity: 0,
      );

      final delivery = Delivery.empty().copyWith(
        storeName: 'Store A',
        transactionStatus: DeliveryStatus.delivered,
        orderAmount: 300.0,
        items: [item],
        isInventoryReserved: true,
        isInventoryDeducted: false,
        isInventorySettled: false,
        createdDate: Timestamp.now(),
      );

      final plan = InventoryService.computeSettlement([
        (id: 'del_1', delivery: delivery),
      ]);

      expect(plan.totalDeliveriesToSettle, 1);
      expect(plan.deliveredCount, 1);
      expect(plan.returnedCount, 0);

      final delta = plan.getDelta('prod_1');
      expect(delta, isNotNull);
      expect(delta!.productName, 'Cornetto Chocolate');
      expect(delta.stockDelta, -10); // physical stock deducted
      expect(delta.reservedDelta, -10); // floating reservation released
    });

    test('Delivered order with itemized partial returns correctly computes delivered and return deltas', () {
      // Picked 10, Returned 3 -> Delivered 7
      final item = const OrderItem(
        productId: 'prod_cornetto',
        productName: 'Cornetto Vanilla',
        sellingPrice: 35.0,
        orderedQuantity: 10,
        pickedQuantity: 10,
        returnedQuantity: 3,
      );

      expect(item.deliveredQuantity, 7);
      expect(item.deliveredLineTotal, 245.0);
      expect(item.returnedLineTotal, 105.0);

      final delivery = Delivery.empty().copyWith(
        storeName: 'Store B',
        transactionStatus: DeliveryStatus.delivered,
        orderAmount: 245.0,
        originalOrderAmount: 350.0,
        returnAmount: 105.0,
        items: [item],
        isInventoryReserved: true,
        isInventoryDeducted: false,
        isInventorySettled: false,
        createdDate: Timestamp.now(),
      );

      expect(delivery.hasReturnedItems, isTrue);
      expect(delivery.totalReturnedItemsAmount, 105.0);

      final plan = InventoryService.computeSettlement([
        (id: 'del_2', delivery: delivery),
      ]);

      expect(plan.totalDeliveriesToSettle, 1);
      expect(plan.deliveredCount, 1);

      final delta = plan.getDelta('prod_cornetto');
      expect(delta, isNotNull);
      // Physical stock only deducted for 7 delivered units
      expect(delta!.stockDelta, -7);
      // Floating reservation released for all 10 units (7 delivered + 3 returned)
      expect(delta.reservedDelta, -10);
    });

    test('Full return on new workflow releases floating reservation without touching physical stock', () {
      final item = const OrderItem(
        productId: 'prod_tub',
        productName: 'Double Dutch Tub',
        sellingPrice: 150.0,
        orderedQuantity: 4,
        pickedQuantity: 4,
        returnedQuantity: 0,
      );

      final delivery = Delivery.empty().copyWith(
        storeName: 'Store C',
        transactionStatus: DeliveryStatus.returned,
        orderAmount: 600.0,
        items: [item],
        isInventoryReserved: true,
        isInventoryDeducted: false,
        isInventorySettled: false,
        createdDate: Timestamp.now(),
      );

      final plan = InventoryService.computeSettlement([
        (id: 'del_3', delivery: delivery),
      ]);

      expect(plan.totalDeliveriesToSettle, 1);
      expect(plan.deliveredCount, 0);
      expect(plan.returnedCount, 1);

      final delta = plan.getDelta('prod_tub');
      expect(delta, isNotNull);
      // Physical stock was never deducted, so stockDelta must be 0
      expect(delta!.stockDelta, 0);
      // Floating reserved stock was released, so reservedDelta is -4
      expect(delta.reservedDelta, -4);
    });

    test('Legacy order with isInventoryDeducted=true restocks returned quantity to physical inventory', () {
      final item = const OrderItem(
        productId: 'prod_legacy',
        productName: 'Legacy Pint',
        sellingPrice: 100.0,
        orderedQuantity: 5,
        pickedQuantity: 5,
        returnedQuantity: 2,
      );

      final delivery = Delivery.empty().copyWith(
        storeName: 'Store Legacy',
        transactionStatus: DeliveryStatus.delivered,
        orderAmount: 300.0,
        originalOrderAmount: 500.0,
        returnAmount: 200.0,
        items: [item],
        isInventoryReserved: false,
        isInventoryDeducted: true, // physical stock was already decremented by 5 in old system
        isInventorySettled: false,
        createdDate: Timestamp.now(),
      );

      final plan = InventoryService.computeSettlement([
        (id: 'del_legacy', delivery: delivery),
      ]);

      final delta = plan.getDelta('prod_legacy');
      expect(delta, isNotNull);
      // 2 returned units added back to physical stock
      expect(delta!.stockDelta, 2);
      expect(delta.reservedDelta, 0);
    });

    test('Multiple deliveries on same date correctly combine product deltas', () {
      final itemA = const OrderItem(
        productId: 'prod_magnum',
        productName: 'Magnum Classic',
        sellingPrice: 65.0,
        orderedQuantity: 10,
        pickedQuantity: 10,
        returnedQuantity: 0,
      );

      final itemB = const OrderItem(
        productId: 'prod_magnum',
        productName: 'Magnum Classic',
        sellingPrice: 65.0,
        orderedQuantity: 6,
        pickedQuantity: 6,
        returnedQuantity: 2,
      );

      final deliveryA = Delivery.empty().copyWith(
        storeName: 'Store A',
        transactionStatus: DeliveryStatus.delivered,
        orderAmount: 650.0,
        items: [itemA],
        isInventoryReserved: true,
        isInventoryDeducted: false,
        isInventorySettled: false,
        createdDate: Timestamp.now(),
      );

      final deliveryB = Delivery.empty().copyWith(
        storeName: 'Store B',
        transactionStatus: DeliveryStatus.delivered,
        orderAmount: 260.0,
        originalOrderAmount: 390.0,
        returnAmount: 130.0,
        items: [itemB],
        isInventoryReserved: true,
        isInventoryDeducted: false,
        isInventorySettled: false,
        createdDate: Timestamp.now(),
      );

      final plan = InventoryService.computeSettlement([
        (id: 'del_a', delivery: deliveryA),
        (id: 'del_b', delivery: deliveryB),
      ]);

      expect(plan.totalDeliveriesToSettle, 2);
      final delta = plan.getDelta('prod_magnum');
      expect(delta, isNotNull);
      // Delivery A: -10 stock, -10 reserved
      // Delivery B: -4 stock, -6 reserved
      // Total: -14 stock, -16 reserved
      expect(delta!.stockDelta, -14);
      expect(delta.reservedDelta, -16);
    });

    test('Already settled deliveries or pending orders are ignored by settlement engine', () {
      final settledDelivery = Delivery.empty().copyWith(
        storeName: 'Settled Store',
        transactionStatus: DeliveryStatus.delivered,
        orderAmount: 100.0,
        items: [
          const OrderItem(productId: 'prod_x', productName: 'Prod X', sellingPrice: 50.0, orderedQuantity: 2, pickedQuantity: 2),
        ],
        isInventorySettled: true,
        createdDate: Timestamp.now(),
      );

      final pendingDelivery = Delivery.empty().copyWith(
        storeName: 'Pending Store',
        transactionStatus: DeliveryStatus.pending,
        orderAmount: 100.0,
        items: [
          const OrderItem(productId: 'prod_x', productName: 'Prod X', sellingPrice: 50.0, orderedQuantity: 2, pickedQuantity: 2),
        ],
        isInventorySettled: false,
        createdDate: Timestamp.now(),
      );

      final plan = InventoryService.computeSettlement([
        (id: 'del_settled', delivery: settledDelivery),
        (id: 'del_pending', delivery: pendingDelivery),
      ]);

      expect(plan.totalDeliveriesToSettle, 0);
      expect(plan.deltas, isEmpty);
    });

    test('Delivery.fromJson resiliently parses strings, nulls, and unusual formats without throwing', () {
      final json = {
        'storeName': 'Store Robust',
        'remarks': '',
        'transactionStatus': DeliveryStatus.delivered,
        'orderAmount': '150.50',
        'originalOrderAmount': '200',
        'returnAmount': 0,
        'creditAmount': '0.0',
        'cashAmount': 150.50,
        'onlineAmount': '0',
        'deliveryDate': Timestamp.now(),
        'picklistSequence': '3',
        'deliverySequence': '1',
        'isInventorySettled': 'false',
        'isInventoryDeducted': 0,
        'isInventoryReserved': 1,
        'items': [
          {
            'productId': 'prod_str',
            'productName': 'Cornetto P35',
            'orderedQuantity': '5',
            'pickedQuantity': '5',
            'returnedQuantity': '1',
            'sellingPrice': '35.0',
            'buyingPrice': '25.0',
            'isPicked': 'true',
          }
        ],
      };

      final delivery = Delivery.fromJson(json);
      expect(delivery.orderAmount, 150.50);
      expect(delivery.originalOrderAmount, 200.0);
      expect(delivery.picklistSequence, 3);
      expect(delivery.deliverySequence, 1);
      expect(delivery.isInventorySettled, isFalse);
      expect(delivery.isInventoryDeducted, isFalse);
      expect(delivery.isInventoryReserved, isTrue);
      expect(delivery.items.length, 1);
      expect(delivery.items.first.pickedQuantity, 5);
      expect(delivery.items.first.returnedQuantity, 1);
      expect(delivery.items.first.deliveredQuantity, 4);
      expect(delivery.items.first.sellingPrice, 35.0);
      expect(delivery.items.first.isPicked, isTrue);
    });
  });
}
