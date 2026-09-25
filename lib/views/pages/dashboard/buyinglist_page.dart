import 'package:flutter/material.dart';
import 'package:flutter_app/controllers/kpi_controller.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/dto/kpi_dto.dart';
import 'package:flutter_app/views/pages/sidebar/transactionlist_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

enum _StoreSort {
  nameAscending,
  nameDescending,
  orderCountAscending,
  orderCountDescending,
  orderTotalAscending,
  orderTotalDescending,
}

class BuyinglistPage extends StatefulWidget {
  const BuyinglistPage({super.key});

  @override
  State<BuyinglistPage> createState() => _BuyinglistPageState();
}

class _BuyinglistPageState extends State<BuyinglistPage> {
  List<KPIBuying> listBuying = [];
  List<KPIBuying> listNonBuying = [];

  int _currentIndex = 0;
  _StoreSort _sort = _StoreSort.nameAscending;
  bool _isLoading = true;
  String? _errorMessage;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> prefetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final (buying, nonBuying) = await KPIController.getListOfBuyingAndNonBuyingStores();
      if (!mounted) return;
      setState(() {
        listBuying = buying;
        listNonBuying = nonBuying;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load store data: $e';
        _isLoading = false;
      });
    }
  }

  int _compareStores(KPIBuying first, KPIBuying second) {
    final comparison = switch (_sort) {
      _StoreSort.nameAscending || _StoreSort.nameDescending =>
        first.storeName.toLowerCase().compareTo(second.storeName.toLowerCase()),
      _StoreSort.orderCountAscending || _StoreSort.orderCountDescending =>
        first.orderCount.compareTo(second.orderCount),
      _StoreSort.orderTotalAscending || _StoreSort.orderTotalDescending =>
        first.deliveredAmount.compareTo(second.deliveredAmount),
    };

    return switch (_sort) {
      _StoreSort.nameDescending ||
      _StoreSort.orderCountDescending ||
      _StoreSort.orderTotalDescending =>
        -comparison,
      _ => comparison,
    };
  }

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
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isBuying ? Icons.insights_outlined : Icons.warning_amber_rounded,
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
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
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Zero Orders',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStoreCard({
    required KPIBuying store,
    required Color statusColor,
    required bool isBuying,
  }) {
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isBuying ? Icons.storefront_outlined : Icons.remove_shopping_cart_outlined,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
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

  Widget _buildScreenList(List<KPIBuying> listStore, {required bool isBuying}) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = isBuying ? colorScheme.primary : colorScheme.error;

    // Filter by search
    final filtered = listStore.where((store) {
      if (_searchQuery.trim().isEmpty) return true;
      return store.storeName.toLowerCase().contains(_searchQuery.trim().toLowerCase());
    }).toList();

    final sortedStores = List<KPIBuying>.of(filtered)..sort(_compareStores);
    final totalSales = sortedStores.fold<double>(0, (sum, store) => sum + store.deliveredAmount);

    return RefreshIndicator(
      onRefresh: prefetchData,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: sortedStores.length + 2, // Search + Banner + Items
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            // Search Bar
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search ${isBuying ? 'buying' : 'non-buying'} stores...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
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
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            );
          }

          if (index == 1) {
            return _buildSummaryBanner(
              storeCount: sortedStores.length,
              totalSales: totalSales,
              statusColor: statusColor,
              label: isBuying ? 'Active Buying Stores' : 'Stores Requiring Attention',
              isBuying: isBuying,
            );
          }

          if (sortedStores.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _searchQuery.isNotEmpty
                      ? 'No stores match "$_searchQuery"'
                      : 'No ${isBuying ? 'buying' : 'non-buying'} stores found.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
            );
          }

          final store = sortedStores[index - 2];
          return _buildStoreCard(store: store, statusColor: statusColor, isBuying: isBuying);
        },
      ),
    );
  }

  Widget _buildSortMenu() {
    final isBuying = _currentIndex == 0;

    return PopupMenuButton<_StoreSort>(
      icon: const Icon(Icons.sort_rounded, color: Colors.white),
      tooltip: 'Sort stores',
      onSelected: (sort) => setState(() => _sort = sort),
      itemBuilder: (context) => [
        _buildSortOption(_StoreSort.nameAscending, 'Store Name (A-Z)', Icons.arrow_upward),
        _buildSortOption(_StoreSort.nameDescending, 'Store Name (Z-A)', Icons.arrow_downward),
        if (isBuying) ...[
          const PopupMenuDivider(),
          _buildSortOption(_StoreSort.orderCountDescending, 'Highest Order Count', Icons.arrow_downward),
          _buildSortOption(_StoreSort.orderCountAscending, 'Lowest Order Count', Icons.arrow_upward),
          _buildSortOption(_StoreSort.orderTotalDescending, 'Highest Sales Total', Icons.arrow_downward),
          _buildSortOption(_StoreSort.orderTotalAscending, 'Lowest Sales Total', Icons.arrow_upward),
        ],
      ],
    );
  }

  PopupMenuItem<_StoreSort> _buildSortOption(_StoreSort sort, String label, IconData icon) {
    return PopupMenuItem(
      value: sort,
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          if (_sort == sort) const Icon(Icons.check_rounded, size: 18),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBuying = _currentIndex == 0;

    return Scaffold(
      appBar: CustomAppbar(
        title: isBuying ? 'KPI - Buying' : 'KPI - Non Buying',
        subtitle: isBuying ? 'Buying store performance' : 'Stores requiring attention',
        actions: [_buildSortMenu()],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
                      const SizedBox(height: 8),
                      Text(_errorMessage!),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: prefetchData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _buildScreenList(isBuying ? listBuying : listNonBuying, isBuying: isBuying),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _currentIndex = index;
            _searchController.clear();
            _searchQuery = '';
          });
        },
        destinations: [
          NavigationDestination(
            icon: Badge(
              label: Text('${listBuying.length}'),
              isLabelVisible: !_isLoading && listBuying.isNotEmpty,
              child: const Icon(Icons.storefront_outlined),
            ),
            selectedIcon: Badge(
              label: Text('${listBuying.length}'),
              isLabelVisible: !_isLoading && listBuying.isNotEmpty,
              child: const Icon(Icons.storefront),
            ),
            label: 'Buying Stores',
          ),
          NavigationDestination(
            icon: Badge(
              backgroundColor: Theme.of(context).colorScheme.error,
              label: Text('${listNonBuying.length}'),
              isLabelVisible: !_isLoading && listNonBuying.isNotEmpty,
              child: const Icon(Icons.remove_shopping_cart_outlined),
            ),
            selectedIcon: Badge(
              backgroundColor: Theme.of(context).colorScheme.error,
              label: Text('${listNonBuying.length}'),
              isLabelVisible: !_isLoading && listNonBuying.isNotEmpty,
              child: const Icon(Icons.remove_shopping_cart),
            ),
            label: 'Non Buying Stores',
          ),
        ],
      ),
    );
  }
}
