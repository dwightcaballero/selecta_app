import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/data.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/placement.dart';
import 'package:flutter_app/services/placement_service.dart';
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

  PlacementController({PlacementService? placementService})
      : _placementService = placementService ?? PlacementService();

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

  /// Persists newly placed items to Firestore via [PlacementService] and logs an audit transaction.
  ///
  /// Returns the updated [Placement] entity.
  Future<Placement> savePlacementProgress({
    required Placement currentPlacement,
    required List<KPlacement> placements,
  }) async {
    final placedCount = placements.where((p) => p.isPlaced).length;
    final isFinished = placements.isNotEmpty && placedCount == placements.length;

    bool getFlag(String code) =>
        placements.where((p) => p.itemCode == code).firstOrNull?.isPlaced ?? false;

    final updated = currentPlacement.copyWith(
      deliveryDate: Timestamp.now(),
      cotc1: getFlag('cotc1'),
      cotc2: getFlag('cotc2'),
      cotc3: getFlag('cotc3'),
      cotc4: getFlag('cotc4'),
      cotc5: getFlag('cotc5'),
      cotc6: getFlag('cotc6'),
      cotc7: getFlag('cotc7'),
      cotc8: getFlag('cotc8'),
      cotc9: getFlag('cotc9'),
      cotc10: getFlag('cotc10'),
      cotc11: getFlag('cotc11'),
      cotc12: getFlag('cotc12'),
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
