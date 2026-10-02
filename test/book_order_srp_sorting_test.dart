import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/services/thermal_printer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SRP and Category Sorting Tests across all modules', () {
    InventoryItem createItem(
      String id,
      String name,
      double sellingPrice,
      String category, {
      InventoryProductSource source = InventoryProductSource.selecta,
      String tag = '',
    }) {
      return InventoryItem(
        id: id,
        productName: name,
        imageUrl: '',
        buyingPrice: 10,
        sellingPrice: sellingPrice,
        isActive: true,
        stockQuantity: 100,
        lowStockThreshold: 5,
        source: source,
        category: category,
        tag: tag,
      );
    }

    int compareProducts(InventoryItem a, InventoryItem b) {
      return Helperfunctions.compareBySrpAndName(
        nameA: a.productName,
        priceA: a.sellingPrice,
        nameB: b.productName,
        priceB: b.sellingPrice,
      );
    }

    test('Helperfunctions: P20 sorts before P105 (ascending numeric SRP)', () {
      final itemP105 = createItem('1', 'P105 SUPREME COFFEE CRUMBLE 450ML', 96.4, 'By Piece');
      final itemP20 = createItem('2', 'P20 CREAMDAE CUPS CHOCO', 264.7, 'By Case');

      final list = [itemP105, itemP20]..sort(compareProducts);

      expect(list.first.productName, equals('P20 CREAMDAE CUPS CHOCO'));
      expect(list.last.productName, equals('P105 SUPREME COFFEE CRUMBLE 450ML'));
    });

    test('Helperfunctions: Full Selecta SRP ascending sequence sorts properly', () {
      final items = [
        createItem('1', 'P105 SUPREME COFFEE CRUMBLE 450ML', 96.4, 'By Piece'),
        createItem('2', 'P20 CREAMDAE CUPS CHOCO', 264.7, 'By Case'),
        createItem('3', 'P10 CHOCKY', 248.16, 'By Case'),
        createItem('4', 'P199 BIRTHDAY ESPESYAL', 182.71, 'By Piece'),
        createItem('5', 'P25 CORNETTO', 551.46, 'By Case'),
        createItem('6', 'P15 AVOCADO CHOCO', 297.79, 'By Case'),
      ];

      items.sort(compareProducts);

      final names = items.map((i) => i.productName).toList();
      expect(names, [
        'P10 CHOCKY',
        'P15 AVOCADO CHOCO',
        'P20 CREAMDAE CUPS CHOCO',
        'P25 CORNETTO',
        'P105 SUPREME COFFEE CRUMBLE 450ML',
        'P199 BIRTHDAY ESPESYAL',
      ]);
    });

    test('Picklist: sorts indices using SRP ascending', () {
      final items = [
        const OrderItem(productId: '1', productName: 'P105 SUPREME PINT', imageUrl: '', productSource: 'selecta', category: 'By Piece', buyingPrice: 50, sellingPrice: 96.4, orderedQuantity: 5, pickedQuantity: 5),
        const OrderItem(productId: '2', productName: 'P20 CREAMDAE', imageUrl: '', productSource: 'selecta', category: 'By Case', buyingPrice: 200, sellingPrice: 264.7, orderedQuantity: 2, pickedQuantity: 2),
        const OrderItem(productId: '3', productName: 'P10 CHOCKY', imageUrl: '', productSource: 'selecta', category: 'By Case', buyingPrice: 180, sellingPrice: 248.16, orderedQuantity: 1, pickedQuantity: 1),
      ];

      final caseIndices = [1, 2];
      caseIndices.sort((a, b) => Helperfunctions.compareBySrpAndName(
        nameA: items[a].productName,
        priceA: items[a].sellingPrice,
        nameB: items[b].productName,
        priceB: items[b].sellingPrice,
      ));

      expect(items[caseIndices[0]].productName, 'P10 CHOCKY');
      expect(items[caseIndices[1]].productName, 'P20 CREAMDAE');
    });

    test('Delivery: Delivery.fromJson automatically parses and sorts items by category and SRP', () {
      final rawData = {
        'storeName': 'Test Store',
        'items': [
          {'productId': '1', 'productName': 'P105 SUPREME', 'category': 'By Piece', 'sellingPrice': 96.4, 'productSource': 'selecta', 'pickedQuantity': 1, 'orderedQuantity': 1},
          {'productId': '2', 'productName': 'P20 CREAMDAE', 'category': 'By Case', 'sellingPrice': 264.7, 'productSource': 'selecta', 'pickedQuantity': 1, 'orderedQuantity': 1},
          {'productId': '3', 'productName': 'P10 CHOCKY', 'category': 'By Case', 'sellingPrice': 248.16, 'productSource': 'selecta', 'pickedQuantity': 1, 'orderedQuantity': 1},
          {'productId': '4', 'productName': 'P60 BASO', 'category': 'By Piece', 'sellingPrice': 55.1, 'productSource': 'selecta', 'pickedQuantity': 1, 'orderedQuantity': 1},
          {'productId': '5', 'productName': 'Ice Bag Large', 'category': 'General', 'sellingPrice': 15.0, 'productSource': 'other', 'pickedQuantity': 1, 'orderedQuantity': 1},
        ],
      };

      final delivery = Delivery.fromJson(rawData);
      final names = delivery.items.map((i) => i.productName).toList();

      expect(names, [
        // By Case items first, sorted by SRP ascending:
        'P10 CHOCKY',
        'P20 CREAMDAE',
        // By Piece items next, sorted by SRP ascending:
        'P60 BASO',
        'P105 SUPREME',
        // Other items at the bottom:
        'Ice Bag Large',
      ]);
    });

    test('Delivery Receipt: ThermalPrinterService.categorizeItems sorts by SRP in each category', () {
      final items = [
        const OrderItem(productId: '1', productName: 'P105 SUPREME', imageUrl: '', productSource: 'selecta', category: 'By Piece', buyingPrice: 50, sellingPrice: 96.4, orderedQuantity: 1, pickedQuantity: 1),
        const OrderItem(productId: '2', productName: 'P20 CREAMDAE', imageUrl: '', productSource: 'selecta', category: 'By Case', buyingPrice: 200, sellingPrice: 264.7, orderedQuantity: 1, pickedQuantity: 1),
        const OrderItem(productId: '3', productName: 'P10 CHOCKY', imageUrl: '', productSource: 'selecta', category: 'By Case', buyingPrice: 180, sellingPrice: 248.16, orderedQuantity: 1, pickedQuantity: 1),
        const OrderItem(productId: '4', productName: 'P60 BASO', imageUrl: '', productSource: 'selecta', category: 'By Piece', buyingPrice: 40, sellingPrice: 55.1, orderedQuantity: 1, pickedQuantity: 1),
      ];

      final cat = ThermalPrinterService.categorizeItems(items);

      expect(cat.selectaCase.map((i) => i.productName), ['P10 CHOCKY', 'P20 CREAMDAE']);
      expect(cat.selectaPiece.map((i) => i.productName), ['P60 BASO', 'P105 SUPREME']);
    });

    test('Inventory: category order (By Case, By Piece, Other) and SRP ascending preserved', () {
      final items = [
        createItem('1', 'P105 SUPREME PINT', 96.4, 'By Piece'),
        createItem('2', 'P20 CREAMDAE', 264.7, 'By Case'),
        createItem('3', 'P10 CHOCKY', 248.16, 'By Case'),
        createItem('4', 'P60 BASO', 55.1, 'By Piece'),
        createItem('5', 'Ice Bag Large', 20.0, 'General', source: InventoryProductSource.other),
      ];

      final selecta = items.where((i) => i.source == InventoryProductSource.selecta).toList()..sort(compareProducts);
      final other = items.where((i) => i.source != InventoryProductSource.selecta).toList()..sort(compareProducts);

      final caseProducts = selecta.where((i) => i.category.toLowerCase().contains('case')).toList();
      final pieceProducts = selecta.where((i) => !i.category.toLowerCase().contains('case')).toList();

      expect(caseProducts.map((i) => i.productName), ['P10 CHOCKY', 'P20 CREAMDAE']);
      expect(pieceProducts.map((i) => i.productName), ['P60 BASO', 'P105 SUPREME PINT']);
      expect(other.map((i) => i.productName), ['Ice Bag Large']);
    });

    test('Book Order: Best Seller category moves tagged products to top with SRP sorting intact', () {
      final items = [
        createItem('1', 'P105 SUPREME PINT', 96.4, 'By Piece'),
        createItem('2', 'P20 CREAMDAE', 264.7, 'By Case', tag: ProductTag.bestSeller),
        createItem('3', 'P10 CHOCKY', 248.16, 'By Case'),
        createItem('4', 'P60 BASO', 55.1, 'By Piece', tag: ProductTag.bestSeller),
        createItem('5', 'Ice Bag Large', 20.0, 'General', source: InventoryProductSource.other),
      ];

      // Partition logic as used in BookOrderPage:
      final bestSellerProducts = items.where((i) => ProductTag.isBestSeller(i.tag)).toList()..sort(compareProducts);
      final nonBestSellerFiltered = items.where((i) => !ProductTag.isBestSeller(i.tag)).toList();

      final selectaFiltered = nonBestSellerFiltered.where((i) => i.source == InventoryProductSource.selecta).toList()..sort(compareProducts);
      final otherFiltered = nonBestSellerFiltered.where((i) => i.source != InventoryProductSource.selecta).toList()..sort(compareProducts);

      final caseProducts = selectaFiltered.where((i) => i.category.toLowerCase().contains('case')).toList();
      final pieceProducts = selectaFiltered.where((i) => !i.category.toLowerCase().contains('case')).toList();

      // Best Seller at top, sorted by SRP ascending (P20 before P60):
      expect(bestSellerProducts.map((i) => i.productName), ['P20 CREAMDAE', 'P60 BASO']);

      // Remaining Selecta: By Case (excluding P20 CREAMDAE which moved to Best Seller):
      expect(caseProducts.map((i) => i.productName), ['P10 CHOCKY']);

      // Remaining Selecta: By Piece (excluding P60 BASO which moved to Best Seller):
      expect(pieceProducts.map((i) => i.productName), ['P105 SUPREME PINT']);

      // Other Products at bottom:
      expect(otherFiltered.map((i) => i.productName), ['Ice Bag Large']);
    });
  });
}
