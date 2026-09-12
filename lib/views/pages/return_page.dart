import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class ReturnPage extends StatefulWidget {
  const ReturnPage({super.key, required this.recID, required this.delivery});

  final String recID;
  final Delivery delivery;

  @override
  State<ReturnPage> createState() => _ReturnPageState();
}

class _ReturnPageState extends State<ReturnPage> {
  final DeliveryService db = DeliveryService();

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

            // 3. Audit & History Card
            _buildAuditCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildReturnOverviewCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200, width: 1.2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: Colors.deepOrange.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.assignment_return_outlined, color: Colors.deepOrange, size: 26),
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
                  const Text('Return Amount', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 2),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(
                      widget.delivery.returnAmount > 0 ? widget.delivery.returnAmount : widget.delivery.orderAmount,
                    ),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepOrange.shade700),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Return Date', style: TextStyle(fontSize: 12, color: Colors.black54)),
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
                onPressed: () async {
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
                onPressed: () async {
                  final confirmed = await ShowMessage.confirm(
                    context,
                    title: 'Redeliver Order',
                    message: 'Reset status to Pending and reschedule delivery for [${widget.delivery.storeName}]?',
                    icon: Icons.local_shipping_outlined,
                    confirmText: 'Redeliver',
                  );
                  if (confirmed) onUpdate();
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 50.0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.local_shipping_outlined, size: 20),
                label: const Text('Redeliver Order', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void onUpdate() async {
    Delivery updatedDelivery = widget.delivery.copyWith(
      storeName: widget.delivery.storeName,
      remarks: '',
      transactionStatus: DeliveryStatus.pending,
      orderAmount: widget.delivery.orderAmount,
      returnAmount: 0,
      creditAmount: widget.delivery.creditAmount,
      cashAmount: widget.delivery.cashAmount,
      onlineAmount: widget.delivery.onlineAmount,
      deliveryDate: Timestamp.now(),
      creditStatus: '',
      createdBy: widget.delivery.createdBy,
      lastUpdatedBy: authService.value.currentUser!.displayName!,
      createdDate: widget.delivery.createdDate,
      lastupdatedDate: Timestamp.now(),
    );
    db.updateDelivery(widget.recID, updatedDelivery);
    ShowMessage.success(context, 'Successfully rescheduled delivery for [${updatedDelivery.storeName}]!');

    Navigator.pop(context);

    await Helperfunctions.logTransaction(
      '[REDELIVER] ${widget.delivery.storeName}',
      'Status: ${updatedDelivery.transactionStatus}\nOrder Amount: ${Helperfunctions.formatDoubleAmountForDisplay(updatedDelivery.orderAmount)}',
      LogAction.update,
    );
  }

  void onDelete() async {
    db.deleteDelivery(widget.recID);
    ShowMessage.success(context, 'Successfully deleted delivery record!\n[${widget.delivery.storeName}]');

    Navigator.pop(context);

    await Helperfunctions.logTransaction(
      '[DELETE] ${widget.delivery.storeName}',
      'Order Amount: ${Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.orderAmount)}',
      LogAction.delete,
    );
  }
}
