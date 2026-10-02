import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/services/export_report_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';

enum ExportDatePreset {
  today('Today', 0),
  yesterday('Yesterday', 1),
  past7Days('Past 7 Days', 7),
  past30Days('Past 30 Days', 30),
  custom('Custom Range', null);

  final String label;
  final int? daysAgo;
  const ExportDatePreset(this.label, this.daysAgo);
}

/// Operational Export Reports Page for generating Excel / CSV reports.
///
/// Enables Field Salesmen, Dealers, and Super-admins to export:
/// - Daily/Weekly Sales & Customer Orders
/// - Delivery Operations & Collections
/// - Accounts Receivable (AR) & Credit Aging Buckets
/// - Current On-Hand Inventory Stock Sheet & Valuations
/// - Field PJP Store Visit Execution Logs
class ExportReportsPage extends StatefulWidget {
  const ExportReportsPage({super.key});

  @override
  State<ExportReportsPage> createState() => _ExportReportsPageState();
}

class _ExportReportsPageState extends State<ExportReportsPage> {
  final ExportReportService _exportService = ExportReportService();

  ExportReportType _selectedReport = ExportReportType.sales;
  ExportDatePreset _datePreset = ExportDatePreset.today;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  bool _isExporting = false;
  ExportResult? _lastExportResult;

  @override
  void initState() {
    super.initState();
    _applyDatePreset(ExportDatePreset.today);
  }

  void _applyDatePreset(ExportDatePreset preset) {
    final now = DateTime.now();
    setState(() {
      _datePreset = preset;
      if (preset == ExportDatePreset.today) {
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day);
      } else if (preset == ExportDatePreset.yesterday) {
        final yest = now.subtract(const Duration(days: 1));
        _startDate = DateTime(yest.year, yest.month, yest.day);
        _endDate = DateTime(yest.year, yest.month, yest.day);
      } else if (preset == ExportDatePreset.past7Days) {
        _startDate = now.subtract(const Duration(days: 6));
        _endDate = now;
      } else if (preset == ExportDatePreset.past30Days) {
        _startDate = now.subtract(const Duration(days: 29));
        _endDate = now;
      }
    });
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _datePreset = ExportDatePreset.custom;
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _runExport() async {
    setState(() => _isExporting = true);

    try {
      final result = await _exportService.generateReport(
        type: _selectedReport,
        startDate: _startDate,
        endDate: _endDate,
      );

      if (mounted) {
        setState(() {
          _lastExportResult = result;
          _isExporting = false;
        });

        ShowMessage.success(context, 'Generated ${result.fileName} (${result.rowCount} records)');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ShowMessage.error(context, 'Export failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final dateOnly = DateFormat('MMM d, yyyy');

    final bool isDateRelevant = _selectedReport != ExportReportType.creditAging && _selectedReport != ExportReportType.inventory;

    return Scaffold(
      appBar: const CustomAppbar(title: 'Export Reports (Excel / CSV)'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Intro
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF1E2430), const Color(0xFF141822)]
                      : [colorScheme.primaryContainer.withValues(alpha: 0.5), colorScheme.primaryContainer.withValues(alpha: 0.15)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: isDark ? 0.25 : 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.table_view_rounded, color: Colors.green, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Export Field Operations Data',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Generate RFC-4180 UTF-8 formatted CSV spreadsheets compatible with Microsoft Excel, Google Sheets, and Numbers.',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 1. Select Report Type
            const Text(
              '1. Select Report Type',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Column(
              children: ExportReportType.values.map((type) {
                final isSelected = _selectedReport == type;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected
                          ? colorScheme.primary
                          : (isDark ? const Color(0xFF28303F) : colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  color: isSelected
                      ? colorScheme.primary.withValues(alpha: isDark ? 0.15 : 0.05)
                      : (isDark ? const Color(0xFF1B202A) : colorScheme.surface),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _selectedReport = type),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Icon(
                            _getReportIcon(type),
                            color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  type.title,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  type.description,
                                  style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // 2. Date Range Configuration (if relevant)
            if (isDateRelevant) ...[
              const Text(
                '2. Select Timeframe / Date Range',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ExportDatePreset.values.map((preset) {
                    final isSelected = _datePreset == preset;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(preset.label, style: const TextStyle(fontSize: 12)),
                        selected: isSelected,
                        onSelected: (val) {
                          if (val) {
                            if (preset == ExportDatePreset.custom) {
                              _pickCustomDateRange();
                            } else {
                              _applyDatePreset(preset);
                            }
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: _pickCustomDateRange,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF141822) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.date_range_outlined, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${dateOnly.format(_startDate)} — ${dateOnly.format(_endDate)}',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Change',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(Icons.edit_calendar_outlined, size: 13, color: colorScheme.primary),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141822) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedReport == ExportReportType.creditAging
                            ? 'Credit aging inspects all active outstanding receivables in real time.'
                            : 'Inventory sheet reflects live on-hand stocks across all catalogs.',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Export Action Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                icon: _isExporting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.download_rounded),
                label: Text(
                  _isExporting ? 'Generating Report...' : 'Generate & Export to Excel / CSV',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                onPressed: _isExporting ? null : _runExport,
              ),
            ),

            const SizedBox(height: 24),

            // Export Result Card (if export has been generated)
            if (_lastExportResult != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2430) : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.green, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _lastExportResult!.fileName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                '${_lastExportResult!.rowCount} records exported successfully',
                                style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.green.shade900),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),

                    // Summary Metrics Grid
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: _lastExportResult!.summary.entries.map((entry) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF141822) : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(entry.key, style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                              Text('${entry.value}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),

                    // Quick Actions
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.open_in_new_rounded, size: 16),
                            label: const Text('Open in Excel / Sheets'),
                            onPressed: () => _exportService.openExportedFile(_lastExportResult!.filePath),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Copy CSV'),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _lastExportResult!.csvContent));
                            ShowMessage.success(context, 'CSV data copied to clipboard!');
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    Text(
                      'Saved to:\n${_lastExportResult!.filePath}',
                      style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getReportIcon(ExportReportType type) {
    switch (type) {
      case ExportReportType.sales:
        return Icons.point_of_sale_rounded;
      case ExportReportType.deliveries:
        return Icons.local_shipping_outlined;
      case ExportReportType.creditAging:
        return Icons.account_balance_wallet_outlined;
      case ExportReportType.inventory:
        return Icons.warehouse_outlined;
      case ExportReportType.storeVisits:
        return Icons.photo_library_outlined;
    }
  }
}
