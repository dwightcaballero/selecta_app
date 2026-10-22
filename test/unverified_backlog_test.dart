import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/models/unverified_summary.dart';
import 'package:selecta_ops/services/breakdown_service.dart';
import 'package:selecta_ops/views/widgets/marked_date_picker.dart';

// Helper fake QueryDocumentSnapshot for testing summaryFromDocs without mock libraries
// ignore: subtype_of_sealed_class
class FakeQueryDocumentSnapshot implements QueryDocumentSnapshot {
  final Map<String, dynamic> _data;
  final String _id;

  FakeQueryDocumentSnapshot(this._id, this._data);

  @override
  String get id => _id;

  @override
  Map<String, dynamic> data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('UnverifiedSummary Model Tests', () {
    test('UnverifiedSummary.empty has zero count and null oldestDate', () {
      const summary = UnverifiedSummary.empty;
      expect(summary.count, 0);
      expect(summary.oldestDate, isNull);
      expect(summary.dates, isEmpty);
      expect(summary.hasUnverified, isFalse);
      expect(summary.oldestAgeDays, 0);
    });

    test('Oldest date and count are correctly computed from dates set via fromDates', () {
      final now = DateTime.now();
      final day1 = DateTime(now.year, now.month, now.day - 5);
      final day2 = DateTime(now.year, now.month, now.day - 2);
      final day3 = DateTime(now.year, now.month, now.day);

      final summary = UnverifiedSummary.fromDates({day2, day1, day3});
      expect(summary.count, 3);
      expect(summary.oldestDate, day1);
      expect(summary.hasUnverified, isTrue);
      expect(summary.oldestAgeDays, 5);
    });
  });

  group('UnverifiedAgeHelper Tests', () {
    test('Calculates age in days correctly ignoring time', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 23, 59);
      final yesterday = DateTime(now.year, now.month, now.day - 1, 1, 0);
      final threeDaysAgo = DateTime(now.year, now.month, now.day - 3, 12, 0);

      expect(UnverifiedAgeHelper.calculateAgeInDays(today), 0);
      expect(UnverifiedAgeHelper.calculateAgeInDays(yesterday), 1);
      expect(UnverifiedAgeHelper.calculateAgeInDays(threeDaysAgo), 3);
    });

    test('Color escalation matches plan (0-1: primary, 2: amber, 3+: red)', () {
      const colorScheme = ColorScheme.light(primary: Colors.blue);
      expect(UnverifiedAgeHelper.getBadgeColor(0, colorScheme), Colors.blue);
      expect(UnverifiedAgeHelper.getBadgeColor(1, colorScheme), Colors.blue);
      expect(UnverifiedAgeHelper.getBadgeColor(2, colorScheme), Colors.amber.shade800);
      expect(UnverifiedAgeHelper.getBadgeColor(3, colorScheme), Colors.red.shade700);
      expect(UnverifiedAgeHelper.getBadgeColor(10, colorScheme), Colors.red.shade700);
    });

    test('Overdue text formatting', () {
      expect(UnverifiedAgeHelper.getOverdueText(0), 'Today');
      expect(UnverifiedAgeHelper.getOverdueText(1), 'Oldest: 1 day overdue');
      expect(UnverifiedAgeHelper.getOverdueText(4), 'Oldest: 4 days overdue');
    });

