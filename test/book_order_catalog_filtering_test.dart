import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/inventory_movement.dart';

void main() {
  group('Book Order Catalog Browsing & Filtering Tests', () {
    InventoryItem createTestItem({
      required String id,
      required String name,
      required String itemCode,
      required String category,
      required double price,
      InventoryProductSource source = InventoryProductSource.selecta,
      String tag = '',
      int availableQty = 10,
    }) {
      return InventoryItem(
        id: id,
        productName: name,
        itemCode: itemCode,
        imageUrl: '',
        buyingPrice: 10,
        sellingPrice: price,
        isActive: true,
        stockQuantity: availableQty,
        lowStockThreshold: 5,
        source: source,
        category: category,
        tag: tag,
      );
    }

    final catalog = [
      createTestItem(
        id: '1',
        name: 'P20 CREAMDAE CUPS CHOCO',
        itemCode: 'SKU-CRMD-20',
        category: 'By Case',
        price: 264.7,
        tag: ProductTag.bestSeller,
        availableQty: 15,
      ),
      createTestItem(
        id: '2',
        name: 'P10 CHOCKY STICK',
        itemCode: 'SKU-CHCK-10',
        category: 'By Case',
        price: 248.16,
        availableQty: 0, // Out of stock
      ),
      createTestItem(
        id: '3',
        name: 'P105 SUPREME COFFEE CRUMBLE 450ML',
        itemCode: 'SKU-SPRM-105',
        category: 'By Piece',
        price: 96.4,
        availableQty: 8,
      ),
      createTestItem(
        id: '4',
        name: 'P15 AVOCADO CHOCO',
        itemCode: 'SKU-AVCD-15',
        category: 'By Piece',
        price: 15.0,
        availableQty: 0, // Out of stock
      ),
      createTestItem(
        id: '5',
        name: 'Heavy Duty Plastic Ice Bag',
        itemCode: 'SKU-BAG-HD',
        category: 'Supplies',
        price: 25.0,
        source: InventoryProductSource.other,
        availableQty: 50,
      ),
    ];

    test('Category Filter Chips: filters by Category correctly', () {
      // Best sellers
      final bestSellers = catalog.where((item) {
        return item.source == InventoryProductSource.selecta && ProductTag.isBestSeller(item.tag);
      }).toList();
      expect(bestSellers.map((i) => i.id), ['1']);

      // By Case
      final byCase = catalog.where((item) {
        return item.source == InventoryProductSource.selecta &&
            !ProductTag.isBestSeller(item.tag) &&
            item.category.trim().toLowerCase().contains('case');
      }).toList();
      expect(byCase.map((i) => i.id), ['2']);

      // By Piece
      final byPiece = catalog.where((item) {
        return item.source == InventoryProductSource.selecta &&
            !ProductTag.isBestSeller(item.tag) &&
            !item.category.trim().toLowerCase().contains('case');
      }).toList();
      expect(byPiece.map((i) => i.id), ['3', '4']);

      // Other
      final other = catalog.where((item) => item.source != InventoryProductSource.selecta).toList();
      expect(other.map((i) => i.id), ['5']);
    });

    test('Expanded Search: finds item by SKU / itemCode, category, and flavor', () {
      bool matchesSearch(InventoryItem item, String query) {
        final q = query.toLowerCase();
        final nameMatch = item.productName.toLowerCase().contains(q);
        final codeMatch = item.itemCode.toLowerCase().contains(q);
        final catMatch = item.category.toLowerCase().contains(q);
        final tagMatch = item.tag.toLowerCase().contains(q);
        return nameMatch || codeMatch || catMatch || tagMatch;
      }

      // Search by SKU
      final matchSku = catalog.where((i) => matchesSearch(i, 'SPRM-105')).toList();
      expect(matchSku.length, 1);
      expect(matchSku.first.productName, 'P105 SUPREME COFFEE CRUMBLE 450ML');

      // Search by Category name
      final matchCat = catalog.where((i) => matchesSearch(i, 'Supplies')).toList();
      expect(matchCat.length, 1);
      expect(matchCat.first.productName, 'Heavy Duty Plastic Ice Bag');

      // Search by Product name / flavor keyword
      final matchFlavor = catalog.where((i) => matchesSearch(i, 'avocado')).toList();
      expect(matchFlavor.length, 1);
      expect(matchFlavor.first.productName, 'P15 AVOCADO CHOCO');
    });

    test('Hide Out of Stock Toggle: removes zero available stock items', () {
      final inStockOnly = catalog.where((i) => i.availableQuantity > 0).toList();
      expect(inStockOnly.map((i) => i.id), ['1', '3', '5']);
      expect(inStockOnly.any((i) => i.id == '2' || i.id == '4'), isFalse);
    });

    test('Unplaced Recommendations Chip: filters strictly to unplaced best sellers', () {
      // Suppose the store has already placed 'P20 CREAMDAE CUPS CHOCO'
      final placedProductNames = {'p20 creamdae cups choco'};

      final unplaced = catalog.where((item) {
        return item.source == InventoryProductSource.selecta &&
            ProductTag.isBestSeller(item.tag) &&
            !placedProductNames.contains(item.productName.trim().toLowerCase());
      }).toList();

      expect(unplaced.isEmpty, isTrue); // item 1 was placed

      // If store has NOT placed 'P20 CREAMDAE CUPS CHOCO'
      final unplacedWithoutPlacement = catalog.where((item) {
        return item.source == InventoryProductSource.selecta &&
            ProductTag.isBestSeller(item.tag) &&
            !<String>{}.contains(item.productName.trim().toLowerCase());
      }).toList();

      expect(unplacedWithoutPlacement.map((i) => i.id), ['1']);
    });
  });
}
