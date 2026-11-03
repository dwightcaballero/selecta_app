import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/selecta_product.dart';

/// Represents a column in the Monthly Placement Report grid.
///
/// Corresponds to either a single Best Seller product or a merged pair of
/// products configured in [PlacementPair].
class PlacementReportColumn {
  final String key;
  final String label;
  final List<SelectaProduct> products;
  final String category;
  final double srpSortKey;

  const PlacementReportColumn({
    required this.key,
    required this.label,
    required this.products,
    required this.category,
    required this.srpSortKey,
  });

  bool get isPair => products.length > 1;

  SelectaProduct get primaryProduct => products.first;

  /// Returns true if this column contains a product with the given [productName].
  bool containsProductName(String productName) {
    final lower = productName.trim().toLowerCase();
    return products.any((p) => p.productName.trim().toLowerCase() == lower);
  }
}

/// Represents a single store row in a day's placement table.
class PlacementReportRow {
  final Hapistore store;
  final int sequenceNumber;
  final Map<String, bool> placed;
  final int placedCount;
  final int totalCount;
  final bool orderedNewProduct;

  const PlacementReportRow({
    required this.store,
    required this.sequenceNumber,
    required this.placed,
    required this.placedCount,
    required this.totalCount,
    required this.orderedNewProduct,
  });

  String get scoreText => '$placedCount/$totalCount';

  double get scorePercentage =>
      totalCount > 0 ? (placedCount / totalCount) * 100 : 0.0;
}

/// Section containing all rows and statistics for a specific PJP day.
class PlacementReportDaySection {
  final String day;
  final List<PlacementReportRow> rows;
  final Map<String, int> perColumnPlacedCount;
  final int totalStores;
  final int dayPlacedTargets;
  final int dayTotalTargets;
  final double dayPlacementPercentage;
  final int newProductOrderedCount;

  const PlacementReportDaySection({
    required this.day,
    required this.rows,
    required this.perColumnPlacedCount,
    required this.totalStores,
    required this.dayPlacedTargets,
    required this.dayTotalTargets,
    required this.dayPlacementPercentage,
    required this.newProductOrderedCount,
  });
}

/// Per-product coverage metric across all included stores.
class PlacementReportProductCoverage {
  final PlacementReportColumn column;
  final int placedStores;
  final int totalStores;
  final double coveragePercentage;

  const PlacementReportProductCoverage({
    required this.column,
    required this.placedStores,
    required this.totalStores,
    required this.coveragePercentage,
  });
}

/// A store entry in the Pitch List with missing Best Seller opportunities.
class PlacementReportPitchItem {
  final Hapistore store;
  final String day;
  final List<PlacementReportColumn> missingColumns;
  final List<PlacementReportColumn> nextToPitch;

  const PlacementReportPitchItem({
    required this.store,
    required this.day,
    required this.missingColumns,
    required this.nextToPitch,
  });
}

/// Overall cover/summary page statistics.
class PlacementReportSummary {
  final int totalScheduledStores;
  final int unscheduledStoresCount;
  final int totalStoresOverall;
  final int totalStoresInPickedDays;
  final int overallPlacedTargets;
  final int overallTotalTargets;
  final double overallPlacementPercentage;
  final int storesWithNewProduct;
  final List<PlacementReportProductCoverage> topProducts;
  final List<PlacementReportProductCoverage> bottomProducts;

  const PlacementReportSummary({
    required this.totalScheduledStores,
    required this.unscheduledStoresCount,
    required this.totalStoresOverall,
    required this.totalStoresInPickedDays,
    required this.overallPlacedTargets,
    required this.overallTotalTargets,
    required this.overallPlacementPercentage,
    required this.storesWithNewProduct,
    required this.topProducts,
    required this.bottomProducts,
  });
}

/// Consolidated data bundle for rendering the Monthly Placement Report PDF.
class PlacementReportData {
  final DateTime month;
  final String companyName;
  final List<String> selectedDays;
  final List<PlacementReportColumn> columns;
  final List<PlacementReportDaySection> sections;
  final PlacementReportSummary summary;
  final List<PlacementReportPitchItem> pitchList;
  final List<SelectaProduct> newProducts;
  final DateTime generatedDate;

  const PlacementReportData({
    required this.month,
    required this.companyName,
    required this.selectedDays,
    required this.columns,
    required this.sections,
    required this.summary,
    required this.pitchList,
    required this.newProducts,
    required this.generatedDate,
  });
}

