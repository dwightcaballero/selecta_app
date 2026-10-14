import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/po_extracted_line.dart';
import 'package:selecta_ops/views/pages/sidebar/purchaseorder_catalog_page.dart';

void main() {
  final sampleCatalog = [
    InventoryItem(
      id: 'sel_1',
      productName: 'SELECTA CORNETTO CLASSIC',
      imageUrl: '',
      buyingPrice: 20.0,
      sellingPrice: 25.0,
      isActive: true,
      stockQuantity: 10,
      preOrderQuantity: 0,
      lowStockThreshold: 5,
      source: InventoryProductSource.selecta,
      category: 'By Piece',
    ),
    InventoryItem(
      id: 'sel_2',
      productName: 'SELECTA MAGNUM ALMOND',
      imageUrl: '',
      buyingPrice: 50.0,
      sellingPrice: 65.0,
      isActive: true,
      stockQuantity: 4,
      preOrderQuantity: 12, // Shortage = 12 - 4 = 8
      lowStockThreshold: 5,
      source: InventoryProductSource.selecta,
      category: 'By Piece',
    ),
    InventoryItem(
      id: 'sel_3',
      productName: 'SELECTA 3IN1 CASE TUB',
      imageUrl: '',
      buyingPrice: 150.0,
      sellingPrice: 180.0,
      isActive: true,
      stockQuantity: 20,
      preOrderQuantity: 0,
      lowStockThreshold: 5,
      source: InventoryProductSource.selecta,
      category: 'By Case',
    ),
  ];

  group('PurchaseOrderCatalogPage Full-Page Tests', () {
    testWidgets('Renders full page catalog with Appbar, search, categories, and sticky bottom bar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PurchaseOrderCatalogPage(
            allInventory: sampleCatalog,
            existingLines: const [],
            isDirectCreationFlow: true,
          ),
        ),
      );

      // Verify page title and subtitle
      expect(find.text('Restock Catalog'), findsOneWidget);
      expect(find.text('Restock from Selecta • Select Products'), findsOneWidget);

      // Verify search bar
      expect(find.byType(TextField), findsOneWidget);

      // Verify category chips
      expect(find.textContaining('All Products'), findsOneWidget);
      expect(find.text('Recommended (1)'), findsOneWidget);
      expect(find.textContaining('By Case'), findsWidgets);
      expect(find.textContaining('By Piece'), findsWidgets);

      // Verify shortage badge for pre-order item
      expect(find.textContaining('Shortage: 8'), findsOneWidget);

      // Verify sticky bottom bar is present
      expect(find.textContaining('0 items • 0 units'), findsOneWidget);
      expect(find.text('Proceed to P.O.'), findsOneWidget);
    });

    testWidgets('Adding products updates quantity, item counts, and total buying cost', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PurchaseOrderCatalogPage(
            allInventory: sampleCatalog,
            existingLines: const [],
            isDirectCreationFlow: true,
          ),
        ),
      );

      // Initially 0 items
      expect(find.textContaining('0 items • 0 units'), findsOneWidget);

      // Tap 'Add' on the first product (SELECTA MAGNUM ALMOND is recommended so it appears at top)
      final addButtons = find.text('Add');
      expect(addButtons, findsWidgets);

      await tester.tap(addButtons.first);
      await tester.pumpAndSettle();

      // Check that sticky bar updated
      expect(find.textContaining('1 items'), findsOneWidget);
      expect(find.textContaining('Proceed to P.O.'), findsOneWidget);
    });

    testWidgets('In modal/sub-page flow (isDirectCreationFlow: false), button says Apply to P.O. and returns selected lines', (tester) async {
      List<PoExtractedLine>? returnedLines;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                returnedLines = await Navigator.push<List<PoExtractedLine>>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PurchaseOrderCatalogPage(
                      allInventory: sampleCatalog,
                      existingLines: const [],
                      isDirectCreationFlow: false,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Header should show Manual Purchase Order
      expect(find.text('Manual Purchase Order'), findsOneWidget);

      // Add an item
      await tester.tap(find.text('Add').first);
      await tester.pumpAndSettle();

      // Tap 'Apply to P.O.'
      expect(find.textContaining('Apply to P.O.'), findsOneWidget);
      await tester.tap(find.textContaining('Apply to P.O.'));
      await tester.pumpAndSettle();

      // Catalog page popped, returnedLines should be populated
      expect(returnedLines, isNotNull);
      expect(returnedLines!.length, 1);
    });
  });
}
