import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/views/widgets/picklist/multi_qty_reminder_dialog.dart';

void main() {
  group('shouldShowMultiQtyReminder', () {
    test('returns false for quantity <= 1', () {
      expect(shouldShowMultiQtyReminder(0), isFalse);
      expect(shouldShowMultiQtyReminder(1), isFalse);
      expect(shouldShowMultiQtyReminder(-1), isFalse);
    });

    test('returns true for quantity >= 2', () {
      expect(shouldShowMultiQtyReminder(2), isTrue);
      expect(shouldShowMultiQtyReminder(5), isTrue);
      expect(shouldShowMultiQtyReminder(100), isTrue);
    });
  });

  group('showMultiQtyReminderDialog Widget Tests', () {
    testWidgets('shows qty, product name, UNITS, no ordered line when unadjusted, and closes on OK', (tester) async {
      const item = OrderItem(
        productId: 'item_1',
        productName: 'Cornetto Disc Chocolate',
        category: 'By Piece',
        sellingPrice: 35.0,
        orderedQuantity: 2,
        pickedQuantity: 2,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showMultiQtyReminderDialog(
                    context,
                    item,
                    requiredQty: 2,
                  ),
                  child: const Text('Open Reminder'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Reminder'));
      await tester.pumpAndSettle();

      expect(find.text('Quantity is more than 1'), findsOneWidget);
      expect(find.text('Cornetto Disc Chocolate'), findsOneWidget);
      expect(find.text('Category: By Piece'), findsOneWidget);
      expect(find.text('×2'), findsOneWidget);
      expect(find.text('UNITS'), findsOneWidget);
      expect(find.text('Pick 2 units for this item.'), findsOneWidget);
      expect(find.text('Ordered: 2'), findsNothing);
      expect(find.text('OK'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Quantity is more than 1'), findsNothing);
    });

    testWidgets('shows CASES and Ordered: N when requiredQty differs from orderedQuantity', (tester) async {
      const item = OrderItem(
        productId: 'item_2',
        productName: 'Magnum Almond Case',
        category: 'By Case',
        sellingPrice: 600.0,
        orderedQuantity: 5,
        pickedQuantity: 3,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showMultiQtyReminderDialog(
                    context,
                    item,
                    requiredQty: 3,
                  ),
                  child: const Text('Open Reminder'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Reminder'));
      await tester.pumpAndSettle();

      expect(find.text('Magnum Almond Case'), findsOneWidget);
      expect(find.text('Category: By Case'), findsOneWidget);
      expect(find.text('×3'), findsOneWidget);
      expect(find.text('CASES'), findsOneWidget);
      expect(find.text('Ordered: 5'), findsOneWidget);
      expect(find.text('Pick 3 cases for this item.'), findsOneWidget);
    });

    testWidgets('closes dialog when tapping barrier outside', (tester) async {
      const item = OrderItem(
        productId: 'item_3',
        productName: 'Selecta Super Thick Strawberry',
        category: 'Pints',
        sellingPrice: 120.0,
        orderedQuantity: 4,
        pickedQuantity: 4,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showMultiQtyReminderDialog(
                    context,
                    item,
                    requiredQty: 4,
                  ),
                  child: const Text('Open Reminder'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Reminder'));
      await tester.pumpAndSettle();
      expect(find.text('Quantity is more than 1'), findsOneWidget);

      // Tap near top-left outside the dialog
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Quantity is more than 1'), findsNothing);
    });
  });
}
