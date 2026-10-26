import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/store_order_controller.dart';
import 'package:selecta_ops/models/store_order.dart';
import 'package:selecta_ops/services/store_order_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';

/// Dealer Review & Approval Page for Hapi Store Orders.
/// Empowers dealers to:
/// - Adjust approved quantities per item for stock shortages
/// - Pick the mandatory delivery date
/// - Recompute approved totals against real-time catalog prices
/// - Approve (creates Delivery doc & reserves stock) or Reject with reason
class DealerStoreOrderReviewPage extends StatefulWidget {
  final String orderId;
  final StoreOrder? order;

  const DealerStoreOrderReviewPage({
    super.key,
    required this.orderId,
    this.order,
  });

  @override
  State<DealerStoreOrderReviewPage> createState() => _DealerStoreOrderReviewPageState();
}

class _DealerStoreOrderReviewPageState extends State<DealerStoreOrderReviewPage> {
  final StoreOrderController _orderController = StoreOrderController();

  final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final _dateFormat = DateFormat('MMM dd, yyyy • hh:mm a');
  final _dateOnlyFormat = DateFormat('EEEE, MMMM dd, yyyy');

  DateTime? _selectedDeliveryDate;
  final Map<String, int> _approvedQuantities = {};
  bool _initialized = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    if (widget.order != null) {
      _initOrderState(widget.order!);
    }
  }

  void _initOrderState(StoreOrder order) {
    if (_initialized) return;
    _initialized = true;

    // Initialize delivery date: existing if set, otherwise tomorrow
    if (order.deliveryDate != null) {
      _selectedDeliveryDate = order.deliveryDate!.toDate();
    } else {
      _selectedDeliveryDate = DateTime.now().add(const Duration(days: 1));
    }

    // Initialize approved quantities
    for (int i = 0; i < order.items.length; i++) {
      final item = order.items[i];
      final key = '${item.productId}_${item.packaging}_$i';
      _approvedQuantities[key] = item.qtyApproved > 0 ? item.qtyApproved : item.qtyOrdered;
    }
  }

  double _calculateApprovedTotal(StoreOrder order) {
    double total = 0.0;
    for (int i = 0; i < order.items.length; i++) {
      final item = order.items[i];
      final key = '${item.productId}_${item.packaging}_$i';
      final qty = _approvedQuantities[key] ?? item.qtyOrdered;
      total += qty * item.unitPrice;
    }
    return total;
  }

  int _calculateApprovedTotalQty(StoreOrder order) {
    int total = 0;
    for (int i = 0; i < order.items.length; i++) {
      final item = order.items[i];
      final key = '${item.productId}_${item.packaging}_$i';
      total += (_approvedQuantities[key] ?? item.qtyOrdered);
    }
    return total;
  }

  Future<void> _pickDeliveryDate(BuildContext context) async {
    final now = DateTime.now();
    final initial = _selectedDeliveryDate ?? now.add(const Duration(days: 1));
    final firstDate = DateTime(now.year, now.month, now.day);
    final lastDate = now.add(const Duration(days: 90));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(firstDate) ? firstDate : initial,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'SELECT SCHEDULED DELIVERY DATE',
    );

    if (picked != null) {
      setState(() => _selectedDeliveryDate = picked);
    }
  }

  Future<void> _onApprove(StoreOrder order) async {
    if (_selectedDeliveryDate == null) {
      ShowMessage.error(context, 'Please select a delivery date before approving.');
      return;
    }

    final totalApprovedQty = _calculateApprovedTotalQty(order);
    if (totalApprovedQty <= 0) {
      ShowMessage.error(
        context,
        'Cannot approve order with 0 total quantity. Please reject the order if all items are unavailable.',
      );
      return;
    }

    final approvedItems = <StoreOrderItem>[];
    for (int i = 0; i < order.items.length; i++) {
      final item = order.items[i];
      final key = '${item.productId}_${item.packaging}_$i';
      final approvedQty = _approvedQuantities[key] ?? item.qtyOrdered;

      approvedItems.add(
        item.copyWith(
          qtyApproved: approvedQty,
          lineTotal: approvedQty * item.unitPrice,
        ),
      );
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Approve Store Order', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to approve this order for ${order.storeName}?'),
            const SizedBox(height: 12),
            Text('• Scheduled Delivery: ${_dateOnlyFormat.format(_selectedDeliveryDate!)}'),
            Text('• Approved Items: $totalApprovedQty units'),
            Text('• Approved Total: ${_currency.format(_calculateApprovedTotal(order))}'),
            const SizedBox(height: 12),
            const Text(
              'Approving will automatically create a pre-sell Delivery and reserve inventory.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm Approval'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      await _orderController.approveOrder(
        orderId: order.id,
        deliveryDate: _selectedDeliveryDate!,
        approvedItems: approvedItems,
      );

      if (!mounted) return;
      ShowMessage.success(context, 'Order ${order.orderNo} approved successfully!');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Approval failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _onReject(StoreOrder order) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Store Order', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Please specify why order ${order.orderNo} is being rejected:'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'e.g. Products temporarily out of stock, unserviceable location...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ShowMessage.error(ctx, 'Please enter a rejection reason.');
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Reject Order'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      await _orderController.rejectOrder(
        orderId: order.id,
        reason: reasonController.text.trim(),
      );

      if (!mounted) return;
      ShowMessage.success(context, 'Order ${order.orderNo} rejected.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Rejection failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
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

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection(STORE_ORDERS_COLLECTION)
          .doc(widget.orderId)
          .snapshots(),
      builder: (context, snapshot) {
        StoreOrder? currentOrder = widget.order;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          currentOrder = StoreOrder.fromJson(data, id: snapshot.data!.id);
        }

        if (currentOrder == null) {
          return const Scaffold(
            appBar: CustomAppbar(title: 'Review Order', subtitle: 'Store Order'),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final order = currentOrder;
        _initOrderState(order);

        final isSubmitted = order.status == StoreOrderStatus.submitted;
        final approvedTotal = _calculateApprovedTotal(order);
        final totalApprovedUnits = _calculateApprovedTotalQty(order);
        final statusColor = _getStatusColor(order.status);
        final statusIcon = _getStatusIcon(order.status);

        return Scaffold(
          appBar: CustomAppbar(
            title: 'Review: ${order.orderNo}',
            subtitle: order.storeName,
            showBackButton: true,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Container(
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
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            children: [
              // Store & Placement Header Card
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
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.storefront_rounded, color: colorScheme.primary, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                order.storeName,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Ordered ${_dateFormat.format(order.createdAt.toDate())}',
                                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (order.remarks != null && order.remarks!.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1, color: cardBorder),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.comment_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Store Remarks: ${order.remarks!}',
                              style: TextStyle(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (order.rejectReason != null && order.rejectReason!.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1, color: cardBorder),
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Rejection Reason: ${order.rejectReason!}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.red,
                                  fontWeight: FontWeight.w500,
                                ),
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

              // Delivery Date Selector Card (Mandatory for Approval)
              Container(
                decoration: BoxDecoration(
                  color: isSubmitted
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.08)
                      : cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSubmitted
                        ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                        : cardBorder,
                  ),
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
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 18,
                          color: isSubmitted ? const Color(0xFFF59E0B) : colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Scheduled Delivery Date',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isSubmitted ? const Color(0xFFF59E0B) : colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (isSubmitted)
                          InkWell(
                            onTap: () => _pickDeliveryDate(context),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit_calendar_rounded, size: 14, color: colorScheme.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Change',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selectedDeliveryDate != null
                          ? _dateOnlyFormat.format(_selectedDeliveryDate!)
                          : 'No date assigned yet',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    if (isSubmitted) ...[
                      const SizedBox(height: 4),
                      Text(
                        'The pre-sell delivery will be scheduled for this date and routed to the assigned salesman.',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Items & Line-by-Line Quantity Review Card
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
                        const Text(
                          'Order Items Review',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        if (isSubmitted)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2A3444) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Adjust qty for shortages',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: order.items.length,
                      separatorBuilder: (context, index) => Divider(height: 20, color: cardBorder),
                      itemBuilder: (context, idx) {
                        final item = order.items[idx];
                        final key = '${item.productId}_${item.packaging}_$idx';
                        final currentApprovedQty = _approvedQuantities[key] ?? item.qtyOrdered;
                        final isAdjusted = currentApprovedQty != item.qtyOrdered;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Full width Product Name
                            Text(
                              item.productName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 6),
                            // 2. Bottom Row: Packaging & Unit Price (Left) + Quantity Stepper & Line Total (Right)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF2A3444) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    item.packaging,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${_currency.format(item.unitPrice)} each',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const Spacer(),
                                // Quantity Adjuster (Editable if Submitted, static otherwise)
                                if (isSubmitted)
                                  Container(
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: cardBorder),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        InkWell(
                                          onTap: currentApprovedQty > 0
                                              ? () => setState(() => _approvedQuantities[key] = currentApprovedQty - 1)
                                              : null,
                                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                                          child: Padding(
                                            padding: const EdgeInsets.all(5),
                                            child: Icon(
                                              Icons.remove_rounded,
                                              size: 18,
                                              color: currentApprovedQty > 0
                                                  ? colorScheme.onSurface
                                                  : colorScheme.onSurface.withValues(alpha: 0.3),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          constraints: const BoxConstraints(minWidth: 26),
                                          alignment: Alignment.center,
                                          child: Text(
                                            '$currentApprovedQty',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: isAdjusted ? const Color(0xFFF59E0B) : null,
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () => setState(() => _approvedQuantities[key] = currentApprovedQty + 1),
                                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                                          child: Padding(
                                            padding: const EdgeInsets.all(5),
                                            child: Icon(
                                              Icons.add_rounded,
                                              size: 18,
                                              color: colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Text(
                                    '${item.effectiveQty} ${item.packaging.toLowerCase()}s',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                const SizedBox(width: 12),
                                // Line Total
                                ConstrainedBox(
                                  constraints: const BoxConstraints(minWidth: 70),
                                  child: Text(
                                    _currency.format(
                                      (isSubmitted ? currentApprovedQty : item.effectiveQty) * item.unitPrice,
                                    ),
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // Adjustment note if changed
                            if (isAdjusted) ...[
                              const SizedBox(height: 5),
                              Text(
                                'Requested: ${item.qtyOrdered} • Approved: $currentApprovedQty',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: currentApprovedQty < item.qtyOrdered
                                      ? Colors.red
                                      : const Color(0xFF3B82F6),
                                ),
                              ),
                            ],
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
                        Text('Original Estimated Total:', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                        Text(
                          _currency.format(order.totalAmount),
                          style: TextStyle(
                            fontSize: 13,
                            decoration: (isSubmitted && approvedTotal != order.totalAmount)
                                ? TextDecoration.lineThrough
                                : null,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isSubmitted ? 'Approved Total ($totalApprovedUnits units):' : 'Final Amount:',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _currency.format(isSubmitted ? approvedTotal : order.effectiveAmount),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Status History Timeline
              if (order.statusHistory.isNotEmpty) ...[
                const SizedBox(height: 14),
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
                      const Text(
                        'Order Timeline',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ...order.statusHistory.map((h) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(top: 5),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${h.status} by ${h.byName.isNotEmpty ? h.byName : 'User'}',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                    Text(
                                      _dateFormat.format(h.timestamp),
                                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 90),
            ],
          ),

          // Action Buttons: Approve and Reject (Only while Submitted)
          bottomNavigationBar: isSubmitted
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: cardBg,
                    border: Border(top: BorderSide(color: cardBorder)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        // Reject Button
                        Expanded(
                          flex: 1,
                          child: OutlinedButton(
                            onPressed: _isProcessing ? null : () => _onReject(order),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Approve Button
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: _isProcessing ? null : () => _onApprove(order),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isProcessing
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.check_circle_outline_rounded, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Approve (${_currency.format(approvedTotal)})',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }
}
