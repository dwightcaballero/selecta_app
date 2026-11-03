import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/data.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/placement.dart';
import 'package:selecta_ops/models/placement_pair.dart';
import 'package:selecta_ops/models/placement_report_models.dart';
import 'package:selecta_ops/models/selecta_product.dart';

/// Pure aggregation and builder functions for the Monthly Placement Report.
class PlacementReportBuilder {
  /// Compares two [SelectaProduct]s using the fixed report order (Rule 8a):
  /// 1. "By Case" first (rank 0), then "By Piece" (rank 1), other categories (rank 2).
  /// 2. Extracted SRP ascending (fallback to selling price).
  /// 3. Alphabetical by name.
  static int compareReportProducts(SelectaProduct a, SelectaProduct b) {
    final catComp = Helperfunctions.compareCategoryHierarchy(a.category, b.category);
    if (catComp != 0) return catComp;

    return Helperfunctions.compareBySrpAndName(
      nameA: a.productName,
      priceA: a.sellingPrice,
      nameB: b.productName,
      priceB: b.sellingPrice,
    );
  }

  /// Builds and sorts report columns from [bestSellers] and configured [pairs].
  ///
  /// - Paired products that both exist in [bestSellers] are merged into one column.
  /// - The pair column is sorted at the position of its FIRST member (using [compareReportProducts]),
  ///   its category is that member's category, and its label is "Product A / Product B".
  /// - Unpaired products form their own single column.
  /// - Product columns are sorted By Case (SRP asc) -> By Piece (SRP asc) -> name.
  static List<PlacementReportColumn> buildColumns({
    required List<SelectaProduct> bestSellers,
    required List<PlacementPair> pairs,
  }) {
    if (bestSellers.isEmpty) return const [];

    final handledIds = <String>{};
    final columns = <PlacementReportColumn>[];

    // 1. Group active pairs
    for (final pair in pairs) {
      final p1 = bestSellers.where((p) => p.productName.trim().toLowerCase() == pair.product1.trim().toLowerCase()).firstOrNull;
      final p2 = bestSellers.where((p) => p.productName.trim().toLowerCase() == pair.product2.trim().toLowerCase()).firstOrNull;

      if (p1 != null && p2 != null && p1.id != p2.id) {
        if (handledIds.contains(p1.id) || handledIds.contains(p2.id)) continue;

        // Sort the two members using the fixed comparator
        final pairProducts = [p1, p2]..sort(compareReportProducts);
        final first = pairProducts[0];
        final second = pairProducts[1];

        final srp = Helperfunctions.extractSrp(first.productName) ?? first.sellingPrice;
        columns.add(
          PlacementReportColumn(
            key: '${first.id}_${second.id}',
            label: '${first.productName} / ${second.productName}',
            products: pairProducts,
            category: first.category,
            srpSortKey: srp,
          ),
        );
        handledIds.add(p1.id);
        handledIds.add(p2.id);
      }
    }

    // 2. Unpaired best sellers
    for (final prod in bestSellers) {
      if (handledIds.contains(prod.id)) continue;

      final srp = Helperfunctions.extractSrp(prod.productName) ?? prod.sellingPrice;
      columns.add(
        PlacementReportColumn(
          key: prod.id,
          label: prod.productName,
          products: [prod],
          category: prod.category,
          srpSortKey: srp,
        ),
      );
      handledIds.add(prod.id);
    }

    // 3. Sort columns by their primary (lead) product
    columns.sort((colA, colB) {
      final comp = compareReportProducts(colA.primaryProduct, colB.primaryProduct);
      if (comp != 0) return comp;
      return colA.label.toLowerCase().compareTo(colB.label.toLowerCase());
    });

    return columns;
  }

  /// Sorts stores for a single PJP day:
  /// - pjpSequence ascending
  /// - null sequence last, sorted alphabetically by storeName
  static List<Hapistore> sortStoresForDay(List<Hapistore> stores) {
    final sorted = List<Hapistore>.from(stores);
    sorted.sort(Helperfunctions.compareStoresByPjpSequence);
    return sorted;
  }

