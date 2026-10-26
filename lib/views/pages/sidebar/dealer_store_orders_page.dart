import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/store_order_controller.dart';
import 'package:selecta_ops/models/store_order.dart';
import 'package:selecta_ops/views/pages/sidebar/dealer_store_order_review_page.dart';
import 'package:selecta_ops/views/widgets/shimmer_loading.dart';

/// Dealer / Admin Store Orders Management Inbox.
/// Allows dealers to view all store orders, filter by status, search by order number
/// or store name, and review incoming orders for approval, quantity adjustments,
/// and delivery date assignment.
class DealerStoreOrdersPage extends StatefulWidget {
  const DealerStoreOrdersPage({super.key});

  @override
  State<DealerStoreOrdersPage> createState() => _DealerStoreOrdersPageState();
}

class _DealerStoreOrdersPageState extends State<DealerStoreOrdersPage>
    with SingleTickerProviderStateMixin {
  final StoreOrderController _orderController = StoreOrderController();
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController;

  final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final _dateFormat = DateFormat('MMM dd, yyyy • hh:mm a');
  final _dateOnlyFormat = DateFormat('EEE, MMM dd, yyyy');

  String _searchQuery = '';

  // Filter tabs definition
  final List<_FilterTab> _tabs = const [
    _FilterTab(label: 'All', status: null),
    _FilterTab(label: 'Submitted', status: StoreOrderStatus.submitted),
    _FilterTab(label: 'Approved', status: StoreOrderStatus.approved),
    _FilterTab(label: 'In Transit', status: StoreOrderStatus.outForDelivery),
    _FilterTab(label: 'Delivered', status: StoreOrderStatus.delivered),
    _FilterTab(label: 'Closed', status: 'Closed'), // cancelled or rejected
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Orders Inbox'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(108),
          child: Column(
            children: [
              // Search input
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search order number or store name...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
              ),

              // Filter Tabs with live Submitted badge
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                tabs: _tabs.map((tab) {
                  if (tab.status == StoreOrderStatus.submitted) {
                    return StreamBuilder<int>(
                      stream: _orderController.getSubmittedCountStream(),
                      initialData: 0,
                      builder: (context, snap) {
                        final count = snap.data ?? 0;
                        return Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(tab.label),
                              if (count > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade700,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$count',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  }
                  return Tab(text: tab.label);
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((tab) => _buildOrdersList(tab.status)).toList(),
      ),
    );
  }

  Widget _buildOrdersList(String? filterStatus) {
    return StreamBuilder<List<StoreOrder>>(
      stream: _orderController.getAllStoreOrdersStream(
        status: (filterStatus == null || filterStatus == 'Closed') ? null : filterStatus,
        searchQuery: _searchQuery,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ListSkeleton(itemCount: 6);
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 12),
                  Text('Failed to load orders: ${snapshot.error}', textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        }

        var orders = snapshot.data ?? [];

        // Apply custom closed filter if selected
        if (filterStatus == 'Closed') {
          orders = orders
              .where((o) => o.status == StoreOrderStatus.cancelled || o.status == StoreOrderStatus.rejected)
              .toList();
        }

        if (orders.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _searchQuery.isNotEmpty ? 'No orders match your search' : 'No orders in this category',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _searchQuery.isNotEmpty
                        ? 'Try searching with a different order number or store name.'
                        : 'Store orders submitted by Hapi Stores will appear here.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final order = orders[index];
            return _buildOrderCard(order);
          },
        );
      },
    );
  }

  Widget _buildOrderCard(StoreOrder order) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSubmitted = order.status == StoreOrderStatus.submitted;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSubmitted ? Colors.amber.shade400 : colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: isSubmitted ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DealerStoreOrderReviewPage(
                orderId: order.id,
                order: order,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Order Number and Status Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          order.orderNo,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      if (order.remarks != null && order.remarks!.contains('[After Cut-off]')) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'After Cut-off',
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  _buildStatusChip(order.status),
                ],
              ),
              const SizedBox(height: 10),

              // Store Name & Placed Date
              Row(
                children: [
                  const Icon(Icons.storefront, size: 18, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.storeName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Text(
                  _dateFormat.format(order.createdAt.toDate()),
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ),

              const Divider(height: 20),

              // Summary footer: Item Count, Amount, Action Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${order.items.length} ${order.items.length == 1 ? 'item' : 'items'} (${order.totalQuantity} pcs)',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currency.format(order.effectiveAmount),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),

                  // Scheduled Delivery Date or Review Button
                  if (order.deliveryDate != null && !isSubmitted)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Delivery Date',
                          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                        ),
                        Text(
                          _dateOnlyFormat.format(order.deliveryDate!.toDate()),
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DealerStoreOrderReviewPage(
                              orderId: order.id,
                              order: order,
                            ),
                          ),
                        );
                      },
                      icon: Icon(
                        isSubmitted ? Icons.rate_review_outlined : Icons.visibility_outlined,
                        size: 16,
                      ),
                      label: Text(isSubmitted ? 'Review' : 'View'),
                      style: FilledButton.styleFrom(
                        backgroundColor: isSubmitted
                            ? Colors.amber.shade100
                            : colorScheme.surfaceContainerHighest,
                        foregroundColor: isSubmitted
                            ? Colors.amber.shade900
                            : colorScheme.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color bg;
    Color fg;

    switch (status) {
      case StoreOrderStatus.submitted:
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        break;
      case StoreOrderStatus.approved:
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade900;
        break;
      case StoreOrderStatus.outForDelivery:
        bg = Colors.purple.shade100;
        fg = Colors.purple.shade900;
        break;
      case StoreOrderStatus.delivered:
        bg = Colors.green.shade100;
        fg = Colors.green.shade900;
        break;
      case StoreOrderStatus.cancelled:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        break;
      case StoreOrderStatus.rejected:
        bg = Colors.red.shade100;
        fg = Colors.red.shade900;
        break;
      default:
        bg = Colors.grey.shade100;
        fg = Colors.black87;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _FilterTab {
  final String label;
  final String? status;
  const _FilterTab({required this.label, this.status});
}
