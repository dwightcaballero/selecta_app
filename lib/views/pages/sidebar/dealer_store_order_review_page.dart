import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/store_order_controller.dart';
import 'package:selecta_ops/models/store_order.dart';
import 'package:selecta_ops/services/store_order_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';

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
        title: const Text('Approve Store Order'),
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
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
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
        title: const Text('Reject Store Order'),
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
              decoration: const InputDecoration(
                hintText: 'e.g. Products temporarily out of stock, unserviceable location...',
                border: OutlineInputBorder(),
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
          return Scaffold(
            appBar: AppBar(title: const Text('Review Order')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final order = currentOrder;
        _initOrderState(order);

        final isSubmitted = order.status == StoreOrderStatus.submitted;
        final approvedTotal = _calculateApprovedTotal(order);
        final totalApprovedUnits = _calculateApprovedTotalQty(order);

        return Scaffold(
          appBar: AppBar(
            title: Text('Review: ${order.orderNo}'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: _buildStatusBadge(order.status)),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Store & Placement Header Card
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: colorScheme.primaryContainer,
                            child: Icon(Icons.storefront, color: colorScheme.onPrimaryContainer),
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
                        const Divider(height: 24),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.comment_outlined, size: 16, color: Colors.blueGrey),
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
                        const Divider(height: 24),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.cancel_outlined, size: 18, color: Colors.red.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Rejection Reason: ${order.rejectReason!}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.red.shade900,
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
              ),

              const SizedBox(height: 16),

              // Delivery Date Selector Card (Mandatory for Approval)
              Card(
                elevation: 0,
                color: isSubmitted ? Colors.amber.shade50 : colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isSubmitted
                        ? Colors.amber.shade400
                        : colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 18,
                                color: isSubmitted ? Colors.amber.shade900 : colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Scheduled Delivery Date',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: isSubmitted ? Colors.amber.shade900 : colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                          if (isSubmitted)
                            TextButton.icon(
                              onPressed: () => _pickDeliveryDate(context),
                              icon: const Icon(Icons.edit_calendar, size: 16),
                              label: const Text('Change Date'),
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
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Items & Line-by-Line Quantity Review Card
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                ),
                child: Padding(
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
                                color: colorScheme.surfaceContainerHighest,
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
                        separatorBuilder: (context, index) => const Divider(height: 20),
                        itemBuilder: (context, idx) {
                          final item = order.items[idx];
                          final key = '${item.productId}_${item.packaging}_$idx';
                          final currentApprovedQty = _approvedQuantities[key] ?? item.qtyOrdered;
                          final isAdjusted = currentApprovedQty != item.qtyOrdered;

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Product Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.productName,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${item.packaging} • ${_currency.format(item.unitPrice)} each',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    if (isAdjusted) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        'Requested: ${item.qtyOrdered} • Approved: $currentApprovedQty',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: currentApprovedQty < item.qtyOrdered
                                              ? Colors.red.shade700
                                              : Colors.blue.shade700,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              // Quantity Adjuster (Editable if Submitted, static otherwise)
                              if (isSubmitted)
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, size: 22),
                                      onPressed: currentApprovedQty > 0
                                          ? () => setState(() => _approvedQuantities[key] = currentApprovedQty - 1)
                                          : null,
                                    ),
                                    Container(
                                      constraints: const BoxConstraints(minWidth: 28),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '$currentApprovedQty',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: isAdjusted ? Colors.amber.shade900 : null,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline, size: 22),
                                      onPressed: () => setState(() => _approvedQuantities[key] = currentApprovedQty + 1),
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  '${item.effectiveQty} ${item.packaging.toLowerCase()}s',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),

                              // Line Total
                              SizedBox(
                                width: 84,
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
                          );
                        },
                      ),

                      const Divider(height: 24),

                      // Totals Summary
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Original Estimated Total:'),
                          Text(
                            _currency.format(order.totalAmount),
                            style: TextStyle(
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
                            isSubmitted ? 'Approved Total ($totalApprovedUnits pcs):' : 'Final Amount:',
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
              ),

              // Status History Timeline
              if (order.statusHistory.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                  ),
                  child: Padding(
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
                                const Icon(Icons.circle, size: 8, color: Colors.blueGrey),
                                const SizedBox(width: 8),
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
                ),
              ],

              const SizedBox(height: 80),
            ],
          ),

          // Action Buttons: Approve and Reject (Only while Submitted)
          bottomNavigationBar: isSubmitted
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4))),
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
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 14),
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
                                      const Icon(Icons.check_circle_outline, size: 18),
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

  Widget _buildStatusBadge(String status) {
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
