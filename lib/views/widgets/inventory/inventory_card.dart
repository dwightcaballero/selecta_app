import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Card displaying product stock status, buy/sell prices, incoming PO / reserved count,
/// and quick stepper buttons (- / +).
class InventoryCard extends StatelessWidget {
  final InventoryItem item;
  final NumberFormat currencyFormat;
  final VoidCallback onTapCard;
  final ValueChanged<int> onQuickStep;

  const InventoryCard({
    super.key,
    required this.item,
    required this.currencyFormat,
    required this.onTapCard,
    required this.onQuickStep,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isLow = item.isLowStock;
    final bool isOut = item.isOutOfStock;
    final Color stockColor = isOut
        ? colorScheme.error
        : (isLow ? const Color(0xFFD97706) : colorScheme.onSurface);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: isOut
          ? colorScheme.error.withValues(alpha: 0.03)
          : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isOut
              ? colorScheme.error.withValues(alpha: 0.35)
              : (isLow
                  ? const Color(0xFFD97706).withValues(alpha: 0.4)
                  : colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTapCard,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CachedProductImage(
                imageUrl: item.imageUrl,
                isActive: !isOut,
                size: 54,
                borderRadius: 10,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.productName,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: isOut ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 3,
                      children: [
                        Text(
                          'Sell: ${currencyFormat.format(item.sellingPrice)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ),
                        ),
                        Text('•', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                        Text(
                          'Buy: ${currencyFormat.format(item.buyingPrice)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (isOut) ...[
                          Text('•', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: colorScheme.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Out of Stock',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.error,
                              ),
                            ),
                          ),
                        ] else if (isLow) ...[
                          Text('•', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD97706).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Low Stock',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFB45309),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (item.incomingQuantity > 0 || item.reservedQuantity > 0) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          if (item.incomingQuantity > 0)
                            Text(
                              '${item.incomingQuantity} incoming PO',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0284C7),
                              ),
                            ),
                          if (item.reservedQuantity > 0)
                            Text(
                              '${item.availableQuantity} available • ${item.reservedQuantity} floating',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF7C3AED),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Quick Stepper Controls (-  Qty  +)
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(9),
                      ),
                      onTap: item.stockQuantity > 0
                          ? () => onQuickStep(-1)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Icon(
                          Icons.remove_rounded,
                          size: 18,
                          color: item.stockQuantity > 0
                              ? colorScheme.onSurface
                              : colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    Container(
                      constraints: const BoxConstraints(minWidth: 36),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      child: Text(
                        '${item.stockQuantity}',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: stockColor,
                        ),
                      ),
                    ),
                    InkWell(
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(9),
                      ),
                      onTap: () => onQuickStep(1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                      ),
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
}