    test('Banner colors escalate with age', () {
      final lightBorder0 = UnverifiedAgeHelper.getBannerBorderColor(0, isDark: false);
      final lightBorder2 = UnverifiedAgeHelper.getBannerBorderColor(2, isDark: false);
      final lightBorder3 = UnverifiedAgeHelper.getBannerBorderColor(3, isDark: false);

      expect(lightBorder0, const Color(0xFFCBD5E1));
      expect(lightBorder2, Colors.amber.shade400);
      expect(lightBorder3, Colors.red.shade300);
    });
  });

  group('BreakdownService summaryFromDocs Tests', () {
    test('Deduplicates records on the same day', () {
      final now = DateTime.now();
      final day1 = DateTime(now.year, now.month, now.day - 2);

      final docs = [
        FakeQueryDocumentSnapshot('doc1', {
          'breakdownDate': Timestamp.fromDate(day1),
          'isVerifiedByDealer': false,
        }),
        FakeQueryDocumentSnapshot('doc2', {
          'breakdownDate': Timestamp.fromDate(day1),
          'isVerifiedByDealer': false,
        }),
      ];

      final summary = BreakdownService.summaryFromDocs(docs);
      expect(summary.count, 1);
      expect(summary.dates.length, 1);
    });

    test('Parses both Timestamp and ISO 8601 String dates', () {
      final now = DateTime.now();
      final day1 = DateTime(now.year, now.month, now.day - 4);
      final day2 = DateTime(now.year, now.month, now.day - 2);

      final docs = [
        FakeQueryDocumentSnapshot('doc1', {
          'breakdownDate': Timestamp.fromDate(day1),
          'isVerifiedByDealer': false,
        }),
        FakeQueryDocumentSnapshot('doc2', {
          'breakdownDate': day2.toIso8601String(),
          'isVerifiedByDealer': false,
        }),
      ];

      final summary = BreakdownService.summaryFromDocs(docs);
      expect(summary.count, 2);
      expect(summary.oldestDate, DateTime(day1.year, day1.month, day1.day));
    });

    test('Treats null or missing isVerifiedByDealer as unverified', () {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day - 1);

      final docs = [
        FakeQueryDocumentSnapshot('doc1', {
          'breakdownDate': Timestamp.fromDate(day),
          // isVerifiedByDealer is missing
        }),
      ];

      final summary = BreakdownService.summaryFromDocs(docs);
      expect(summary.count, 1);
    });

    test('Excludes verified records', () {
      final now = DateTime.now();
      final day1 = DateTime(now.year, now.month, now.day - 3);
      final day2 = DateTime(now.year, now.month, now.day - 1);

      final docs = [
        FakeQueryDocumentSnapshot('doc1', {
          'breakdownDate': Timestamp.fromDate(day1),
          'isVerifiedByDealer': true,
        }),
        FakeQueryDocumentSnapshot('doc2', {
          'breakdownDate': Timestamp.fromDate(day2),
          'isVerifiedByDealer': false,
        }),
      ];

      final summary = BreakdownService.summaryFromDocs(docs);
      expect(summary.count, 1);
      expect(summary.oldestDate, DateTime(day2.year, day2.month, day2.day));
    });

    test('Filters out records before cutoffDate', () {
      final cutoff = DateTime(2026, 1, 1);
      final beforeCutoff = DateTime(2025, 12, 15);
      final afterCutoff = DateTime(2026, 1, 10);

      final docs = [
        FakeQueryDocumentSnapshot('doc1', {
          'breakdownDate': Timestamp.fromDate(beforeCutoff),
          'isVerifiedByDealer': false,
        }),
        FakeQueryDocumentSnapshot('doc2', {
          'breakdownDate': Timestamp.fromDate(afterCutoff),
          'isVerifiedByDealer': false,
        }),
      ];

      final summary = BreakdownService.summaryFromDocs(docs, cutoffDate: cutoff);
      expect(summary.count, 1);
      expect(summary.oldestDate, DateTime(2026, 1, 10));
    });
  });

  group('Oldest-First Enforcement Tests', () {
    test('OlderUnverifiedException properties', () {
      final oldest = DateTime(2026, 9, 15);
      final exception = OlderUnverifiedException(
        'Please verify 2026-09-15 first.',
        oldestDate: oldest,
      );

      expect(exception.oldestDate, oldest);
      expect(exception.toString(), contains('2026-09-15'));
    });

    test('Next unverified selection skips currently selected date', () {
      final day1 = DateTime(2026, 9, 10);
      final day2 = DateTime(2026, 9, 12);
      final day3 = DateTime(2026, 9, 15);

      final summary = UnverifiedSummary.fromDates({day1, day2, day3});

      // When user is currently viewing day1:
      final remaining = summary.dates
          .where((d) => d.year != day1.year || d.month != day1.month || d.day != day1.day)
          .toList()
        ..sort();

      expect(remaining.first, day2);
    });
  });

  group('MarkedDatePicker Widget Tests', () {
    testWidgets('Renders calendar with day statuses and legend', (tester) async {
      final now = DateTime(2026, 9, 15);
      final pendingDay = DateTime(2026, 9, 10);
      final doneDay = DateTime(2026, 9, 12);

      final statuses = {
        pendingDay: DayStatus.pending,
        doneDay: DayStatus.done,
      };

      DateTime? pickedDate;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  pickedDate = await showMarkedDatePicker(
                    context: context,
                    initialDate: now,
                    dayStatuses: statuses,
                    firstDate: DateTime(2026, 1, 1),
                    lastDate: DateTime(2026, 12, 31),
                  );
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      );

      // Tap to open dialog
      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      // Verify legend is visible
      expect(find.text('1 Pending'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);

      // Tap a date cell (e.g. day 10)
      final day10Finder = find.descendant(
        of: find.byType(Dialog),
        matching: find.text('10'),
      );
      expect(day10Finder, findsOneWidget);
      await tester.tap(day10Finder);
      await tester.pumpAndSettle();

      // Verify dialog closed and picked date is day 10
      expect(pickedDate, equals(DateTime(2026, 9, 10)));
    });
  });
}
