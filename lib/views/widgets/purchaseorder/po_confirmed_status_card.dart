import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/purchaseorder.dart';

/// Card widget displayed when a purchase order has been confirmed,
/// invoiced, and permanently replenished into dealer inventory.
class PoConfirmedStatusCard extends StatelessWidget {
  final Purchaseorder purchaseorder;
  final NumberFormat? currencyFormat;

  const PoConfirmedStatusCard({
    super.key,
    required this.purchaseorder,
    this.currencyFormat,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currency = currencyFormat ?? NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.green.shade300, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.verified_rounded, color: Colors.green, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        purchaseorder.invoiceVerificationPending ? 'Manually Received — Invoice Unverified' : 'Purchase Order Invoiced & Replenished',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text('Stocks replenished into inventory permanently', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('P.O. Number:'),
                Text(
                  purchaseorder.poNumber.isNotEmpty
                      ? purchaseorder.poNumber
                      : purchaseorder.invoiceNumber,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('P.O. Date:'),
                Text(
                  DateFormat('MMM dd, yyyy').format(purchaseorder.orderDate.toDate()),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(purchaseorder.invoiceVerificationPending ? 'Invoice / DR Reference:' : 'Official Invoice No:'),
                Text(
                  purchaseorder.invoiceNumber.isNotEmpty ? purchaseorder.invoiceNumber : 'N/A',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(purchaseorder.invoiceVerificationPending ? 'Received Date:' : 'Invoice Date:'),
                Text(
                  DateFormat('MMM dd, yyyy').format(purchaseorder.invoiceDate.toDate()),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(purchaseorder.invoiceVerificationPending ? 'Estimated Receipt Value:' : 'Invoice Amount:'),
                Text(
                  currency.format(purchaseorder.invoiceVerificationPending ? purchaseorder.manualReceiptValue : purchaseorder.invoiceAmount),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Replenished Items:'),
                Text('${purchaseorder.items.length} products', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            if (purchaseorder.manualReceiptLines.isNotEmpty) ...[
              const Divider(height: 24),
              const Text('Manual receipt (short quantities closed)', style: TextStyle(fontWeight: FontWeight.bold)),
              if (purchaseorder.manualReceiptRecordedAt != null)
                Text(
                  'Recorded by ${purchaseorder.manualReceiptRecordedBy} on '
                  '${DateFormat('MMM dd, yyyy HH:mm').format(purchaseorder.manualReceiptRecordedAt!.toDate())}',
                ),
              const SizedBox(height: 8),
              for (final line in purchaseorder.manualReceiptLines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${line.item.productName}: ${line.receivedQuantity} of ${line.item.effectiveQuantity} received'
                    '${line.receivedQuantity < line.item.effectiveQuantity ? ' — ${line.shortageReason}' : ''}',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
