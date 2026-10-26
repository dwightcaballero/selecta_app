import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/store_cart_controller.dart';
import 'package:selecta_ops/controllers/store_order_controller.dart';
import 'package:selecta_ops/models/store_order.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:selecta_ops/views/pages/store/store_cart_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';

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
        return const Color(0xFFF59E0B);
      case StoreOrderStatus.approved:
        return const Color(0xFF3B82F6);
      case StoreOrderStatus.outForDelivery:
        return const Color(0xFF8B5CF6);
      case StoreOrderStatus.delivered:
        return const Color(0xFF10B981);
      case StoreOrderStatus.rejected:
        return const Color(0xFFEF4444);
      case StoreOrderStatus.cancelled:
        return const Color(0xFF94A3B8);
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

  Future<void> _cancelOrder(StoreOrder order) async {
    final reasonController = TextEditingController();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: isDark ? const Color(0xFF1E2430) : Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cancel_outlined, color: Colors.red, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Cancel Order?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to cancel order #${order.orderNumber}? This action cannot be undone.'),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'Reason for cancellation (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
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

  Widget _buildStepIndicator({
    required String label,
    required IconData icon,
    required bool isActive,
    required bool isCompleted,
    required Color activeColor,
    required bool isDark,
  }) {
    final bgColor = isCompleted
        ? activeColor
        : (isActive ? activeColor.withValues(alpha: 0.15) : (isDark ? const Color(0xFF2A3444) : const Color(0xFFF1F5F9)));
    final iconColor = isCompleted
        ? Colors.white
        : (isActive ? activeColor : (isDark ? Colors.white38 : const Color(0xFF94A3B8)));

    return Expanded(
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: isCompleted || isActive ? activeColor : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Icon(
              isCompleted ? Icons.check_rounded : icon,
              size: 16,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: isActive || isCompleted ? FontWeight.bold : FontWeight.w500,
              color: isActive || isCompleted
                  ? (isDark ? Colors.white : const Color(0xFF1E293B))
                  : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );
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
          return const Scaffold(
            appBar: CustomAppbar(title: 'Order Details', subtitle: 'Store Order'),
            body: Center(child: Text('Order not found.')),
          );
        }

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final cardBorder = isDark ? const Color(0xFF384152) : const Color(0xFFE2E8F0);
        final cardBg = isDark ? const Color(0xFF1E2430) : Colors.white;
        final statusColor = _getStatusColor(currentOrder.status);
        final statusIcon = _getStatusIcon(currentOrder.status);

        // Progress bar step logic
        final isCancelled = currentOrder.status == StoreOrderStatus.cancelled || currentOrder.status == StoreOrderStatus.rejected;
        final isApproved = currentOrder.status == StoreOrderStatus.approved ||
            currentOrder.status == StoreOrderStatus.outForDelivery ||
            currentOrder.status == StoreOrderStatus.delivered;
        final isOutForDelivery = currentOrder.status == StoreOrderStatus.outForDelivery ||
            currentOrder.status == StoreOrderStatus.delivered;
        final isDelivered = currentOrder.status == StoreOrderStatus.delivered;

        return Scaffold(
          appBar: CustomAppbar(
            title: 'Order #${currentOrder.orderNumber}',
            subtitle: 'Order Summary & Tracking',
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Status & Header Card
                Container(
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
                                  child: Icon(Icons.receipt_long_rounded, size: 16, color: colorScheme.primary),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Order #${currentOrder.orderNumber}',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.2),
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
                                  currentOrder.status,
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
                            'Placed: ${_dateFormat.format(currentOrder.createdAt.toDate())}',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),

                      // Delivery Date Highlight Box
                      if (currentOrder.deliveryDate != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.local_shipping_outlined, color: Color(0xFF3B82F6), size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Scheduled Delivery Date',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF3B82F6)),
                                    ),
                                    Text(
                                      _dateOnly.format(currentOrder.deliveryDate!.toDate()),
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Rejection Alert Box
                      if (currentOrder.status == StoreOrderStatus.rejected && currentOrder.rejectionReason != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Order Rejection Reason',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
                                    ),
                                    const SizedBox(height: 2),
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
                const SizedBox(height: 14),

                // Order Flow Progress Bar (if not cancelled/rejected)
                if (!isCancelled)
                  Container(
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Order Progress', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            _buildStepIndicator(
                              label: 'Submitted',
                              icon: Icons.assignment_outlined,
                              isActive: currentOrder.status == StoreOrderStatus.submitted,
                              isCompleted: isApproved || isOutForDelivery || isDelivered,
                              activeColor: const Color(0xFFF59E0B),
                              isDark: isDark,
                            ),
                            Container(
                              height: 2,
                              width: 18,
                              color: isApproved ? const Color(0xFF3B82F6) : cardBorder,
                            ),
                            _buildStepIndicator(
                              label: 'Approved',
                              icon: Icons.check_circle_outline,
                              isActive: currentOrder.status == StoreOrderStatus.approved,
                              isCompleted: isOutForDelivery || isDelivered,
                              activeColor: const Color(0xFF3B82F6),
                              isDark: isDark,
                            ),
                            Container(
                              height: 2,
                              width: 18,
                              color: isOutForDelivery ? const Color(0xFF8B5CF6) : cardBorder,
                            ),
                            _buildStepIndicator(
                              label: 'In Transit',
                              icon: Icons.local_shipping_outlined,
                              isActive: currentOrder.status == StoreOrderStatus.outForDelivery,
                              isCompleted: isDelivered,
                              activeColor: const Color(0xFF8B5CF6),
                              isDark: isDark,
                            ),
                            Container(
                              height: 2,
                              width: 18,
                              color: isDelivered ? const Color(0xFF10B981) : cardBorder,
                            ),
                            _buildStepIndicator(
                              label: 'Delivered',
                              icon: Icons.done_all_rounded,
                              isActive: currentOrder.status == StoreOrderStatus.delivered,
                              isCompleted: isDelivered,
                              activeColor: const Color(0xFF10B981),
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (!isCancelled) const SizedBox(height: 14),

                // Status Timeline Stepper
                Container(
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
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.timeline_rounded, size: 16, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          const Text(
                            'Status History',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (currentOrder.statusHistory.isEmpty)
                        Text(
                          'No status updates recorded yet.',
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                        )
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
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: histColor.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isLast ? Icons.check_circle_rounded : Icons.radio_button_checked_rounded,
                                    size: 14,
                                    color: histColor,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            history.status,
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: histColor),
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
                const SizedBox(height: 14),

                // Itemized Breakdown Card
                Container(
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
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 16, color: colorScheme.primary),
                              const SizedBox(width: 8),
                              const Text(
                                'Order Items',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2A3444) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${currentOrder.items.length} products • ${currentOrder.totalQuantity} units',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: currentOrder.items.length,
                        separatorBuilder: (context, index) => Divider(height: 20, color: cardBorder),
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
                                            color: isDark ? const Color(0xFF2A3444) : const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: cardBorder),
                                          ),
                                          child: Text(
                                            item.packaging,
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${_currency.format(item.unitPrice)} each',
                                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (qtyChanged) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Qty: ${item.qtyOrdered} → ${item.qtyApproved}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF3B82F6)),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _currency.format(item.effectivePrice),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ] else ...[
                                    Text('Qty: ${item.qtyOrdered}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _currency.format(item.totalPrice),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1, color: cardBorder),
                      ),

                      // Totals Summary
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Estimated Total', style: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant)),
                          Text(_currency.format(currentOrder.estimatedTotal), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      if (currentOrder.approvedTotal != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Approved Final Total', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            Text(
                              _currency.format(currentOrder.approvedTotal),
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colorScheme.primary),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Delivery Instructions if present
                if (currentOrder.remarks != null && currentOrder.remarks!.isNotEmpty) ...[
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cardBorder),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.notes_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            const Text('Delivery Instructions', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(currentOrder.remarks!, style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Action Buttons
                Row(
                  children: [
                    if (currentOrder.status == StoreOrderStatus.submitted) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isCancelling ? null : () => _cancelOrder(currentOrder),
                          icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
                          label: const Text('Cancel Order', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _reorder(currentOrder),
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: const Text('Reorder Items', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}
