import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/supplier_product_mapping.dart';
import 'package:selecta_ops/services/ocr/catalog_matcher.dart';
import 'package:selecta_ops/services/ocr/document_layout_parser.dart';

void main() {
  group('CatalogMatcher Unit Tests', () {
    final catalog = [
      const InventoryItem(
        id: 'p1',
        productName: 'Cornetto Classic Chocolate',
        imageUrl: '',
        itemCode: '10423',
        buyingPrice: 240.0,
        sellingPrice: 300.0,
        isActive: true,
        stockQuantity: 100,
        lowStockThreshold: 10,
        source: InventoryProductSource.selecta,
      ),
      const InventoryItem(
        id: 'p2',
        productName: 'Cornetto Disc White Chocolate',
        imageUrl: '',
        itemCode: '10424',
        buyingPrice: 260.0,
        sellingPrice: 320.0,
        isActive: true,
        stockQuantity: 80,
        lowStockThreshold: 10,
        source: InventoryProductSource.selecta,
      ),
      const InventoryItem(
        id: 'p3',
        productName: 'Magnum Almond Pint 440ml',
        imageUrl: '',
        itemCode: '20101',
        buyingPrice: 180.0,
        sellingPrice: 240.0,
        isActive: true,
        stockQuantity: 50,
        lowStockThreshold: 10,
        source: InventoryProductSource.selecta,
      ),
      const InventoryItem(
        id: 'p4',
        productName: 'Magnum Almond Tub 1.3L',
        imageUrl: '',
        itemCode: '20102',
        buyingPrice: 380.0,
        sellingPrice: 480.0,
        isActive: true,
        stockQuantity: 30,
        lowStockThreshold: 5,
        source: InventoryProductSource.selecta,
      ),
    ];

    final mappings = [
      const SupplierProductMapping(
        id: 'm1',
        rawSupplierText: 'CORN DISC WH...',
        normalizedText: 'CORN DISC WH',
        productId: 'p2',
        productName: 'Cornetto Disc White Chocolate',
      ),
      const SupplierProductMapping(
        id: 'm2',
        rawSupplierText: 'CORNETTO MULTI FLAVOR',
        normalizedText: 'CORNETTO MULTI FLAVOR',
        productId: 'p1',
        productName: 'Cornetto Classic Chocolate',
        candidateProductIds: ['p1', 'p2'],
        isMultiMatch: true,
      ),
    ];

    final matcher = CatalogMatcher(catalog: catalog, learnedMappings: mappings);

    test('Matches exact item code with high confidence', () {
      const row = ParsedRow(
        rawText: '10423 UNKNOWN TEXT 12 CS',
        itemCode: '10423',
        description: 'UNKNOWN TEXT',
        quantity: 12,
      );

      final res = matcher.matchRow(row);
      expect(res.status, equals(MatchStatus.matched));
      expect(res.matchedItem?.id, equals('p1'));
      expect(res.confidence, greaterThanOrEqualTo(0.95));
    });

    test('Matches learned alias including truncated prefix', () {
      const row = ParsedRow(
        rawText: 'CORN DISC WH... 5 CS',
        description: 'CORN DISC WH...',
        quantity: 5,
      );

      final res = matcher.matchRow(row);
      expect(res.status, equals(MatchStatus.matched));
      expect(res.matchedItem?.id, equals('p2'));
    });

    test('Multi-match alias returns ambiguous with top candidates', () {
      const row = ParsedRow(
        rawText: 'CORNETTO MULTI FLAVOR 10 CS',
        description: 'CORNETTO MULTI FLAVOR',
        quantity: 10,
      );

      final res = matcher.matchRow(row);
      expect(res.status, equals(MatchStatus.ambiguous));
      expect(res.topCandidates.map((c) => c.item.id), containsAll(['p1', 'p2']));
    });

    test('Expands abbreviations and matches fuzzy product name', () {
      const row = ParsedRow(
        rawText: 'CORN CLASSIC CHOC 10 CS',
        description: 'CORN CLASSIC CHOC',
        quantity: 10,
      );

      final res = matcher.matchRow(row);
      expect(res.status, equals(MatchStatus.matched));
      expect(res.matchedItem?.id, equals('p1'));
    });

    test('Uses detected price to disambiguate Pint vs Tub', () {
      // Pint price is 180, Tub price is 380
      const rowPint = ParsedRow(
        rawText: 'MAGNUM ALMOND 180.00 5 CS',
        description: 'MAGNUM ALMOND',
        quantity: 5,
        unitPrice: 180.0,
      );

      final resPint = matcher.matchRow(rowPint);
      expect(resPint.matchedItem?.id, equals('p3')); // Pint

      const rowTub = ParsedRow(
        rawText: 'MAGNUM ALMOND 380.00 5 CS',
        description: 'MAGNUM ALMOND',
        quantity: 5,
        unitPrice: 380.0,
      );

      final resTub = matcher.matchRow(rowTub);
      expect(resTub.matchedItem?.id, equals('p4')); // Tub
    });

    test('Completely unknown product returns unmatched', () {
      const row = ParsedRow(
        rawText: 'DETERGENT POWDER 1KG',
        description: 'DETERGENT POWDER 1KG',
        quantity: 1,
      );

      final res = matcher.matchRow(row);
      expect(res.status, equals(MatchStatus.unmatched));
      expect(res.isResolved, isFalse);
    });

    test('Empty catalog is handled safely without throwing', () {
      final emptyMatcher = CatalogMatcher(catalog: []);
      const row = ParsedRow(
        rawText: 'SOME ITEM',
        description: 'SOME ITEM',
        quantity: 1,
      );

      final res = emptyMatcher.matchRow(row);
      expect(res.status, equals(MatchStatus.unmatched));
    });
  });
}
