import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/hapistore_service.dart';

/// Aggregated metrics and sorted store lists for the expansion tracking dashboard.
class ExpansionData {
  /// Stores opened within the current calendar month, sorted newest-first.
  final List<Hapistore> storesThisMonth;

  /// Stores opened within the past 3 months, sorted newest-first.
  final List<Hapistore> storesPastThreeMonths;

  /// Count of new store openings for the current month.
  final int totalExpansionThisMonth;

  /// Count of store openings over the past 3 months.
  final int totalExpansionPastThreeMonths;

  /// Ratio of monthly store openings relative to [monthlyTarget], clamped [0.0, 1.0].
  final double monthlyProgress;

  /// Whether current month's openings met or exceeded the target.
  final bool targetReached;

  /// Count of stores opened beyond the monthly target (0 if not exceeded).
  final int surplus;

  const ExpansionData({
    required this.storesThisMonth,
    required this.storesPastThreeMonths,
    required this.totalExpansionThisMonth,
    required this.totalExpansionPastThreeMonths,
    required this.monthlyProgress,
    required this.targetReached,
    required this.surplus,
  });
}

/// Controller responsible for managing business logic, metrics calculations,
/// and data queries for [ExpansionPage].
///
/// Keeps presentation decoupled from data fetching by delegating Firestore queries
/// to [HapiStoreService].
class ExpansionController {
  /// Default target quota of store expansions per month.
  static const int monthlyTarget = 8;

  /// Fetches new store expansions, sorts records by opening date,
  /// and calculates progress against the target.
  Future<ExpansionData> loadExpansionData({int target = monthlyTarget}) async {
    final listPastThreeMonths = await HapiStoreService.getListHapiStoresOpenedWithinPastThreeMonths();
    final listThisMonth = await HapiStoreService.getListHapiStoresWithOpeningDateInCurrentMonth();

    final sortedThisMonth = List<Hapistore>.from(listThisMonth)..sort(sortByOpeningDate);
    final sortedPastThreeMonths = List<Hapistore>.from(listPastThreeMonths)..sort(sortByOpeningDate);

    final totalThisMonth = sortedThisMonth.length;
    final totalPastThreeMonths = sortedPastThreeMonths.length;
    final progress = (totalThisMonth / target).clamp(0.0, 1.0).toDouble();
    final targetReached = totalThisMonth >= target;
    final surplus = totalThisMonth > target ? totalThisMonth - target : 0;

    return ExpansionData(
      storesThisMonth: sortedThisMonth,
      storesPastThreeMonths: sortedPastThreeMonths,
      totalExpansionThisMonth: totalThisMonth,
      totalExpansionPastThreeMonths: totalPastThreeMonths,
      monthlyProgress: progress,
      targetReached: targetReached,
      surplus: surplus,
    );
  }

  /// Sorts two [Hapistore] items by opening date in descending order (newest first).
  /// Falls back to alphabetical store name if both dates are null.
  int sortByOpeningDate(Hapistore first, Hapistore second) {
    final firstDate = first.openingDate?.toDate();
    final secondDate = second.openingDate?.toDate();
    if (firstDate == null && secondDate == null) {
      return first.storeName.compareTo(second.storeName);
    }
    if (firstDate == null) return 1;
    if (secondDate == null) return -1;
    return secondDate.compareTo(firstDate);
  }

  /// Filters a list of [Hapistore] items by matching store name or address
  /// against the provided [searchQuery].
  List<Hapistore> filterStores({
    required List<Hapistore> stores,
    required String searchQuery,
  }) {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return stores;

    return stores.where((s) {
      final nameMatches = s.storeName.toLowerCase().contains(query);
      final addressMatches = s.storeAddress.toLowerCase().contains(query);
      return nameMatches || addressMatches;
    }).toList();
  }
}
