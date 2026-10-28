import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/services/thermal_printer_service.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';
import 'package:selecta_ops/views/widgets/digital_receipt_dialog.dart';

class FakeThermalPrinterService extends ThermalPrinterService {
  bool printResult;
  int printCount = 0;
  bool connected;
  bool bluetoothEnabled;

  FakeThermalPrinterService({
    this.printResult = true,
    this.connected = true,
    this.bluetoothEnabled = true,
  }) : super.forTesting();

  @override
  Future<ThermalPaperSize> getPaperSize() async => ThermalPaperSize.mm58;

  @override
  Future<void> setPaperSize(ThermalPaperSize size) async {}

  @override
  Future<String?> getSavedPrinterName() async => 'Fake Bluetooth Printer';

  @override
  Future<String?> getSavedPrinterMac() async => '00:11:22:33:44:55';

  @override
  Future<bool> isConnected() async => connected;

  @override
  Future<bool> isBluetoothEnabled() async => bluetoothEnabled;

  @override
  Future<bool> connect(String mac) async => connected;

  @override
  String generateTextReceipt({
    required Delivery delivery,
    required String dealerName,
    String? deliveryId,
    ThermalPaperSize paperSize = ThermalPaperSize.mm58,
  }) {
    return 'FAKE RECEIPT FOR ${delivery.storeName}';
  }

