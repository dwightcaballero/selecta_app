import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/services/supplier_oos_service.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/views/widgets/purchaseorder/product_supplier_calendar_dialog.dart';

/// Card displaying a single Selecta product in the Supplier OOS list.
/// Shows product details, current status, streak, SRP, and opens the supplier calendar dialog.
class SupplierOosProductCard extends StatelessWidget {
  final ProductOosSummary summary;
  final NumberFormat currencyFormat;

  const SupplierOosProductCard({
    super.key,
    required this.summary,
    required this.currencyFormat,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final product = summary.product;

    final isOos = summary.isCurrentlyOos;
    final isTracked = summary.totalRecordedDays > 0;

    Color statusColor;
    Color statusBgColor;
    String statusText;
    IconData statusIcon;

    if (isOos) {
      statusColor = Colors.red.shade700;
      statusBgColor = Colors.red.withValues(alpha: 0.12);
      statusText = summary.currentStreak > 1
          ? 'OOS for ${summary.currentStreak} days'
          : 'Out of Stock';
      statusIcon = Icons.cancel_rounded;
    } else if (isTracked) {
      statusColor = Colors.green.shade700;
      statusBgColor = Colors.green.withValues(alpha: 0.12);
      statusText = 'In Stock (${summary.availabilityRate.toStringAsFixed(0)}%)';
      statusIcon = Icons.check_circle_rounded;
    } else {
      statusColor = colorScheme.onSurfaceVariant;
      statusBgColor = colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
      statusText = 'No Scan This Month';
      statusIcon = Icons.help_outline_rounded;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isOos
              ? Colors.red.withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: isOos ? 1.4 : 1,
        ),
      ),
      color: isDark ? const Color(0xFF191F2C) : colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          ProductSupplierCalendarDialog.show(
            context: context,
            productId: product.id,
            productName: product.productName,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Product Thumbnail
              CachedProductImage(
                imageUrl: product.imageUrl,
                isActive: product.isActive,
                size: 48,
              ),
              const SizedBox(width: 12),

              // Product Info & SRP
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.productName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          'SRP: ${currencyFormat.format(product.sellingPrice)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                        if (product.category.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              product.category,
                              style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Status Badge
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusBgColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, size: 12, color: statusColor),
                              const SizedBox(width: 4),
                              Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isTracked && summary.monthOosDays > 0 && !isOos)
                          Text(
                            '(${summary.monthOosDays}d OOS this mo)',
                            style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Calendar Button
              IconButton.filledTonal(
                icon: const Icon(Icons.calendar_month_rounded, size: 20),
                tooltip: 'View Supplier Calendar',
                style: IconButton.styleFrom(
                  backgroundColor: isOos
                      ? Colors.red.withValues(alpha: 0.12)
                      : colorScheme.primary.withValues(alpha: 0.12),
                  foregroundColor: isOos ? Colors.red.shade700 : colorScheme.primary,
                ),
                onPressed: () {
                  ProductSupplierCalendarDialog.show(
                    context: context,
                    productId: product.id,
                    productName: product.productName,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
