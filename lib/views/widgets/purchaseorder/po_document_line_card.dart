import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/po_extracted_line.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Card widget displaying a single extracted PO/Invoice line item with
/// sequence number, image, details, pricing, and flag/correct action triggers.
class PoDocumentLineCard extends StatelessWidget {
  final int index;
  final PoExtractedLine line;
  final VoidCallback onToggleFlag;
  final VoidCallback onCorrect;
  final NumberFormat? currencyFormat;

  const PoDocumentLineCard({
    super.key,
    required this.index,
    required this.line,
    required this.onToggleFlag,
    required this.onCorrect,
    this.currencyFormat,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currency = currencyFormat ?? NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    Color cardBg = colorScheme.surface;
    Color borderColor = colorScheme.outlineVariant.withValues(alpha: 0.5);
    double borderWidth = 1.0;

    if (line.isIncorrect) {
      cardBg = Colors.red.withValues(alpha: 0.05);
      borderColor = Colors.red.shade400;
      borderWidth = 1.5;
    } else if (line.isCorrected) {
      cardBg = Colors.blue.withValues(alpha: 0.04);
      borderColor = Colors.blue.shade400;
      borderWidth = 1.5;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor, width: borderWidth),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sequence Badge (#1, #2...)
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: line.isIncorrect
                        ? Colors.red.shade100
                        : line.isCorrected
                            ? Colors.blue.shade100
                            : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: line.isIncorrect
                          ? Colors.red.shade900
                          : line.isCorrected
                              ? Colors.blue.shade900
                              : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Product Image
                CachedProductImage(imageUrl: line.imageUrl, size: 48),
                const SizedBox(width: 12),

                // Product Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.productName,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, height: 1.2),
                      ),
                      const SizedBox(height: 3),
                      if (line.rawDocText.isNotEmpty && line.rawDocText != line.productName)
                        Text(
                          'Doc: "${line.rawDocText}"',
                          style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '${currency.format(line.buyingPrice)} × ${line.quantity}',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                          ),
                          const Spacer(),
                          Text(
                            currency.format(line.lineTotal),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colorScheme.primary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 6),

            // Bottom Actions on the Card: Mark as Incorrect & Correct
            Row(
              children: [
                if (line.isIncorrect)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        '⚠️ Flagged',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade900),
                      ),
                    ),
                  )
                else if (line.isCorrected)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        '✓ Corrected',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                      ),
                    ),
                  ),
                const Spacer(),

                // Toggle Mark as Incorrect
                TextButton.icon(
                  onPressed: onToggleFlag,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    foregroundColor: line.isIncorrect ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                  icon: Icon(line.isIncorrect ? Icons.check_circle_outline : Icons.flag_outlined, size: 14),
                  label: Text(line.isIncorrect ? 'Unflag' : 'Flag', style: const TextStyle(fontSize: 11)),
                ),

                const SizedBox(width: 4),

                // Correct button
                FilledButton.tonalIcon(
                  onPressed: onCorrect,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Correct', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
