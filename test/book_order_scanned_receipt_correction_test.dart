import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/views/widgets/book_order/product_order_card.dart';
import 'package:selecta_ops/views/widgets/book_order/receipt_scan_flow.dart';

void main() {
  final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  final testItem = InventoryItem(
    id: 'test_item_1',
    productName: 'Selecta Supreme Classic Vanilla 1.4L Tub',
    imageUrl: '',
    buyingPrice: 150.0,
    sellingPrice: 195.0,
    isActive: true,
    stockQuantity: 50,
    lowStockThreshold: 5,
    source: InventoryProductSource.selecta,
    category: 'Tub',
  );

  group('Book Order Scanned Receipt Comparison and Correction Tests', () {
    testWidgets('ProductOrderCard renders full device name and full scanned document name', (tester) async {
      bool correctTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductOrderCard(
              item: testItem,
              selectedQty: 3,
              maxOrderable: 50,
              isPlaced: false,
              currencyFormat: currencyFormat,
              receiptIndex: 1,
              rawReceiptText: 'SELEC SUPR CLAS VAN 1.4L (POS LINE ITEM)',
              isCorrected: false,
              onCorrectAi: () {
                correctTapped = true;
              },
              onTap: () {},
            ),
          ),
        ),
      );

      // Verify the full product name in device is present
      expect(find.text('Selecta Supreme Classic Vanilla 1.4L Tub'), findsOneWidget);

      // Verify receipt sequence badge
      expect(find.text('#1 on Receipt'), findsOneWidget);

      // Verify label and full scanned document text
      expect(find.text('SCANNED ON DOCUMENT:'), findsOneWidget);
      expect(find.text('SELEC SUPR CLAS VAN 1.4L (POS LINE ITEM)'), findsOneWidget);

      // Verify Correct AI button is rendered and clickable
      expect(find.text('Correct AI Reading'), findsOneWidget);
      await tester.tap(find.text('Correct AI Reading'));
      expect(correctTapped, isTrue);
    });

    testWidgets('ProductOrderCard displays ✓ Corrected badge when item was corrected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductOrderCard(
              item: testItem,
              selectedQty: 2,
              maxOrderable: 50,
              isPlaced: false,
              currencyFormat: currencyFormat,
              receiptIndex: 2,
              rawReceiptText: 'SELEC CORNETTO CHOCO',
              isCorrected: true,
              onTap: () {},
            ),
          ),
        ),
      );

      // Verify corrected badge appears
      expect(find.text('✓ Corrected'), findsOneWidget);
      expect(find.text('SELEC CORNETTO CHOCO'), findsOneWidget);
    });

    testWidgets('ReceiptScanFlow.showSummary displays scanned products with comparison', (tester) async {
      final scannedLines = [
        ScannedReceiptLine(
          item: testItem,
          quantity: 4,
          rawText: 'RAW DOC TEXT VANILLA 1.4L',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                ReceiptScanFlow.showSummary(
                  context,
                  skuCount: 1,
                  unitCount: 4,
                  capped: [],
                  skipped: [],
                  scannedLines: scannedLines,
                );
              },
              child: const Text('Open Summary'),
            ),
          ),
        ),
      );

      // Tap button to open summary bottom sheet
      await tester.tap(find.text('Open Summary'));
      await tester.pumpAndSettle();

      // Verify summary shows scanned products section
      expect(find.text('SCANNED RECEIPT PRODUCTS (1)'), findsOneWidget);
      expect(find.text('Selecta Supreme Classic Vanilla 1.4L Tub'), findsOneWidget);
      expect(find.text('Qty: 4'), findsOneWidget);
      expect(find.textContaining('RAW DOC TEXT VANILLA 1.4L'), findsOneWidget);
    });

    testWidgets('ReceiptScanFlow.showSummary invokes onCorrectLine when Correct button is tapped', (tester) async {
      ScannedReceiptLine? correctedLine;
      final scannedLines = [
        ScannedReceiptLine(
          item: testItem,
          quantity: 2,
          rawText: 'RAW DOC TEXT CORNETTO',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                ReceiptScanFlow.showSummary(
                  context,
                  skuCount: 1,
                  unitCount: 2,
                  capped: [],
                  skipped: [],
                  scannedLines: scannedLines,
                  onCorrectLine: (line) async {
                    correctedLine = line;
                  },
                );
              },
              child: const Text('Open Summary'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Summary'));
      await tester.pumpAndSettle();

      expect(find.text('Correct'), findsOneWidget);
      await tester.tap(find.text('Correct'));
      await tester.pumpAndSettle();

      expect(correctedLine, isNotNull);
      expect(correctedLine!.rawText, 'RAW DOC TEXT CORNETTO');
    });
  });
}
