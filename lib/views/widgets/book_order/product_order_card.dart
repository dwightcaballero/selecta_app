import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Product Card in Book Order list with stock indicator, tag badges, price,
/// and quantity badge/prompt.
class ProductOrderCard extends StatelessWidget {
  final InventoryItem item;
  final int selectedQty;
  final int maxOrderable;
  final bool isPlaced;
  final NumberFormat currencyFormat;
  final VoidCallback onTap;
  final int? receiptIndex;
  final String? rawReceiptText;

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
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = selectedQty > 0;
    final isOutOfStock = maxOrderable <= 0;

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
        onTap: isOutOfStock ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              CachedProductImage(imageUrl: item.imageUrl, isActive: !isOutOfStock, size: 54),
              const SizedBox(width: 12),
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
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: isOutOfStock ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
                        height: 1.25,
                      ),
                    ),
                    if (rawReceiptText != null && rawReceiptText!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'From receipt: "${rawReceiptText!.trim()}"',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 7,
                      runSpacing: 2,
                      children: [
                        Text(
                          currencyFormat.format(item.sellingPrice),
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: colorScheme.primary),
                        ),
                        if (isOutOfStock)
                          Text(
                            'Out of stock',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: stockColor),
                          )
                        else if (item.stockQuantity <= 0 && item.incomingQuantity > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(color: const Color(0xFF0284C7).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.local_shipping_outlined, size: 12, color: Color(0xFF0284C7)),
                                const SizedBox(width: 3),
                                Text(
                                  '${item.incomingQuantity} incoming PO',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0369A1)),
                                ),
                              ],
                            ),
                          )
                        else if (item.incomingQuantity > 0)
                          Text(
                            '+${item.incomingQuantity} incoming',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0284C7)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (!isSelected)
                SizedBox(
                  width: 46,
                  height: 46,
                  child: FilledButton(
                    onPressed: isOutOfStock ? null : onTap,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                      minimumSize: const Size(46, 46),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Icon(Icons.add_rounded, size: 24),
                  ),
                )
              else
                GestureDetector(
                  onTap: onTap,
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: colorScheme.primary, borderRadius: BorderRadius.circular(23)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.edit_outlined, size: 18, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          '$selectedQty',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
