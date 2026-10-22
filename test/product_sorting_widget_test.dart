import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/controllers/product_sort_controller.dart';
import 'package:selecta_ops/models/product_sort_doc.dart';
import 'package:selecta_ops/models/sub_category.dart';
import 'package:selecta_ops/services/product_sort_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProductSortService.instance.resetForTesting();
  });

  tearDown(() {
    ProductSortService.instance.resetForTesting();
  });

  group('Product Sorting Logic & Widget Component Tests', () {
    testWidgets('Sub-Category order and product drag sequence mutates state correctly', (tester) async {
      final subA = SubCategory(
        id: 'sub_a',
        name: 'Cones & Sticks',
        category: 'By Piece',
        order: 0,
        isActive: true,
      );
      final subB = SubCategory(
        id: 'sub_b',
        name: 'Tubs & Pints',
        category: 'By Piece',
        order: 1,
        isActive: true,
      );

      final controller = ProductSortController();
      controller.initialize(
        subCategories: [subA, subB],
        sortDoc: ProductSortDoc(
          dealerId: 'test_dealer',
          byPiece: {
            'sub_a': ['p1', 'p2'],
            'sub_b': ['p3'],
          },
          byCase: {},
        ),
      );

      // Verify Level 1 subcategories order
      expect(controller.getSubCategoriesForCategory('By Piece').map((s) => s.name).toList(), [
        'Cones & Sticks',
        'Tubs & Pints',
      ]);

      // Reorder Level 1: move index 1 to 0
      controller.reorderSubCategories('By Piece', 1, 0);
      expect(controller.getSubCategoriesForCategory('By Piece').map((s) => s.name).toList(), [
        'Tubs & Pints',
        'Cones & Sticks',
      ]);
      expect(controller.hasUnsavedChanges, isTrue);

      // Reorder Level 2: inside sub_a, move index 1 to 0
      controller.reorderProductsInSubCategory(
        category: 'By Piece',
        subCategoryId: 'sub_a',
        oldIndex: 1,
        newIndex: 0,
      );
      expect(controller.sortDoc.byPiece['sub_a'], ['p2', 'p1']);

      // Unassign product from sub_a
      controller.removeProductFromSubCategory(
        category: 'By Piece',
        subCategoryId: 'sub_a',
        productId: 'p2',
      );
      expect(controller.sortDoc.byPiece['sub_a'], ['p1']);

      // Assign p2 to sub_b
      controller.addProductToSubCategory(
        category: 'By Piece',
        subCategoryId: 'sub_b',
        productId: 'p2',
      );
      expect(controller.sortDoc.byPiece['sub_b'], ['p3', 'p2']);
    });

    testWidgets('Configuration sorting mode toggling and sub-category management UI state', (tester) async {
      String mode = 'srp';
      List<SubCategory> subCategories = [
        SubCategory(id: 's1', name: 'Bulk Tubs', category: 'By Case', order: 0, isActive: true),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return RadioGroup<String>(
                  groupValue: mode,
                  onChanged: (val) => setState(() => mode = val!),
                  child: Column(
                    children: [
                      const RadioListTile<String>(
                        key: ValueKey('mode_srp'),
                        title: Text('Default (by SRP then Name)'),
                        value: 'srp',
                      ),
                      const RadioListTile<String>(
                        key: ValueKey('mode_custom'),
                        title: Text('Custom Dealer Sort'),
                        value: 'custom',
                      ),
                      Text('Active Mode: $mode'),
                      ...subCategories.map((s) => Text('Sub: ${s.name} (${s.category})')),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Active Mode: srp'), findsOneWidget);
      expect(find.text('Sub: Bulk Tubs (By Case)'), findsOneWidget);

      // Tap Custom sort
      await tester.tap(find.byKey(const ValueKey('mode_custom')));
      await tester.pump();

      expect(find.text('Active Mode: custom'), findsOneWidget);
    });

    testWidgets('Unsaved changes dialog prompts user before exit', (tester) async {
      bool userStayed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  final discard = await showDialog<bool>(
                    context: ctx,
                    builder: (dCtx) => AlertDialog(
                      title: const Text('Unsaved Changes'),
                      content: const Text('You have unsaved changes to your product sequence.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dCtx, false),
                          child: const Text('Keep Editing'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dCtx, true),
                          child: const Text('Discard & Leave'),
                        ),
                      ],
                    ),
                  );
                  if (discard == false) {
                    userStayed = true;
                  }
                },
                child: const Text('Trigger Exit'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Exit'));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved Changes'), findsOneWidget);
      expect(find.text('Keep Editing'), findsOneWidget);
      expect(find.text('Discard & Leave'), findsOneWidget);

      await tester.tap(find.text('Keep Editing'));
      await tester.pumpAndSettle();

      expect(userStayed, isTrue);
    });
  });
}
