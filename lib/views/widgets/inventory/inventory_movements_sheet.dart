import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:selecta_ops/controllers/inventory_controller.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';

/// Reusable tile rendering a single stock movement delta, audit tags, and expandable metadata.
class InventoryMovementTile extends StatefulWidget {
  final InventoryMovement movement;
  final DateFormat dateFormat;
  final bool compact;
  final bool isChainBroken;

  const InventoryMovementTile({
    super.key,
    required this.movement,
    required this.dateFormat,
    this.compact = false,
    this.isChainBroken = false,
  });

  @override
  State<InventoryMovementTile> createState() => _InventoryMovementTileState();
}

class _InventoryMovementTileState extends State<InventoryMovementTile> {
  bool _expanded = false;

  Color _getMovementColor(MovementType type, ColorScheme colorScheme) {
    switch (type) {
      case MovementType.receipt:
      case MovementType.incoming_added:
        return const Color(0xFF15803D); // Green
      case MovementType.pick:
      case MovementType.van_load:
        return const Color(0xFF0284C7); // Sky Blue
      case MovementType.van_return:
      case MovementType.customer_return:
        return const Color(0xFF0D9488); // Teal
      case MovementType.damage_expiry:
        return colorScheme.error; // Red
      case MovementType.adjustment:
      case MovementType.count_correction:
        return const Color(0xFF7C3AED); // Purple
      case MovementType.reserve:
      case MovementType.release:
        return const Color(0xFFD97706); // Amber
      case MovementType.reversal:
        return const Color(0xFFEA580C); // Deep Orange
      case MovementType.settlement:
        return const Color(0xFF2563EB); // Royal Blue
      default:
        return colorScheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.movement;
    final colorScheme = Theme.of(context).colorScheme;
    final isPositive = m.delta > 0;
    final isZero = m.delta == 0;
    final deltaColor = isZero
        ? colorScheme.outline
        : (isPositive ? const Color(0xFF15803D) : colorScheme.error);
    final deltaText = isZero ? '0' : (isPositive ? '+${m.delta}' : '${m.delta}');
    final typeColor = _getMovementColor(m.movementType, colorScheme);

    return InkWell(
      onTap: () {
        setState(() => _expanded = !_expanded);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: EdgeInsets.symmetric(vertical: widget.compact ? 3 : 5),
        padding: EdgeInsets.all(widget.compact ? 8 : 12),
        decoration: BoxDecoration(
          color: widget.isChainBroken
              ? colorScheme.errorContainer.withValues(alpha: 0.25)
              : (m.clamped
                  ? Colors.amber.withValues(alpha: 0.1)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.isChainBroken
                ? colorScheme.error
                : (m.clamped ? Colors.amber.shade700 : colorScheme.outlineVariant.withValues(alpha: 0.4)),
            width: widget.isChainBroken ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Delta indicator badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: deltaColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    deltaText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: deltaColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Movement Type badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: typeColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    m.movementType.displayName,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: typeColor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Clamped warning chip
                if (m.clamped)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.amber.shade800),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 12, color: Colors.amber.shade900),
                        const SizedBox(width: 3),
                        Text(
                          'Clamped (Req: ${m.requestedQuantity})',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Chain broken alert chip
                if (widget.isChainBroken) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.link_off_rounded, size: 12, color: colorScheme.error),
                        const SizedBox(width: 3),
                        Text(
                          'Chain Break',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const Spacer(),
                Text(
                  widget.dateFormat.format(m.createdAt.toDate()),
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Product & Reason line
            if (!widget.compact)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  m.productName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            Row(
              children: [
                Expanded(
                  child: Text(
                    '${m.reasonCode?.displayName ?? m.reason}${m.notes.isNotEmpty ? ' • ${m.notes}' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: widget.compact ? FontWeight.w600 : FontWeight.normal,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: _expanded ? 10 : 1,
                    overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Physical: ${m.previousStock} → ${m.newStock}',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                ),
                if ((m.previousReserved != m.newReserved) || ((m.newReserved ?? 0) > 0)) ...[
                  const SizedBox(width: 8),
                  Text(
                    '• Reserved: ${m.previousReserved ?? 0} → ${m.newReserved ?? 0}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFFD97706), fontWeight: FontWeight.w500),
                  ),
                ],
                if ((m.previousIncoming != m.newIncoming) || ((m.newIncoming ?? 0) > 0)) ...[
                  const SizedBox(width: 8),
                  Text(
                    '• Incoming: ${m.previousIncoming ?? 0} → ${m.newIncoming ?? 0}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF0D9488), fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),

            // Expanded metadata section
            if (_expanded) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              if (m.referenceLabel != null && m.referenceLabel!.isNotEmpty)
                _buildMetaRow('Document / Ref', '${m.referenceType?.displayName ?? "Doc"}: ${m.referenceLabel}', colorScheme),
              if (m.referenceId != null && m.referenceId!.isNotEmpty && m.referenceId != m.referenceLabel)
                _buildMetaRow('Reference ID', m.referenceId!, colorScheme),
              _buildMetaRow('Logged By', '${m.displayActor} (${m.actorRole})', colorScheme),
              if (m.actorUid != null && m.actorUid!.isNotEmpty)
                _buildMetaRow('Actor UID', m.actorUid!, colorScheme),
              if (m.notes.isNotEmpty)
                _buildMetaRow('Full Notes', m.notes, colorScheme),
              _buildMetaRow('App & Device', '${(m.appVersion?.isNotEmpty ?? false) ? m.appVersion : "v1.0.0"} • ${(m.deviceId?.isNotEmpty ?? false) ? m.deviceId : "client"}', colorScheme),
              if (m.batchId != null && m.batchId!.isNotEmpty)
                _buildMetaRow('Batch ID', m.batchId!, colorScheme),
              _buildMetaRow('Movement ID', m.id, colorScheme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetaRow(String label, String value, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Comprehensive bottom sheet displaying the audit ledger of stock movements
/// with multi-attribute filtering, search, and CSV export.
class InventoryMovementsSheet extends StatefulWidget {
  final InventoryController controller;
  final DateFormat dateFormat;
  final String? initialProductId;

  const InventoryMovementsSheet({
    super.key,
    required this.controller,
    required this.dateFormat,
    this.initialProductId,
  });

  static void show({
    required BuildContext context,
    required InventoryController controller,
    required DateFormat dateFormat,
    String? initialProductId,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => InventoryMovementsSheet(
        controller: controller,
        dateFormat: dateFormat,
        initialProductId: initialProductId,
      ),
    );
  }

  @override
  State<InventoryMovementsSheet> createState() => _InventoryMovementsSheetState();
}

class _InventoryMovementsSheetState extends State<InventoryMovementsSheet> {
  final TextEditingController _searchController = TextEditingController();
  MovementType? _selectedType;
  String _dateFilter = 'All Time'; // 'All Time', 'Today', '7 Days', '30 Days'
  bool _onlyClamped = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime? _getDateFilterThreshold() {
    final now = DateTime.now();
    switch (_dateFilter) {
      case 'Today':
        return DateTime(now.year, now.month, now.day);
      case '7 Days':
        return now.subtract(const Duration(days: 7));
      case '30 Days':
        return now.subtract(const Duration(days: 30));
      default:
        return null;
    }
  }

  Future<void> _exportCsv(List<InventoryMovement> movements) async {
    if (movements.isEmpty) {
      ShowMessage.error(context, 'No movements available to export.');
      return;
    }

    try {
      final csvContent = widget.controller.exportMovementsToCsv(movements);
      final tempDir = await getTemporaryDirectory();
      final nowStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${tempDir.path}/inventory_audit_$nowStr.csv');
      await file.writeAsString(csvContent);

      if (!mounted) return;

      final colorScheme = Theme.of(context).colorScheme;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.table_view_rounded, color: Color(0xFF15803D)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Audit Ledger Exported',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Generated CSV with ${movements.length} audit records.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                file.path,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    csvContent.length > 2000 ? '${csvContent.substring(0, 2000)}...\n[truncated]' : csvContent,
                    style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () => OpenFilex.open(file.path),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Open CSV'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: csvContent));
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ShowMessage.success(context, 'Audit CSV copied to clipboard!');
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy to Clipboard'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to export CSV: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title and Actions Row
              Row(
                children: [
                  Icon(Icons.history_edu_rounded, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Stock Movement Audit Trail',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 8),

              // Search bar
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search product, actor, PO#, store, or notes...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 8),

              // Filter row: Type chips, Date chips, Clamped toggle
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Movement type filter
                    PopupMenuButton<MovementType?>(
                      initialValue: _selectedType,
                      tooltip: 'Filter by Movement Type',
                      onSelected: (type) => setState(() => _selectedType = type),
                      child: Chip(
                        avatar: Icon(
                          _selectedType == null ? Icons.filter_list_rounded : Icons.check_circle_rounded,
                          size: 16,
                          color: _selectedType == null ? colorScheme.onSurfaceVariant : colorScheme.primary,
                        ),
                        label: Text(
                          _selectedType == null ? 'All Types' : _selectedType!.displayName,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: _selectedType != null ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: null,
                          child: Text('All Types'),
                        ),
                        ...MovementType.values.map(
                          (t) => PopupMenuItem(
                            value: t,
                            child: Text(t.displayName),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 6),

                    // Date filters
                    ...['All Time', 'Today', '7 Days', '30 Days'].map((df) {
                      final isSelected = _dateFilter == df;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(df, style: const TextStyle(fontSize: 11)),
                          selected: isSelected,
                          selectedColor: colorScheme.primary.withValues(alpha: 0.18),
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _dateFilter = df),
                        ),
                      );
                    }),

                    // Clamped only toggle
                    FilterChip(
                      label: const Text('Clamped Only', style: TextStyle(fontSize: 11)),
                      selected: _onlyClamped,
                      selectedColor: Colors.amber.shade200,
                      visualDensity: VisualDensity.compact,
                      onSelected: (val) => setState(() => _onlyClamped = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Stream movements list
              Expanded(
                child: StreamBuilder<List<InventoryMovement>>(
                  stream: widget.initialProductId != null
                      ? widget.controller.getProductMovementsStream(widget.initialProductId!, limit: 120)
                      : widget.controller.getRecentMovementsStream(limit: 150),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading movements: ${snapshot.error}',
                          style: TextStyle(color: colorScheme.error),
                        ),
                      );
                    }

                    var logs = snapshot.data ?? [];

                    // Apply in-memory filters
                    final dateThreshold = _getDateFilterThreshold();
                    if (dateThreshold != null) {
                      logs = logs.where((m) => m.createdAt.toDate().isAfter(dateThreshold)).toList();
                    }

                    if (_selectedType != null) {
                      logs = logs.where((m) => m.movementType == _selectedType).toList();
                    }

                    if (_onlyClamped) {
                      logs = logs.where((m) => m.clamped).toList();
                    }

                    final query = _searchController.text.trim().toLowerCase();
                    if (query.isNotEmpty) {
                      logs = logs.where((m) {
                        return m.productName.toLowerCase().contains(query) ||
                            m.notes.toLowerCase().contains(query) ||
                            m.displayActor.toLowerCase().contains(query) ||
                            (m.referenceLabel?.toLowerCase().contains(query) ?? false) ||
                            (m.referenceId?.toLowerCase().contains(query) ?? false) ||
                            m.reason.toLowerCase().contains(query);
                      }).toList();
                    }

                    if (logs.isEmpty) {
                      return Center(
                        child: Text(
                          'No stock movements match your filters.',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      );
                    }

                    return Column(
                      children: [
                        // Results summary and CSV export button
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${logs.length} movement records found',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _exportCsv(logs),
                                icon: const Icon(Icons.download_rounded, size: 16),
                                label: const Text('Export CSV', style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Movement list with ledger continuity verification
                        Expanded(
                          child: ListView.builder(
                            controller: scrollController,
                            itemCount: logs.length,
                            itemBuilder: (context, index) {
                              final m = logs[index];

                              // Detect ledger sequence break for the same product
                              bool isChainBroken = false;
                              for (int nextIdx = index + 1; nextIdx < logs.length; nextIdx++) {
                                final older = logs[nextIdx];
                                if (older.productId == m.productId) {
                                  if (m.previousStock != older.newStock) {
                                    isChainBroken = true;
                                  }
                                  break;
                                }
                              }

                              return InventoryMovementTile(
                                movement: m,
                                dateFormat: widget.dateFormat,
                                isChainBroken: isChainBroken,
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
