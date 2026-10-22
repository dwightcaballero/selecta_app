import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/inventory_controller.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/services/inventory_service.dart';
import 'package:selecta_ops/views/widgets/inventory/cycle_count_dialog.dart';
import 'package:selecta_ops/views/widgets/snackbar_widget.dart';

/// Full-height bottom sheet presenting the Dealer Exception Dashboard & Audit KPIs.
/// Surfaces short picks, clamped-at-zero events, returns in quarantine, ledger anomalies,
/// and provides quick-action shortcuts for cycle count resolution.
class InventoryExceptionsSheet extends StatefulWidget {
  final InventoryController controller;

  const InventoryExceptionsSheet({
    super.key,
    required this.controller,
  });

  static Future<void> show({
    required BuildContext context,
    required InventoryController controller,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => InventoryExceptionsSheet(controller: controller),
    );
  }

  @override
  State<InventoryExceptionsSheet> createState() => _InventoryExceptionsSheetState();
}

class _InventoryExceptionsSheetState extends State<InventoryExceptionsSheet> {
  bool _isLoading = true;
  InventoryExceptionDashboardMetrics? _metrics;
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    setState(() => _isLoading = true);
    try {
      final metrics = await widget.controller.fetchExceptionDashboardMetrics();
      if (mounted) {
        setState(() {
          _metrics = metrics;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        SnackBarWidget.error(context, 'Failed to load exception dashboard: $e');
      }
    }
  }

  Future<void> _resolveDiscrepancy(StockDiscrepancy d) async {
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolve Discrepancy'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${d.productName} (${d.discrepancyType})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              d.message,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Resolution Notes',
                hintText: 'e.g. Recounted shelf, inventory adjusted via PO, etc.',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Mark Resolved'),
          ),
        ],
      ),
    );

    if (confirmed == true && d.id.isNotEmpty) {
      try {
        await widget.controller.resolveDiscrepancy(
          discrepancyId: d.id,
          resolutionNotes: notesController.text.trim(),
        );
        if (mounted) {
          SnackBarWidget.success(context, 'Discrepancy marked resolved.');
          _loadMetrics();
        }
      } catch (e) {
        if (mounted) {
          SnackBarWidget.error(context, 'Failed to resolve: $e');
        }
      }
    }
  }

  Future<void> _openCycleCountForDiscrepancy(StockDiscrepancy d) async {
    final item = InventoryItem(
      id: d.productId,
      productName: d.productName,
      imageUrl: '',
      buyingPrice: 0,
      sellingPrice: 0,
      isActive: true,
      stockQuantity: d.actualValue,
      lowStockThreshold: 5,
      source: d.productSource == 'other' ? InventoryProductSource.other : InventoryProductSource.selecta,
    );

    await CycleCountDialog.show(
      context: context,
      item: item,
      controller: widget.controller,
    );
    if (mounted) {
      _loadMetrics();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _buildHeader(theme),
          const Divider(height: 1),
          if (_isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (_metrics == null)
            const Expanded(
              child: Center(child: Text('Failed to load metrics.')),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  _buildKpiSection(theme, _metrics!),
                  const SizedBox(height: 16),
                  _buildFilterChips(theme),
                  const SizedBox(height: 12),
                  _buildDiscrepanciesList(theme, _metrics!),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.analytics_outlined, color: Colors.amber.shade900),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Exceptions & Audit KPIs',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Operational exceptions, short picks & shrinkage tracking',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadMetrics,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiSection(ThemeData theme, InventoryExceptionDashboardMetrics m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Operational Quality KPIs',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.3),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'Inventory Accuracy',
                value: '${m.inventoryAccuracyRate.toStringAsFixed(1)}%',
                subtitle: 'Healthy product ratio',
                color: m.inventoryAccuracyRate >= 95 ? Colors.teal : Colors.orange,
                icon: Icons.verified_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                title: 'Pick Accuracy',
                value: '${m.pickAccuracyRate.toStringAsFixed(1)}%',
                subtitle: 'Zero short-pick rate',
                color: m.pickAccuracyRate >= 95 ? Colors.indigo : Colors.deepOrange,
                icon: Icons.checklist_rtl_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'Open Discrepancies',
                value: '${m.openDiscrepanciesCount}',
                subtitle: 'Active action items',
                color: m.openDiscrepanciesCount == 0 ? Colors.teal : Colors.red,
                icon: Icons.warning_amber_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                title: 'Short Picks',
                value: '${m.shortPicksCount}',
                subtitle: 'Fulfillment shortfalls',
                color: m.shortPicksCount == 0 ? Colors.grey : Colors.amber.shade900,
                icon: Icons.remove_shopping_cart_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'Clamped Deductions',
                value: '${m.clampedZeroCount}',
                subtitle: 'Prevented negative stock',
                color: m.clampedZeroCount == 0 ? Colors.grey : Colors.red.shade800,
                icon: Icons.shield_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                title: 'In Quarantine',
                value: '${m.quarantinedItemsCount}',
                subtitle: 'Pending return inspection',
                color: m.quarantinedItemsCount == 0 ? Colors.grey : Colors.purple,
                icon: Icons.inventory_2_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(ThemeData theme) {
    final filters = ['All', 'Short Picks', 'Clamped Zero', 'Quarantined', 'Ledger'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final isSelected = _selectedFilter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f),
              selected: isSelected,
              onSelected: (val) {
                if (val) setState(() => _selectedFilter = f);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDiscrepanciesList(ThemeData theme, InventoryExceptionDashboardMetrics m) {
    var list = m.recentDiscrepancies;
    if (_selectedFilter == 'Short Picks') {
      list = list.where((d) => d.discrepancyType == 'short_pick').toList();
    } else if (_selectedFilter == 'Clamped Zero') {
      list = list.where((d) => d.discrepancyType == 'clamped_negative_stock').toList();
    } else if (_selectedFilter == 'Quarantined') {
      list = list.where((d) => d.discrepancyType == 'return_quarantine').toList();
    } else if (_selectedFilter == 'Ledger') {
      list = list.where((d) => d.discrepancyType.contains('ledger') || d.discrepancyType.contains('chain')).toList();
    }

    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: Colors.teal.shade400),
            const SizedBox(height: 12),
            const Text(
              'No Open Exceptions Found',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'All stock movements and ledger balance checks are healthy.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Active Exceptions (${list.length})',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...list.map((d) => _buildDiscrepancyCard(theme, d)),
      ],
    );
  }

  Widget _buildDiscrepancyCard(ThemeData theme, StockDiscrepancy d) {
    final Color badgeColor;
    final String typeLabel;

    switch (d.discrepancyType) {
      case 'short_pick':
        badgeColor = Colors.amber.shade800;
        typeLabel = 'Short Pick';
        break;
      case 'clamped_negative_stock':
        badgeColor = Colors.red.shade700;
        typeLabel = 'Clamped at 0';
        break;
      case 'return_quarantine':
        badgeColor = Colors.purple.shade700;
        typeLabel = 'Quarantined';
        break;
      case 'return_write_off':
        badgeColor = Colors.brown.shade700;
        typeLabel = 'Write-Off';
        break;
      case 'chain_broken':
        badgeColor = Colors.deepOrange.shade700;
        typeLabel = 'Ledger Break';
        break;
      case 'ledger_mismatch':
        badgeColor = Colors.orange.shade700;
        typeLabel = 'Stock Mismatch';
        break;
      default:
        badgeColor = Colors.blueGrey;
        typeLabel = d.discrepancyType;
    }

    final dateStr = DateFormat('MMM d, h:mm a').format(d.detectedAt);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    typeLabel.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    d.productName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  dateStr,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              d.message,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Expected: ${d.expectedValue}   Actual: ${d.actualValue}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const Spacer(),
                if (d.productId.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.indigo.shade700,
                    ),
                    icon: const Icon(Icons.check_box_outlined, size: 16),
                    label: const Text('Count Now', style: TextStyle(fontSize: 12)),
                    onPressed: () => _openCycleCountForDiscrepancy(d),
                  ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Colors.teal.shade700,
                  ),
                  onPressed: () => _resolveDiscrepancy(d),
                  child: const Text('Resolve', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
