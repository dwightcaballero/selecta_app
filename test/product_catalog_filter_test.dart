import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/views/pages/sidebar/product_catalog_page.dart';

void main() {
  group('Product Catalog Logic & Margin Calculation Tests', () {
    test('CatalogItem calculates gross margin, margin percentage, and stock statuses correctly', () {
      const item = CatalogItem(
        id: 'sel_01',
        name: 'Selecta Cornetto Classic 110ml',
        itemCode: '480011002233',
        category: 'Cones',
        imageUrl: 'https://example.com/cornetto.png',
        buyingPrice: 30.0,
        sellingPrice: 40.0,
        stockQuantity: 15,
        isSelecta: true,
        isActive: true,
      );

      // Margin = 40 - 30 = 10
      expect(item.margin, 10.0);

      // Markup % = (10 / 30) * 100 = 33.333%
      expect(item.marginPercent, closeTo(33.33, 0.01));

      // Gross Margin Ratio % = (10 / 40) * 100 = 25.0%
      expect(item.grossMarginRatio, 25.0);

      // Stock status
      expect(item.isOutOfStock, isFalse);
      expect(item.isLowStock, isFalse);
    });

    test('CatalogItem identifies low stock and out-of-stock items accurately', () {
      const lowStockItem = CatalogItem(
        id: 'sel_02',
        name: 'Selecta Super Thick Vanilla 1.5L',
        itemCode: '480011005544',
        category: 'Tubs',
        imageUrl: '',
        buyingPrice: 180.0,
        sellingPrice: 240.0,
        stockQuantity: 4,
        isSelecta: true,
        isActive: true,
      );

      expect(lowStockItem.isLowStock, isTrue);
      expect(lowStockItem.isOutOfStock, isFalse);

      const oosItem = CatalogItem(
        id: 'sel_03',
        name: 'Selecta Magnum Almond 90ml',
        itemCode: '480011009988',
        category: 'Bars',
        imageUrl: '',
        buyingPrice: 65.0,
        sellingPrice: 85.0,
        stockQuantity: 0,
        isSelecta: true,
        isActive: true,
      );

      expect(oosItem.isOutOfStock, isTrue);
      expect(oosItem.isLowStock, isFalse);
    });

    test('Catalog items sort properly by price, margin, and stock', () {
      final items = [
        const CatalogItem(
          id: '1',
          name: 'Bravo Cone',
          itemCode: '111',
          category: 'Cones',
          imageUrl: '',
          buyingPrice: 20,
          sellingPrice: 25, // margin %: 25%
          stockQuantity: 50,
          isSelecta: true,
          isActive: true,
        ),
        const CatalogItem(
          id: '2',
          name: 'Alpha Tub',
          itemCode: '222',
          category: 'Tubs',
          imageUrl: '',
          buyingPrice: 100,
          sellingPrice: 150, // margin %: 50%
          stockQuantity: 10,
          isSelecta: true,
          isActive: true,
        ),
        const CatalogItem(
          id: '3',
          name: 'Charlie Bar',
          itemCode: '333',
          category: 'Bars',
          imageUrl: '',
          buyingPrice: 10,
          sellingPrice: 20, // margin %: 100%
          stockQuantity: 100,
          isSelecta: true,
          isActive: true,
        ),
      ];

      // Sort by Name Ascending
      final sortedByName = [...items]..sort((a, b) => a.name.compareTo(b.name));
      expect(sortedByName.first.name, 'Alpha Tub');
      expect(sortedByName.last.name, 'Charlie Bar');

      // Sort by Price Descending
      final sortedByPriceDesc = [...items]..sort((a, b) => b.sellingPrice.compareTo(a.sellingPrice));
      expect(sortedByPriceDesc.first.name, 'Alpha Tub');
      expect(sortedByPriceDesc.last.name, 'Charlie Bar');

      // Sort by Margin % Descending
      final sortedByMarginDesc = [...items]..sort((a, b) => b.marginPercent.compareTo(a.marginPercent));
      expect(sortedByMarginDesc.first.name, 'Charlie Bar'); // 100% margin
      expect(sortedByMarginDesc.last.name, 'Bravo Cone'); // 25% margin
    });
  });
}
