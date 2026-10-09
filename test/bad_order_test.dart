import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/controllers/badorder_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/badorder.dart';
import 'package:selecta_ops/models/selecta_product.dart';

import 'package:selecta_ops/services/badorder_service.dart';
import 'package:selecta_ops/services/hapistore_service.dart';

class FakeBadOrderService extends Fake implements BadOrderService {}
class FakeHapiStoreService extends Fake implements HapiStoreService {}

// ignore: subtype_of_sealed_class
class FakeBadOrderDoc extends Fake implements QueryDocumentSnapshot<BadOrder> {
  final BadOrder _data;
  final String _id;
  FakeBadOrderDoc(this._data, [this._id = '']);

  @override
  BadOrder data() => _data;

  @override
  String get id => _id;
}

void main() {
  group('Bad Order Models & Pricing Logic Tests', () {
    test('SelectaProduct pricing rules for By Piece vs By Case', () {
      final byPieceProduct = SelectaProduct(
        id: 'p_piece',
        productName: 'Cornetto Choco',
        itemCode: 'P1',
        category: 'By Piece',
        imageUrl: '',
        buyingPrice: 22.50,
        sellingPrice: 30.00,
      );

      expect(byPieceProduct.boPricePerPiece, equals(22.50));
      expect(byPieceProduct.isBoPriceConfigured, isTrue);

      final byCaseProductUnconfigured = SelectaProduct(
        id: 'p_case_1',
        productName: 'Chocky Case',
        itemCode: 'C1',
        category: 'By Case',
        imageUrl: '',
        buyingPrice: 248.00,
        sellingPrice: 320.00,
        badOrderPricePerPiece: null,
      );

      expect(byCaseProductUnconfigured.boPricePerPiece, equals(0.0));
      expect(byCaseProductUnconfigured.isBoPriceConfigured, isFalse);

      final byCaseProductConfigured = SelectaProduct(
        id: 'p_case_2',
        productName: 'Chocky Case',
        itemCode: 'C2',
        category: 'By Case',
        imageUrl: '',
        buyingPrice: 248.00,
        sellingPrice: 320.00,
        badOrderPricePerPiece: 8.00,
      );

      expect(byCaseProductConfigured.boPricePerPiece, equals(8.00));
      expect(byCaseProductConfigured.isBoPriceConfigured, isTrue);
    });

    test('BadOrderItem correctly serializes and deserializes', () {
      final item = const BadOrderItem(
        productId: 'prod_123',
        productName: 'Chocky',
        category: 'By Case',
        quantity: 5,
        pricePerPiece: 8.0,
        subtotal: 40.0,
        imageUrl: 'https://example.com/chocky.png',
      );

      final json = item.toJson();
      expect(json['productId'], 'prod_123');
      expect(json['productName'], 'Chocky');
      expect(json['quantity'], 5);
      expect(json['pricePerPiece'], 8.0);
      expect(json['subtotal'], 40.0);

      final restored = BadOrderItem.fromJson(json);
      expect(restored.productId, item.productId);
      expect(restored.productName, item.productName);
      expect(restored.quantity, item.quantity);
      expect(restored.pricePerPiece, item.pricePerPiece);
      expect(restored.subtotal, item.subtotal);
    });

    test('BadOrder model computes total amount from items and serializes properly', () {
      final now = Timestamp.now();
      final items = [
        const BadOrderItem(
          productId: 'p1',
          productName: 'Cornetto Choco',
          category: 'By Piece',
          quantity: 2,
          pricePerPiece: 22.50,
          subtotal: 45.0,
        ),
        const BadOrderItem(
          productId: 'p2',
          productName: 'Chocky',
          category: 'By Case',
          quantity: 10,
          pricePerPiece: 8.00,
          subtotal: 80.0,
        ),
      ];

      final bo = BadOrder(
        id: 'bo_test_1',
        hapistore: 'Store Alpha',
        badorderDate: now,
        imagePath: 'https://storage.googleapis.com/test/bo.jpg',
        status: BadOrderStatus.storePullout,
        notes: 'Melted upon delivery arrival',
        items: items,
        createdBy: 'Salesman John',
        lastUpdatedBy: 'Salesman John',
        createdDate: now,
        lastupdatedDate: now,
      );

      expect(bo.totalAmount, equals(125.0));
      expect(bo.badorderAmount, equals(125.0));
      expect(bo.isNewRecord, isTrue);

      final json = bo.toJson();
      expect(json['hapistore'], 'Store Alpha');
      expect(json['badorderAmount'], 125.0);
      expect(json['status'], BadOrderStatus.storePullout);
      expect(json['imagePath'], 'https://storage.googleapis.com/test/bo.jpg');
      expect(json['items'], isA<List>());
      expect((json['items'] as List).length, 2);

      final restored = BadOrder.fromJson(json, 'bo_test_1');
      expect(restored.id, 'bo_test_1');
      expect(restored.totalAmount, equals(125.0));
      expect(restored.items.length, 2);
      expect(restored.status, BadOrderStatus.storePullout);
    });

    test('Old legacy bad order records are identified and filtered out by BadOrderController', () {
      final now = Timestamp.now();

      // Legacy record: has flat amount, no items, schemaVersion 1
      final legacyRecord = BadOrder(
        id: 'legacy_1',
        hapistore: 'Old Store',
        badorderDate: now,
        items: const [],
        badorderAmount: 500.0,
        schemaVersion: 1,
        createdBy: 'Old Salesman',
        lastUpdatedBy: 'Old Salesman',
        createdDate: now,
        lastupdatedDate: now,
      );
      expect(legacyRecord.isNewRecord, isFalse);

      // New itemized record
      final newRecord = BadOrder(
        id: 'new_1',
        hapistore: 'Store Bravo',
        badorderDate: now,
        items: const [
          BadOrderItem(
            productId: 'p1',
            productName: 'Chocky',
            category: 'By Case',
            quantity: 3,
            pricePerPiece: 8.0,
            subtotal: 24.0,
          ),
        ],
        schemaVersion: 2,
        createdBy: 'Salesman Dave',
        lastUpdatedBy: 'Salesman Dave',
        createdDate: now,
        lastupdatedDate: now,
      );
      expect(newRecord.isNewRecord, isTrue);

      final controller = BadOrderController(
        badOrderService: FakeBadOrderService(),
        hapiStoreService: FakeHapiStoreService(),
      );
      final filtered = controller.filterBadOrders(
        docs: [
          FakeBadOrderDoc(legacyRecord, 'legacy_1'),
          FakeBadOrderDoc(newRecord, 'new_1'),
        ],
        searchQuery: '',
        selectedPeriod: 'All',
        statusFilter: 'All',
        now: DateTime.now(),
      );

      expect(filtered.filteredDocs.length, equals(1));
      expect(filtered.filteredDocs.first.id, equals('new_1'));
      expect(filtered.allCount, equals(1));
      expect(filtered.periodTotalAmount, equals(24.0));
    });

    test('BadOrderController filterBadOrders status and search filtering', () {
      final now = Timestamp.now();
      final r1 = BadOrder(
        id: 'r1',
        hapistore: '7-Eleven Cubao',
        badorderDate: now,
        status: BadOrderStatus.storePullout,
        notes: 'Crushed box',
        items: const [
          BadOrderItem(
            productId: 'p1',
            productName: 'Magnum Classic',
            category: 'By Piece',
            quantity: 2,
            pricePerPiece: 60.0,
            subtotal: 120.0,
          ),
        ],
        createdBy: 'Dealer A',
        lastUpdatedBy: 'Dealer A',
        createdDate: now,
        lastupdatedDate: now,
      );

      final r2 = BadOrder(
        id: 'r2',
        hapistore: 'Ministop Anonas',
        badorderDate: now,
        status: BadOrderStatus.settled,
        notes: 'Settled by dealer',
        items: const [
          BadOrderItem(
            productId: 'p2',
            productName: 'Cornetto Vanilla',
            category: 'By Piece',
            quantity: 1,
            pricePerPiece: 30.0,
            subtotal: 30.0,
          ),
        ],
        createdBy: 'Dealer A',
        lastUpdatedBy: 'Dealer A',
        createdDate: now,
        lastupdatedDate: now,
      );

      final controller = BadOrderController(
        badOrderService: FakeBadOrderService(),
        hapiStoreService: FakeHapiStoreService(),
      );
      final docs = [FakeBadOrderDoc(r1, 'r1'), FakeBadOrderDoc(r2, 'r2')];

      // Filter by status: settled
      final settledResult = controller.filterBadOrders(
        docs: docs,
        searchQuery: '',
        selectedPeriod: 'All',
        statusFilter: BadOrderStatus.settled,
        now: DateTime.now(),
      );
      expect(settledResult.filteredDocs.length, 1);
      expect(settledResult.filteredDocs.first.id, 'r2');

      // Filter by search query: product name match
      final magnumResult = controller.filterBadOrders(
        docs: docs,
        searchQuery: 'magnum',
        selectedPeriod: 'All',
        statusFilter: 'All',
        now: DateTime.now(),
      );
      expect(magnumResult.filteredDocs.length, 1);
      expect(magnumResult.filteredDocs.first.id, 'r1');

      // Filter by search query: store name match
      final cubaoResult = controller.filterBadOrders(
        docs: docs,
        searchQuery: 'cubao',
        selectedPeriod: 'All',
        statusFilter: 'All',
        now: DateTime.now(),
      );
      expect(cubaoResult.filteredDocs.length, 1);
      expect(cubaoResult.filteredDocs.first.id, 'r1');
    });
  });
}
