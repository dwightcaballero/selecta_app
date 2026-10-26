import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/store_cart_controller.dart';
import 'package:selecta_ops/controllers/store_order_controller.dart';
import 'package:selecta_ops/models/store_order.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:selecta_ops/views/pages/store/store_cart_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';

/// Detailed view of a Store Order with status timeline, itemized pricing,
/// scheduled delivery date, and cancellation/reorder capabilities.
class StoreOrderDetailPage extends StatefulWidget {
  final StoreOrder? order;
  final String? orderId;

  const StoreOrderDetailPage({
    super.key,
    this.order,
    this.orderId,
  });

  @override
  State<StoreOrderDetailPage> createState() => _StoreOrderDetailPageState();
}

class _StoreOrderDetailPageState extends State<StoreOrderDetailPage> {
  final StoreOrderController _orderController = StoreOrderController();
  final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final _dateFormat = DateFormat('EEE, MMM d, yyyy • h:mm a');
  final _dateOnly = DateFormat('EEEE, MMM d, yyyy');

  bool _isCancelling = false;

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

  Future<void> _cancelOrder(StoreOrder order) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Order?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to cancel order #${order.orderNumber}?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for cancellation (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Confirm Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isCancelling = true);

    try {
      await _orderController.cancelOrder(
        orderId: order.id,
        reason: reasonController.text.trim().isNotEmpty ? reasonController.text.trim() : 'Cancelled by store',
      );

      if (mounted) {
        ShowMessage.success(context, 'Order #${order.orderNumber} has been cancelled.');
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to cancel order: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isCancelling = false);
      }
    }
  }

  Future<void> _reorder(StoreOrder order) async {
    try {
      final catalog = await SelectaProductService().getAllSelectaProductList();
      StoreCartController().loadFromStoreOrder(order, catalog);

      if (mounted) {
        ShowMessage.success(context, 'Items from order #${order.orderNumber} added to cart!');
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StoreCartPage()),
        );
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Unable to load products for reorder: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveOrderId = widget.order?.id ?? widget.orderId ?? '';

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('store_orders').doc(effectiveOrderId).snapshots(),
      builder: (context, snapshot) {
        StoreOrder currentOrder;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          currentOrder = StoreOrder.fromJson(data, id: snapshot.data!.id);
        } else if (widget.order != null) {
          currentOrder = widget.order!;
        } else if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        } else {
          return Scaffold(
            appBar: AppBar(title: const Text('Order Details')),
            body: const Center(child: Text('Order not found.')),
          );
        }

        final colorScheme = Theme.of(context).colorScheme;
        final statusColor = _getStatusColor(currentOrder.status);

        return Scaffold(
          appBar: AppBar(
            title: Text('Order #${currentOrder.orderNumber}'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Status Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Order #${currentOrder.orderNumber}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: statusColor),
                              ),
                              child: Text(
                                currentOrder.status,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Placed: ${_dateFormat.format(currentOrder.createdAt.toDate())}',
                          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                        ),
                        if (currentOrder.deliveryDate != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.local_shipping_outlined, color: Colors.blue, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Scheduled Delivery Date',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue),
                                      ),
                                      Text(
                                        _dateOnly.format(currentOrder.deliveryDate!.toDate()),
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (currentOrder.status == StoreOrderStatus.rejected && currentOrder.rejectionReason != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Rejection Reason', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
                                      Text(currentOrder.rejectionReason!, style: const TextStyle(fontSize: 13)),
                                    ],
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
                const SizedBox(height: 16),

                // Status Timeline Stepper
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Order Status Timeline',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 14),
                        if (currentOrder.statusHistory.isEmpty)
                          Text('No status updates recorded.', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13))
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: currentOrder.statusHistory.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, idx) {
                              final history = currentOrder.statusHistory[idx];
                              final isLast = idx == currentOrder.statusHistory.length - 1;
                              final histColor = _getStatusColor(history.status);

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Column(
                                    children: [
                                      Icon(
                                        isLast ? Icons.check_circle : Icons.radio_button_checked,
                                        size: 18,
                                        color: histColor,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              history.status,
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: histColor),
                                            ),
                                            Text(
                                              _dateFormat.format(history.timestamp),
                                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                            ),
                                          ],
                                        ),
                                        if (history.note != null && history.note!.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(history.note!, style: const TextStyle(fontSize: 12)),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Itemized Breakdown Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order Items (${currentOrder.totalQuantity} items)',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 14),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: currentOrder.items.length,
                          separatorBuilder: (context, index) => const Divider(height: 16),
                          itemBuilder: (context, idx) {
                            final item = currentOrder.items[idx];
                            final qtyChanged = item.qtyApproved != item.qtyOrdered;

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.productName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                      ),
                                      if (item.flavor.isNotEmpty)
                                        Text(item.flavor, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: colorScheme.surfaceContainerHighest,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(item.packaging, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                          ),
                                          const SizedBox(width: 8),
                                          Text('${_currency.format(item.unitPrice)} each', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (qtyChanged) ...[
                                      Text(
                                        'Qty: ${item.qtyOrdered} -> ${item.qtyApproved}',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue),
                                      ),
                                      Text(
                                        _currency.format(item.effectivePrice),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                      ),
                                    ] else ...[
                                      Text('Qty: ${item.qtyOrdered}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                      Text(
                                        _currency.format(item.totalPrice),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                        const Divider(height: 24),

                        // Totals Summary
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Estimated Total', style: TextStyle(fontSize: 14)),
                            Text(_currency.format(currentOrder.estimatedTotal), style: const TextStyle(fontSize: 14)),
                          ],
                        ),
                        if (currentOrder.approvedTotal != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Approved Final Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              Text(
                                _currency.format(currentOrder.approvedTotal),
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: colorScheme.primary),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Remarks if present
                if (currentOrder.remarks != null && currentOrder.remarks!.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Delivery Instructions', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text(currentOrder.remarks!, style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    if (currentOrder.status == StoreOrderStatus.submitted) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isCancelling ? null : () => _cancelOrder(currentOrder),
                          icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                          label: const Text('Cancel Order', style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _reorder(currentOrder),
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text('Reorder Items'),
                        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
