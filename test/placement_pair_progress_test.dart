import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/controllers/placement_controller.dart';
import 'package:selecta_ops/data/data.dart';
import 'package:selecta_ops/models/placement_pair.dart';

void main() {
  group('PlacementPair and Target Count Progress Tests', () {
    test('PlacementPair serialization and helpers', () {
      final pair = PlacementPair(product1: 'Watermelon Slice', product2: 'Chocky Stick');
      expect(pair.matches('Watermelon Slice'), isTrue);
      expect(pair.matches('watermelon slice'), isTrue);
      expect(pair.matches('Chocky Stick'), isTrue);
      expect(pair.matches('chocky stick'), isTrue);
      expect(pair.matches('Boom Boom'), isFalse);

      expect(pair.getOther('Watermelon Slice'), equals('Chocky Stick'));
      expect(pair.getOther('Chocky Stick'), equals('Watermelon Slice'));
      expect(pair.getOther('Other'), isNull);

      final json = pair.toJson();
      final fromJson = PlacementPair.fromJson(json);
      expect(fromJson, equals(pair));
    });

    test('Paired products count as ONE target when either is placed', () {
      final allProducts = [
        'Prod 1',
        'Prod 2',
        'Prod 3',
        'Prod 4',
        'Prod 5',
        'Prod 6',
        'Prod 7',
        'Prod 8',
        'Prod 9',
        'Prod 10',
        'Prod 11',
        'Prod 12',
        'Prod 13',
        'Prod 14',
        'Prod 15',
      ];

      // 3 pairs among the 15 products
      final pairs = [
        PlacementPair(product1: 'Prod 1', product2: 'Prod 2'),
        PlacementPair(product1: 'Prod 3', product2: 'Prod 4'),
        PlacementPair(product1: 'Prod 5', product2: 'Prod 6'),
      ];

      // 15 products with 3 pairs = 12 total unique targets
      final initialSummary = PlacementController.computeProgress(
        allProductNames: allProducts,
        placedProductNames: [],
        placementPairs: pairs,
      );
      expect(initialSummary.totalTargets, equals(12));
      expect(initialSummary.placedTargets, equals(0));
      expect(initialSummary.isFinished, isFalse);

      // Only Prod 1 placed (either of Pair 1 placed) -> counts as 1 target
      final summaryOneOfPair = PlacementController.computeProgress(
        allProductNames: allProducts,
        placedProductNames: ['Prod 1'],
        placementPairs: pairs,
      );
      expect(summaryOneOfPair.totalTargets, equals(12));
      expect(summaryOneOfPair.placedTargets, equals(1));
      expect(summaryOneOfPair.isFinished, isFalse);

      // Both Prod 1 and Prod 2 placed -> STILL counts as 1 target!
      final summaryBothOfPair = PlacementController.computeProgress(
        allProductNames: allProducts,
        placedProductNames: ['Prod 1', 'Prod 2'],
        placementPairs: pairs,
      );
      expect(summaryBothOfPair.totalTargets, equals(12));
      expect(summaryBothOfPair.placedTargets, equals(1));
      expect(summaryBothOfPair.isFinished, isFalse);

      // Prod 1 (Pair 1), Prod 4 (Pair 2), Prod 7 (Unpaired) -> 3 targets placed
      final summaryThreeTargets = PlacementController.computeProgress(
        allProductNames: allProducts,
        placedProductNames: ['Prod 1', 'Prod 4', 'Prod 7'],
        placementPairs: pairs,
      );
      expect(summaryThreeTargets.totalTargets, equals(12));
      expect(summaryThreeTargets.placedTargets, equals(3));
      expect(summaryThreeTargets.progressRatio, closeTo(3 / 12, 0.001));
      expect(summaryThreeTargets.progressPercent, equals(25));

      // All 12 targets satisfied
      final allSatisfiedNames = [
        'Prod 1', // satisfies Pair 1
        'Prod 3', // satisfies Pair 2
        'Prod 6', // satisfies Pair 3
        'Prod 7',
        'Prod 8',
        'Prod 9',
        'Prod 10',
        'Prod 11',
        'Prod 12',
        'Prod 13',
        'Prod 14',
        'Prod 15',
      ];
      final summaryFinished = PlacementController.computeProgress(
        allProductNames: allProducts,
        placedProductNames: allSatisfiedNames,
        placementPairs: pairs,
      );
      expect(summaryFinished.totalTargets, equals(12));
      expect(summaryFinished.placedTargets, equals(12));
      expect(summaryFinished.isFinished, isTrue);
      expect(summaryFinished.progressRatio, equals(1.0));
      expect(summaryFinished.progressPercent, equals(100));
    });

    test('computeProgressFromPlacements with KPlacement list', () {
      final placements = [
        KPlacement(itemName: 'P1', itemCode: '1', isPlaced: true, isPlacedFromDB: true, itemImagePath: ''),
        KPlacement(itemName: 'P2', itemCode: '2', isPlaced: true, isPlacedFromDB: true, itemImagePath: ''),
        KPlacement(itemName: 'P3', itemCode: '3', isPlaced: false, isPlacedFromDB: false, itemImagePath: ''),
      ];
      final pairs = [PlacementPair(product1: 'P1', product2: 'P2')];

      // P1 and P2 form 1 pair target (placed), P3 forms 1 single target (unplaced).
      // Total targets = 2, placed targets = 1
      final summary = PlacementController.computeProgressFromPlacements(
        placements: placements,
        placementPairs: pairs,
      );
      expect(summary.totalTargets, equals(2));
      expect(summary.placedTargets, equals(1));
      expect(summary.isFinished, isFalse);
    });
  });
}
