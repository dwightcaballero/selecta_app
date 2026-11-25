import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/manual_purchase_receipt.dart';
import 'package:selecta_ops/models/purchaseorder.dart';
import 'package:selecta_ops/views/widgets/purchaseorder/manual_receipt_dialog.dart';
import 'package:selecta_ops/views/widgets/purchaseorder/manual_invoice_dialog.dart';
import 'package:selecta_ops/views/widgets/purchaseorder/po_confirmed_status_card.dart';

void main() {
  const items = [
    OrderItem(productId: 'a', productName: 'Product A', sellingPrice: 20, buyingPrice: 10, orderedQuantity: 10),
    OrderItem(productId: 'b', productName: 'Product B', sellingPrice: 30, buyingPrice: 20, orderedQuantity: 8),
  ];

  test('receipt plan adds only received quantities and clears the full ordered quantities', () {
    final plan = ManualPurchaseReceipt.prepare(items, [
      ManualReceiptLine(item: items[0], receivedQuantity: 7, shortageReason: 'Damaged / rejected'),
      ManualReceiptLine(item: items[1], receivedQuantity: 0, shortageReason: 'Not delivered'),
    ]);
    expect(plan.products.map((p) => (p.ordered, p.received)).toList(), [(10, 7), (8, 0)]);
    expect(plan.receivedItems.single.effectiveQuantity, 7);
    expect(plan.total, 70);
  });

  test('receipt plan aggregates repeated product lines and rejects invalid input', () {
    final lines = [
      ManualReceiptLine(item: items[0], receivedQuantity: 10),
      ManualReceiptLine(item: items[0], receivedQuantity: 4, shortageReason: 'Not delivered'),
    ];
    final plan = ManualPurchaseReceipt.prepare([items[0], items[0]], lines);
    expect(plan.products.single.ordered, 20);
    expect(plan.products.single.received, 14);
    expect(plan.total, 140);
    expect(() => ManualPurchaseReceipt.prepare(items, lines), throwsStateError);
    expect(() => ManualPurchaseReceipt.prepare([items[0]], [ManualReceiptLine(item: items[0], receivedQuantity: 11)]), throwsStateError);
    expect(() => ManualPurchaseReceipt.prepare([items[0]], [ManualReceiptLine(item: items[0], receivedQuantity: 5)]), throwsStateError);
    expect(() => ManualPurchaseReceipt.prepare([items[0]], [ManualReceiptLine(item: items[0], receivedQuantity: 0, shortageReason: 'Not delivered')]), throwsStateError);
  });

  test('manual receipt survives model round trip and legacy orders remain readable', () {
    final order = Purchaseorder.empty().copyWith(
      manualReceiptLines: [
        ManualReceiptLine(item: items[0], receivedQuantity: 7, shortageReason: 'Damaged / rejected'),
        ManualReceiptLine(item: items[1], receivedQuantity: 0, shortageReason: 'Not delivered'),
      ],
      manualReceiptDate: Timestamp.fromDate(DateTime(2026, 11, 12)),
      manualReceiptRecordedAt: Timestamp.fromDate(DateTime(2026, 11, 12, 10)),
      manualReceiptRecordedBy: 'Dealer',
      manualReceiptRecordedByUid: 'uid',
      invoiceVerificationPending: true,
    );
    final restored = Purchaseorder.fromJson(order.toJson());
    expect(restored.manualReceiptLines[0].receivedQuantity, 7);
    expect(restored.manualReceiptLines[0].item.effectiveQuantity, 10);
    expect(restored.manualReceiptLines[1].shortageReason, 'Not delivered');
    expect(restored.manualReceiptDate, order.manualReceiptDate);
    expect(restored.manualReceiptRecordedAt, order.manualReceiptRecordedAt);
    expect(restored.manualReceiptRecordedByUid, 'uid');
    expect(restored.invoiceVerificationPending, isTrue);
    final legacy = Purchaseorder.empty().toJson()
      ..remove('manualReceiptLines')
      ..remove('invoiceVerificationPending');
    expect(Purchaseorder.fromJson(legacy).manualReceiptLines, isEmpty);
    expect(Purchaseorder.fromJson(legacy).invoiceVerificationPending, isFalse);
  });

  testWidgets('manual receipt defaults to all and can exclude a SKU', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ManualReceiptResult? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(
        onPressed: () async {
          result = await showDialog<ManualReceiptResult>(context: context, builder: (_) => const ManualReceiptDialog(items: items, orderAmount: 260));
        },
        child: const Text('Open'),
      ),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('10'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    await tester.tap(find.text('Not received').last);
    await tester.pumpAndSettle();
    expect(find.text('Not delivered'), findsOneWidget);
    expect(find.textContaining('₱160.00'), findsOneWidget);
    await tester.tap(find.text('Confirm & restock'));
    await tester.pumpAndSettle();
    expect(result!.lines[0].receivedQuantity, 10);
    expect(result!.lines[1].receivedQuantity, 0);
    expect(result!.lines[1].shortageReason, 'Not delivered');
  });

  testWidgets('manual receipt rejects over-receipt and requires shortage reason', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ManualReceiptDialog(items: items, orderAmount: 260))));
    await tester.enterText(find.byType(TextFormField).first, '11');
    await tester.tap(find.text('Confirm & restock'));
    await tester.pumpAndSettle();
    expect(find.text('Enter 0 to 10'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '5');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm & restock'));
    await tester.pumpAndSettle();
    expect(find.text('Select a reason'), findsOneWidget);
  });

  testWidgets('unverified receipt shows original and received quantities and prefills invoice estimate', (tester) async {
    final order = Purchaseorder.empty().copyWith(
      manualReceiptLines: [
        ManualReceiptLine(item: items[0], receivedQuantity: 7, shortageReason: 'Damaged / rejected'),
        ManualReceiptLine(item: items[1], receivedQuantity: 0, shortageReason: 'Not delivered'),
      ],
      invoiceVerificationPending: true,
    );
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PoConfirmedStatusCard(purchaseorder: order))));
    expect(find.text('Manually Received — Invoice Unverified'), findsOneWidget);
    expect(find.textContaining('Product B: 0 of 8 received'), findsOneWidget);
    expect(find.textContaining('₱70.00'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManualInvoiceDialog(order: order))));
    expect(find.text('70.00'), findsOneWidget);
    await tester.tap(find.text('Confirm invoice'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the invoice number'), findsOneWidget);
  });
}
