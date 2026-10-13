import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/data.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/placement.dart';
import 'package:selecta_ops/models/placement_pair.dart';
import 'package:selecta_ops/services/placement_service.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:intl/intl.dart';

/// Summary representing placement targets and fulfillment,
/// where paired products count as ONE target if either product in the pair is placed.
class PlacementProgressSummary {
  final int totalTargets;
  final int placedTargets;
  final bool isFinished;

  const PlacementProgressSummary({
    required this.totalTargets,
    required this.placedTargets,
    required this.isFinished,
  });

  double get progressRatio => totalTargets > 0 ? (placedTargets / totalTargets).clamp(0.0, 1.0) : 0.0;
  int get progressPercent => (progressRatio * 100).round();
}

/// Available sorting options for the placement checklist overview.
enum PlacementSort {
  storeNameAscending,
  storeNameDescending,
  progressCountAscending,
  progressCountDescending,
}

/// Controller responsible for managing store product placement checklists,
/// sorting, search filtering, and persistence for [PlacementlistPage] and [PlacementPage].
///
/// Ensures all direct database queries are delegated to [PlacementService].
class PlacementController {
  final PlacementService _placementService;
  final SelectaProductService _selectaProductService;

  PlacementController({
    PlacementService? placementService,
    SelectaProductService? selectaProductService,
  })  : _placementService = placementService ?? PlacementService(),
        _selectaProductService = selectaProductService ?? SelectaProductService();

  // ==========================================
  // Placement Target Grouping & Progress Math
  // ==========================================

  /// Computes placement progress where paired products count as ONE target
  /// as long as either of the pair is placed.
  static PlacementProgressSummary computeProgress({
    required Iterable<String> allProductNames,
    required Iterable<String> placedProductNames,
    required List<PlacementPair> placementPairs,
  }) {
    final allList = allProductNames.map((n) => n.trim()).where((n) => n.isNotEmpty).toSet().toList();
    if (allList.isEmpty) {
      return const PlacementProgressSummary(totalTargets: 0, placedTargets: 0, isFinished: false);
    }

    final placedLower = placedProductNames.map((n) => n.trim().toLowerCase()).toSet();

    // Group products into target slots.
    // Each pair whose products intersect allList forms 1 target slot.
    final visited = <String>{};
    final groups = <Set<String>>[];

    for (final pair in placementPairs) {
      final p1Lower = pair.product1.trim().toLowerCase();
      final p2Lower = pair.product2.trim().toLowerCase();

      final inAll1 = allList.where((p) => p.toLowerCase() == p1Lower).toList();
      final inAll2 = allList.where((p) => p.toLowerCase() == p2Lower).toList();

      if (inAll1.isNotEmpty || inAll2.isNotEmpty) {
        final group = <String>{};
        if (inAll1.isNotEmpty) {
          group.add(inAll1.first);
          visited.add(p1Lower);
        }
        if (inAll2.isNotEmpty) {
          group.add(inAll2.first);
          visited.add(p2Lower);
        }
        if (group.isNotEmpty) {
          groups.add(group);
        }
      }
    }

    // Unpaired products: each forms its own target slot
    for (final prod in allList) {
      if (!visited.contains(prod.toLowerCase())) {
        groups.add({prod});
        visited.add(prod.toLowerCase());
      }
    }

    final totalTargets = groups.length;
    int placedTargets = 0;
    for (final group in groups) {
      final isGroupPlaced = group.any((p) => placedLower.contains(p.toLowerCase()));
      if (isGroupPlaced) {
        placedTargets++;
      }
    }

    final isFinished = totalTargets > 0 && placedTargets >= totalTargets;

    return PlacementProgressSummary(
      totalTargets: totalTargets,
      placedTargets: placedTargets,
      isFinished: isFinished,
    );
  }

  /// Computes placement progress directly from a hydrated [KPlacement] checklist.
  static PlacementProgressSummary computeProgressFromPlacements({
    required List<KPlacement> placements,
    required List<PlacementPair> placementPairs,
  }) {
    return computeProgress(
      allProductNames: placements.map((p) => p.itemName),
      placedProductNames: placements.where((p) => p.isPlaced).map((p) => p.itemName),
      placementPairs: placementPairs,
    );
  }

  /// Returns the total unique placement targets after accounting for active pairs.
  Future<int> getTotalTargetCount() async {
    final bestSellers = await _selectaProductService.getBestSellerProducts();
    final allNames = bestSellers.isNotEmpty
        ? bestSellers.map((p) => p.productName).toList()
        : KData.getListPlacement().map((p) => p.itemName).toList();
    final config = await ConfigurationService().getConfiguration();
    final summary = computeProgress(
      allProductNames: allNames,
      placedProductNames: const [],
      placementPairs: config.placementPairs,
    );
    return summary.totalTargets > 0 ? summary.totalTargets : 12;
  }

