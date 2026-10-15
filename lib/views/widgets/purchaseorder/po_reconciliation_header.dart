import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Simplified Purchase Order Details Header.
///
/// Displays the P.O. number, order date, and live summary of items, units,
/// and order total cost without clutter from document scanning or OCR diffing.
class PoReconciliationHeader extends StatelessWidget {
  final bool isNewRecord;
  final TextEditingController orderNumberController;
  final DateTime selectedOrderDate;
  final VoidCallback onPickOrderDate;
  final ValueChanged<String>? onOrderNumberChanged;
  final double currentListTotalCost;
  final int currentListUnits;
  final int currentListCount;
  final bool showDetailsCard;
  final VoidCallback onToggleDetailsCard;
  final NumberFormat currencyFormat;

  const PoReconciliationHeader({
    super.key,
    required this.isNewRecord,
    required this.orderNumberController,
    required this.selectedOrderDate,
    required this.onPickOrderDate,
    this.onOrderNumberChanged,
    required this.currentListTotalCost,
    required this.currentListUnits,
    required this.currentListCount,
    required this.showDetailsCard,
    required this.onToggleDetailsCard,
    required this.currencyFormat,
  });

  Widget _buildDateField({
    required BuildContext context,
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        child: Text(
          DateFormat('MMM dd, yyyy').format(date),
          style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.receipt_long_rounded, size: 20, color: Colors.orange.shade800),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        orderNumberController.text.isNotEmpty
                            ? 'PO #${orderNumberController.text}'
                            : (isNewRecord ? 'New Purchase Order' : 'Purchase Order'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '$currentListCount items • $currentListUnits units • ${currencyFormat.format(currentListTotalCost)}'
                        '${isNewRecord ? "" : " • 🟡 Pending Delivery"}',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(showDetailsCard ? Icons.expand_less : Icons.expand_more),
                  tooltip: showDetailsCard ? 'Hide details' : 'Show details',
                  onPressed: onToggleDetailsCard,
                ),
              ],
            ),
            if (showDetailsCard) ...[
              const Divider(height: 18),

              // P.O. Number & P.O. Date Row
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: orderNumberController,
                      decoration: InputDecoration(
                        labelText: 'P.O. Number',
                        hintText: 'e.g. PO-2026-001',
                        prefixIcon: const Icon(Icons.tag, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      textCapitalization: TextCapitalization.characters,
                      onChanged: onOrderNumberChanged,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildDateField(
                      context: context,
                      label: 'P.O. Date',
                      date: selectedOrderDate,
                      onTap: onPickOrderDate,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Order Summary Row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total SKUs', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Text('$currentListCount', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Container(width: 1, height: 28, color: colorScheme.outlineVariant),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Units', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Text('$currentListUnits pcs', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Container(width: 1, height: 28, color: colorScheme.outlineVariant),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Order Total', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Text(
                          currencyFormat.format(currentListTotalCost),
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: colorScheme.primary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
