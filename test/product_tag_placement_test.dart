import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/models/admin_selecta_product.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/models/inventory_movement.dart';
import 'package:flutter_app/models/placement.dart';
import 'package:flutter_app/models/selecta_product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProductTag and Model Tag Tests', () {
    test('ProductTag validation and helpers', () {
      expect(ProductTag.isBestSeller('Best Seller'), isTrue);
      expect(ProductTag.isBestSeller('best seller'), isTrue);
      expect(ProductTag.isBestSeller('  Best Seller  '), isTrue);
      expect(ProductTag.isBestSeller('New Product'), isFalse);
      expect(ProductTag.isBestSeller(null), isFalse);
      expect(ProductTag.isBestSeller(''), isFalse);

      expect(ProductTag.isNewProduct('New Product'), isTrue);
      expect(ProductTag.isNewProduct('new product'), isTrue);
      expect(ProductTag.isNewProduct('Best Seller'), isFalse);
      expect(ProductTag.isNewProduct(null), isFalse);
    });

    test('AdminSelectaProduct tag serialization and defaults', () {
      final p1 = AdminSelectaProduct(
        id: 'p1',
        productName: 'CORNETTO CHOCO',
        imageUrl: 'http://img.com/p1.png',
        tag: ProductTag.bestSeller,
      );
      expect(p1.tag, equals('Best Seller'));
      final json = p1.toJson();
      expect(json['tag'], equals('Best Seller'));

      final pParsed = AdminSelectaProduct.fromJson('p1', json);
      expect(pParsed.tag, equals('Best Seller'));

      final pEmpty = AdminSelectaProduct.empty();
      expect(pEmpty.tag, isEmpty);
    });

    test('SelectaProduct tag propagation from AdminSelectaProduct and JSON', () {
      final admin = AdminSelectaProduct(
        id: 'prod-123',
        productName: 'SELECTA SUPER DD',
        imageUrl: 'http://img.com/dd.png',
        tag: ProductTag.newProduct,
      );

      final dealer = SelectaProduct.fromAdminProduct(
        id: admin.id,
        productName: admin.productName,
        imageUrl: admin.imageUrl,
        buyingPrice: admin.buyingPrice,
        sellingPrice: admin.sellingPrice,
        category: admin.category,
        tag: admin.tag,
      );

      expect(dealer.tag, equals('New Product'));
      final json = dealer.toJson();
      expect(json['tag'], equals('New Product'));

      final dealerFromJson = SelectaProduct.fromJson('prod-123', json);
      expect(dealerFromJson.tag, equals('New Product'));
    });

    test('InventoryItem and OrderItem preserve tag', () {
      final selecta = SelectaProduct(
        id: 's1',
        itemCode: '',
        productName: 'BOOM BOOM',
        imageUrl: '',
        buyingPrice: 10,
        sellingPrice: 15,
        category: 'By Piece',
        tag: ProductTag.bestSeller,
      );

      final inv = InventoryItem.fromSelectaProduct(selecta);
      expect(inv.tag, equals(ProductTag.bestSeller));

      final orderItem = OrderItem(
        productId: inv.id,
        productName: inv.productName,
        imageUrl: inv.imageUrl,
        productSource: inv.source.key,
        category: inv.category,
        tag: inv.tag,
        buyingPrice: inv.buyingPrice,
        sellingPrice: inv.sellingPrice,
        orderedQuantity: 2,
        pickedQuantity: 2,
      );
      expect(orderItem.tag, equals(ProductTag.bestSeller));

      final itemJson = orderItem.toJson();
      expect(itemJson['tag'], equals(ProductTag.bestSeller));

      final parsedOrderItem = OrderItem.fromJson(itemJson);
      expect(parsedOrderItem.tag, equals(ProductTag.bestSeller));
    });
  });

  group('Placement Model & Best Seller Placed Tests', () {
    test('Placement model supports placedProductNames and isProductPlaced', () {
      final placement = Placement(
        id: 'pl-1',
        storeName: 'Store ABC',
        deliveryDate: Timestamp.now(),
        placedProductNames: ['Watermelon Slice', 'Cornetto Choco'],
        cotc1: true,
        cotc2: false,
        cotc3: false,
        cotc4: false,
        cotc5: true,
        cotc6: false,
        cotc7: false,
        cotc8: false,
        cotc9: false,
        cotc10: false,
        cotc11: false,
        cotc12: false,
        isFinished: false,
        progressCount: 2,
      );

      expect(placement.isProductPlaced('Watermelon Slice'), isTrue);
      expect(placement.isProductPlaced('watermelon slice'), isTrue);
      expect(placement.isProductPlaced('Cornetto Choco'), isTrue);
      expect(placement.isProductPlaced('Boom Boom Choco'), isFalse);

      final json = placement.toJson();
      expect(json['placedProductNames'], equals(['Watermelon Slice', 'Cornetto Choco']));

      final parsed = Placement.fromJson(json);
      expect(parsed.placedProductNames, contains('Watermelon Slice'));
      expect(parsed.placedProductNames, contains('Cornetto Choco'));
    });

    test('Backward compatibility: Placement hydrates placedProductNames from legacy cotc flags when absent', () {
      final legacyJson = {
        'id': 'legacy-doc',
        'storeName': 'Legacy Store',
        'deliveryDate': Timestamp.now(),
        'cotc1': true, // Watermelon Slice
        'cotc5': true, // Cornetto Choco
        'cotc2': false,
        'cotc3': false,
        'cotc4': false,
        'cotc6': false,
        'cotc7': false,
        'cotc8': false,
        'cotc9': false,
        'cotc10': false,
        'cotc11': false,
        'cotc12': false,
        'isFinished': false,
        'progressCount': 2,
      };

      final parsed = Placement.fromJson(legacyJson);
      expect(parsed.placedProductNames, contains('Watermelon Slice'));
      expect(parsed.placedProductNames, contains('Cornetto Choco'));
      expect(parsed.isProductPlaced('Watermelon Slice'), isTrue);
      expect(parsed.isProductPlaced('Cornetto Choco'), isTrue);
      expect(parsed.isProductPlaced('Chocky Stick'), isFalse);
    });

    test('Mark for Best Seller products not yet placed vs already placed', () {
      final placedProductNames = {'cornetto choco', 'watermelon slice'};

      bool shouldShowNotPlacedMark({required String tag, required String productName}) {
        final isBestSeller = ProductTag.isBestSeller(tag);
        final isPlaced = placedProductNames.contains(productName.trim().toLowerCase());
        return isBestSeller && !isPlaced;
      }

      // Best Seller that is not placed -> Should show mark
      expect(
        shouldShowNotPlacedMark(tag: ProductTag.bestSeller, productName: 'Avocado Choco'),
        isTrue,
      );

      // Best Seller that is already placed -> Mark is removed
      expect(
        shouldShowNotPlacedMark(tag: ProductTag.bestSeller, productName: 'Cornetto Choco'),
        isFalse,
      );

      // New Product (not best seller) -> Should NOT show not placed mark
      expect(
        shouldShowNotPlacedMark(tag: ProductTag.newProduct, productName: 'Avocado Choco'),
        isFalse,
      );

      // Normal product without tag -> Should NOT show mark
      expect(
        shouldShowNotPlacedMark(tag: '', productName: 'Avocado Choco'),
        isFalse,
      );
    });
  });
}
