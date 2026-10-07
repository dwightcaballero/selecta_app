import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Card displaying product stock status, buy/sell prices, incoming PO / reserved count,
/// and stock quantity indicator.
///
/// Uses a two-tier layout (similar to ProductOrderCard in BookOrderPage) to cater to long product names:
/// - Top tier: Full-width product title with thumbnail image and tag/SKU badges (no truncation).
/// - Bottom tier: Pricing & floating stock on the left, on-hand quantity indicator on the right.
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
    final bool isBestSeller = ProductTag.isBestSeller(item.tag);
    final bool isNewProduct = ProductTag.isNewProduct(item.tag);
    final bool isOther = item.source == InventoryProductSource.other;
    final bool hasFloating = item.incomingQuantity > 0 || item.reservedQuantity > 0;

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top Tier: Thumbnail + Full-Width Title & Badges ───────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CachedProductImage(
                    imageUrl: item.imageUrl,
                    isActive: !isOut,
                    size: 50,
                    borderRadius: 10,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isBestSeller || isNewProduct || isOther || item.itemCode.isNotEmpty) ...[
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (isBestSeller)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.star_rounded, size: 12, color: Color(0xFFD97706)),
                                      SizedBox(width: 3),
                                      Text(
                                        'Best Seller',
                                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                                      ),
                                    ],
                                  ),
                                ),
                              if (isNewProduct)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE0F2FE),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.fiber_new_rounded, size: 13, color: Color(0xFF0284C7)),
                                      SizedBox(width: 3),
                                      Text(
                                        'New Product',
                                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF0369A1)),
                                      ),
                                    ],
                                  ),
                                ),
                              if (isOther)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(color: const Color(0xFF94A3B8).withValues(alpha: 0.5)),
                                  ),
                                  child: const Text(
                                    'Other Product',
                                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                  ),
                                ),
                              if (item.itemCode.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    '#${item.itemCode}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                        ],
                        // Full Product Name with NO truncation
                        Text(
                          item.productName,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: isOut ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Row 1: Financials & Stock Health Alert ─────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Financial info (flexible and wraps if needed)
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              currencyFormat.format(item.sellingPrice),
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'SRP',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        Text('•', style: TextStyle(fontSize: 12, color: colorScheme.outlineVariant)),
                        Text(
                          'Cost: ${currencyFormat.format(item.buyingPrice)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Stock Alert Badge (if low or out of stock)
                  if (isOut) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'OUT OF STOCK',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          color: colorScheme.error,
                        ),
                      ),
                    ),
                  ] else if (isLow) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.35)),
                      ),
                      child: const Text(
                        'LOW STOCK',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 6),

              // ── Row 2: Dedicated "Stock Pipeline" Strip ───────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5.5),
                decoration: BoxDecoration(
                  color: isOut
                      ? colorScheme.error.withValues(alpha: 0.05)
                      : (isLow
                          ? const Color(0xFFD97706).withValues(alpha: 0.06)
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isOut
                        ? colorScheme.error.withValues(alpha: 0.25)
                        : (isLow
                            ? const Color(0xFFD97706).withValues(alpha: 0.25)
                            : colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                ),
                child: Row(
                  children: [
                    // Segment Strip
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 1. On-Hand Stock (Primary)
                            Icon(Icons.inventory_2_outlined, size: 14, color: stockColor),
                            const SizedBox(width: 4),
                            Text(
                              '${item.stockQuantity}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: stockColor,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'On-Hand',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),

                            // If reserved exists: show Available & Reserved
                            if (item.reservedQuantity > 0) ...[
                              _buildPipelineDivider(colorScheme),
                              Text(
                                '${item.availableQuantity}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 2.5),
                              Text(
                                'Avail',
                                style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant),
                              ),
                              _buildPipelineDivider(colorScheme),
                              const Icon(Icons.lock_outline_rounded, size: 12, color: Color(0xFF7C3AED)),
                              const SizedBox(width: 2.5),
                              Text(
                                '${item.reservedQuantity}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF7C3AED),
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Text(
                                'Rsrv',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF7C3AED)),
                              ),
                            ],

                            // If incoming exists: show Incoming PO
                            if (item.incomingQuantity > 0) ...[
                              _buildPipelineDivider(colorScheme),
                              const Icon(Icons.local_shipping_outlined, size: 13, color: Color(0xFF0284C7)),
                              const SizedBox(width: 2.5),
                              Text(
                                '${item.incomingQuantity}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0284C7),
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Text(
                                'PO',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF0284C7)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 6),

                    // Right End: Floating details trigger or Adjust stock chevron
                    if (hasFloating && onTapFloating != null)
                      InkWell(
                        onTap: onTapFloating,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.sync_alt_rounded, size: 13, color: Color(0xFF7C3AED)),
                              const SizedBox(width: 1),
                              Icon(Icons.chevron_right_rounded, size: 14, color: colorScheme.outlineVariant),
                            ],
                          ),
                        ),
                      )
                    else
                      Icon(Icons.chevron_right_rounded, size: 15, color: colorScheme.outlineVariant),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPipelineDivider(ColorScheme colorScheme) {
    return Container(
      height: 11,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 7),
      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
    );
  }
}