  // ==========================================
  // List Operations (PlacementlistPage)
  // ==========================================

  /// Loads all placement records across all active stores, normalized with any active SKU pairs.
  /// Paired products count as ONE target as long as either of the pair is placed.
  Future<List<Placement>> loadAllPlacements() async {
    final placements = await PlacementService.getListPlacementForAllStores();
    final config = await ConfigurationService().getConfiguration();
    final bestSellers = await _selectaProductService.getBestSellerProducts();
    final allNames = bestSellers.isNotEmpty
        ? bestSellers.map((p) => p.productName).toList()
        : KData.getListPlacement().map((p) => p.itemName).toList();

    for (final p in placements) {
      final names = p.placedProductNames.map((n) => n.trim().toLowerCase()).toSet();
      for (final pair in config.placementPairs) {
        final p1 = pair.product1.trim().toLowerCase();
        final p2 = pair.product2.trim().toLowerCase();
        if (names.contains(p1) && !names.contains(p2)) {
          names.add(p2);
          p.placedProductNames.add(pair.product2);
        } else if (names.contains(p2) && !names.contains(p1)) {
          names.add(p1);
          p.placedProductNames.add(pair.product1);
        }
      }

      // Compute progress count where paired products count as one
      final summary = computeProgress(
        allProductNames: allNames,
        placedProductNames: p.placedProductNames,
        placementPairs: config.placementPairs,
      );
      p.progressCount = summary.placedTargets;
      p.isFinished = summary.isFinished;
    }

    return placements;
  }

  /// Filters placement records by completion status and search query, then sorts them.
  List<Placement> filterAndSortPlacements({
    required List<Placement> placements,
    required bool isFinished,
    required String searchQuery,
    required PlacementSort sort,
  }) {
    final query = searchQuery.trim().toLowerCase();

    final filtered = placements.where((p) {
      final matchesStatus = p.isFinished == isFinished;
      final matchesSearch = query.isEmpty || p.storeName.toLowerCase().contains(query);
      return matchesStatus && matchesSearch;
    }).toList();

    filtered.sort((first, second) => comparePlacements(first, second, sort));
    return filtered;
  }

  /// Comparator logic to order two [Placement] records according to [PlacementSort].
  int comparePlacements(Placement first, Placement second, PlacementSort sort) {
    final comparison = switch (sort) {
      PlacementSort.storeNameAscending ||
      PlacementSort.storeNameDescending =>
        first.storeName.toLowerCase().compareTo(second.storeName.toLowerCase()),
      PlacementSort.progressCountAscending ||
      PlacementSort.progressCountDescending =>
        first.progressCount.compareTo(second.progressCount),
    };

    return switch (sort) {
      PlacementSort.storeNameDescending ||
      PlacementSort.progressCountDescending =>
        -comparison,
      _ => comparison,
    };
  }

  // ==========================================
  // Detail & Checklist Operations (PlacementPage)
  // ==========================================

  /// Resolves the placement record for the current month.
  /// If the record belongs to an older month or is empty, creates a fresh template.
  Placement resolveInitialPlacement(Placement placement) {
    final now = DateTime.now();
    final placementDate = placement.deliveryDate.toDate();
    final isSameMonth = placementDate.year == now.year && placementDate.month == now.month;

    if (isSameMonth && placement.id.isNotEmpty) {
      return placement;
    }
    return Placement.empty().copyWith(
      storeName: placement.storeName,
      deliveryDate: Timestamp.now(),
    );
  }

  /// Queries for an existing placement record for the specified store in the current calendar month.
  Future<Placement?> getExistingPlacementForCurrentMonth(String storeName) async {
    if (storeName.isEmpty) return null;
    return await _placementService.getPlacementByStoreAndDate(storeName, DateTime.now());
  }

  /// Hydrates a fresh checklist of products with the placed status from [placement].
  List<KPlacement> mapPlacementFlags(Placement placement) {
    final list = KData.getListPlacement();
    final flags = {
      'cotc1': placement.cotc1,
      'cotc2': placement.cotc2,
      'cotc3': placement.cotc3,
      'cotc4': placement.cotc4,
      'cotc5': placement.cotc5,
      'cotc6': placement.cotc6,
      'cotc7': placement.cotc7,
      'cotc8': placement.cotc8,
      'cotc9': placement.cotc9,
      'cotc10': placement.cotc10,
      'cotc11': placement.cotc11,
      'cotc12': placement.cotc12,
    };

    for (final item in list) {
      final isPlaced = flags[item.itemCode] ?? false;
      item.isPlaced = isPlaced;
      item.isPlacedFromDB = isPlaced;
    }

    return list;
  }