  /// Identifies store names that have ordered at least one "New Product" item
  /// on a DELIVERED order in the given month.
  ///
  /// Criteria (Rule 2 & 12):
  /// - transactionStatus == Delivered
  /// - item.tag is "New Product" (or resolved from [productTagsById] if item.tag is empty)
  /// - item.isFreeReward == false
  /// - net delivered quantity (pickedQuantity - returnedQuantity) > 0
  static Set<String> findStoresWithNewProductOrders({
    required List<Delivery> deliveries,
    Map<String, String>? productTagsById,
  }) {
    final storesWithNewProduct = <String>{};

    for (final delivery in deliveries) {
      if (delivery.transactionStatus != DeliveryStatus.delivered) continue;

      for (final item in delivery.items) {
        if (item.isFreeReward) continue;

        final netQty = item.pickedQuantity - item.returnedQuantity;
        if (netQty <= 0) continue;

        var tag = item.tag;
        if ((tag.isEmpty || tag == ProductTag.none) && productTagsById != null) {
          tag = productTagsById[item.productId] ?? '';
        }

        if (ProductTag.isNewProduct(tag)) {
          storesWithNewProduct.add(delivery.storeName);
          break; // Store qualified; proceed to next delivery
        }
      }
    }

    return storesWithNewProduct;
  }

  /// Builds row models for all stores in a day.
  static List<PlacementReportRow> buildRows({
    required List<Hapistore> stores,
    required List<PlacementReportColumn> columns,
    required Map<String, Placement> placementsByStore,
    required List<PlacementPair> pairs,
    required Set<String> storesWithNewProduct,
  }) {
    final legacyList = KData.getListPlacement();
    final rows = <PlacementReportRow>[];

    for (int i = 0; i < stores.length; i++) {
      final store = stores[i];
      final placement = placementsByStore[store.storeName];
      final placedLowerNames = <String>{};

      if (placement != null) {
        // 1. Placed product names recorded on the document
        for (final name in placement.placedProductNames) {
          if (name.trim().isNotEmpty) {
            placedLowerNames.add(name.trim().toLowerCase());
          }
        }

        // 2. Backward compatibility with legacy cotc1..12 flags
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

        // 3. Expand with active placement pairs (if either is placed, both are placed)
        for (final pair in pairs) {
          final p1 = pair.product1.trim().toLowerCase();
          final p2 = pair.product2.trim().toLowerCase();
          if (placedLowerNames.contains(p1)) placedLowerNames.add(p2);
          if (placedLowerNames.contains(p2)) placedLowerNames.add(p1);
        }
      }

      // Check each column
      final placedMap = <String, bool>{};
      int placedCount = 0;

      for (final col in columns) {
        final isPlaced = col.products.any(
          (prod) => placedLowerNames.contains(prod.productName.trim().toLowerCase()),
        );
        placedMap[col.key] = isPlaced;
        if (isPlaced) placedCount++;
      }

      final orderedNewProduct = storesWithNewProduct.contains(store.storeName);

      rows.add(
        PlacementReportRow(
          store: store,
          sequenceNumber: i + 1,
          placed: placedMap,
          placedCount: placedCount,
          totalCount: columns.length,
          orderedNewProduct: orderedNewProduct,
        ),
      );
    }

    return rows;
  }

  /// Builds a [PlacementReportDaySection] from rows and columns.
  static PlacementReportDaySection buildDaySection({
    required String day,
    required List<PlacementReportRow> rows,
    required List<PlacementReportColumn> columns,
  }) {
    final perColumnPlacedCount = <String, int>{};
    for (final col in columns) {
      perColumnPlacedCount[col.key] = rows.where((r) => r.placed[col.key] == true).length;
    }

    final totalStores = rows.length;
    final dayPlacedTargets = rows.fold<int>(0, (sum, r) => sum + r.placedCount);
    final dayTotalTargets = rows.fold<int>(0, (sum, r) => sum + r.totalCount);
    final dayPlacementPercentage =
        dayTotalTargets > 0 ? (dayPlacedTargets / dayTotalTargets) * 100 : 0.0;
    final newProductOrderedCount = rows.where((r) => r.orderedNewProduct).length;

    return PlacementReportDaySection(
      day: day,
      rows: rows,
      perColumnPlacedCount: perColumnPlacedCount,
      totalStores: totalStores,
      dayPlacedTargets: dayPlacedTargets,
      dayTotalTargets: dayTotalTargets,
      dayPlacementPercentage: dayPlacementPercentage,
      newProductOrderedCount: newProductOrderedCount,
    );
  }

