import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Sticky bottom summary bar showing SKU count, total units, formatted total currency,
/// expandable cart preview icon, and the primary "Save Order" button.
class StickyOrderSummaryBar extends StatelessWidget {
  final int skuCount;
  final int totalUnits;
  final double totalAmount;
  final NumberFormat currencyFormat;
  final bool isSaving;
  final VoidCallback? onTapCartSummary;
  final VoidCallback? onSaveOrder;

  const StickyOrderSummaryBar({
    super.key,
    required this.skuCount,
    required this.totalUnits,
    required this.totalAmount,
    required this.currencyFormat,
    this.isSaving = false,
    this.onTapCartSummary,
    this.onSaveOrder,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              offset: const Offset(0, -2),
              blurRadius: 6,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: skuCount > 0 ? onTapCartSummary : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '$skuCount SKU${skuCount == 1 ? '' : 's'} • $totalUnits unit${totalUnits == 1 ? '' : 's'}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (skuCount > 0) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.keyboard_arrow_up_rounded, size: 20, color: colorScheme.primary),
                              ],
                            ],
                          ),
                          Text(
                            currencyFormat.format(totalAmount),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: isSaving ? null : onSaveOrder,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(148, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline, size: 22),
                  label: const Text(
                    'Save Order',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
