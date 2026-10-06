import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/services/supplier_oos_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';

/// Top summary KPI card for the Supplier Out of Stock page.
class SupplierOosSummaryCard extends StatelessWidget {
  final List<ProductOosSummary> summaries;
  final DateTime selectedMonth;
  final int totalScansRecorded;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final String formattedMonth;

  const SupplierOosSummaryCard({
    super.key,
    required this.summaries,
    required this.selectedMonth,
    required this.totalScansRecorded,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.formattedMonth,
  });

  void _copyBatchConcernNotice(BuildContext context) {
    final oosItems = summaries.where((s) => s.isCurrentlyOos).toList();
    if (oosItems.isEmpty) {
      ShowMessage.info(context, 'No products are currently marked out of stock.');
      return;
    }

    final message = SupplierOosService().generateBatchConcernMessage(
      oosSummaries: oosItems,
      monthDate: selectedMonth,
    );
    Clipboard.setData(ClipboardData(text: message));
    ShowMessage.success(
      context,
      '📋 Copied supplier concern notice for ${oosItems.length} out-of-stock item(s) to clipboard!',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final currentlyOos = summaries.where((s) => s.isCurrentlyOos).toList();
    final int maxStreak = summaries.fold<int>(0, (prev, s) => s.currentStreak > prev ? s.currentStreak : prev);

    final int totalTracked = summaries.where((s) => s.totalRecordedDays > 0).length;
    final double overallRate = totalTracked > 0
        ? ((totalTracked - currentlyOos.length) / totalTracked) * 100
        : 100.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2430) : colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: currentlyOos.isNotEmpty
              ? Colors.red.withValues(alpha: 0.3)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Month Selector Row
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: (currentlyOos.isNotEmpty ? Colors.red : Colors.teal).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        currentlyOos.isNotEmpty ? Icons.report_problem_rounded : Icons.check_circle_outline_rounded,
                        color: currentlyOos.isNotEmpty ? Colors.red : Colors.teal,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Supplier Stock Health',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '$totalScansRecorded scan(s) in $formattedMonth',
                            style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // Month Navigation
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      onPressed: onPreviousMonth,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        formattedMonth,
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      onPressed: selectedMonth.isBefore(DateTime(DateTime.now().year, DateTime.now().month))
                          ? onNextMonth
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Compact 3-metric KPI row
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: 'OOS Now',
                  value: '${currentlyOos.length}',
                  valueColor: currentlyOos.isNotEmpty ? Colors.red : Colors.green,
                  bgColor: currentlyOos.isNotEmpty
                      ? Colors.red.withValues(alpha: 0.08)
                      : Colors.green.withValues(alpha: 0.08),
                  icon: Icons.cancel_outlined,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: 'Max Streak',
                  value: '${maxStreak}d',
                  valueColor: maxStreak > 2 ? Colors.orange.shade800 : colorScheme.onSurface,
                  bgColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  icon: Icons.trending_up_rounded,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: 'Available',
                  value: '${overallRate.toStringAsFixed(0)}%',
                  valueColor: overallRate >= 80 ? Colors.teal : Colors.orange,
                  bgColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  icon: Icons.donut_large_rounded,
                ),
              ),
            ],
          ),

          if (currentlyOos.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 32,
              child: OutlinedButton.icon(
                onPressed: () => _copyBatchConcernNotice(context),
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: Text(
                  'Copy Supplier Notice (${currentlyOos.length} items OOS)',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String label,
    required String value,
    required Color valueColor,
    required Color bgColor,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: valueColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: valueColor,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
