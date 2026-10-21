import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';

void main() {
  group('AsyncButton Widgets', () {
    testWidgets('AsyncFilledButton shows spinner, disables itself, and executes task', (tester) async {
      final completer = Completer<void>();
      var executedCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AsyncFilledButton(
                loadingLabel: 'Saving...',
                onPressed: () async {
                  executedCount++;
                  await completer.future;
                },
                child: const Text('Save'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Save'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Tap button once
      await tester.tap(find.text('Save'));
      await tester.pump(); // Start loading state

      expect(executedCount, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Saving...'), findsOneWidget);

      // Tap again while loading to verify double-tap prevention
      await tester.tap(find.byType(AsyncFilledButton));
      await tester.pump();
      expect(executedCount, 1); // should still be 1!

      // Complete async operation
      completer.complete();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('AsyncOutlinedButton.icon renders icon and updates label while executing', (tester) async {
      final completer = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AsyncOutlinedButton.icon(
                loadingLabel: 'Deleting...',
                onPressed: () async => await completer.future,
                icon: const Icon(Icons.delete),
                label: const Text('Delete'),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.delete), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tester.tap(find.byType(AsyncOutlinedButton));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Deleting...'), findsOneWidget);

      completer.complete();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('AsyncIconButton auto-disables and displays spinner during execution', (tester) async {
      final completer = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AsyncIconButton(
                onPressed: () async => await completer.future,
                icon: const Icon(Icons.sync),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.sync), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete();
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.sync), findsOneWidget);
    });
  });

  group('ShowMessage.runWithLoading', () {
    testWidgets('Displays blocking modal with message and dismisses upon completion', (tester) async {
      final completer = Completer<String>();
      String? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await ShowMessage.runWithLoading(
                    ctx,
                    message: 'Processing batch sync...',
                    task: () => completer.future,
                  );
                },
                child: const Text('Run Task'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Run Task'));
      await tester.pump(); // open dialog

      expect(find.text('Processing batch sync...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete('Success Payload');
      await tester.pumpAndSettle();

      expect(find.text('Processing batch sync...'), findsNothing);
      expect(result, 'Success Payload');
    });
  });
}
