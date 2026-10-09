import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/po_extracted_line.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Streamlined Card widget displaying a single extracted PO/Invoice line item.
/// Clean layout with high readability, no visual clutter, and direct tap-to-correct.
class PoDocumentLineCard extends StatelessWidget {
  final int index;
  final PoExtractedLine line;
  final InventoryItem? inventoryItem;
  final VoidCallback onToggleFlag;
  final VoidCallback onCorrect;
  final NumberFormat? currencyFormat;

  const PoDocumentLineCard({
    super.key,
    required this.index,
    required this.line,
    this.inventoryItem,
    required this.onToggleFlag,
    required this.onCorrect,
    this.currencyFormat,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currency = currencyFormat ?? NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    Color cardBg = colorScheme.surface;
    Color borderColor = colorScheme.outlineVariant.withValues(alpha: 0.4);
    double borderWidth = 1.0;

    if (line.isIncorrect) {
      cardBg = Colors.red.withValues(alpha: 0.04);
      borderColor = Colors.red.shade400;
      borderWidth = 1.2;
    } else if (line.isCorrected) {
      cardBg = Colors.blue.withValues(alpha: 0.04);
      borderColor = Colors.blue.shade400;
      borderWidth = 1.2;
    } else if (inventoryItem != null && inventoryItem!.hasPreOrderDeficit) {
      cardBg = const Color(0xFF7C3AED).withValues(alpha: 0.03);
      borderColor = const Color(0xFF8B5CF6).withValues(alpha: 0.4);
      borderWidth = 1.2;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: borderWidth),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onCorrect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Sequence Badge (#1, #2...)
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: line.isIncorrect
                      ? Colors.red.shade100
                      : line.isCorrected
                          ? Colors.blue.shade100
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: line.isIncorrect
                        ? Colors.red.shade900
                        : line.isCorrected
                            ? Colors.blue.shade900
                            : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Product Image
              CachedProductImage(imageUrl: line.imageUrl, size: 40),
              const SizedBox(width: 10),

              // Product Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (inventoryItem != null && inventoryItem!.isPreOrderRecommended) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE9FE),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          inventoryItem!.hasPreOrderShortage
                              ? '⭐ Shortage: +${inventoryItem!.preOrderShortage} pcs'
                              : '⭐ Low Stock Alert',
                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF6D28D9)),
                        ),
                      ),
                    ],
                    Text(
                      line.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.2),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          '${currency.format(line.buyingPrice)} × ${line.quantity}',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                        ),
                        if (line.isIncorrect) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                            child: Text(
                              'Flagged',
                              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.red.shade900),
                            ),
                          ),
                        ] else if (line.isCorrected) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(4)),
                            child: Text(
                              'Corrected',
                              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Trailing Section: Line Total & Quick Actions
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currency.format(line.lineTotal),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: line.isIncorrect ? 'Unflag item' : 'Flag as incorrect',
                        icon: Icon(
                          line.isIncorrect ? Icons.flag_rounded : Icons.flag_outlined,
                          size: 15,
                          color: line.isIncorrect ? Colors.red.shade700 : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        onPressed: onToggleFlag,
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
