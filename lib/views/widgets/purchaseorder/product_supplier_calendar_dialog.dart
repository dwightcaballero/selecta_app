import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/supplier_oos_log.dart';
import 'package:selecta_ops/services/supplier_oos_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';

/// Modal dialog displaying a monthly calendar of supplier availability for a specific product.
/// Shows green dots for in-stock days, red dots for out-of-stock days, and supplier concern metrics.
class ProductSupplierCalendarDialog extends StatefulWidget {
  final String productId;
  final String productName;
  final SupplierOosService oosService;

  const ProductSupplierCalendarDialog({
    super.key,
    required this.productId,
    required this.productName,
    required this.oosService,
  });

  static Future<void> show({
    required BuildContext context,
    required String productId,
    required String productName,
    SupplierOosService? oosService,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => ProductSupplierCalendarDialog(
        productId: productId,
        productName: productName,
        oosService: oosService ?? SupplierOosService(),
      ),
    );
  }

  @override
  State<ProductSupplierCalendarDialog> createState() => _ProductSupplierCalendarDialogState();
}

class _ProductSupplierCalendarDialogState extends State<ProductSupplierCalendarDialog> {
  late DateTime _selectedMonth;
  bool _isLoading = true;
  SupplierProductHistory? _history;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final history = await widget.oosService.getProductHistory(
        productId: widget.productId,
        productName: widget.productName,
        year: _selectedMonth.year,
        month: _selectedMonth.month,
      );
      if (mounted) {
        setState(() {
          _history = history;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
    _loadHistory();
  }

  void _copyConcernMessage() {
    if (_history == null) return;
    final msg = widget.oosService.generateConcernMessage(_history!);
    Clipboard.setData(ClipboardData(text: msg));
    ShowMessage.success(context, 'Copied supplier concern note to clipboard!');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final monthTitle = DateFormat('MMMM yyyy').format(_selectedMonth);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.calendar_month_rounded, color: Colors.blue, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.productName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Supplier Stock History',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Month Selector
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _changeMonth(-1),
                  ),
                  Text(
                    monthTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _selectedMonth.isBefore(DateTime(DateTime.now().year, DateTime.now().month))
                        ? () => _changeMonth(1)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (_isLoading)
                const SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_history != null) ...[
                // Metric Chips
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryMetric(
                        label: 'In Stock',
                        value: '${_history!.inStockDays}d',
                        color: Colors.green,
                      ),
                      _buildSummaryMetric(
                        label: 'Out of Stock',
                        value: '${_history!.outOfStockDays}d',
                        color: Colors.red,
                      ),
                      _buildSummaryMetric(
                        label: 'Current OOS',
                        value: '${_history!.currentOosStreak}d',
                        color: _history!.currentOosStreak > 0 ? Colors.red : Colors.grey,
                      ),
                      _buildSummaryMetric(
                        label: 'Reliability',
                        value: '${_history!.availabilityRate.toStringAsFixed(0)}%',
                        color: _history!.availabilityRate >= 70 ? Colors.green : Colors.orange,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Calendar Grid
                _buildCalendarGrid(_history!),
                const SizedBox(height: 12),

                // Legend
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildLegendItem(color: Colors.green, label: 'In Stock'),
                    const SizedBox(width: 14),
                    _buildLegendItem(color: Colors.red, label: 'Out of Stock'),
                    const SizedBox(width: 14),
                    _buildLegendItem(color: Colors.grey.shade300, label: 'No Data'),
                  ],
                ),
              ],

              const SizedBox(height: 16),
              // Action Button to copy supplier concern
              FilledButton.icon(
                onPressed: _history != null && _history!.outOfStockDays > 0
                    ? _copyConcernMessage
                    : null,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy Concern Message for Supplier'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildLegendItem({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildCalendarGrid(SupplierProductHistory history) {
    const daysOfWeek = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final firstDay = DateTime(history.year, history.month, 1);
    final daysInMonth = DateTime(history.year, history.month + 1, 0).day;
    // Monday is 1, Sunday is 7 in DateTime.weekday
    final leadingBlanks = (firstDay.weekday - 1) % 7;

    final List<Widget> cells = [];

    // Weekday headers
    for (final dayName in daysOfWeek) {
      cells.add(
        Center(
          child: Text(
            dayName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
          ),
        ),
      );
    }

    // Leading blanks for start of month
    for (int i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox());
    }

    // Days of month
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(history.year, history.month, day);
      final status = history.dailyStatus[date] ?? SupplierProductDayStatus.notRecorded;

      Color badgeColor;
      Color textColor;
      switch (status) {
        case SupplierProductDayStatus.inStock:
          badgeColor = Colors.green.withValues(alpha: 0.15);
          textColor = Colors.green.shade800;
          break;
        case SupplierProductDayStatus.outOfStock:
          badgeColor = Colors.red.withValues(alpha: 0.18);
          textColor = Colors.red.shade800;
          break;
        case SupplierProductDayStatus.notRecorded:
          badgeColor = Colors.transparent;
          textColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
          break;
      }

      cells.add(
        Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(8),
            border: status == SupplierProductDayStatus.outOfStock
                ? Border.all(color: Colors.red.withValues(alpha: 0.5), width: 1.2)
                : (status == SupplierProductDayStatus.inStock
                    ? Border.all(color: Colors.green.withValues(alpha: 0.5), width: 1.2)
                    : null),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: TextStyle(
                  fontWeight: status != SupplierProductDayStatus.notRecorded
                      ? FontWeight.bold
                      : FontWeight.normal,
                  fontSize: 12,
                  color: textColor,
                ),
              ),
              if (status != SupplierProductDayStatus.notRecorded) ...[
                const SizedBox(height: 1),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: status == SupplierProductDayStatus.outOfStock ? Colors.red : Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 3,
      crossAxisSpacing: 3,
      children: cells,
    );
  }
}
