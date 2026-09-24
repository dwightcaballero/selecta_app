import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/purchaseorder.dart';
import 'package:flutter_app/services/purchaseorder_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/imageviewer_page.dart';
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
  bool _isSettling = false;

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied to clipboard'), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating));
  }

  Future<void> _settleOverpayment() async {
    if (_isSettling || widget.purchaseorder.isSettled == true) return;

    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Settle Overpayment',
      message: 'Mark this overpayment as settled?',
      icon: Icons.check_circle_outline,
      confirmText: 'Settle',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isSettling = true);

    try {
      widget.purchaseorder.isSettled = true;
      db.updatePurchaseorder(widget.purchaseorderID, widget.purchaseorder);
      Helperfunctions.logUpdate(
        widget.purchaseorder.invoiceNumber.isNotEmpty
            ? widget.purchaseorder.invoiceNumber
            : Helperfunctions.formatTimestampForDisplay(widget.purchaseorder.orderDate),
        {...widget.purchaseorder.toJson(), 'isSettled': false},
        widget.purchaseorder.toJson(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Overpayment settled successfully')));
    } catch (e) {
      if (mounted) {
        setState(() => _isSettling = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error settling overpayment: $e')));
      }
    }
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
    final isSettled = widget.purchaseorder.isSettled == true;
    final invoiceNum = widget.purchaseorder.invoiceNumber.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isSettled ? Colors.green.withValues(alpha: 0.06) : colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSettled ? Colors.green.withValues(alpha: 0.3) : colorScheme.primary.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: isSettled ? Colors.green.withValues(alpha: 0.14) : colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSettled ? Icons.check_circle_outline : Icons.account_balance_wallet_outlined,
              color: isSettled ? Colors.green : colorScheme.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),
          Text(isSettled ? 'Settled Overpayment' : 'Outstanding Overpayment', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 3),
          Text(
            Helperfunctions.formatDoubleAmountForDisplay(widget.purchaseorder.overpayment),
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: isSettled ? Colors.green.shade700 : colorScheme.primary),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isSettled ? Colors.green.withValues(alpha: 0.14) : Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSettled ? Icons.check_circle : Icons.pending_actions,
                  size: 14,
                  color: isSettled ? Colors.green.shade700 : Colors.orange.shade800,
                ),
                const SizedBox(width: 4),
                Text(
                  isSettled ? 'Settled' : 'Awaiting Settlement',
                  style: TextStyle(
                    color: isSettled ? Colors.green.shade700 : Colors.orange.shade800,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMetric('Order Date', Helperfunctions.formatTimestampForDisplay(widget.purchaseorder.orderDate), colorScheme),
              _buildMetric('Invoice Date', Helperfunctions.formatTimestampForDisplay(widget.purchaseorder.invoiceDate), colorScheme),
              _buildMetric(
                'Invoice #',
                invoiceNum.isEmpty ? 'No reference' : invoiceNum,
                colorScheme,
                alignEnd: true,
                onTap: invoiceNum.isNotEmpty ? () => _copyToClipboard(invoiceNum, 'Invoice number') : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value, ColorScheme colorScheme, {bool alignEnd = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Column(
        crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              if (onTap != null) ...[const SizedBox(width: 4), Icon(Icons.copy, size: 12, color: colorScheme.onSurfaceVariant)],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderDetailsCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return _buildSectionCard(
      title: 'Order & Invoice Details',
      icon: Icons.receipt_long_outlined,
      child: Column(
        children: [
          _buildDetailRow('Order Amount', Helperfunctions.formatDoubleAmountForDisplay(widget.purchaseorder.orderAmount)),
          _buildDetailRow('Invoice Amount', Helperfunctions.formatDoubleAmountForDisplay(widget.purchaseorder.invoiceAmount)),
          _buildDetailRow(
            'Overpayment Difference',
            Helperfunctions.formatDoubleAmountForDisplay(widget.purchaseorder.overpayment),
            valueColor: colorScheme.primary,
          ),
          const SizedBox(height: 12),
          // Formula breakdown container
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildFormulaItem('Invoice', Helperfunctions.formatDoubleAmountForDisplay(widget.purchaseorder.invoiceAmount), colorScheme),
                Text(
                  '−',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                ),
                _buildFormulaItem('Order', Helperfunctions.formatDoubleAmountForDisplay(widget.purchaseorder.orderAmount), colorScheme),
                Text(
                  '=',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                ),
                _buildFormulaItem(
                  'Variance',
                  Helperfunctions.formatDoubleAmountForDisplay(widget.purchaseorder.overpayment),
                  colorScheme,
                  highlightColor: colorScheme.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormulaItem(String label, String value, ColorScheme colorScheme, {Color? highlightColor}) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: highlightColor ?? colorScheme.onSurface),
        ),
      ],
    );
  }

  Widget _buildAttachmentCard() {
    final imagePath = widget.purchaseorder.imagePath.trim();
    if (imagePath.isEmpty) return const SizedBox.shrink();

    return _buildSectionCard(
      title: 'Invoice Photo / Receipt',
      icon: Icons.image_outlined,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Helperfunctions.navigateTo(context, ImageViewerPage(image: null, networkImagePath: imagePath)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Image.network(
                imagePath,
                height: 190,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    height: 190,
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    child: const Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 130,
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image_outlined, size: 36, color: Colors.grey),
                        SizedBox(height: 6),
                        Text('Unable to preview invoice photo', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.zoom_in, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Tap to view full invoice photo',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
    final isSettled = widget.purchaseorder.isSettled == true;

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Overpayment Details',
        subtitle: widget.purchaseorder.invoiceNumber.isNotEmpty ? widget.purchaseorder.invoiceNumber : 'Purchase Order',
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6))),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -2), blurRadius: 6)],
          ),
          child: FilledButton.icon(
            onPressed: (isSettled || _isSettling) ? null : _settleOverpayment,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              backgroundColor: isSettled ? Colors.green.shade600 : null,
            ),
            icon: _isSettling
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(isSettled ? Icons.check_circle : Icons.check_circle_outline),
            label: Text(
              isSettled
                  ? 'Overpayment Settled'
                  : _isSettling
                  ? 'Settling Overpayment...'
                  : 'Settle Overpayment',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 16,
          children: [_buildOverviewCard(), _buildOrderDetailsCard(), _buildAttachmentCard(), _buildAuditCard(), const SizedBox(height: 8)],
        ),
      ),
    );
  }
}
