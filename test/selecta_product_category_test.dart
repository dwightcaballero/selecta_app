import 'package:flutter_app/models/admin_selecta_product.dart';
import 'package:flutter_app/models/selecta_product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Selecta Product Category Tests', () {
    test('AdminSelectaProduct correctly parses and serializes "By Case" category', () {
      final product = AdminSelectaProduct(
        id: 'prod_123',
        productName: 'Cornetto Disc',
        imageUrl: 'https://example.com/img.png',
        buyingPrice: 30.0,
        sellingPrice: 40.0,
        category: 'By Case',
      );

      final json = product.toJson();
      expect(json['category'], equals('By Case'));

      final parsed = AdminSelectaProduct.fromJson('prod_123', json);
      expect(parsed.category, equals('By Case'));
    });

    test('AdminSelectaProduct normalizes case variations to "By Case"', () {
      final p1 = AdminSelectaProduct.fromJson('1', {'category': 'by case'});
      expect(p1.category, equals('By Case'));

      final p2 = AdminSelectaProduct.fromJson('2', {'category': 'case'});
      expect(p2.category, equals('By Case'));

      final p3 = AdminSelectaProduct.fromJson('3', {'category': 'By Piece'});
      expect(p3.category, equals('By Piece'));

      final p4 = AdminSelectaProduct.fromJson('4', {'category': ''});
      expect(p4.category, equals('By Piece'));
    });

    test('SelectaProduct correctly normalizes and preserves "By Case"', () {
      final sp = SelectaProduct.fromJson('p1', {
        'productName': 'Super Thick Chocolate',
        'category': 'By Case',
      });
      expect(sp.category, equals('By Case'));

      final spCaseLower = SelectaProduct.fromJson('p2', {
        'productName': 'Super Thick Vanilla',
        'category': 'by case',
      });
      expect(spCaseLower.category, equals('By Case'));

      final spPiece = SelectaProduct.fromJson('p3', {
        'productName': 'Cornetto',
        'category': 'By Piece',
      });
      expect(spPiece.category, equals('By Piece'));
    });

    test('SelectaProduct.fromAdminProduct preserves "By Case" category', () {
      const adminProduct = AdminSelectaProduct(
        id: 'admin_1',
        productName: 'Double Dutch 1.3L',
        imageUrl: '',
        category: 'By Case',
      );

      final dealerProduct = SelectaProduct.fromAdminProduct(
        id: adminProduct.id,
        productName: adminProduct.productName,
        imageUrl: adminProduct.imageUrl,
        buyingPrice: adminProduct.buyingPrice,
        sellingPrice: adminProduct.sellingPrice,
        category: adminProduct.category,
      );

      expect(dealerProduct.category, equals('By Case'));
      expect(dealerProduct.toJson()['category'], equals('By Case'));
    });
  });
}
