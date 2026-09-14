import 'package:flutter/material.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/purchaseorder.dart';
import 'package:flutter_app/services/purchaseorder_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class OverpaymentPage extends StatefulWidget {
  const OverpaymentPage({super.key, required this.purchaseorderID, required this.purchaseorder});

  final Purchaseorder purchaseorder;
  final String purchaseorderID;

  @override
  State<OverpaymentPage> createState() => _OverpaymentPageState();
}

class _OverpaymentPageState extends State<OverpaymentPage> {
  final PurchaseOrderService db = PurchaseOrderService();

  Future<void> _settleOverpayment() async {
    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Settle Overpayment',
      message: 'Mark this overpayment as settled?',
      icon: Icons.check_circle_outline,
      confirmText: 'Settle',
    );
    if (!confirmed || !mounted) return;

    widget.purchaseorder.isSettled = true;
    db.updatePurchaseorder(widget.purchaseorderID, widget.purchaseorder);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Overpayment settled successfully')));
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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

  Widget _buildOverviewCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200, width: 1.2),
      ),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.deepOrange, size: 28),
          ),
          const SizedBox(height: 12),
          const Text('Outstanding Overpayment', style: TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 3),
          Text(
            Helperfunctions.formatDoubleAmountForDisplay(widget.purchaseorder.overpayment),
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.deepOrange.shade700),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
            child: const Text(
              'Awaiting Settlement',
              style: TextStyle(color: Colors.deepOrange, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMetric('Order Date', Helperfunctions.formatTimestampForDisplay(widget.purchaseorder.orderDate), colorScheme),
              _buildMetric(
                'Invoice',
                widget.purchaseorder.invoiceNumber.isEmpty ? 'No reference' : widget.purchaseorder.invoiceNumber,
                colorScheme,
                alignEnd: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value, ColorScheme colorScheme, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildOrderDetailsCard() {
    return _buildSectionCard(
      title: 'Order & Invoice Details',
      icon: Icons.receipt_long_outlined,
      child: Column(
        children: [
          _buildDetailRow('Order Amount', Helperfunctions.formatDoubleAmountForDisplay(widget.purchaseorder.orderAmount)),
          _buildDetailRow('Invoice Amount', Helperfunctions.formatDoubleAmountForDisplay(widget.purchaseorder.invoiceAmount)),
          _buildDetailRow(
            'Overpayment',
            Helperfunctions.formatDoubleAmountForDisplay(widget.purchaseorder.overpayment),
            valueColor: Colors.deepOrange.shade700,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor),
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
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.history, size: 18, color: colorScheme.primary),
        ),
        title: const Text('Audit & History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAuditRow('Created By', widget.purchaseorder.createdBy),
                _buildAuditRow('Created Date', DateFormat('E, d MMM yyyy, hh:mm a').format(widget.purchaseorder.createdDate.toDate())),
                const Divider(height: 16),
                _buildAuditRow('Last Updated By', widget.purchaseorder.lastUpdatedBy),
                _buildAuditRow('Last Updated Date', DateFormat('E, d MMM yyyy, hh:mm a').format(widget.purchaseorder.lastupdatedDate.toDate())),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditRow(String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(title: 'Overpayment Details', subtitle: widget.purchaseorder.invoiceNumber),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6))),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -2), blurRadius: 6)],
          ),
          child: FilledButton.icon(
            onPressed: _settleOverpayment,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Settle Overpayment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 16,
          children: [_buildOverviewCard(), _buildOrderDetailsCard(), _buildAuditCard(), const SizedBox(height: 8)],
        ),
      ),
    );
  }
}
