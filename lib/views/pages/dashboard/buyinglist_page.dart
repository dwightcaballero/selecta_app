import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/buyinglist_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/dto/kpi_dto.dart';
import 'package:selecta_ops/views/pages/sidebar/transactionlist_page.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';

/// Presentation view for the KPI Buying and Non-Buying store breakdown.
///
/// This widget focuses purely on the UI layer. All business logic, filtering,
/// sorting, aggregation, and data-fetching orchestration are handled by
/// [BuyingListController], while backend/Firebase queries reside in the services layer.
class BuyinglistPage extends StatefulWidget {
  final bool showAppBar;
  const BuyinglistPage({super.key, this.showAppBar = true});

  @override
  State<BuyinglistPage> createState() => _BuyinglistPageState();
}

class _BuyinglistPageState extends State<BuyinglistPage> {
  /// Controller managing presentation state and business logic.
  late final BuyingListController _controller;

  /// Text controller for the search input field.
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = BuyingListController();
    // Initiate initial data retrieval from the controller/services
    _controller.prefetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ==========================================
  // UI Building Blocks
  // ==========================================

  /// Builds the top summary banner showing total store count and cumulative sales
  /// for buying stores, or an alert badge for non-buying stores.
  Widget _buildSummaryBanner({
    required int storeCount,
    required double totalSales,
    required Color statusColor,
    required String label,
    required bool isBuying,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          // Status icon indicator
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(isBuying ? Icons.insights_outlined : Icons.warning_amber_rounded, color: statusColor, size: 20),
          ),
          const SizedBox(width: 12),

          // Label and store count
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  '$storeCount ${storeCount == 1 ? 'store' : 'stores'}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // Total sales indicator for buying stores, or zero-order badge for non-buying
          if (isBuying)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Total Sales', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(
                  Helperfunctions.formatDoubleAmountForDisplay(totalSales),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: statusColor),
                ),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: Text(
                'Zero Orders',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
              ),
            ),
        ],
      ),
    );
  }

  /// Builds a clickable card representing an individual store and its purchase metrics.
  Widget _buildStoreCard({required KPIBuying store, required Color statusColor, required bool isBuying}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Helperfunctions.navigateTo(context, TransactionListPage(storeName: store.storeName)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Store leading icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(isBuying ? Icons.storefront_outlined : Icons.remove_shopping_cart_outlined, color: statusColor, size: 20),
              ),
              const SizedBox(width: 12),

              // Store name and monthly order count
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isBuying ? '${store.orderCount} orders this month' : 'No purchases this month',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Delivered amount or history indicator
              if (isBuying)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Helperfunctions.formatDoubleAmountForDisplay(store.deliveredAmount),
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: statusColor),
                    ),
                    const SizedBox(height: 2),
                    Icon(Icons.chevron_right, size: 16, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  ],
                )
              else
                Row(
                  children: [
                    Text(
                      'View history',
                      style: TextStyle(fontSize: 11, color: colorScheme.primary, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right, size: 16, color: colorScheme.primary),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the search input field connected to the controller.
  Widget _buildSearchBar({required ColorScheme colorScheme, required bool isBuying}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search ${isBuying ? 'buying' : 'non-buying'} stores...',
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _controller.searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _controller.clearSearch();
                  },
                )
              : null,
          isDense: true,
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
        onChanged: _controller.setSearchQuery,
      ),
    );
  }

  /// Builds the scrollable list of stores with pull-to-refresh support.
  Widget _buildScreenList({required List<KPIBuying> stores, required bool isBuying}) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = isBuying ? colorScheme.primary : colorScheme.error;
    final hasNoStores = stores.isEmpty;

    return RefreshIndicator(
      onRefresh: _controller.prefetchData,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        // Search bar (index 0) + Banner (index 1) + stores (or empty state card)
        itemCount: hasNoStores ? 3 : stores.length + 2,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          // Index 0: Search input
          if (index == 0) {
            return _buildSearchBar(colorScheme: colorScheme, isBuying: isBuying);
          }

          // Index 1: Summary banner
          if (index == 1) {
            return _buildSummaryBanner(
              storeCount: stores.length,
              totalSales: _controller.totalSales,
              statusColor: statusColor,
              label: isBuying ? 'Active Buying Stores' : 'Stores Requiring Attention',
              isBuying: isBuying,
            );
          }

          // Index 2 (when empty): Empty results message
          if (hasNoStores) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _controller.searchQuery.isNotEmpty
                      ? 'No stores match "${_controller.searchQuery}"'
                      : 'No ${isBuying ? 'buying' : 'non-buying'} stores found.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
            );
          }

          // Index 2+: Store cards
          final store = stores[index - 2];
          return _buildStoreCard(store: store, statusColor: statusColor, isBuying: isBuying);
        },
      ),
    );
  }

  /// Builds the sort options popup menu.
  Widget _buildSortMenu({required bool isBuying}) {
    return PopupMenuButton<StoreSort>(
      icon: const Icon(Icons.sort_rounded, color: Colors.white),
      tooltip: 'Sort stores',
      onSelected: _controller.setSort,
      itemBuilder: (context) => [
        _buildSortOption(StoreSort.nameAscending, 'Store Name (A-Z)', Icons.arrow_upward),
        _buildSortOption(StoreSort.nameDescending, 'Store Name (Z-A)', Icons.arrow_downward),
        if (isBuying) ...[
          const PopupMenuDivider(),
          _buildSortOption(StoreSort.orderCountDescending, 'Highest Order Count', Icons.arrow_downward),
          _buildSortOption(StoreSort.orderCountAscending, 'Lowest Order Count', Icons.arrow_upward),
          _buildSortOption(StoreSort.orderTotalDescending, 'Highest Sales Total', Icons.arrow_downward),
          _buildSortOption(StoreSort.orderTotalAscending, 'Lowest Sales Total', Icons.arrow_upward),
        ],
      ],
    );
  }

  /// Builds an individual sort menu item with a checkmark for the active sort.
  PopupMenuItem<StoreSort> _buildSortOption(StoreSort sort, String label, IconData icon) {
    return PopupMenuItem(
      value: sort,
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          if (_controller.sort == sort) const Icon(Icons.check_rounded, size: 18),
        ],
      ),
    );
  }

  /// Builds the error state widget with a retry button.
  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 8),
          Text(message),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(onPressed: _controller.prefetchData, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final isBuying = _controller.isBuyingTab;

        return Scaffold(
          appBar: widget.showAppBar
              ? CustomAppbar(
                  title: isBuying ? 'KPI - Buying' : 'KPI - Non Buying',
                  subtitle: isBuying ? 'Buying store performance' : 'Stores requiring attention',
                  actions: [_buildSortMenu(isBuying: isBuying)],
                )
              : null,
          body: _controller.isLoading
              ? const Center(child: CircularProgressIndicator())
              : _controller.errorMessage != null
              ? _buildErrorState(_controller.errorMessage!)
              : _buildScreenList(stores: _controller.filteredAndSortedStores, isBuying: isBuying),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _controller.currentIndex,
            onDestinationSelected: (int index) {
              _searchController.clear();
              _controller.setTabIndex(index);
            },
            destinations: [
              NavigationDestination(
                icon: Badge(
                  label: Text('${_controller.buyingStoreCount}'),
                  isLabelVisible: !_controller.isLoading && _controller.buyingStoreCount > 0,
                  child: const Icon(Icons.storefront_outlined),
                ),
                selectedIcon: Badge(
                  label: Text('${_controller.buyingStoreCount}'),
                  isLabelVisible: !_controller.isLoading && _controller.buyingStoreCount > 0,
                  child: const Icon(Icons.storefront),
                ),
                label: 'Buying Stores',
              ),
              NavigationDestination(
                icon: Badge(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  label: Text('${_controller.nonBuyingStoreCount}'),
                  isLabelVisible: !_controller.isLoading && _controller.nonBuyingStoreCount > 0,
                  child: const Icon(Icons.remove_shopping_cart_outlined),
                ),
                selectedIcon: Badge(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  label: Text('${_controller.nonBuyingStoreCount}'),
                  isLabelVisible: !_controller.isLoading && _controller.nonBuyingStoreCount > 0,
                  child: const Icon(Icons.remove_shopping_cart),
                ),
                label: 'Non Buying Stores',
              ),
            ],
          ),
        );
      },
    );
  }
}
