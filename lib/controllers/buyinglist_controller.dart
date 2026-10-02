import 'package:flutter/foundation.dart';
import 'package:selecta_ops/controllers/kpi_controller.dart';
import 'package:selecta_ops/dto/kpi_dto.dart';

/// Available sorting criteria for buying and non-buying store lists.
enum StoreSort {
  nameAscending,
  nameDescending,
  orderCountAscending,
  orderCountDescending,
  orderTotalAscending,
  orderTotalDescending,
}

/// Controller responsible for managing the state and business logic
/// of the [BuyinglistPage].
///
/// Implements [ChangeNotifier] to provide reactive state updates to the UI
/// layer while keeping presentation code completely decoupled from business
/// calculations, filtering, and backend service communication.
class BuyingListController extends ChangeNotifier {
  // ==========================================
  // State Variables
  // ==========================================

  /// Raw list of buying stores retrieved from the backend/services.
  List<KPIBuying> _listBuying = [];

  /// Raw list of non-buying stores retrieved from the backend/services.
  List<KPIBuying> _listNonBuying = [];

  /// Currently selected tab index:
  /// - 0: Buying stores
  /// - 1: Non-buying stores
  int _currentIndex = 0;

  /// Active sorting criterion for the store list.
  StoreSort _sort = StoreSort.nameAscending;

  /// Indicates if data is currently being fetched.
  bool _isLoading = true;

  /// Holds an error message if the fetch operation fails; null otherwise.
  String? _errorMessage;

  /// Current search text query for filtering stores by name.
  String _searchQuery = '';

  // ==========================================
  // Getters
  // ==========================================

  /// Whether data is in loading state.
  bool get isLoading => _isLoading;

  /// The error message, or null if no error has occurred.
  String? get errorMessage => _errorMessage;

  /// The index of the currently active bottom navigation tab.
  int get currentIndex => _currentIndex;

  /// Whether the currently active tab is "Buying Stores".
  bool get isBuyingTab => _currentIndex == 0;

  /// The current sort order.
  StoreSort get sort => _sort;

  /// The active search filter query.
  String get searchQuery => _searchQuery;

  /// Total count of buying stores.
  int get buyingStoreCount => _listBuying.length;

  /// Total count of non-buying stores.
  int get nonBuyingStoreCount => _listNonBuying.length;

  /// The raw store list for the currently active tab.
  List<KPIBuying> get currentRawStores => isBuyingTab ? _listBuying : _listNonBuying;

  /// Filtered and sorted stores ready for UI presentation.
  ///
  /// Filters the current list by [searchQuery] and applies the selected [sort].
  List<KPIBuying> get filteredAndSortedStores {
    final baseList = currentRawStores;
    final trimmedQuery = _searchQuery.trim().toLowerCase();

    // Step 1: Filter stores by search query (case-insensitive)
    final filtered = trimmedQuery.isEmpty
        ? baseList
        : baseList.where((store) => store.storeName.toLowerCase().contains(trimmedQuery)).toList();

    // Step 2: Sort stores according to current sort selection
    final sorted = List<KPIBuying>.of(filtered)..sort(_compareStores);
    return sorted;
  }

  /// Calculates the total delivered sales amount for the currently displayed stores.
  double get totalSales {
    return filteredAndSortedStores.fold<double>(
      0.0,
      (runningTotal, store) => runningTotal + store.deliveredAmount,
    );
  }

  // ==========================================
  // Business Logic & State Mutations
  // ==========================================

  /// Fetches buying and non-buying store data from the service layer via [KPIController].
  ///
  /// Handles loading and error states and notifies UI listeners.
  Future<void> prefetchData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final (buying, nonBuying) = await KPIController.getListOfBuyingAndNonBuyingStores();
      _listBuying = buying;
      _listNonBuying = nonBuying;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load store data: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Updates the active tab index and resets the search query.
  void setTabIndex(int index) {
    if (_currentIndex == index) return;
    _currentIndex = index;
    _searchQuery = '';
    notifyListeners();
  }

  /// Updates the search filter query and triggers a UI rebuild.
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Clears the active search query.
  void clearSearch() {
    if (_searchQuery.isEmpty) return;
    _searchQuery = '';
    notifyListeners();
  }

  /// Updates the sort criteria and triggers a UI rebuild.
  void setSort(StoreSort newSort) {
    if (_sort == newSort) return;
    _sort = newSort;
    notifyListeners();
  }

  /// Comparator logic that sorts two [KPIBuying] items according to the active [_sort].
  int _compareStores(KPIBuying first, KPIBuying second) {
    final comparison = switch (_sort) {
      StoreSort.nameAscending || StoreSort.nameDescending =>
        first.storeName.toLowerCase().compareTo(second.storeName.toLowerCase()),
      StoreSort.orderCountAscending || StoreSort.orderCountDescending =>
        first.orderCount.compareTo(second.orderCount),
      StoreSort.orderTotalAscending || StoreSort.orderTotalDescending =>
        first.deliveredAmount.compareTo(second.deliveredAmount),
    };

    return switch (_sort) {
      StoreSort.nameDescending ||
      StoreSort.orderCountDescending ||
      StoreSort.orderTotalDescending =>
        -comparison,
      _ => comparison,
    };
  }
}
