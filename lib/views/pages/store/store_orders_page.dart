import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/store_order_controller.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/store_order.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/views/pages/store/store_order_detail_page.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/empty_state_widget.dart';

/// Store Order History View.
/// Displays all submitted, approved, out-for-delivery, and completed orders with status filtering.
class StoreOrdersPage extends StatefulWidget {
  const StoreOrdersPage({super.key});

  @override
  State<StoreOrdersPage> createState() => _StoreOrdersPageState();
}

class _StoreOrdersPageState extends State<StoreOrdersPage> {
  final StoreOrderController _orderController = StoreOrderController();
  final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final _dateFormat = DateFormat('MMM d, yyyy • h:mm a');
  final _dateOnly = DateFormat('EEE, MMM d');

  String _selectedStatusFilter = 'All';

  final List<String> _filters = [
    'All',
    StoreOrderStatus.submitted,
    StoreOrderStatus.approved,
    StoreOrderStatus.outForDelivery,
    StoreOrderStatus.delivered,
    StoreOrderStatus.cancelled,
  ];

  Color _getStatusColor(String status) {
    switch (status) {
      case StoreOrderStatus.submitted:
        return const Color(0xFFF59E0B); // Amber
      case StoreOrderStatus.approved:
        return const Color(0xFF3B82F6); // Blue
      case StoreOrderStatus.outForDelivery:
        return const Color(0xFF8B5CF6); // Purple
      case StoreOrderStatus.delivered:
        return const Color(0xFF10B981); // Emerald
      case StoreOrderStatus.rejected:
        return const Color(0xFFEF4444); // Red
      case StoreOrderStatus.cancelled:
        return const Color(0xFF94A3B8); // Slate
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
      case StoreOrderStatus.rejected:
      case StoreOrderStatus.cancelled:
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

    return FutureBuilder<Users?>(
      future: KVariables.getUser(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = userSnapshot.data ?? Users.empty();
        final storeId = user.storeId;

        if (storeId.isEmpty) {
          return Scaffold(
            appBar: const CustomAppbar(
              title: 'My Orders',
              subtitle: 'Order History',
              showBackButton: false,
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.error_outline_rounded, size: 36, color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  const Text('Store account not found.', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text('Please re-login with your store credentials.', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          appBar: const CustomAppbar(
            title: 'My Orders',
            subtitle: 'Track and review past orders',
            showBackButton: false,
          ),
          body: Column(
            children: [
              // Filter Chips
              Container(
                height: 54,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filters.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final filter = _filters[idx];
                    final isSelected = _selectedStatusFilter == filter;
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _selectedStatusFilter = filter),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primary
                              : (isDark ? const Color(0xFF1E2430) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? colorScheme.primary
                                : (isDark ? const Color(0xFF384152) : const Color(0xFFE2E8F0)),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            filter,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : const Color(0xFF475569)),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Orders Stream List
              Expanded(
                child: StreamBuilder<List<StoreOrder>>(
                  stream: _orderController.getStoreOrdersStream(storeId: storeId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading orders: ${snapshot.error}',
                          style: TextStyle(color: colorScheme.error),
                        ),
                      );
                    }

                    final orders = snapshot.data ?? [];
                    final filteredOrders = orders.where((o) {
                      if (_selectedStatusFilter == 'All') return true;
                      return o.status == _selectedStatusFilter;
                    }).toList();

                    if (filteredOrders.isEmpty) {
                      return EmptyStateWidget(
                        icon: Icons.receipt_long_outlined,
                        title: _selectedStatusFilter == 'All'
                            ? 'No orders placed yet'
                            : 'No orders with status "$_selectedStatusFilter"',
                        message: _selectedStatusFilter == 'All'
                            ? 'Orders placed via the catalog will appear here.'
                            : 'Try selecting another status filter above.',
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: filteredOrders.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, idx) {
                        final order = filteredOrders[idx];
                        final statusColor = _getStatusColor(order.status);
                        final statusIcon = _getStatusIcon(order.status);
                        final totalAmount = order.approvedTotal ?? order.estimatedTotal;

                        return Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cardBorder),
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
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StoreOrderDetailPage(order: order),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  color: colorScheme.primary.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Icon(Icons.tag_rounded, size: 16, color: colorScheme.primary),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  '#${order.orderNumber}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                    letterSpacing: 0.2,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
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
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Icon(Icons.schedule_rounded, size: 13, color: colorScheme.onSurfaceVariant),
                                        const SizedBox(width: 4),
                                        Text(
                                          _dateFormat.format(order.createdAt.toDate()),
                                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      child: Divider(height: 1, color: cardBorder),
                                    ),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${order.items.length} items (${order.totalQuantity} units)',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              _currency.format(totalAmount),
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: colorScheme.primary,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              size: 18,
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (order.deliveryDate != null) ...[
                                      const SizedBox(height: 10),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: const Color(0xFF3B82F6).withValues(alpha: 0.25),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.local_shipping_outlined, size: 14, color: Color(0xFF3B82F6)),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Est. Delivery: ${_dateOnly.format(order.deliveryDate!.toDate())}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF3B82F6),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

