import 'dart:io';
import 'package:dio/dio.dart';
import 'package:selecta_ops/models/admin_selecta_product.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Selecta Product CSV Parser Tests', () {
    test('parseCsvRows handles basic comma-separated rows', () {
      const csv = 'Name,Price\nCornetto,30\nMagnum,60';
      final rows = SelectaProductService.parseCsvRows(csv);
      expect(rows.length, equals(3));
      expect(rows[0], equals(['Name', 'Price']));
      expect(rows[1], equals(['Cornetto', '30']));
      expect(rows[2], equals(['Magnum', '60']));
    });

    test('parseCsvRows handles quotes and embedded commas', () {
      const csv = '"Product, Special",25.50,"By Piece"\n"Double ""Dutch""",180,"By Case"';
      final rows = SelectaProductService.parseCsvRows(csv);
      expect(rows.length, equals(2));
      expect(rows[0], equals(['Product, Special', '25.50', 'By Piece']));
      expect(rows[1], equals(['Double "Dutch"', '180', 'By Case']));
    });

    test('parseCsvRows handles semicolon and tab delimiters', () {
      const semicolonCsv = 'Name;Price;Category\nCornetto;30;By Piece';
      final rowsSemi = SelectaProductService.parseCsvRows(semicolonCsv);
      expect(rowsSemi.length, equals(2));
      expect(rowsSemi[1], equals(['Cornetto', '30', 'By Piece']));

      const tabCsv = 'Name\tPrice\tCategory\nCornetto\t30\tBy Piece';
      final rowsTab = SelectaProductService.parseCsvRows(tabCsv);
      expect(rowsTab.length, equals(2));
      expect(rowsTab[1], equals(['Cornetto', '30', 'By Piece']));
    });

    test('parseAdminProductsFromCsv maps standard column headers', () {
      const csv = '''Product Name,Buying Price,Selling Price,Category,Image URL
Cornetto Chocolate,25.00,30.00,By Piece,https://example.com/cornetto.png
Magnum Classic,50.00,65.00,By Piece,https://example.com/magnum.png
Super Thick Vanilla 1.4L,180.00,210.00,By Case,
''';
      final products = SelectaProductService.parseAdminProductsFromCsv(csv);
      expect(products.length, equals(3));

      expect(products[0].productName, equals('Cornetto Chocolate'));
      expect(products[0].buyingPrice, equals(25.0));
      expect(products[0].sellingPrice, equals(30.0));
      expect(products[0].category, equals('By Piece'));
      expect(products[0].imageUrl, equals('https://example.com/cornetto.png'));

      expect(products[1].productName, equals('Magnum Classic'));
      expect(products[1].buyingPrice, equals(50.0));
      expect(products[1].sellingPrice, equals(65.0));

      expect(products[2].productName, equals('Super Thick Vanilla 1.4L'));
      expect(products[2].category, equals('By Case'));
      expect(products[2].imageUrl, isEmpty);
    });

    test('parseAdminProductsFromCsv maps Tag column headers correctly', () {
      const csv = '''Product Name,Buying Price,Selling Price,Category,Tag,Image URL
Cornetto Chocolate,25.00,30.00,By Piece,Best Seller,https://example.com/c.png
Boom Boom,15.00,18.00,By Piece,New Product,
''';
      final products = SelectaProductService.parseAdminProductsFromCsv(csv);
      expect(products.length, equals(2));
      expect(products[0].tag, equals('Best Seller'));
      expect(products[1].tag, equals('New Product'));
    });

    test('parseAdminProductsFromCsv normalizes currency symbols and commas in numbers', () {
      const csv = '''Item,Cost,SRP,Type
Premium Pint,"₱ 1,250.50","\\\$ 1,500.00",Case
Solo Cup,PHP 35.00,Php 40.00,Piece
''';
      final products = SelectaProductService.parseAdminProductsFromCsv(csv);
      expect(products.length, equals(2));

      expect(products[0].productName, equals('Premium Pint'));
      expect(products[0].buyingPrice, equals(1250.50));
      expect(products[0].sellingPrice, equals(1500.00));
      expect(products[0].category, equals('By Case'));

      expect(products[1].productName, equals('Solo Cup'));
      expect(products[1].buyingPrice, equals(35.0));
      expect(products[1].sellingPrice, equals(40.0));
      expect(products[1].category, equals('By Piece'));
    });

    test('parseAdminProductsFromCsv supports single Price column fallback', () {
      const csv = '''Product,Price
Twin Pops,15.00
''';
      final products = SelectaProductService.parseAdminProductsFromCsv(csv);
      expect(products.length, equals(1));
      expect(products[0].productName, equals('Twin Pops'));
      expect(products[0].buyingPrice, equals(15.0));
      expect(products[0].sellingPrice, equals(15.0));
      expect(products[0].category, equals('By Piece'));
    });

    test('parseAdminProductsFromData automatically distinguishes JSON from CSV', () {
      const json = '[{"productName": "Halo-Halo", "buyingPrice": 40.0, "sellingPrice": 50.0}]';
      final fromJson = SelectaProductService.parseAdminProductsFromData(json);
      expect(fromJson.length, equals(1));
      expect(fromJson[0].productName, equals('Halo-Halo'));

      const csv = 'Product Name,Buying Price,Selling Price\nUbe Keso,45.0,55.0';
      final fromCsv = SelectaProductService.parseAdminProductsFromData(csv);
      expect(fromCsv.length, equals(1));
      expect(fromCsv[0].productName, equals('Ube Keso'));
    });

    test('parses dwightcaballero importselecta.csv correctly', () {
      final csv = File('test/importselecta.csv').readAsStringSync();
      final products = SelectaProductService.parseAdminProductsFromCsv(csv);
      expect(products.length, equals(89));
    });

    test('fetches and parses live importselecta.csv from GitHub URL', () async {
      final client = HttpClient();
      final uri = Uri.parse('https://raw.githubusercontent.com/dwightcaballero/dwightcaballero.github.io/refs/heads/master/importselecta.csv');
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(SystemEncoding().decoder).join();
      final products = SelectaProductService.parseAdminProductsFromData(body);
      expect(products.length, equals(89));
    });

    test('Dio fetches and parses live importselecta.csv from GitHub URL', () async {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 25),
        ),
      );
      final response = await dio.get<String>(
        'https://raw.githubusercontent.com/dwightcaballero/dwightcaballero.github.io/refs/heads/master/importselecta.csv',
        options: Options(responseType: ResponseType.plain),
      );
      final body = response.data ?? '';
      final products = SelectaProductService.parseAdminProductsFromData(body);
      expect(products.length, equals(89));
    });

    test('computeCatalogSignature is identical whether products have Firestore IDs or empty IDs', () {
      final remoteList = <AdminSelectaProduct>[
        const AdminSelectaProduct(
          id: '',
          productName: 'Cornetto Disc',
          imageUrl: '',
          buyingPrice: 35.0,
          sellingPrice: 40.0,
          category: 'By Piece',
        ),
        const AdminSelectaProduct(
          id: '',
          productName: 'Double Dutch 1.4L',
          imageUrl: '',
          buyingPrice: 180.0,
          sellingPrice: 210.0,
          category: 'By Case',
        ),
      ];

      final localList = <AdminSelectaProduct>[
        const AdminSelectaProduct(
          id: 'firestore_generated_id_1',
          productName: 'Cornetto Disc',
          imageUrl: '',
          buyingPrice: 35.0,
          sellingPrice: 40.0,
          category: 'By Piece',
        ),
        const AdminSelectaProduct(
          id: 'firestore_generated_id_2',
          productName: 'Double Dutch 1.4L',
          imageUrl: '',
          buyingPrice: 180.0,
          sellingPrice: 210.0,
          category: 'By Case',
        ),
      ];

      final remoteSig = SelectaProductService.computeCatalogSignature(remoteList);
      final localSig = SelectaProductService.computeCatalogSignature(localList);

      expect(remoteSig, equals(localSig));
    });
  });
}





