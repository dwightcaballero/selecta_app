import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/views/widgets/exit_guard.dart';

void main() {
  testWidgets('ExitGuard does not trigger onBackIntercept when child route is pushed', (tester) async {
    bool intercepted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: ExitGuard(
          onBackIntercept: () {
            intercepted = true;
            return true;
          },
          child: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => Scaffold(
                        appBar: AppBar(title: const Text('Child Route')),
                        body: const Text('Child Screen'),
                      ),
                    ),
                  );
                },
                child: const Text('Open Child'),
              ),
            ),
          ),
        ),
      ),
    );

    // Verify initial home screen
    expect(find.text('Open Child'), findsOneWidget);

    // Push child route
    await tester.tap(find.text('Open Child'));
    await tester.pumpAndSettle();
    expect(find.text('Child Screen'), findsOneWidget);

    // Simulate system back gesture while child route is open
    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    await widgetsAppState.didPopRoute();
    await tester.pumpAndSettle();

    // Verify child route popped back to home, but ExitGuard did not intercept or switch tabs
    expect(intercepted, isFalse);
    expect(find.text('Open Child'), findsOneWidget);
  });

  testWidgets('ExitGuard intercepts back gesture on non-zero tab and returns to Home tab', (tester) async {
    int currentTabIndex = 1;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return ExitGuard(
              onBackIntercept: () {
                if (currentTabIndex != 0) {
                  setState(() => currentTabIndex = 0);
                  return true;
                }
                return false;
              },
              child: Scaffold(
                body: IndexedStack(
                  index: currentTabIndex,
                  children: const [
                    Text('Home Tab Screen'),
                    Text('Inventory Tab Screen'),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    // Initial state: Inventory tab is visible
    expect(find.text('Inventory Tab Screen'), findsOneWidget);
    expect(currentTabIndex, equals(1));

    // Simulate system back gesture (e.g. edge swipe or back button)
    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    await widgetsAppState.didPopRoute();
    await tester.pumpAndSettle();

    // Verify back navigation switched to Home tab and did not pop root route
    expect(currentTabIndex, equals(0));
    expect(find.text('Home Tab Screen'), findsOneWidget);
  });
}

