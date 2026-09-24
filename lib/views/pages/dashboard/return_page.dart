import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/imageviewer_page.dart';
import 'package:intl/intl.dart';

class ReturnPage extends StatefulWidget {
  const ReturnPage({super.key, required this.recID, required this.delivery});

  final Delivery delivery;
  final String recID;

  @override
  State<ReturnPage> createState() => _ReturnPageState();
}

class _ReturnPageState extends State<ReturnPage> {
  final DeliveryService db = DeliveryService();
  bool _isProcessing = false;

  void onUpdate({DateTime? rescheduleDate}) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final targetDate = rescheduleDate != null ? Timestamp.fromDate(rescheduleDate) : Timestamp.now();
      final updatedDelivery = widget.delivery.copyWith(
        storeName: widget.delivery.storeName,
        remarks: '',
        transactionStatus: DeliveryStatus.pending,
        orderAmount: widget.delivery.orderAmount,
        returnAmount: 0,
        creditAmount: widget.delivery.creditAmount,
        cashAmount: widget.delivery.cashAmount,
        onlineAmount: widget.delivery.onlineAmount,
        deliveryDate: targetDate,
        creditStatus: '',
        createdBy: widget.delivery.createdBy,
        lastUpdatedBy: authService.value.currentUser?.displayName ?? authService.value.currentUser?.email ?? 'Admin',
        createdDate: widget.delivery.createdDate,
        lastupdatedDate: Timestamp.now(),
      );

      db.updateDelivery(widget.recID, updatedDelivery);
      if (!mounted) return;
      ShowMessage.success(context, 'Successfully rescheduled delivery for [${updatedDelivery.storeName}]!');

      Navigator.pop(context);

      await Helperfunctions.logUpdate('[REDELIVER] ${widget.delivery.storeName}', widget.delivery.toJson(), updatedDelivery.toJson());
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to reschedule delivery: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void onDelete() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      if (widget.delivery.imagePath.isNotEmpty) {
        await Helperfunctions.deleteImage(context, widget.delivery.imagePath);
      }

      db.deleteDelivery(widget.recID);
      if (!mounted) return;
      ShowMessage.success(context, 'Successfully deleted delivery record!\n[${widget.delivery.storeName}]');

      Navigator.pop(context);

      await Helperfunctions.logDelete('[DELETE] ${widget.delivery.storeName}', widget.delivery.toJson());
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to delete record: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _showRedeliverDialog() async {
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
                  Text('Reset status to Pending for ${widget.delivery.storeName}.', style: const TextStyle(fontSize: 13.5)),
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

  Widget _buildAuditCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.history, size: 18, color: colorScheme.primary),
        ),
        title: const Text('Audit & History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        initiallyExpanded: false,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                _buildAuditRow('Created By', widget.delivery.createdBy),
                _buildAuditRow('Created Date', DateFormat('E, d MMM yyyy, hh:mm a').format(widget.delivery.createdDate.toDate())),
                const Divider(height: 12),
                _buildAuditRow('Last Updated By', widget.delivery.lastUpdatedBy),
                _buildAuditRow('Last Updated Date', DateFormat('E, d MMM yyyy, hh:mm a').format(widget.delivery.lastupdatedDate.toDate())),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditRow(String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        ),
      ],
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
    final colorScheme = Theme.of(context).colorScheme;
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
            Expanded(
              flex: 1,
              child: OutlinedButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () async {
                        final confirmed = await ShowMessage.confirm(
                          context,
                          title: 'Delete Return Record',
                          message: 'Are you sure you want to permanently delete this return record for [${widget.delivery.storeName}]?',
                          isDestructive: true,
                          icon: Icons.delete_outline,
                          confirmText: 'Delete',
                        );
                        if (confirmed) onDelete();
                      },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 50.0),
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300, width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _isProcessing ? null : _showRedeliverDialog,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 50.0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isProcessing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.local_shipping_outlined, size: 20),
                label: Text(_isProcessing ? 'Processing...' : 'Redeliver Order', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(title: 'Return Details', subtitle: widget.delivery.storeName),
      bottomNavigationBar: _buildStickyBottomBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 16,
          children: [
            // 1. Return Overview Hero Card
            _buildReturnOverviewCard(),

            // 2. Remarks / Reason Card
            if (widget.delivery.remarks.isNotEmpty) _buildRemarksCard(),

            // 3. Proof of Return / Attachment Card
            if (widget.delivery.imagePath.isNotEmpty) _buildProofCard(),

            // 4. Payment breakdown if recorded
            _buildPaymentDetailsCard(),

            // 5. Audit & History Card
            _buildAuditCard(),
          ],
        ),
      ),
    );
  }
}
