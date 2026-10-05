import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Card displaying product stock status, buy/sell prices, incoming PO / reserved count,
/// and stock quantity indicator.
class InventoryCard extends StatelessWidget {
  final InventoryItem item;
  final NumberFormat currencyFormat;
  final VoidCallback onTapCard;
  final VoidCallback? onTapFloating;

  const InventoryCard({
    super.key,
    required this.item,
    required this.currencyFormat,
    required this.onTapCard,
    this.onTapFloating,
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
                      const SizedBox(height: 5),
                      InkWell(
                        onTap: onTapFloating,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 2,
                            children: [
                              if (item.incomingQuantity > 0)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.arrow_downward_rounded, size: 12, color: Color(0xFF0284C7)),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${item.incomingQuantity} incoming PO',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF0284C7),
                                      ),
                                    ),
                                  ],
                                ),
                              if (item.reservedQuantity > 0)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.arrow_upward_rounded, size: 12, color: Color(0xFF7C3AED)),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${item.availableQuantity} avail • ${item.reservedQuantity} floating',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF7C3AED),
                                      ),
                                    ),
                                  ],
                                ),
                              if (onTapFloating != null)
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Stock Quantity Indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isOut
                      ? colorScheme.error.withValues(alpha: 0.08)
                      : (isLow
                          ? const Color(0xFFD97706).withValues(alpha: 0.08)
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isOut
                        ? colorScheme.error.withValues(alpha: 0.3)
                        : (isLow
                            ? const Color(0xFFD97706).withValues(alpha: 0.35)
                            : colorScheme.outlineVariant.withValues(alpha: 0.45)),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${item.stockQuantity}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: stockColor,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          'in stock',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isOut
                                ? colorScheme.error
                                : (isLow
                                    ? const Color(0xFFB45309)
                                    : colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: colorScheme.outlineVariant,
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
