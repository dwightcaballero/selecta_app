import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/store_order_controller.dart';
import 'package:selecta_ops/models/store_order.dart';
import 'package:selecta_ops/views/pages/sidebar/dealer_store_order_review_page.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/empty_state_widget.dart';
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

  Color _getStatusColor(String status) {
    switch (status) {
      case StoreOrderStatus.submitted:
        return const Color(0xFFF59E0B);
      case StoreOrderStatus.approved:
        return const Color(0xFF3B82F6);
      case StoreOrderStatus.outForDelivery:
        return const Color(0xFF8B5CF6);
      case StoreOrderStatus.delivered:
        return const Color(0xFF10B981);
      case StoreOrderStatus.cancelled:
        return const Color(0xFF94A3B8);
      case StoreOrderStatus.rejected:
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF64748B);
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case StoreOrderStatus.submitted:
        return Icons.hourglass_top_rounded;
      case StoreOrderStatus.approved:
        return Icons.check_circle_outline_rounded;
      case StoreOrderStatus.outForDelivery:
        return Icons.local_shipping_outlined;
      case StoreOrderStatus.delivered:
        return Icons.done_all_rounded;
      case StoreOrderStatus.cancelled:
      case StoreOrderStatus.rejected:
        return Icons.cancel_outlined;
      default:
        return Icons.receipt_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final cardBorder = isDark ? const Color(0xFF384152) : const Color(0xFFE2E8F0);
    final cardBg = isDark ? const Color(0xFF1E2430) : Colors.white;

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Store Orders Inbox',
        subtitle: 'Review & manage store orders',
        showBackButton: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(114),
          child: Column(
            children: [
              // Search input with polished border & styling
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E2430) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search order number or store name...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      prefixIcon: Icon(Icons.search_rounded, size: 20, color: colorScheme.primary),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  ),
                ),
              ),

              // Filter Tabs with live Submitted badge
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white.withValues(alpha: 0.65),
                indicatorColor: const Color(0xFFF59E0B),
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
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
                                    color: const Color(0xFFF59E0B),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$count',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
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
        children: _tabs.map((tab) => _buildOrdersList(tab.status, cardBg, cardBorder, isDark)).toList(),
      ),
    );
  }

  Widget _buildOrdersList(String? filterStatus, Color cardBg, Color cardBorder, bool isDark) {
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
                  Icon(Icons.error_outline_rounded, size: 48, color: Theme.of(context).colorScheme.error),
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
          return EmptyStateWidget(
            icon: Icons.inbox_outlined,
            title: _searchQuery.isNotEmpty ? 'No orders match your search' : 'No orders in this category',
            message: _searchQuery.isNotEmpty
                ? 'Try searching with a different order number or store name.'
                : 'Store orders submitted by Hapi Stores will appear here.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          itemCount: orders.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final order = orders[index];
            return _buildOrderCard(order, cardBg, cardBorder, isDark);
          },
        );
      },
    );
  }

  Widget _buildOrderCard(StoreOrder order, Color cardBg, Color cardBorder, bool isDark) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSubmitted = order.status == StoreOrderStatus.submitted;
    final statusColor = _getStatusColor(order.status);
    final statusIcon = _getStatusIcon(order.status);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSubmitted ? const Color(0xFFF59E0B).withValues(alpha: 0.7) : cardBorder,
          width: isSubmitted ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
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
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: cardBorder),
                            ),
                            child: Text(
                              order.orderNo,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.2),
                            ),
                          ),
                          if (order.remarks != null && order.remarks!.contains('[After Cut-off]'))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                              ),
                              child: const Text(
                                'After Cut-off',
                                style: TextStyle(
                                  color: Color(0xFFF59E0B),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 12, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            order.status,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Store Name & Placed Date
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.storefront_rounded, size: 18, color: colorScheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.storeName,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _dateFormat.format(order.createdAt.toDate()),
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: cardBorder),
                ),

                // Summary footer: Item Count, Amount, Action Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${order.items.length} ${order.items.length == 1 ? 'item' : 'items'} (${order.totalQuantity} units)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _currency.format(order.effectiveAmount),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),

                    // Scheduled Delivery Date or Review Button
                    if (order.deliveryDate != null && !isSubmitted)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.local_shipping_outlined, size: 14, color: Color(0xFF3B82F6)),
                            const SizedBox(width: 6),
                            Text(
                              _dateOnlyFormat.format(order.deliveryDate!.toDate()),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF3B82F6)),
                            ),
                          ],
                        ),
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
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                              : colorScheme.surfaceContainerHighest,
                          foregroundColor: isSubmitted
                              ? const Color(0xFFF59E0B)
                              : colorScheme.onSurfaceVariant,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
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
