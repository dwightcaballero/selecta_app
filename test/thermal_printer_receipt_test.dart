import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/thermal_printer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Thermal Printer & Receipt Formatting Tests', () {
    final testItems = [
      const OrderItem(
        productId: 'prod_1',
        productName: 'Selecta Cornetto Classic 110ml',
        productSource: 'selecta',
        category: 'By Piece',
        sellingPrice: 35.0,
        orderedQuantity: 10,
        pickedQuantity: 10,
        isPicked: true,
      ),
      const OrderItem(
        productId: 'prod_2',
        productName: 'Selecta Super Thick Vanilla 1.3L',
        productSource: 'selecta',
        category: 'By Case',
        sellingPrice: 650.0,
        orderedQuantity: 2,
        pickedQuantity: 2,
        isPicked: true,
      ),
      const OrderItem(
        productId: 'prod_3',
        productName: 'Cone Wrapper Pack',
        productSource: 'other',
        category: '',
        sellingPrice: 120.0,
        orderedQuantity: 1,
        pickedQuantity: 1,
        isPicked: true,
      ),
    ];

    final testDelivery = Delivery(
      storeName: 'Sari-Sari Store Alpha',
      remarks: 'Deliver before noon',
      transactionStatus: 'Pending',
      imagePath: '',
      orderAmount: 1770.0,
      cashAmount: 0.0,
      onlineAmount: 0.0,
      creditAmount: 0.0,
      returnAmount: 0.0,
      creditStatus: 'Unpaid',
      deliveryDate: Timestamp.now(),
      items: testItems,
      createdBy: 'Salesman 1',
      lastUpdatedBy: 'Salesman 1',
      createdDate: Timestamp.now(),
      lastupdatedDate: Timestamp.now(),
      createdPage: 'Picklist',
      lastUpdatedPage: 'Picklist',
      isInventoryReserved: true,
      isInventoryDeducted: false,
    );

    test('categorizeItems separates By Case, By Piece, and Other products with quantity and price subtotals', () {
      final categorized = ThermalPrinterService.categorizeItems(testItems);

      expect(categorized.selectaCase.length, equals(1));
      expect(categorized.selectaCase.first.productName, contains('Vanilla 1.3L'));
      expect(categorized.subtotalQtyCase, equals(2));
      expect(categorized.subtotalCase, equals(1300.0)); // 2 x 650

      expect(categorized.selectaPiece.length, equals(1));
      expect(categorized.selectaPiece.first.productName, contains('Cornetto'));
      expect(categorized.subtotalQtyPiece, equals(10));
      expect(categorized.subtotalPiece, equals(350.0)); // 10 x 35

      expect(categorized.otherProducts.length, equals(1));
      expect(categorized.otherProducts.first.productName, equals('Cone Wrapper Pack'));
      expect(categorized.subtotalQtyOther, equals(1));
      expect(categorized.subtotalOther, equals(120.0)); // 1 x 120
    });

    test('generateTextReceipt formats aligned columns, subtotals, removes ref/status, and removes everything below Grand Total', () {
      final service = ThermalPrinterService();
      final receipt = service.generateTextReceipt(
        delivery: testDelivery,
        dealerName: 'Metro Ice Cream Trading',
        deliveryId: 'DEL-12345678',
        paperSize: ThermalPaperSize.mm58,
      );

      // Header checks: Dealer name, DELIVERY RECEIPT, Store name, date are present
      expect(receipt, contains('METRO ICE CREAM TRADING'));
      expect(receipt, contains('DELIVERY RECEIPT'));
      expect(receipt, contains('STORE: SARI-SARI STORE ALPHA'));

      // Reference number and Status MUST NOT be present
      expect(receipt.contains('REF:'), isFalse);
      expect(receipt.contains('STATUS:'), isFalse);

      // Column Header check - must appear only once
      expect(receipt, contains('ITEM        QTY   PRICE    TOTAL'));
      expect('ITEM        QTY   PRICE    TOTAL'.allMatches(receipt).length, equals(1));

      // Category names MUST NOT be present
      expect(receipt.contains('[ SELECTA PRODUCTS (BY CASE) ]'), isFalse);
      expect(receipt.contains('[ SELECTA PRODUCTS (BY PIECE) ]'), isFalse);
      expect(receipt.contains('[ OTHER PRODUCTS ]'), isFalse);

      // Order of items must still be preserved: Case first, then Piece, then Other
      final vanillaCaseIndex = receipt.indexOf('VANILLA');
      final cornettoPieceIndex = receipt.indexOf('CORNETTO');
      final coneOtherIndex = receipt.indexOf('CONE');
      expect(vanillaCaseIndex < cornettoPieceIndex, isTrue);
      expect(cornettoPieceIndex < coneOtherIndex, isTrue);

      // Subtotals for each section are preserved
      expect(receipt, contains('SUBTOTAL      2         1,300.00'));
      expect(receipt, contains('SUBTOTAL     10           350.00'));
      expect(receipt, contains('SUBTOTAL      1           120.00'));

      // Footer check: Grand Total only
      expect(receipt, contains('GRAND TOTAL  13         1,770.00'));

      // Must NOT contain anything below Grand Total
      expect(receipt.contains('Deliver before noon'), isFalse);
      expect(receipt.contains('Customer Signature'), isFalse);
      expect(receipt.contains('Received in good order'), isFalse);
      expect(receipt.contains('Thank you for your business'), isFalse);
    });

    test('generateTextReceipt does not show category names and only shows items and subtotals', () {
      final service = ThermalPrinterService();

      // Only By Piece items
      final onlyPieceDelivery = Delivery(
        storeName: 'Quick Corner Mart',
        remarks: 'None',
        transactionStatus: 'Pending',
        imagePath: '',
        orderAmount: 70.0,
        cashAmount: 0.0,
        onlineAmount: 0.0,
        creditAmount: 0.0,
        returnAmount: 0.0,
        creditStatus: 'Unpaid',
        deliveryDate: Timestamp.now(),
        items: [
          const OrderItem(
            productId: 'prod_1',
            productName: 'Selecta Cornetto Classic 110ml',
            productSource: 'selecta',
            category: 'By Piece',
            sellingPrice: 35.0,
            orderedQuantity: 2,
            pickedQuantity: 2,
            isPicked: true,
          ),
        ],
        createdBy: 'Salesman 1',
        lastUpdatedBy: 'Salesman 1',
        createdDate: Timestamp.now(),
        lastupdatedDate: Timestamp.now(),
        createdPage: 'Picklist',
        lastUpdatedPage: 'Picklist',
        isInventoryReserved: true,
        isInventoryDeducted: false,
      );

      final receipt = service.generateTextReceipt(
        delivery: onlyPieceDelivery,
        dealerName: 'Metro Ice Cream Trading',
        paperSize: ThermalPaperSize.mm58,
      );

      // By Piece item and subtotal should be visible
      expect(receipt, contains('CORNETTO'));
      expect(receipt, contains('SUBTOTAL      2            70.00'));
      expect(receipt, contains('GRAND TOTAL   2            70.00'));

      // Category names MUST NOT be shown
      expect(receipt.contains('[ SELECTA PRODUCTS (BY CASE) ]'), isFalse);
      expect(receipt.contains('[ SELECTA PRODUCTS (BY PIECE) ]'), isFalse);
      expect(receipt.contains('[ OTHER PRODUCTS ]'), isFalse);
    });

    test('generateTextReceipt supports 80mm wider line wrapping and columns', () {
      final service = ThermalPrinterService();
      final receipt = service.generateTextReceipt(
        delivery: testDelivery,
        dealerName: 'Metro Ice Cream Trading',
        deliveryId: 'DEL-12345678',
        paperSize: ThermalPaperSize.mm80,
      );

      expect(receipt, contains('=' * 48));
      expect(receipt, contains('-' * 48));
      expect(receipt, contains('ITEM                    QTY     PRICE      TOTAL'));
      expect(receipt, contains('GRAND TOTAL'));
      expect(receipt, contains('1,770.00'));
    });

    test('generateEscPosBytes outputs line feeds for empty lines in receipt', () async {
      final service = ThermalPrinterService();
      final bytes = await service.generateEscPosBytes(
        delivery: testDelivery,
        dealerName: 'Metro Ice Cream Trading',
        paperSize: ThermalPaperSize.mm58,
      );

      expect(bytes, isNotEmpty);
      // Newlines in ESC/POS are ASCII 10 (0x0A) line feeds
      expect(bytes.contains(10), isTrue);
    });
  });
}
