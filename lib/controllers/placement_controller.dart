import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/data.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/placement.dart';
import 'package:selecta_ops/services/placement_service.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:intl/intl.dart';

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
  // List Operations (PlacementlistPage)
  // ==========================================

  /// Loads all placement records across all active stores.
  Future<List<Placement>> loadAllPlacements() async {
    return await PlacementService.getListPlacementForAllStores();
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

    return bestSellers.map((prod) {
      final isPlaced = placedLowerNames.contains(prod.productName.trim().toLowerCase());
      return KPlacement(
        itemName: prod.productName,
        itemCode: prod.id,
        isPlaced: isPlaced,
        isPlacedFromDB: isPlaced,
        itemImagePath: prod.imageUrl.isNotEmpty ? prod.imageUrl : 'assets/images/placement/watermelon.png',
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
    final placedItems = placements.where((p) => p.isPlaced).toList();
    final placedCount = placedItems.length;
    final isFinished = placements.isNotEmpty && placedCount == placements.length;
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
      isFinished: isFinished,
      progressCount: placedCount,
    );

    await _placementService.savePlacement(updated);

    final currentMonthLabel = DateFormat('MMMM yyyy').format(DateTime.now());
    await Helperfunctions.logTransaction(
      'Placement Update - ${updated.storeName}',
      'Placed $placedCount of ${placements.length} products for $currentMonthLabel.',
      LogAction.update,
      page: AppPages.placement,
    );

    return updated;
  }
}