  /// Hydrates a checklist of products based on products tagged as "Best Seller".
  /// Falls back to legacy [KData.getListPlacement()] if no products are tagged as Best Seller yet.
  Future<List<KPlacement>> loadBestSellerPlacements({required Placement placement}) async {
    final bestSellers = await _selectaProductService.getBestSellerProducts();

    if (bestSellers.isEmpty) {
      return mapPlacementFlags(placement);
    }

    final placedLowerNames = placement.placedProductNames.map((n) => n.trim().toLowerCase()).toSet();

    // Also consider legacy cotc flags for backward compatibility
    final legacyList = KData.getListPlacement();
    final flags = {
      'cotc1': placement.cotc1,
      'cotc2': placement.cotc2,
      'cotc3': placement.cotc3,
      'cotc4': placement.cotc4,
      'cotc5': placement.cotc5,
      'cotc6': placement.cotc6,
      'cotc7': placement.cotc7,
      'cotc8': placement.cotc8,
      'cotc9': placement.cotc9,
      'cotc10': placement.cotc10,
      'cotc11': placement.cotc11,
      'cotc12': placement.cotc12,
    };
    for (final legacyItem in legacyList) {
      if (flags[legacyItem.itemCode] == true) {
        placedLowerNames.add(legacyItem.itemName.trim().toLowerCase());
      }
    }

    final config = await ConfigurationService().getConfiguration();
    // Expand with active placement pairs (if either is placed, both are placed)
    for (final pair in config.placementPairs) {
      final p1 = pair.product1.trim().toLowerCase();
      final p2 = pair.product2.trim().toLowerCase();
      if (placedLowerNames.contains(p1)) {
        placedLowerNames.add(p2);
      }
      if (placedLowerNames.contains(p2)) {
        placedLowerNames.add(p1);
      }
    }

    return bestSellers.map((prod) {
      final isPlaced = placedLowerNames.contains(prod.productName.trim().toLowerCase());
      String? pairedWith;
      for (final pair in config.placementPairs) {
        if (pair.matches(prod.productName)) {
          pairedWith = pair.getOther(prod.productName);
          break;
        }
      }
      return KPlacement(
        itemName: prod.productName,
        itemCode: prod.id,
        isPlaced: isPlaced,
        isPlacedFromDB: isPlaced,
        itemImagePath: prod.imageUrl.isNotEmpty ? prod.imageUrl : 'assets/images/placement/watermelon.png',
        pairedProductName: pairedWith,
      );
    }).toList();
  }

  /// Persists newly placed items to Firestore via [PlacementService] and logs an audit transaction.
  ///
  /// Returns the updated [Placement] entity.
  Future<Placement> savePlacementProgress({
    required Placement currentPlacement,
    required List<KPlacement> placements,
  }) async {
    final config = await ConfigurationService().getConfiguration();
    final summary = computeProgressFromPlacements(
      placements: placements,
      placementPairs: config.placementPairs,
    );
    final placedItems = placements.where((p) => p.isPlaced).toList();
    final placedNames = placedItems.map((p) => p.itemName).toList();

    // Map to legacy cotc flags if any matching names exist
    final legacyList = KData.getListPlacement();
    final legacyMap = <String, bool>{};
    for (int i = 0; i < legacyList.length; i++) {
      final code = 'cotc${i + 1}';
      final match = placedItems.any((p) => p.itemName.trim().toLowerCase() == legacyList[i].itemName.trim().toLowerCase());
      legacyMap[code] = match;
    }

    final updated = currentPlacement.copyWith(
      deliveryDate: Timestamp.now(),
      placedProductNames: placedNames,
      cotc1: legacyMap['cotc1'] ?? false,
      cotc2: legacyMap['cotc2'] ?? false,
      cotc3: legacyMap['cotc3'] ?? false,
      cotc4: legacyMap['cotc4'] ?? false,
      cotc5: legacyMap['cotc5'] ?? false,
      cotc6: legacyMap['cotc6'] ?? false,
      cotc7: legacyMap['cotc7'] ?? false,
      cotc8: legacyMap['cotc8'] ?? false,
      cotc9: legacyMap['cotc9'] ?? false,
      cotc10: legacyMap['cotc10'] ?? false,
      cotc11: legacyMap['cotc11'] ?? false,
      cotc12: legacyMap['cotc12'] ?? false,
      isFinished: summary.isFinished,
      progressCount: summary.placedTargets,
    );

    await _placementService.savePlacement(updated);

    final currentMonthLabel = DateFormat('MMMM yyyy').format(DateTime.now());
    await Helperfunctions.logTransaction(
      'Placement Update - ${updated.storeName}',
      'Placed ${summary.placedTargets} of ${summary.totalTargets} targets for $currentMonthLabel.',
      LogAction.update,
      page: AppPages.placement,
    );

    return updated;
  }
}
