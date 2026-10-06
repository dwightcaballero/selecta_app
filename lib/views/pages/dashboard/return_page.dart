import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/return_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/audithistory_widget.dart';
import 'package:selecta_ops/views/widgets/digital_receipt_dialog.dart';
import 'package:selecta_ops/views/widgets/imageviewer_page.dart';
import 'package:intl/intl.dart';

/// Presentation view for inspecting, redelivering, or deleting a returned delivery order.
///
/// Authentication checks, model updates, image deletions, and service interactions
/// are delegated to [ReturnController].
class ReturnPage extends StatefulWidget {
  const ReturnPage({super.key, required this.recID, required this.delivery});

  final Delivery delivery;
  final String recID;

  @override
  State<ReturnPage> createState() => _ReturnPageState();
}

class _ReturnPageState extends State<ReturnPage> {
  final ReturnController _controller = ReturnController();
  late Delivery _delivery;
  bool _isProcessing = false;
  bool _isDealer = false;

  @override
  void initState() {
    super.initState();
    _delivery = widget.delivery;
    prefetchData();
  }

  void prefetchData() async {
    final dealer = await _controller.checkIsDealer();
    if (mounted) {
      setState(() {
        _isDealer = dealer;
      });
    }
  }

  void onApproveReturn() async {
    if (!_isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to approve returned stock.');
      return;
    }
    if (_isProcessing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warehouse_rounded, color: Color(0xFF15803D)),
            SizedBox(width: 8),
            Text('Approve Returned Stock', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Confirm that returned products for [${_delivery.storeName}] have physically arrived and been checked into the warehouse?\n\nThis will move the returned stock from Incoming Stock into Current Stock.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF15803D)),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Approve by Dealer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);
    try {
      final updated = await _controller.approveReturnedStock(
        deliveryId: widget.recID,
        delivery: _delivery,
      );
      if (!mounted) return;
      setState(() {
        _delivery = updated;
      });
      ShowMessage.success(context, 'Returned stock approved and added to Current Stock!');
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to approve return: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void onUpdate({DateTime? rescheduleDate}) async {
    if (!_isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to redeliver orders.');
      return;
    }
    if (!_delivery.isReturnApprovedByDealer) {
      ShowMessage.error(context, 'Dealer approval is required before rescheduling. Please approve the return first.');
      return;
    }
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final updatedDelivery = await _controller.rescheduleDelivery(
        deliveryId: widget.recID,
        delivery: _delivery,
        rescheduleDate: rescheduleDate,
      );

      if (!mounted) return;
      setState(() {
        _delivery = updatedDelivery;
      });
      ShowMessage.success(context, 'Successfully rescheduled delivery for [${updatedDelivery.storeName}]!');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to reschedule delivery: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void onFinalizeReturn() async {
    if (!_isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to finalize return records.');
      return;
    }
    if (!_delivery.isReturnApprovedByDealer) {
      ShowMessage.error(context, 'Dealer approval is required before finalizing. Please approve the return first.');
      return;
    }
    if (_delivery.isReturnFinalized) {
      ShowMessage.info(context, 'This return has already been finalized.');
      return;
    }
    if (_isProcessing) return;

    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Finalize Return',
      message:
          'Returned items for [${_delivery.storeName}] have already been checked into Current Stock in the warehouse.\n\n'
          'Finalizing this return will close the transaction as cancelled and clear it from active returns.\n\n'
          'Do you want to finalize this return?',
      confirmText: 'Finalize Return',
      icon: Icons.archive_outlined,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      final updatedDelivery = await _controller.finalizeReturn(
        deliveryId: widget.recID,
        delivery: _delivery,
      );

      if (!mounted) return;
      setState(() {
        _delivery = updatedDelivery;
      });
      ShowMessage.success(context, 'Successfully finalized return for [${updatedDelivery.storeName}]!');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to finalize return: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void onDelete() async {
    if (!_isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to delete return records.');
      return;
    }
    if (_delivery.isReturnApprovedByDealer) {
      ShowMessage.error(context, 'Cannot delete a return record after it has already been approved by dealer.');
      return;
    }
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      await _controller.deleteReturn(
        context: context,
        deliveryId: widget.recID,
        delivery: _delivery,
      );

      if (!mounted) return;
      ShowMessage.success(context, 'Successfully deleted delivery record!\n[${_delivery.storeName}]');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to delete record: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _showRedeliverDialog() async {
    if (!_isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to reschedule deliveries.');
      return;
    }
    if (!_delivery.isReturnApprovedByDealer) {
      ShowMessage.error(context, 'Dealer approval is required before rescheduling. Please click "Approved by Dealer" first.');
      return;
    }
    DateTime selectedDate = DateTime.now();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        DateTime tempDate = selectedDate;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.local_shipping_outlined, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('Reschedule Delivery', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reschedule this returned order to a new delivery date. A new Booked order will be created with reserved stock so warehouse staff can prepare its picklist.',
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  const SizedBox(height: 16),
                  const Text('Scheduled Date:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: tempDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 7)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setModalState(() {
                          tempDate = picked;
                        });
                        selectedDate = picked;
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(DateFormat('EEEE, d MMM yyyy').format(tempDate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                          const Spacer(),
                          const Icon(Icons.edit_calendar_outlined, size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm Redelivery')),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      onUpdate(rescheduleDate: selectedDate);
    }
  }

  Widget _buildReturnOverviewCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final displayAmount = widget.delivery.returnAmount > 0 ? widget.delivery.returnAmount : widget.delivery.orderAmount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1.2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(Icons.assignment_return_outlined, color: colorScheme.primary, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.delivery.storeName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      'Original Order: ${Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.orderAmount)}',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Return Amount', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(displayAmount),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Return Date', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_month_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        Helperfunctions.formatTimestampForDisplay(widget.delivery.lastupdatedDate),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRemarksCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.notes_outlined, size: 18, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                const Text('Return Reason & Remarks', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10)),
              child: Text(widget.delivery.remarks, style: const TextStyle(fontSize: 14, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildReturnedItemsCard() {
    if (_delivery.items.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    final isFullReturn = _delivery.transactionStatus == DeliveryStatus.returned;
    final returnedItems = _delivery.items.where((item) {
      return item.returnedQuantity > 0 || (isFullReturn && item.pickedQuantity > 0);
    }).toList();

    if (returnedItems.isEmpty) return const SizedBox.shrink();

    final totalReturnedQty = returnedItems.fold<int>(
      0,
      (sum, item) => sum + (item.returnedQuantity > 0 ? item.returnedQuantity : item.pickedQuantity),
    );

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.inventory_2_outlined, size: 18, color: colorScheme.primary),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Returned Products',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    '$totalReturnedQty units',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: returnedItems.length,
              separatorBuilder: (context, index) => const Divider(height: 12),
              itemBuilder: (context, index) {
                final item = returnedItems[index];
                final qty = item.returnedQuantity > 0 ? item.returnedQuantity : item.pickedQuantity;
                final lineTotal = item.returnedLineTotal > 0 ? item.returnedLineTotal : (qty * item.sellingPrice);

                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productName,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '₱${Helperfunctions.formatDoubleAmountForDisplay(item.sellingPrice)} each',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₱${Helperfunctions.formatDoubleAmountForDisplay(lineTotal)}',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$qty returned',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProofCard() {
    if (widget.delivery.imagePath.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.photo_library_outlined, size: 18, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                const Text('Proof of Return / Attachment', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => Helperfunctions.navigateTo(context, ImageViewerPage(image: null, networkImagePath: widget.delivery.imagePath)),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.network(
                      widget.delivery.imagePath,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        height: 120,
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image_outlined, size: 36, color: colorScheme.onSurfaceVariant),
                            const SizedBox(height: 4),
                            Text('Unable to load image', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          height: 180,
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                          alignment: Alignment.center,
                          child: const Center(child: CircularProgressIndicator()),
                        );
                      },
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(20)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.zoom_in, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Tap to view full image',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentDetailsCard() {
    final d = widget.delivery;
    if (d.cashAmount == 0 && d.onlineAmount == 0 && d.creditAmount == 0) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.payments_outlined, size: 18, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                const Text('Payment Settlement Recorded', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 20),
            if (d.cashAmount > 0) _buildAmountRow('Cash Paid', d.cashAmount, colorScheme.primary),
            if (d.onlineAmount > 0) _buildAmountRow('Online Paid', d.onlineAmount, colorScheme.primary),
            if (d.creditAmount > 0) _buildAmountRow('Credit / AR', d.creditAmount, Colors.orange.shade800),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountRow(String label, double amount, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.black87)),
          Text(
            Helperfunctions.formatDoubleAmountForDisplay(amount),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyBottomBar() {
    if (!_isDealer) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    final isApproved = _delivery.isReturnApprovedByDealer;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1.0)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -2), blurRadius: 6)],
        ),
        child: Row(
          children: [
            if (!isApproved) ...[
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: (_isProcessing || _delivery.isInventorySettled)
                      ? null
                      : () async {
                          final confirmed = await ShowMessage.confirm(
                            context,
                            title: 'Delete Return Record',
                            message: 'Are you sure you want to permanently delete this return record for [${_delivery.storeName}]?',
                            isDestructive: true,
                            icon: Icons.delete_outline,
                            confirmText: 'Delete',
                          );
                          if (confirmed) onDelete();
                        },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 50.0),
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(
                      color: _delivery.isInventorySettled ? Colors.grey.shade300 : Colors.red.shade300,
                      width: 1.2,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed: _isProcessing ? null : onApproveReturn,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF15803D),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 50.0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isProcessing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline, size: 20),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Approved by Dealer',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ] else if (_delivery.isReturnFinalized) ...[
              Expanded(
                child: Container(
                  height: 50.0,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, color: Colors.grey.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Return Finalized (Stock in Warehouse)',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade800, fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (_delivery.isRescheduled) ...[
              Expanded(
                child: Container(
                  height: 50.0,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Already Rescheduled (New Order Created)',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade800, fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Expanded(
                flex: 1,
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : onFinalizeReturn,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 50.0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    foregroundColor: Colors.orange.shade800,
                    side: BorderSide(color: Colors.orange.shade400, width: 1.2),
                  ),
                  icon: const Icon(Icons.archive_outlined, size: 20),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Finalize Return',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: FilledButton.icon(
                  onPressed: _isProcessing ? null : _showRedeliverDialog,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 50.0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isProcessing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.local_shipping_outlined, size: 20),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Redeliver Order',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(
        title: 'Return Details',
        subtitle: _delivery.storeName,
        actions: [
          if (_delivery.items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.receipt_long_rounded, color: Colors.white),
              tooltip: 'Digital Receipt & Thermal Print',
              onPressed: () => DigitalReceiptDialog.show(
                context,
                delivery: _delivery,
                deliveryId: widget.recID,
                proceedLabel: 'Close',
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildStickyBottomBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 16,
          children: [
            if (!_isDealer)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300, width: 1.2),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, color: Colors.amber.shade900, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'View-Only: Only dealers are authorized to approve returned stock, redeliver, or delete returned orders.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_delivery.isReturnFinalized)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300, width: 1.2),
                ),
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: Colors.grey.shade700, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Return Finalized (Completed)',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Returned stock was physically checked into the warehouse by ${_delivery.returnApprovedBy.isNotEmpty ? _delivery.returnApprovedBy : "Dealer"}. This order has been finalized and closed${_delivery.returnFinalizedBy.isNotEmpty ? " by ${_delivery.returnFinalizedBy}" : ""}${_delivery.returnFinalizedDate != null ? " on ${DateFormat('MMM d, yyyy h:mm a').format(_delivery.returnFinalizedDate!.toDate())}" : ""}.',
                            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else if (_delivery.isRescheduled)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade300, width: 1.2),
                ),
                child: Row(
                  children: [
                    Icon(Icons.local_shipping_outlined, color: Colors.blue.shade700, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rescheduled for Redelivery',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'A new delivery order has been booked in Pending Picklist${_delivery.rescheduledDate != null ? " for ${DateFormat('MMM d, yyyy').format(_delivery.rescheduledDate!.toDate())}" : ""}. Warehouse staff will prepare the picklist for redelivery.',
                            style: TextStyle(fontSize: 12.5, color: Colors.blue.shade800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else if (_delivery.isReturnApprovedByDealer)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade300, width: 1.2),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Approved by Dealer',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Returned stock was physically checked into the warehouse by ${_delivery.returnApprovedBy.isNotEmpty ? _delivery.returnApprovedBy : "Dealer"}${_delivery.returnApprovedDate != null ? " on ${DateFormat('MMM d, yyyy h:mm a').format(_delivery.returnApprovedDate!.toDate())}" : ""}. Items are now in Current Stock. You can now Redeliver or Finalize this return below.',
                            style: TextStyle(fontSize: 12.5, color: Colors.green.shade800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3), width: 1.2),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFF0369A1), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Incoming Return Stock',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0369A1)),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Returned stock is counted as Incoming Stock. Click "Approved by Dealer" below once the items physically arrive and are verified in the warehouse to add them to Current Stock.',
                            style: TextStyle(fontSize: 12.5, color: Color(0xFF0C4A6E)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (_delivery.isRescheduled)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade300, width: 1.2),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade900, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This return has already been rescheduled to a new delivery scheduled for ${_delivery.rescheduledDate != null ? DateFormat('MMM d, yyyy').format(_delivery.rescheduledDate!.toDate()) : 'a future date'}.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 1. Return Overview Hero Card
            _buildReturnOverviewCard(),

            // 2. Returned Products Card
            _buildReturnedItemsCard(),

            // 3. Remarks / Reason Card
            if (widget.delivery.remarks.isNotEmpty) _buildRemarksCard(),

            // 4. Proof of Return / Attachment Card
            if (widget.delivery.imagePath.isNotEmpty) _buildProofCard(),

            // 5. Payment breakdown if recorded
            _buildPaymentDetailsCard(),

            // 5. Audit & History Card
            AuditHistoryWidget(
              createdBy: widget.delivery.createdBy,
              createdDate: widget.delivery.createdDate,
              createdPage: widget.delivery.createdPage,
              lastUpdatedBy: widget.delivery.lastUpdatedBy,
              lastUpdatedDate: widget.delivery.lastupdatedDate,
              lastUpdatedPage: widget.delivery.lastUpdatedPage,
            ),
          ],
        ),
      ),
    );
  }
}