  @override
  Future<bool> printReceipt({
    required Delivery delivery,
    required String dealerName,
    String? deliveryId,
    ThermalPaperSize? paperSize,
  }) async {
    printCount++;
    return printResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testDelivery = Delivery(
    storeName: 'Test Store 101',
    remarks: 'Deliver fast',
    transactionStatus: 'For Delivery',
    imagePath: '',
    orderAmount: 1500.0,
    cashAmount: 0.0,
    onlineAmount: 0.0,
    creditAmount: 0.0,
    returnAmount: 0.0,
    creditStatus: 'Unpaid',
    deliveryDate: Timestamp.now(),
    items: const [
      OrderItem(
        productId: 'p1',
        productName: 'Cornetto Chocolate',
        productSource: 'selecta',
        category: 'By Piece',
        sellingPrice: 35.0,
        orderedQuantity: 10,
        pickedQuantity: 10,
        isPicked: true,
      ),
    ],
    createdBy: 'Tester',
    lastUpdatedBy: 'Tester',
    createdDate: Timestamp.now(),
    lastupdatedDate: Timestamp.now(),
  );

  Widget createTestWidget({
    required bool remindIfNotPrinted,
    required ThermalPrinterService printerService,
    VoidCallback? onProceed,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              DigitalReceiptDialog.show(
                context,
                delivery: testDelivery,
                deliveryId: 'DEL-101',
                dealerName: 'Test Ice Cream Dealer',
                proceedLabel: 'Close',
                remindIfNotPrinted: remindIfNotPrinted,
                printerService: printerService,
                onProceed: onProceed,
              );
            },
            child: const Text('Open Receipt'),
          ),
        ),
      ),
    );
  }

  group('DigitalReceiptDialog Print Reminder Tests', () {
    testWidgets('Case a & b: remindIfNotPrinted=true triggers reminder, Close Without Printing closes dialog and calls onProceed',
        (tester) async {
      bool onProceedCalled = false;
      final fakePrinter = FakeThermalPrinterService();

      await tester.pumpWidget(createTestWidget(
        remindIfNotPrinted: true,
        printerService: fakePrinter,
        onProceed: () => onProceedCalled = true,
      ));

      // Open receipt dialog
      await tester.tap(find.text('Open Receipt'));
      await tester.pumpAndSettle();
      expect(find.byType(DigitalReceiptDialog), findsOneWidget);

      // Tap bottom Close button
      await tester.tap(find.widgetWithText(AsyncFilledButton, 'Close'));
      await tester.pumpAndSettle();

      // Case a: Reminder dialog is shown, dialog and onProceed not triggered yet
      expect(find.text('Receipt not printed yet'), findsOneWidget);
      expect(
        find.text(
          'This transaction has not been printed. The salesman should bring the receipt together with the stocks. Print it now?',
        ),
        findsOneWidget,
      );
      expect(onProceedCalled, isFalse);
      expect(find.byType(DigitalReceiptDialog), findsOneWidget);

      // Case b: Tap "Close Without Printing"
      await tester.tap(find.text('Close Without Printing'));
      await tester.pumpAndSettle();

      // Dialog closed, onProceed called once
      expect(find.text('Receipt not printed yet'), findsNothing);
      expect(find.byType(DigitalReceiptDialog), findsNothing);
      expect(onProceedCalled, isTrue);
    });

    testWidgets('Case c: "Print Now" with successful print allows next Close without reminder', (tester) async {
      bool onProceedCalled = false;
      final fakePrinter = FakeThermalPrinterService(printResult: true);

      await tester.pumpWidget(createTestWidget(
        remindIfNotPrinted: true,
        printerService: fakePrinter,
        onProceed: () => onProceedCalled = true,
      ));

      await tester.tap(find.text('Open Receipt'));
      await tester.pumpAndSettle();

      // Tap Close -> reminder appears
      await tester.tap(find.widgetWithText(AsyncFilledButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.text('Receipt not printed yet'), findsOneWidget);

      // Tap "Print Now"
      await tester.tap(find.text('Print Now'));
      await tester.pumpAndSettle();

      // Print was called once, modal stays open
      expect(fakePrinter.printCount, equals(1));
      expect(find.byType(DigitalReceiptDialog), findsOneWidget);
      expect(find.text('Receipt not printed yet'), findsNothing);
      expect(onProceedCalled, isFalse);

      // Tap Close again -> exits cleanly with no reminder because _hasPrinted == true
      await tester.tap(find.widgetWithText(AsyncFilledButton, 'Close'));
      await tester.pumpAndSettle();

      expect(find.text('Receipt not printed yet'), findsNothing);
      expect(find.byType(DigitalReceiptDialog), findsNothing);
      expect(onProceedCalled, isTrue);
    });

    testWidgets('Case d: "Print Now" with failed print keeps reminder active on next Close', (tester) async {
      bool onProceedCalled = false;
      final fakePrinter = FakeThermalPrinterService(printResult: false);

      await tester.pumpWidget(createTestWidget(
        remindIfNotPrinted: true,
        printerService: fakePrinter,
        onProceed: () => onProceedCalled = true,
      ));

      await tester.tap(find.text('Open Receipt'));
      await tester.pumpAndSettle();

      // Tap Close -> reminder appears
      await tester.tap(find.widgetWithText(AsyncFilledButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.text('Receipt not printed yet'), findsOneWidget);

      // Tap "Print Now" (will fail)
      await tester.tap(find.text('Print Now'));
      await tester.pumpAndSettle();

      expect(fakePrinter.printCount, equals(1));
      expect(find.byType(DigitalReceiptDialog), findsOneWidget);
      expect(onProceedCalled, isFalse);

      // Tap Close again -> reminder MUST appear again because print failed (_hasPrinted remains false)
      await tester.tap(find.widgetWithText(AsyncFilledButton, 'Close'));
      await tester.pumpAndSettle();

      expect(find.text('Receipt not printed yet'), findsOneWidget);
      expect(onProceedCalled, isFalse);

      // Can still knowingly close
      await tester.tap(find.text('Close Without Printing'));
      await tester.pumpAndSettle();
      expect(onProceedCalled, isTrue);
      expect(find.byType(DigitalReceiptDialog), findsNothing);
    });

    testWidgets('Case e1: Header X button triggers the guarded reminder', (tester) async {
      final fakePrinter = FakeThermalPrinterService();

      await tester.pumpWidget(createTestWidget(
        remindIfNotPrinted: true,
        printerService: fakePrinter,
      ));

      await tester.tap(find.text('Open Receipt'));
      await tester.pumpAndSettle();

      // Test Header 'X' IconButton
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Receipt not printed yet'), findsOneWidget);

      // Close without printing to finish
      await tester.tap(find.text('Close Without Printing'));
      await tester.pumpAndSettle();
      expect(find.byType(DigitalReceiptDialog), findsNothing);
    });

    testWidgets('Case e2: Android Back gesture triggers the guarded reminder', (tester) async {
      final fakePrinter = FakeThermalPrinterService();

      await tester.pumpWidget(createTestWidget(
        remindIfNotPrinted: true,
        printerService: fakePrinter,
      ));

      await tester.tap(find.text('Open Receipt'));
      await tester.pumpAndSettle();

      // Test Android Back (didPopRoute)
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Receipt not printed yet'), findsOneWidget);

      // Close without printing to finish
      await tester.tap(find.text('Close Without Printing'));
      await tester.pumpAndSettle();
      expect(find.byType(DigitalReceiptDialog), findsNothing);
    });

    testWidgets('Case f: remindIfNotPrinted=false (default) exits immediately with no reminder', (tester) async {
      bool onProceedCalled = false;
      final fakePrinter = FakeThermalPrinterService();

      await tester.pumpWidget(createTestWidget(
        remindIfNotPrinted: false,
        printerService: fakePrinter,
        onProceed: () => onProceedCalled = true,
      ));

      await tester.tap(find.text('Open Receipt'));
      await tester.pumpAndSettle();

      // Tap Close
      await tester.tap(find.widgetWithText(AsyncFilledButton, 'Close'));
      await tester.pumpAndSettle();

      // Should close immediately without reminder
      expect(find.text('Receipt not printed yet'), findsNothing);
      expect(find.byType(DigitalReceiptDialog), findsNothing);
      expect(onProceedCalled, isTrue);
    });

    testWidgets('Case g: Tap outside the reminder does not dismiss it', (tester) async {
      final fakePrinter = FakeThermalPrinterService();

      await tester.pumpWidget(createTestWidget(
        remindIfNotPrinted: true,
        printerService: fakePrinter,
      ));

      await tester.tap(find.text('Open Receipt'));
      await tester.pumpAndSettle();

      // Tap Close to show reminder
      await tester.tap(find.widgetWithText(AsyncFilledButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.text('Receipt not printed yet'), findsOneWidget);

      // Tap outside the dialog (top-left corner)
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Reminder must still be visible (barrierDismissible = false)
      expect(find.text('Receipt not printed yet'), findsOneWidget);
    });
  });
}
