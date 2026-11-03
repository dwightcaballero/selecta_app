import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/placement_pair.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/views/pages/reports/reports_page.dart';
import 'package:selecta_ops/views/widgets/reports/placement_report_dialog.dart';

Widget buildTestDialog({
  bool isDealer = true,
  List<Hapistore>? stores,
  List<SelectaProduct>? bestSellers,
  List<PlacementPair>? pairs,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PlacementReportDialog(
        isDealerCheck: () async => isDealer,
        storesLoader: () async => stores ?? [
          Hapistore.empty()..storeName = 'Store A'..pjpSchedule = 'Monday',
          Hapistore.empty()..storeName = 'Store B'..pjpSchedule = 'Tuesday',
        ],
        bestSellersLoader: () async => bestSellers ?? [
          const SelectaProduct(
            id: '1',
            itemCode: '1',
            productName: 'Cone 35',
            category: 'By Piece',
            sellingPrice: 35.0,
            imageUrl: '',
          ),
        ],
        pairsLoader: () async => pairs ?? const [],
      ),
    ),
  );
}

void main() {
  group('PlacementReportDialog & ReportsPage Entry Tests', () {
    testWidgets('Entry card is shown when isDealer == true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ReportsPage(
            isDealer: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Placement Report (PDF)'), findsOneWidget);
      expect(
        find.text('Printable monthly client-facing placement report by PJP day'),
        findsOneWidget,
      );
    });

    testWidgets('Entry card is hidden when isDealer == false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ReportsPage(
            isDealer: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Placement Report (PDF)'), findsNothing);
      expect(
        find.text('Printable monthly client-facing placement report by PJP day'),
        findsNothing,
      );
    });

    testWidgets('Dialog displays Access Restricted for non-dealer user', (tester) async {
      await tester.pumpWidget(buildTestDialog(isDealer: false));
      await tester.pumpAndSettle();

      expect(find.text('Access Restricted'), findsOneWidget);
      expect(
        find.text('The Monthly Placement Report is only available to Dealers and Admins.'),
        findsOneWidget,
      );
    });

    testWidgets('Dialog allows month navigation up to current month and blocks future months', (tester) async {
      await tester.pumpWidget(buildTestDialog(isDealer: true));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final currentMonthStr = DateFormat('MMMM yyyy').format(now);
      expect(find.text(currentMonthStr), findsOneWidget);

      // Verify the Next Month icon button is disabled when at current month
      final nextMonthButtonFinder = find.widgetWithIcon(IconButton, Icons.chevron_right_rounded);
      expect(nextMonthButtonFinder, findsOneWidget);
      final nextButton = tester.widget<IconButton>(nextMonthButtonFinder);
      expect(nextButton.onPressed, isNull); // disabled

      // Tap previous month
      final prevMonthButtonFinder = find.widgetWithIcon(IconButton, Icons.chevron_left_rounded);
      await tester.tap(prevMonthButtonFinder);
      await tester.pumpAndSettle();

      final lastMonth = DateTime(now.year, now.month - 1, 1);
      final lastMonthStr = DateFormat('MMMM yyyy').format(lastMonth);
      expect(find.text(lastMonthStr), findsOneWidget);

      // Now Next Month button should be enabled
      final nextButtonEnabled = tester.widget<IconButton>(nextMonthButtonFinder);
      expect(nextButtonEnabled.onPressed, isNotNull);

      // Tap Next Month to return to current month
      await tester.tap(nextMonthButtonFinder);
      await tester.pumpAndSettle();
      expect(find.text(currentMonthStr), findsOneWidget);

      // And it should be disabled again
      final nextButtonDisabledAgain = tester.widget<IconButton>(nextMonthButtonFinder);
      expect(nextButtonDisabledAgain.onPressed, isNull);
    });

    testWidgets('Dialog options checkboxes can be toggled', (tester) async {
      await tester.pumpWidget(buildTestDialog(isDealer: true));
      await tester.pumpAndSettle();

      // Checkboxes default to true
      final coverCheckboxFinder = find.widgetWithText(CheckboxListTile, 'Include Cover & Executive Summary Page');
      final pitchCheckboxFinder = find.widgetWithText(CheckboxListTile, 'Include Pitch List (Missing Products per Store)');

      expect(coverCheckboxFinder, findsOneWidget);
      expect(pitchCheckboxFinder, findsOneWidget);

      var coverTile = tester.widget<CheckboxListTile>(coverCheckboxFinder);
      var pitchTile = tester.widget<CheckboxListTile>(pitchCheckboxFinder);
      expect(coverTile.value, isTrue);
      expect(pitchTile.value, isTrue);

      // Toggle cover checkbox
      await tester.ensureVisible(coverCheckboxFinder);
      await tester.tap(coverCheckboxFinder);
      await tester.pumpAndSettle();

      coverTile = tester.widget<CheckboxListTile>(coverCheckboxFinder);
      expect(coverTile.value, isFalse);

      // Toggle pitch list checkbox
      await tester.ensureVisible(pitchCheckboxFinder);
      await tester.tap(pitchCheckboxFinder);
      await tester.pumpAndSettle();

      pitchTile = tester.widget<CheckboxListTile>(pitchCheckboxFinder);
      expect(pitchTile.value, isFalse);
    });

    testWidgets('Day chips show store count, empty days are disabled, and select all / clear works', (tester) async {
      // Only Monday has 1 store, others have 0
      final stores = [
        Hapistore.empty()..storeName = 'Mon Store'..pjpSchedule = 'Monday',
      ];

      await tester.pumpWidget(buildTestDialog(isDealer: true, stores: stores));
      await tester.pumpAndSettle();

      // Monday (1) should be present and selected
      expect(find.text('Monday (1)'), findsOneWidget);
      final mondayChipFinder = find.widgetWithText(FilterChip, 'Monday (1)');
      final mondayChip = tester.widget<FilterChip>(mondayChipFinder);
      expect(mondayChip.selected, isTrue);

      // Tuesday (0) should be present and disabled
      expect(find.text('Tuesday (0)'), findsOneWidget);
      final tuesdayChipFinder = find.widgetWithText(FilterChip, 'Tuesday (0)');
      final tuesdayChip = tester.widget<FilterChip>(tuesdayChipFinder);
      expect(tuesdayChip.onSelected, isNull); // disabled

      // Clear button clears selection
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(mondayChipFinder).selected, isFalse);

      // Select All selects only days with > 0 stores (Monday)
      await tester.tap(find.text('Select All'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(mondayChipFinder).selected, isTrue);
    });
  });
}
