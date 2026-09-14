import 'package:flutter/material.dart';
import 'package:flutter_app/controllers/kpi_controller.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/dto/kpi_dto.dart';
import 'package:flutter_app/views/pages/sidebar/transactionlist_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

enum _StoreSort { nameAscending, nameDescending, orderCountAscending, orderCountDescending, orderTotalAscending, orderTotalDescending }

class BuyinglistPage extends StatefulWidget {
  const BuyinglistPage({super.key});

  @override
  State<BuyinglistPage> createState() => _BuyinglistPageState();
}

class _BuyinglistPageState extends State<BuyinglistPage> {
  String appbarTitle = '';
  List<KPIBuying> listBuying = [];
  List<KPIBuying> listNonBuying = [];

  int _currentIndex = 0;
  _StoreSort _sort = _StoreSort.nameAscending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      prefetchData();
    });
  }

  void prefetchData() async {
    // Get list of buying and non buying stores
    List<KPIBuying> buying = [];
    List<KPIBuying> nonBuying = [];
    (buying, nonBuying) = await KPIController.getListOfBuyingAndNonBuyingStores();
    listBuying = buying;
    listNonBuying = nonBuying;
    appbarTitle = 'KPI - Buying';
    setState(() {});
  }

  // List of screens to navigate
  List<Widget> get _screens => [_screenList(listBuying, isBuying: true), _screenList(listNonBuying, isBuying: false)];

  Widget _screenList(List<KPIBuying> listStore, {required bool isBuying}) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = isBuying ? colorScheme.primary : colorScheme.error;
    final sortedStores = List<KPIBuying>.of(listStore)..sort(_compareStores);
    final totalSales = sortedStores.fold<double>(0, (sum, store) => sum + store.deliveredAmount);

    if (sortedStores.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isBuying ? Icons.storefront_outlined : Icons.search_off_outlined, size: 48, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('No ${isBuying ? 'buying' : 'non-buying'} stores found', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'There are no stores to show for this KPI.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: sortedStores.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildSummaryBanner(
            storeCount: sortedStores.length,
            totalSales: totalSales,
            statusColor: statusColor,
            label: isBuying ? 'Buying performance' : 'Stores requiring attention',
          );
        }

        final store = sortedStores[index - 1];
        return _buildStoreCard(store: store, statusColor: statusColor, isBuying: isBuying);
      },
    );
  }

  int _compareStores(KPIBuying first, KPIBuying second) {
    final comparison = switch (_sort) {
      _StoreSort.nameAscending || _StoreSort.nameDescending => first.storeName.toLowerCase().compareTo(second.storeName.toLowerCase()),
      _StoreSort.orderCountAscending || _StoreSort.orderCountDescending => first.orderCount.compareTo(second.orderCount),
      _StoreSort.orderTotalAscending || _StoreSort.orderTotalDescending => first.deliveredAmount.compareTo(second.deliveredAmount),
    };

    return switch (_sort) {
      _StoreSort.nameDescending || _StoreSort.orderCountDescending || _StoreSort.orderTotalDescending => -comparison,
      _ => comparison,
    };
  }

  Widget _buildSummaryBanner({required int storeCount, required double totalSales, required Color statusColor, required String label}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.insights_outlined, color: statusColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 3),
                Text('$storeCount stores', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Order total', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 3),
              Text(
                Helperfunctions.formatDoubleAmountForDisplay(totalSales),
                style: TextStyle(fontWeight: FontWeight.bold, color: statusColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStoreCard({required KPIBuying store, required Color statusColor, required bool isBuying}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Helperfunctions.navigateTo(context, TransactionListPage(storeName: store.storeName)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(isBuying ? Icons.storefront_outlined : Icons.warning_amber_outlined, color: statusColor),
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
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 5),
                    Text('${store.orderCount} orders', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Order total', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 3),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(store.deliveredAmount),
                    style: TextStyle(fontWeight: FontWeight.bold, color: statusColor),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortMenu() {
    return PopupMenuButton<_StoreSort>(
      icon: const Icon(Icons.sort_rounded, color: Colors.white),
      tooltip: 'Sort stores',
      onSelected: (sort) => setState(() => _sort = sort),
      itemBuilder: (context) => [
        _buildSortOption(_StoreSort.nameAscending, 'Customer Name', true),
        _buildSortOption(_StoreSort.nameDescending, 'Customer Name', false),
        _buildSortOption(_StoreSort.orderCountAscending, 'Order Count', true),
        _buildSortOption(_StoreSort.orderCountDescending, 'Order Count', false),
        _buildSortOption(_StoreSort.orderTotalAscending, 'Order Total', true),
        _buildSortOption(_StoreSort.orderTotalDescending, 'Order Total', false),
      ],
    );
  }

  PopupMenuItem<_StoreSort> _buildSortOption(_StoreSort sort, String label, bool ascending) {
    return PopupMenuItem(
      value: sort,
      child: Row(
        children: [
          Icon(ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text('$label (${ascending ? 'Ascending' : 'Descending'})')),
          if (_sort == sort) const Icon(Icons.check_rounded, size: 18),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(
        title: appbarTitle.isEmpty ? 'KPI - Buying' : appbarTitle,
        subtitle: _currentIndex == 0 ? 'Buying store performance' : 'Stores requiring attention',
        actions: [_buildSortMenu()],
      ),
      body: _screens[_currentIndex],

      // 4. Implement the NavigationBar
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          _currentIndex = index; // Rebuilds the UI with the new screen
          if (_currentIndex == 0) {
            appbarTitle = 'KPI - Buying';
          } else {
            appbarTitle = 'KPI - Non Buying';
          }
          setState(() {});
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Buying Stores'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Non Buying Stores'),
        ],
      ),
    );
  }
}
