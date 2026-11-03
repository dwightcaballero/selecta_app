import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/placement.dart';
import 'package:selecta_ops/models/placement_pair.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/services/placement_report_builder.dart';

void main() {
  group('PlacementReportBuilder Tests', () {
    // Helper to create test products
    SelectaProduct makeProduct({required String id, required String name, required String category, required double price}) {
      return SelectaProduct(
        id: id,
        itemCode: id,
        productName: name,
        category: category,
        sellingPrice: price,
        buyingPrice: price * 0.8,
        imageUrl: 'https://example.com/$id.png',
        tag: ProductTag.bestSeller,
        isActive: true,
      );
    }

    test('Column sort: By Case (SRP asc) -> By Piece (SRP asc) -> ties by name', () {
      final p1 = makeProduct(id: '1', name: 'Cornetto Disc 35', category: 'By Piece', price: 35.0);
      final p2 = makeProduct(id: '2', name: 'Magnum Classic 65', category: 'By Piece', price: 65.0);
      final p3 = makeProduct(id: '3', name: 'Super Thick Vanilla 150', category: 'By Case', price: 150.0);
      final p4 = makeProduct(id: '4', name: 'Party Pack Chocolate 100', category: 'By Case', price: 100.0);
      final p5 = makeProduct(id: '5', name: 'Alpha Piece 35', category: 'By Piece', price: 35.0);
      final p6 = makeProduct(id: '6', name: 'Beta Plain (No SRP)', category: 'By Piece', price: 20.0);

      final columns = PlacementReportBuilder.buildColumns(bestSellers: [p1, p2, p3, p4, p5, p6], pairs: const []);

      final columnLabels = columns.map((c) => c.label).toList();

      // "By Case" first (SRP 100 then 150), then "By Piece"
      // p6 has no SRP in name, falls back to selling price 20.0
      // p1 & p5 both have SRP 35, sorted alphabetically: Alpha Piece 35 before Cornetto Disc 35
      // p2 has SRP 65
      expect(columnLabels, [
        'Party Pack Chocolate 100',
        'Super Thick Vanilla 150',
        'Beta Plain (No SRP)',
        'Alpha Piece 35',
        'Cornetto Disc 35',
        'Magnum Classic 65',
      ]);
    });

    test('Pair merge: one column, label A / B, placed if either member is placed', () {
      final p1 = makeProduct(id: 'p1', name: 'Cornetto Choc 35', category: 'By Piece', price: 35.0);
      final p2 = makeProduct(id: 'p2', name: 'Cornetto Van 35', category: 'By Piece', price: 35.0);
      final p3 = makeProduct(id: 'p3', name: 'Magnum Almond 70', category: 'By Piece', price: 70.0);

      final pair = const PlacementPair(product1: 'Cornetto Choc 35', product2: 'Cornetto Van 35');

      final columns = PlacementReportBuilder.buildColumns(bestSellers: [p1, p2, p3], pairs: [pair]);

      // p1 and p2 should merge into 1 column
      expect(columns.length, 2);
      expect(columns[0].isPair, isTrue);
      expect(columns[0].label, 'Cornetto Choc 35 / Cornetto Van 35');
      expect(columns[0].products.length, 2);
      expect(columns[1].label, 'Magnum Almond 70');

      // Test placement check: store placing only Cornetto Van 35 should have columns[0] marked placed
      final store = Hapistore.empty()..storeName = 'Store Alpha';
      final placement = Placement.empty()
        ..id = 'pl1'
        ..storeName = 'Store Alpha'
        ..placedProductNames = ['Cornetto Van 35'];

      final rows = PlacementReportBuilder.buildRows(
        stores: [store],
        columns: columns,
        placementsByStore: {'Store Alpha': placement},
        pairs: [pair],
        storesWithNewProduct: {},
      );

      expect(rows.first.placed[columns[0].key], isTrue);
      expect(rows.first.placed[columns[1].key], isFalse);
      expect(rows.first.placedCount, 1);
      expect(rows.first.totalCount, 2);
    });

    test('Pair with members in different categories puts column under first member category', () {
      final pCase = makeProduct(id: 'c1', name: 'Case Tub 120', category: 'By Case', price: 120.0);
      final pPiece = makeProduct(id: 'pc1', name: 'Piece Stick 40', category: 'By Piece', price: 40.0);

      final pair = const PlacementPair(product1: 'Piece Stick 40', product2: 'Case Tub 120');

      final columns = PlacementReportBuilder.buildColumns(bestSellers: [pCase, pPiece], pairs: [pair]);

      expect(columns.length, 1);
      // Fixed comparator puts By Case first
      expect(columns[0].category, 'By Case');
      expect(columns[0].label, 'Case Tub 120 / Piece Stick 40');
      expect(columns[0].primaryProduct.id, 'c1');
    });

    test('Pair where only one member is a Best Seller creates single column with pair placement support', () {
      final p1 = makeProduct(id: 'p1', name: 'Best Seller Twin 30', category: 'By Piece', price: 30.0);
      // p2 is NOT in best sellers list
      final pair = const PlacementPair(product1: 'Best Seller Twin 30', product2: 'Non Best Seller Partner');

      final columns = PlacementReportBuilder.buildColumns(bestSellers: [p1], pairs: [pair]);

      expect(columns.length, 1);
      expect(columns[0].isPair, isFalse);
      expect(columns[0].label, 'Best Seller Twin 30');

      // If store placed the paired non-best-seller partner, the Best Seller column is marked placed
      final store = Hapistore.empty()..storeName = 'Store Beta';
      final placement = Placement.empty()
        ..id = 'pl2'
        ..storeName = 'Store Beta'
        ..placedProductNames = ['Non Best Seller Partner'];

      final rows = PlacementReportBuilder.buildRows(
        stores: [store],
        columns: columns,
        placementsByStore: {'Store Beta': placement},
        pairs: [pair],
        storesWithNewProduct: {},
      );

      expect(rows.first.placed[columns[0].key], isTrue);
      expect(rows.first.placedCount, 1);
    });

    test('Store sort: pjpSequence ascending; null sequence last alphabetical by name', () {
      final s1 = Hapistore.empty()
        ..storeName = 'Zeta Store'
        ..pjpSequence = 2;
      final s2 = Hapistore.empty()
        ..storeName = 'Alpha Store'
        ..pjpSequence = null;
      final s3 = Hapistore.empty()
        ..storeName = 'Gamma Store'
        ..pjpSequence = 1;
      final s4 = Hapistore.empty()
        ..storeName = 'Beta Store'
        ..pjpSequence = null;

      final sorted = PlacementReportBuilder.sortStoresForDay([s1, s2, s3, s4]);

      expect(sorted.map((s) => s.storeName).toList(), [
        'Gamma Store', // seq 1
        'Zeta Store', // seq 2
        'Alpha Store', // null seq, A-Z
        'Beta Store', // null seq, A-Z
      ]);
    });

    test('New Product checks: Delivered counts; Pending/Voided/Returned and free rewards do not', () {
      final itemNew = const OrderItem(
        productId: 'np1',
        productName: 'New Cone 30',
        sellingPrice: 30.0,
        orderedQuantity: 5,
        pickedQuantity: 5,
        returnedQuantity: 0,
        tag: ProductTag.newProduct,
      );

      final itemFreeReward = const OrderItem(
        productId: 'np2',
        productName: 'New Promo Freebie',
        sellingPrice: 0.0,
        orderedQuantity: 1,
        pickedQuantity: 1,
        isFreeReward: true,
        tag: ProductTag.newProduct,
      );

      final itemReturnedAll = const OrderItem(
        productId: 'np3',
        productName: 'New Returned Item',
        sellingPrice: 40.0,
        orderedQuantity: 2,
        pickedQuantity: 2,
        returnedQuantity: 2, // net 0
        tag: ProductTag.newProduct,
      );

      final itemEmptyTag = const OrderItem(
        productId: 'np4',
        productName: 'Untagged Item In Delivery',
        sellingPrice: 50.0,
        orderedQuantity: 3,
        pickedQuantity: 3,
        returnedQuantity: 0,
        tag: '',
      );

      final now = Timestamp.now();

      final deliv1 = Delivery.empty()
        ..storeName = 'Store 1'
        ..transactionStatus = DeliveryStatus.delivered
        ..deliveryDate = now
        ..items = [itemNew];

      final deliv2Pending = Delivery.empty()
        ..storeName = 'Store 2'
        ..transactionStatus = DeliveryStatus.pending
        ..deliveryDate = now
        ..items = [itemNew];

      final deliv3Voided = Delivery.empty()
        ..storeName = 'Store 3'
        ..transactionStatus = DeliveryStatus.voided
        ..deliveryDate = now
        ..items = [itemNew];

      final deliv4Returned = Delivery.empty()
        ..storeName = 'Store 4'
        ..transactionStatus = DeliveryStatus.returned
        ..deliveryDate = now
        ..items = [itemNew];

      final deliv5FreeOnly = Delivery.empty()
        ..storeName = 'Store 5'
        ..transactionStatus = DeliveryStatus.delivered
        ..deliveryDate = now
        ..items = [itemFreeReward];

      final deliv6NetZero = Delivery.empty()
        ..storeName = 'Store 6'
        ..transactionStatus = DeliveryStatus.delivered
        ..deliveryDate = now
        ..items = [itemReturnedAll];

      final deliv7CatalogLookup = Delivery.empty()
        ..storeName = 'Store 7'
        ..transactionStatus = DeliveryStatus.delivered
        ..deliveryDate = now
        ..items = [itemEmptyTag];

      final qualifyingStores = PlacementReportBuilder.findStoresWithNewProductOrders(
        deliveries: [deliv1, deliv2Pending, deliv3Voided, deliv4Returned, deliv5FreeOnly, deliv6NetZero, deliv7CatalogLookup],
        productTagsById: {'np4': ProductTag.newProduct},
      );

      expect(qualifyingStores.contains('Store 1'), isTrue);
      expect(qualifyingStores.contains('Store 2'), isFalse);
      expect(qualifyingStores.contains('Store 3'), isFalse);
      expect(qualifyingStores.contains('Store 4'), isFalse);
      expect(qualifyingStores.contains('Store 5'), isFalse);
      expect(qualifyingStores.contains('Store 6'), isFalse);
      expect(qualifyingStores.contains('Store 7'), isTrue);
    });

    test('Score, coverage, day section math, and empty/unplaced store handling', () {
      final p1 = makeProduct(id: '1', name: 'Product A 50', category: 'By Piece', price: 50.0);
      final p2 = makeProduct(id: '2', name: 'Product B 60', category: 'By Piece', price: 60.0);

      final columns = PlacementReportBuilder.buildColumns(bestSellers: [p1, p2], pairs: const []);

      final store1 = Hapistore.empty()
        ..storeName = 'Store 1'
        ..pjpSequence = 1;
      final store2 = Hapistore.empty()
        ..storeName = 'Store 2 (No Placement)'
        ..pjpSequence = 2;

      final pl1 = Placement.empty()
        ..id = 'pl1'
        ..storeName = 'Store 1'
        ..placedProductNames = ['Product A 50'];

      final rows = PlacementReportBuilder.buildRows(
        stores: [store1, store2],
        columns: columns,
        placementsByStore: {'Store 1': pl1},
        pairs: const [],
        storesWithNewProduct: {'Store 1'},
      );

      expect(rows[0].placedCount, 1);
      expect(rows[0].totalCount, 2);
      expect(rows[0].orderedNewProduct, isTrue);

      expect(rows[1].placedCount, 0);
      expect(rows[1].totalCount, 2);
      expect(rows[1].orderedNewProduct, isFalse);

      final section = PlacementReportBuilder.buildDaySection(day: 'Monday', rows: rows, columns: columns);

      expect(section.totalStores, 2);
      expect(section.dayPlacedTargets, 1);
      expect(section.dayTotalTargets, 4);
      expect(section.dayPlacementPercentage, 25.0);
      expect(section.perColumnPlacedCount[columns[0].key], 1);
      expect(section.perColumnPlacedCount[columns[1].key], 0);
      expect(section.newProductOrderedCount, 1);

      // Pitch list
      final pitchList = PlacementReportBuilder.buildPitchList(sections: [section], columns: columns);
      expect(pitchList.length, 2);
      // Store 1 is missing Product B
      expect(pitchList[0].missingColumns.map((c) => c.label), ['Product B 60']);
      // Store 2 is missing both Product A and B
      expect(pitchList[1].missingColumns.length, 2);
    });

    test('Zero-store day section handles 0 gracefully', () {
      final p1 = makeProduct(id: '1', name: 'Product A 50', category: 'By Piece', price: 50.0);
      final columns = PlacementReportBuilder.buildColumns(bestSellers: [p1], pairs: const []);

      final emptySection = PlacementReportBuilder.buildDaySection(day: 'Sunday', rows: const [], columns: columns);

      expect(emptySection.totalStores, 0);
      expect(emptySection.dayPlacedTargets, 0);
      expect(emptySection.dayTotalTargets, 0);
      expect(emptySection.dayPlacementPercentage, 0.0);
      expect(emptySection.newProductOrderedCount, 0);
      expect(emptySection.perColumnPlacedCount[columns.first.key], 0);
    });
  });
}
