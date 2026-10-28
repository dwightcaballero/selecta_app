import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/controllers/badorder_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/badorder.dart';
import 'package:selecta_ops/models/badorder_batch.dart';
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
  group('Bad Order Models & Dual Pricing Logic Tests', () {
    test('SelectaProduct refund rates for By Piece vs By Case', () {
      final byPieceProduct = SelectaProduct(
        id: 'p_piece',
        productName: 'Cornetto Choco',
        itemCode: 'P1',
        category: 'By Piece',
        imageUrl: '',
        buyingPrice: 22.50,
        sellingPrice: 30.00,
      );

      expect(byPieceProduct.isCaseProduct, isFalse);
      expect(byPieceProduct.isBoPricingReady, isTrue);
      expect(byPieceProduct.storeRefundPerPiece, equals(30.00));
      expect(byPieceProduct.supplierRefundPerPiece, equals(22.50));

      final byCaseUnconfigured = SelectaProduct(
        id: 'p_case_1',
        productName: 'Chocky Case',
        itemCode: 'C1',
        category: 'By Case',
        imageUrl: '',
        buyingPrice: 180.00,
        sellingPrice: 210.00,
        boPiecesPerCase: null,
      );

      expect(byCaseUnconfigured.isCaseProduct, isTrue);
      expect(byCaseUnconfigured.hasValidBoPiecesPerCase, isFalse);
      expect(byCaseUnconfigured.isBoPricingReady, isFalse);
      expect(byCaseUnconfigured.storeRefundPerPiece, equals(0.0));
      expect(byCaseUnconfigured.supplierRefundPerPiece, equals(0.0));

      final byCaseConfigured = SelectaProduct(
        id: 'p_case_2',
        productName: 'Chocky Case',
        itemCode: 'C2',
        category: 'By Case',
        imageUrl: '',
        buyingPrice: 180.00,
        sellingPrice: 210.00,
        boPiecesPerCase: 12,
      );

      expect(byCaseConfigured.isCaseProduct, isTrue);
      expect(byCaseConfigured.hasValidBoPiecesPerCase, isTrue);
      expect(byCaseConfigured.isBoPricingReady, isTrue);
      expect(byCaseConfigured.storeRefundPerPiece, equals(17.50)); // 210 / 12
      expect(byCaseConfigured.supplierRefundPerPiece, equals(15.00)); // 180 / 12
    });

    test('BadOrderItem.fromProduct By Piece dual pricing and subtotals', () {
      final product = SelectaProduct(
        id: 'piece_1',
        productName: 'Magnum Classic',
        itemCode: 'M1',
        category: 'By Piece',
        imageUrl: '',
        buyingPrice: 50.00,
        sellingPrice: 65.00,
      );

      final item = BadOrderItem.fromProduct(
        product: product,
        quantity: 3,
      );

      expect(item.pricePerPiece, equals(65.00)); // Store refund rate
      expect(item.subtotal, equals(195.00)); // 3 * 65.00
      expect(item.supplierPricePerPiece, equals(50.00)); // Supplier refund rate
      expect(item.supplierSubtotal, equals(150.00)); // 3 * 50.00
      expect(item.piecesPerCase, isNull);
    });

    test('BadOrderItem.fromProduct By Case dual pricing and subtotals', () {
      final product = SelectaProduct(
        id: 'case_1',
        productName: 'Twin Pops',
        itemCode: 'TP1',
        category: 'By Case',
        imageUrl: '',
        buyingPrice: 180.00,
        sellingPrice: 210.00,
        boPiecesPerCase: 12,
      );

      final item = BadOrderItem.fromProduct(
        product: product,
        quantity: 5,
      );

      expect(item.pricePerPiece, equals(17.50)); // 210 / 12
      expect(item.subtotal, equals(87.50)); // 5 * 17.50
      expect(item.supplierPricePerPiece, equals(15.00)); // 180 / 12
      expect(item.supplierSubtotal, equals(75.00)); // 5 * 15.00
      expect(item.piecesPerCase, equals(12));
      expect(item.caseSellingPrice, equals(210.00));
      expect(item.caseBuyingPrice, equals(180.00));
    });

    test('roundToTwoDecimals preserves rounding accuracy on fractional line items', () {
      // 5 pieces of a 100 peso case with 12 pieces:
      // 5 * (100 / 12) = 41.6666666667 -> 41.67
      final unrounded = 5 * (100.0 / 12.0);
      final rounded = roundToTwoDecimals(unrounded);
      expect(rounded, equals(41.67));

      expect(roundToTwoDecimals(10.004), equals(10.00));
      expect(roundToTwoDecimals(10.005), equals(10.01));
    });

    test('BadOrderItem serialization and deserialization with dual pricing', () {
      final item = const BadOrderItem(
        productId: 'prod_123',
        productName: 'Chocky',
        category: 'By Case',
        quantity: 5,
        pricePerPiece: 17.50,
        subtotal: 87.50,
        supplierPricePerPiece: 15.00,
        supplierSubtotal: 75.00,
        piecesPerCase: 12,
        caseSellingPrice: 210.00,
        caseBuyingPrice: 180.00,
        imageUrl: 'https://example.com/chocky.png',
      );

      final json = item.toJson();
      expect(json['productId'], 'prod_123');
      expect(json['productName'], 'Chocky');
      expect(json['pricePerPiece'], 17.50);
      expect(json['subtotal'], 87.50);
      expect(json['supplierPricePerPiece'], 15.00);
      expect(json['supplierSubtotal'], 75.00);
      expect(json['piecesPerCase'], 12);
      expect(json['caseSellingPrice'], 210.00);
      expect(json['caseBuyingPrice'], 180.00);

      final restored = BadOrderItem.fromJson(json);
      expect(restored.productId, item.productId);
      expect(restored.pricePerPiece, equals(17.50));
      expect(restored.subtotal, equals(87.50));
      expect(restored.supplierPricePerPiece, equals(15.00));
      expect(restored.supplierSubtotal, equals(75.00));
      expect(restored.piecesPerCase, equals(12));
      expect(restored.isLegacy, isFalse);
    });

    test('BadOrderItem deserializes legacy JSON gracefully (fallback to pricePerPiece)', () {
      final legacyJson = {
        'productId': 'legacy_prod',
        'productName': 'Old Item',
        'category': 'By Piece',
        'quantity': 2,
        'pricePerPiece': 25.0,
        'subtotal': 50.0,
      };

      final restored = BadOrderItem.fromJson(legacyJson);
      expect(restored.productId, 'legacy_prod');
      expect(restored.pricePerPiece, equals(25.0));
      expect(restored.subtotal, equals(50.0));
      // Legacy fallback in fromJson defaults supplier values to store values and marks isLegacy
      expect(restored.supplierPricePerPiece, equals(25.0));
      expect(restored.supplierSubtotal, equals(50.0));
      expect(restored.isLegacy, isTrue);
    });

    test('BadOrder model computes store total, supplier amount, and net loss amount', () {
      final now = Timestamp.now();
      final items = [
        const BadOrderItem(
          productId: 'p1',
          productName: 'Cornetto Choco',
          category: 'By Piece',
          quantity: 2,
          pricePerPiece: 30.00,
          subtotal: 60.00,
          supplierPricePerPiece: 22.50,
          supplierSubtotal: 45.00,
        ),
        const BadOrderItem(
          productId: 'p2',
          productName: 'Chocky',
          category: 'By Case',
          quantity: 10,
          pricePerPiece: 17.50,
          subtotal: 175.00,
          supplierPricePerPiece: 15.00,
          supplierSubtotal: 150.00,
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
        supplierAmount: 195.00, // 45 + 150
        schemaVersion: 3,
        createdBy: 'Salesman John',
        lastUpdatedBy: 'Salesman John',
        createdDate: now,
        lastupdatedDate: now,
      );

      expect(bo.totalAmount, equals(235.0)); // 60 + 175
      expect(bo.supplierAmount, equals(195.0)); // 45 + 150
      expect(bo.netLossAmount, equals(40.0)); // 235 - 195
      expect(bo.hasDualPricing, isTrue);
      expect(bo.isNewRecord, isTrue);

      final json = bo.toJson();
      expect(json['schemaVersion'], 3);
      expect(json['supplierAmount'], 195.0);
      expect(json['badorderAmount'], 235.0);

      final restored = BadOrder.fromJson(json, 'bo_test_1');
      expect(restored.id, 'bo_test_1');
      expect(restored.totalAmount, equals(235.0));
      expect(restored.supplierAmount, equals(195.0));
      expect(restored.netLossAmount, equals(40.0));
      expect(restored.hasDualPricing, isTrue);
    });

    test('BadOrderBatch model supports supplier_buying_v1 and legacy basis', () {
      final now = Timestamp.now();

      final newBatch = BadOrderBatch(
        batchNumber: 'BO-202610-001',
        supplierRefNo: 'DR-1234',
        pulloutDate: now,
        badOrderIds: ['bo1', 'bo2'],
        totalBatchAmount: 195.00, // Expected supplier refund
        totalStoreRefundAmount: 235.00, // Total store refund
        pricingBasis: 'supplier_buying_v1',
        createdBy: 'Dealer A',
        createdDate: now,
        lastUpdatedBy: 'Dealer A',
        lastupdatedDate: now,
      );

      expect(newBatch.isLegacyBasis, isFalse);
      expect(newBatch.totalBatchAmount, equals(195.00));
      expect(newBatch.totalStoreRefundAmount, equals(235.00));
      expect(newBatch.pricingBasis, equals('supplier_buying_v1'));

      final legacyBatch = BadOrderBatch(
        batchNumber: 'BO-202609-001',
        supplierRefNo: 'DR-0001',
        pulloutDate: now,
        badOrderIds: ['bo_old'],
        totalBatchAmount: 500.00,
        pricingBasis: 'store_selling_legacy',
        createdBy: 'Dealer A',
        createdDate: now,
        lastUpdatedBy: 'Dealer A',
        lastupdatedDate: now,
      );

      expect(legacyBatch.isLegacyBasis, isTrue);
      expect(legacyBatch.totalStoreRefundAmount, isNull);
    });

    test('Old legacy bad order records without items are handled properly by controller', () {
      final now = Timestamp.now();

      // Legacy record: flat amount, no items, schemaVersion 1
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
      expect(legacyRecord.hasDualPricing, isFalse);
      expect(legacyRecord.netLossAmount, equals(500.0)); // 100% loss

      // New itemized record with dual pricing
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
            pricePerPiece: 17.5,
            subtotal: 52.5,
            supplierPricePerPiece: 15.0,
            supplierSubtotal: 45.0,
          ),
        ],
        supplierAmount: 45.0,
        schemaVersion: 3,
        createdBy: 'Salesman Dave',
        lastUpdatedBy: 'Salesman Dave',
        createdDate: now,
        lastupdatedDate: now,
      );
      expect(newRecord.isNewRecord, isTrue);
      expect(newRecord.hasDualPricing, isTrue);
      expect(newRecord.netLossAmount, equals(7.5));

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
      expect(filtered.periodTotalAmount, equals(52.5));
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
            supplierPricePerPiece: 50.0,
            supplierSubtotal: 100.0,
          ),
        ],
        supplierAmount: 100.0,
        schemaVersion: 3,
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
            supplierPricePerPiece: 22.5,
            supplierSubtotal: 22.5,
          ),
        ],
        supplierAmount: 22.5,
        schemaVersion: 3,
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
