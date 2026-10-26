import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/store_order_controller.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/store_order.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/views/pages/store/store_order_detail_page.dart';

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
        return Colors.orange;
      case StoreOrderStatus.approved:
        return Colors.blue;
      case StoreOrderStatus.outForDelivery:
        return Colors.purple;
      case StoreOrderStatus.delivered:
        return Colors.green;
      case StoreOrderStatus.rejected:
        return Colors.red;
      case StoreOrderStatus.cancelled:
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<Users?>(
      future: KVariables.getUser(),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data ?? Users.empty();
        final storeId = user.storeId;

        if (storeId.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('My Orders')),
            body: const Center(child: Text('Store account not found.')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('My Orders'),
          ),
          body: Column(
            children: [
              // Filter Chips
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  itemCount: _filters.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final filter = _filters[idx];
                    final isSelected = _selectedStatusFilter == filter;
                    return ChoiceChip(
                      label: Text(filter),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _selectedStatusFilter = filter),
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
                      return Center(child: Text('Error loading orders: ${snapshot.error}'));
                    }

                    final orders = snapshot.data ?? [];
                    final filteredOrders = orders.where((o) {
                      if (_selectedStatusFilter == 'All') return true;
                      return o.status == _selectedStatusFilter;
                    }).toList();

                    if (filteredOrders.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 60, color: colorScheme.outlineVariant),
                            const SizedBox(height: 12),
                            Text(
                              _selectedStatusFilter == 'All'
                                  ? 'No orders placed yet.'
                                  : 'No orders with status "$_selectedStatusFilter".',
                              style: TextStyle(color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredOrders.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, idx) {
                        final order = filteredOrders[idx];
                        final statusColor = _getStatusColor(order.status);
                        final totalAmount = order.approvedTotal ?? order.estimatedTotal;

                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                          ),
                          elevation: 0,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StoreOrderDetailPage(order: order),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '#${order.orderNumber}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: statusColor.withValues(alpha: 0.6)),
                                        ),
                                        child: Text(
                                          order.status,
                                          style: TextStyle(
                                            color: statusColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _dateFormat.format(order.createdAt.toDate()),
                                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                  ),
                                  const Divider(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${order.items.length} items (${order.totalQuantity} units)',
                                        style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                                      ),
                                      Text(
                                        _currency.format(totalAmount),
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (order.deliveryDate != null) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.local_shipping_outlined, size: 15, color: Colors.blue),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Est. Delivery: ${_dateOnly.format(order.deliveryDate!.toDate())}',
                                          style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
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
