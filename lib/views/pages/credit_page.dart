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

class CreditPage extends StatefulWidget {
  const CreditPage({super.key, required this.recID, required this.delivery});

  final String recID;
  final Delivery delivery;

  @override
  State<CreditPage> createState() => _CreditPageState();
}

class _CreditPageState extends State<CreditPage> {
  final DeliveryService db = DeliveryService();
  late String _selectedStatus;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.delivery.creditStatus.isNotEmpty ? widget.delivery.creditStatus : CreditStatus.unpaid;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(title: 'Credit Settlement', subtitle: widget.delivery.storeName),
      bottomNavigationBar: _buildStickyBottomBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 16,
          children: [
            // 1. Credit Overview Card
            _buildCreditOverviewCard(),

            // 2. Status Selector Card
            _buildStatusCard(),

            // 3. Audit History Card
            _buildAuditCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
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
                  child: Icon(icon, size: 18, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildCreditOverviewCard() {
    final colorScheme = Theme.of(context).colorScheme;
    bool isUnpaid = _selectedStatus == CreditStatus.unpaid;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: isUnpaid ? Colors.red.withValues(alpha: 0.05) : Colors.green.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isUnpaid ? Colors.red.shade200 : Colors.green.shade200, width: 1.2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(Icons.storefront_outlined, color: colorScheme.primary, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.delivery.storeName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      'Delivery Order: ${Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.orderAmount)}',
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
                  const Text('Credit Amount', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 2),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.creditAmount),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isUnpaid ? Colors.red.shade700 : Colors.green.shade700),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Credit Date', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_month_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        widget.delivery.deliveryDate != null ? Helperfunctions.formatDateForDisplay(widget.delivery.deliveryDate!.toDate()) : 'N/A',
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

  Widget _buildStatusCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return _buildSectionCard(
      title: 'Payment Status',
      icon: Icons.payments_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select whether this credit has been fully settled:', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              segments: [
                ButtonSegment<String>(
                  value: CreditStatus.unpaid,
                  label: const Text(CreditStatus.unpaid, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  icon: Icon(
                    Icons.hourglass_top_rounded,
                    size: 18,
                    color: _selectedStatus == CreditStatus.unpaid ? Colors.red.shade700 : colorScheme.onSurfaceVariant,
                  ),
                ),
                ButtonSegment<String>(
                  value: CreditStatus.paid,
                  label: const Text(CreditStatus.paid, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  icon: Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: _selectedStatus == CreditStatus.paid ? Colors.green.shade700 : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              selected: {_selectedStatus},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() {
                  _selectedStatus = newSelection.first;
                });
              },
            ),
          ),
        ],
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
        child: FilledButton.icon(
          onPressed: () async {
            final confirmed = await ShowMessage.confirm(
              context,
              title: ConfirmTitle.update,
              message: 'Update the credit status of [${widget.delivery.storeName}] to "$_selectedStatus"?',
              icon: Icons.check_circle_outline,
              confirmText: 'Update',
            );
            if (confirmed) onUpdate();
          },
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 50.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.check_circle_outline, size: 20),
          label: const Text('Update Credit Record', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  void onUpdate() {
    Delivery updatedDelivery = widget.delivery.copyWith(
      storeName: widget.delivery.storeName,
      remarks: widget.delivery.remarks,
      transactionStatus: widget.delivery.transactionStatus,
      orderAmount: widget.delivery.orderAmount,
      returnAmount: widget.delivery.returnAmount,
      creditAmount: widget.delivery.creditAmount,
      cashAmount: widget.delivery.cashAmount,
      onlineAmount: widget.delivery.onlineAmount,
      deliveryDate: widget.delivery.deliveryDate,
      creditStatus: _selectedStatus,
      createdBy: widget.delivery.createdBy,
      lastUpdatedBy: authService.value.currentUser!.displayName!,
      createdDate: widget.delivery.createdDate,
      lastupdatedDate: Timestamp.now(),
    );
    db.updateDelivery(widget.recID, updatedDelivery);
    ShowMessage.success(context, 'Successfully updated the credit status!\n[${updatedDelivery.storeName}]');
    Navigator.pop(context);
  }
}