  /// Computes summary metrics across all picked day sections.
  static PlacementReportSummary buildSummary({
    required List<PlacementReportDaySection> sections,
    required List<PlacementReportColumn> columns,
    required int totalStoresOverall,
    required int totalScheduledStores,
    required int unscheduledStoresCount,
  }) {
    final allRows = sections.expand((s) => s.rows).toList();
    final totalStoresInPickedDays = allRows.length;
    final overallPlacedTargets = allRows.fold<int>(0, (sum, r) => sum + r.placedCount);
    final overallTotalTargets = allRows.fold<int>(0, (sum, r) => sum + r.totalCount);
    final overallPlacementPercentage =
        overallTotalTargets > 0 ? (overallPlacedTargets / overallTotalTargets) * 100 : 0.0;
    final storesWithNewProduct = allRows.where((r) => r.orderedNewProduct).length;

    // Per-column coverage
    final coverages = columns.map((col) {
      final placedStores = allRows.where((r) => r.placed[col.key] == true).length;
      final pct = totalStoresInPickedDays > 0 ? (placedStores / totalStoresInPickedDays) * 100 : 0.0;
      return PlacementReportProductCoverage(
        column: col,
        placedStores: placedStores,
        totalStores: totalStoresInPickedDays,
        coveragePercentage: pct,
      );
    }).toList();

    // Sort by coverage descending (ties broken by SRP asc then name)
    final sortedByCoverageDesc = List<PlacementReportProductCoverage>.from(coverages)
      ..sort((a, b) {
        final pctComp = b.coveragePercentage.compareTo(a.coveragePercentage);
        if (pctComp != 0) return pctComp;
        return compareReportProducts(a.column.primaryProduct, b.column.primaryProduct);
      });

    final topProducts = sortedByCoverageDesc.take(3).toList();

    // Sort by coverage ascending for bottom products
    final sortedByCoverageAsc = List<PlacementReportProductCoverage>.from(coverages)
      ..sort((a, b) {
        final pctComp = a.coveragePercentage.compareTo(b.coveragePercentage);
        if (pctComp != 0) return pctComp;
        return compareReportProducts(a.column.primaryProduct, b.column.primaryProduct);
      });

    final bottomProducts = sortedByCoverageAsc.take(3).toList();

    return PlacementReportSummary(
      totalScheduledStores: totalScheduledStores,
      unscheduledStoresCount: unscheduledStoresCount,
      totalStoresOverall: totalStoresOverall,
      totalStoresInPickedDays: totalStoresInPickedDays,
      overallPlacedTargets: overallPlacedTargets,
      overallTotalTargets: overallTotalTargets,
      overallPlacementPercentage: overallPlacementPercentage,
      storesWithNewProduct: storesWithNewProduct,
      topProducts: topProducts,
      bottomProducts: bottomProducts,
    );
  }

  /// Builds the Pitch List items (missing products per store) grouped by day.
  static List<PlacementReportPitchItem> buildPitchList({
    required List<PlacementReportDaySection> sections,
    required List<PlacementReportColumn> columns,
  }) {
    final pitchList = <PlacementReportPitchItem>[];

    for (final section in sections) {
      for (final row in section.rows) {
        final missing = columns.where((col) => row.placed[col.key] != true).toList();
        final nextToPitch = missing.take(3).toList();

        pitchList.add(
          PlacementReportPitchItem(
            store: row.store,
            day: section.day,
            missingColumns: missing,
            nextToPitch: nextToPitch,
          ),
        );
      }
    }

    return pitchList;
  }
}
