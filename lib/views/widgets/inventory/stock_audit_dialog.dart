import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/inventory_controller.dart';
import 'package:selecta_ops/services/inventory_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';

/// Modal dialog for running and reviewing in-app inventory reconciliation audits.
class StockAuditDialog extends StatefulWidget {
  final InventoryController controller;
  final String? targetProductId;

  const StockAuditDialog({
    super.key,
    required this.controller,
    this.targetProductId,
  });

  static Future<void> show({
    required BuildContext context,
    required InventoryController controller,
    String? targetProductId,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StockAuditDialog(
        controller: controller,
        targetProductId: targetProductId,
      ),
    );
  }

  @override
  State<StockAuditDialog> createState() => _StockAuditDialogState();
}

class _StockAuditDialogState extends State<StockAuditDialog> {
  bool _isRunning = false;
  StockAuditReport? _report;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _executeAudit();
  }

  Future<void> _executeAudit() async {
    setState(() {
      _isRunning = true;
      _errorMessage = null;
    });

    try {
      final report = await widget.controller.runStockAudit(
        targetProductId: widget.targetProductId,
      );
      if (mounted) {
        setState(() {
          _report = report;
          _isRunning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isRunning = false;
        });
      }
    }
  }

  Color _getDiscrepancyColor(String type, ColorScheme colorScheme) {
    switch (type) {
      case 'chain_broken':
        return colorScheme.error;
      case 'ledger_mismatch':
        return const Color(0xFFEA580C);
      case 'reserved_mismatch':
        return const Color(0xFFD97706);
      default:
        return colorScheme.primary;
    }
  }

  String _formatDiscrepancyType(String type) {
    switch (type) {
      case 'chain_broken':
        return 'Chain Broken';
      case 'ledger_mismatch':
        return 'Direct Product Edit';
      case 'reserved_mismatch':
        return 'Reserved Mismatch';
      default:
        return type.replaceAll('_', ' ').toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.rule_folder_rounded, color: colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Inventory Stock Audit',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _buildBody(colorScheme),
      ),
      actions: [
        if (!_isRunning) ...[
          OutlinedButton.icon(
            onPressed: _executeAudit,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Rerun Audit'),
          ),
          if (_report != null && _report!.discrepancies.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                final summary = _report!.discrepancies
                    .map((d) => '[${d.discrepancyType}] ${d.productName}: Expected ${d.expectedValue}, Actual ${d.actualValue} (${d.message})')
                    .join('\n');
                await Clipboard.setData(ClipboardData(text: summary));
                if (context.mounted) {
                  ShowMessage.success(context, 'Audit findings copied to clipboard.');
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy Report'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ],
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_isRunning) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text(
              'Running reconciliation audit...',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Verifying reserved stock against open picklists and validating movement ledger continuity...',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: colorScheme.error, size: 36),
            const SizedBox(height: 8),
            Text(
              'Audit run failed',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.error),
            ),
            const SizedBox(height: 4),
            Text(
              _errorMessage!,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_report == null) return const SizedBox.shrink();

    final report = _report!;
    final bool hasDiscrepancies = report.discrepanciesFound > 0;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hasDiscrepancies
                  ? Colors.amber.withValues(alpha: 0.12)
                  : const Color(0xFF15803D).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasDiscrepancies ? Colors.amber.shade700 : const Color(0xFF15803D),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasDiscrepancies ? Icons.warning_amber_rounded : Icons.verified_rounded,
                  color: hasDiscrepancies ? Colors.amber.shade900 : const Color(0xFF15803D),
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasDiscrepancies
                            ? '${report.discrepanciesFound} Discrepanc${report.discrepanciesFound == 1 ? 'y' : 'ies'} Detected'
                            : 'All Ledgers Synchronized & Verified',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: hasDiscrepancies ? Colors.amber.shade900 : const Color(0xFF15803D),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Audited ${report.totalProductsAudited} product records at ${DateFormat('MMM d, yyyy h:mm a').format(report.auditedAt)}.',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          if (hasDiscrepancies) ...[
            Text(
              'Audit Findings (${report.discrepancies.length})',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            ...report.discrepancies.map((d) {
              final tagColor = _getDiscrepancyColor(d.discrepancyType, colorScheme);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: tagColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: tagColor.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            _formatDiscrepancyType(d.discrepancyType),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: tagColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            d.productName,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Expected: ${d.expectedValue} • Actual: ${d.actualValue}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: tagColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      d.message,
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              );
            }),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'No floating stock or ledger sequence anomalies found. All product balances align with recorded movements.',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
