import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Product Card in Book Order list with two-tier layout:
/// - Top tier: Thumbnail image and full-width product title with tag badges and scanned document info.
/// - Bottom tier: Pricing & stock availability on the left, and inline stepper / add button on the right.
///
/// Designed to prevent RenderFlex overflow and title compression on narrow mobile devices,
/// even when product titles span 3 to 4 lines.
class ProductOrderCard extends StatelessWidget {
  final InventoryItem item;
  final int selectedQty;
  final int maxOrderable;
  final bool isPlaced;
  final NumberFormat currencyFormat;
  final VoidCallback onTap;
  final int? receiptIndex;
  final String? rawReceiptText;
  final bool isCorrected;
  final VoidCallback? onCorrectAi;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final bool isFutureDelivery;

  const ProductOrderCard({
    super.key,
    required this.item,
    required this.selectedQty,
    required this.maxOrderable,
    required this.isPlaced,
    required this.currencyFormat,
    required this.onTap,
    this.receiptIndex,
    this.rawReceiptText,
    this.isCorrected = false,
    this.onCorrectAi,
    this.onIncrement,
    this.onDecrement,
    this.isFutureDelivery = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = selectedQty > 0;
    final isOutOfStock = !isFutureDelivery && maxOrderable <= 0;

    final bool isBestSeller = ProductTag.isBestSeller(item.tag);
    final bool isNewProduct = ProductTag.isNewProduct(item.tag);
    final bool showNotPlacedMark = isBestSeller && !isPlaced;

    final Color stockColor = isOutOfStock
        ? colorScheme.error
        : (maxOrderable <= item.lowStockThreshold ? const Color(0xFFD97706) : colorScheme.primary);

    Color cardBgColor = colorScheme.surface;
    Color cardBorderColor = colorScheme.outlineVariant.withValues(alpha: 0.45);
    double cardBorderWidth = 1.0;

    if (isSelected) {
      cardBgColor = colorScheme.primary.withValues(alpha: 0.05);
      cardBorderColor = colorScheme.primary;
      cardBorderWidth = 1.5;
    } else if (isCorrected) {
      cardBgColor = Colors.blue.withValues(alpha: 0.04);
      cardBorderColor = Colors.blue.shade400;
      cardBorderWidth = 1.2;
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cardBgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cardBorderColor, width: cardBorderWidth),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isOutOfStock ? null : (!isSelected ? (onIncrement ?? onTap) : onTap),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top Tier: Image + Full-Width Product Info ────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CachedProductImage(imageUrl: item.imageUrl, isActive: !isOutOfStock, size: 50),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (receiptIndex != null || isBestSeller || isNewProduct || showNotPlacedMark) ...[
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (receiptIndex != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.amber.shade400.withValues(alpha: 0.6)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.receipt_long_outlined, size: 12, color: Colors.amber.shade900),
                                      const SizedBox(width: 3),
                                      Text(
                                        '#$receiptIndex on Receipt',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.amber.shade900),
                                      ),
                                    ],
                                  ),
                                ),
                              if (isBestSeller)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.star_rounded, size: 13, color: Color(0xFFD97706)),
                                      SizedBox(width: 3),
                                      Text(
                                        'Best Seller',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                                      ),
                                    ],
                                  ),
                                ),
                              if (isNewProduct)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE0F2FE),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.fiber_new_rounded, size: 14, color: Color(0xFF0284C7)),
                                      SizedBox(width: 3),
                                      Text(
                                        'New Product',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0369A1)),
                                      ),
                                    ],
                                  ),
                                ),
                              if (showNotPlacedMark)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEE2E2),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.6)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.warning_amber_rounded, size: 13, color: Color(0xFFDC2626)),
                                      SizedBox(width: 3),
                                      Text(
                                        'Not Placed',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB91C1C)),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          item.productName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isOutOfStock ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
                            height: 1.25,
                          ),
                        ),
                        if (rawReceiptText != null && rawReceiptText!.trim().isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.receipt_long_outlined, size: 12, color: Colors.amber.shade900),
                                    const SizedBox(width: 4),
                                    Text(
                                      'SCANNED ON DOCUMENT:',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.4,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                    if (isCorrected) ...[
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade100,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '✓ Corrected',
                                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  rawReceiptText!.trim(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (onCorrectAi != null) ...[
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: onCorrectAi,
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit_note_rounded, size: 15, color: Colors.blue.shade700),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Correct AI Reading',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Bottom Tier: Price & Stock on Left, Stepper on Right ──────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left: Price & Available stock
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 60),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          Text(
                            currencyFormat.format(item.sellingPrice),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colorScheme.primary),
                          ),
                          if (!isFutureDelivery) ...[
                            if (isOutOfStock)
                              Text(
                                'Out of stock',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: stockColor),
                              )
                            else if (item.stockQuantity <= 0 && item.incomingQuantity > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(color: const Color(0xFF0284C7).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.local_shipping_outlined, size: 11, color: Color(0xFF0284C7)),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${item.incomingQuantity} incoming PO',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0369A1)),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Text(
                                '• $maxOrderable available',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant),
                              ),
                          ] else ...[
                            if (item.availableQuantity > 0)
                              Text(
                                '• ${item.availableQuantity} available',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.amber.shade300, width: 0.8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.inventory_2_outlined, size: 11, color: Colors.amber.shade900),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Restock via PO',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.amber.shade900),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Right: Add button or Stepper
                  if (isOutOfStock)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '0 stock',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: colorScheme.outline),
                      ),
                    )
                  else if (!isSelected)
                    FilledButton.icon(
                      onPressed: onIncrement ?? onTap,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        minimumSize: const Size(82, 40),
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    )
                  else
                    Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(19)),
                              onTap: onDecrement,
                              child: SizedBox(
                                width: 36,
                                height: 38,
                                child: Icon(
                                  selectedQty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                                  size: 19,
                                  color: selectedQty == 1 ? colorScheme.error : colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: onTap,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 36),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              alignment: Alignment.center,
                              child: Text(
                                '$selectedQty',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(19)),
                              onTap: (selectedQty < maxOrderable && maxOrderable > 0) ? onIncrement : null,
                              child: SizedBox(
                                width: 36,
                                height: 38,
                                child: Icon(
                                  Icons.add_rounded,
                                  size: 19,
                                  color: (selectedQty < maxOrderable && maxOrderable > 0)
                                      ? colorScheme.primary
                                      : colorScheme.outlineVariant,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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
