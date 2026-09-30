import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/controllers/inventory_controller.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/inventory_movement.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/cached_product_image.dart';
import 'package:intl/intl.dart';

/// Dedicated Inventory Management page unifying active [SelectaProduct] and [OtherProduct] items.
class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final InventoryController _controller = InventoryController();
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy • h:mm a');

  String _searchQuery = '';
  String _selectedFilter = 'All'; // 'All', 'Selecta', 'Other', 'Low Stock', 'Out of Stock'
  bool _isSummaryExpanded = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value.trim().toLowerCase());
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedFilter = 'All';
    });
  }

  List<InventoryItem> _applyFilters(List<InventoryItem> items) {
    return items.where((item) {
      final matchesSearch = _searchQuery.isEmpty ||
          item.productName.toLowerCase().contains(_searchQuery);
      if (!matchesSearch) return false;

      return switch (_selectedFilter) {
        'Selecta' => item.source == InventoryProductSource.selecta,
        'Other' => item.source == InventoryProductSource.other,
        'Low Stock' => item.isLowStock,
        'Out of Stock' => item.isOutOfStock,
        _ => true,
      };
    }).toList();
  }

  Future<void> _handleQuickStep(InventoryItem item, int delta) async {
    if (delta < 0 && item.stockQuantity <= 0) return;
    try {
      await _controller.adjustStockByDelta(
        item: item,
        delta: delta,
        reason: delta > 0 ? 'Quick Restock (+1)' : 'Quick Deduction (-1)',
      );
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to update stock: $e');
      }
    }
  }

  Future<void> _showAdjustStockSheet(InventoryItem item) async {
    String mode = 'add'; // 'add', 'deduct', 'set'
    final qtyController = TextEditingController(text: '1');
    final thresholdController = TextEditingController(
      text: item.lowStockThreshold.toString(),
    );
    final notesController = TextEditingController();
    String selectedReason = 'Restock / PO';
    bool isSaving = false;

    const reasonsByMode = <String, List<String>>{
      'add': ['Restock / PO', 'Return from Store', 'Physical Audit', 'Manual Adjustment'],
      'deduct': ['Delivery / Sale', 'Bad Order', 'Physical Audit', 'Manual Adjustment'],
      'set': ['Physical Audit', 'Initial Stock', 'Manual Adjustment'],
    };

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final colorScheme = Theme.of(ctx).colorScheme;
            final inputVal = int.tryParse(qtyController.text.trim()) ?? 0;
            final previewStock = switch (mode) {
              'add' => item.stockQuantity + (inputVal > 0 ? inputVal : 0),
              'deduct' => (item.stockQuantity - (inputVal > 0 ? inputVal : 0)).clamp(0, 999999),
              _ => inputVal.clamp(0, 999999),
            };
            final previewDelta = previewStock - item.stockQuantity;
            final reasons = reasonsByMode[mode]!;
            if (!reasons.contains(selectedReason)) {
              selectedReason = reasons.first;
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Product Header
                    Row(
                      children: [
                        CachedProductImage(
                          imageUrl: item.imageUrl,
                          isActive: true,
                          size: 48,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  _buildSourceChip(item.source, colorScheme),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Current Stock: ${item.stockQuantity}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.productName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Mode Selector (Add / Deduct / Set Exact)
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'add',
                          icon: Icon(Icons.add_circle_outline, size: 18),
                          label: Text('Stock In (+)'),
                        ),
                        ButtonSegment(
                          value: 'deduct',
                          icon: Icon(Icons.remove_circle_outline, size: 18),
                          label: Text('Stock Out (-)'),
                        ),
                        ButtonSegment(
                          value: 'set',
                          icon: Icon(Icons.fact_check_outlined, size: 18),
                          label: Text('Exact (=)'),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (newSelection) {
                        setSheetState(() {
                          mode = newSelection.first;
                          if (mode == 'set') {
                            qtyController.text = item.stockQuantity.toString();
                          } else if (qtyController.text == item.stockQuantity.toString()) {
                            qtyController.text = '1';
                          }
                          selectedReason = reasonsByMode[mode]!.first;
                        });
                      },
                    ),
                    const SizedBox(height: 14),

                    // Quantity Input + Quick Presets
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: qtyController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            onChanged: (_) => setSheetState(() {}),
                            decoration: InputDecoration(
                              labelText: mode == 'set' ? 'New Exact Stock' : 'Quantity',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: thresholdController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              labelText: 'Low Alert ≤',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Preset quantity buttons
                    if (mode != 'set')
                      Wrap(
                        spacing: 8,
                        children: [1, 5, 10, 20, 50].map((preset) {
                          return ActionChip(
                            label: Text(
                              '${mode == 'add' ? '+' : '-'}$preset',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              setSheetState(() {
                                qtyController.text = preset.toString();
                              });
                            },
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 10),

                    // Reason Chips
                    Text(
                      'Reason',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: reasons.map((reason) {
                        final isSelected = selectedReason == reason;
                        return ChoiceChip(
                          label: Text(
                            reason,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                          selected: isSelected,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setSheetState(() => selectedReason = reason),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),

                    // Optional Notes
                    TextField(
                      controller: notesController,
                      decoration: InputDecoration(
                        labelText: 'Notes / Reference (Optional)',
                        hintText: 'e.g. PO #1024 or Store Name',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Preview Banner + Save Button
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Resulting Stock: ${item.stockQuantity} → $previewStock '
                            '(${previewDelta >= 0 ? '+$previewDelta' : '$previewDelta'})',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _currencyFormat.format(previewStock * item.sellingPrice),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: isSaving
                            ? null
                            : () async {
                                setSheetState(() => isSaving = true);
                                try {
                                  final newThreshold = int.tryParse(
                                        thresholdController.text.trim(),
                                      ) ??
                                      item.lowStockThreshold;
                                  await _controller.updateStock(
                                    item: item,
                                    newStockQuantity: previewStock,
                                    newLowStockThreshold: newThreshold,
                                    reason: selectedReason,
                                    notes: notesController.text,
                                  );
                                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                                  if (mounted) {
                                    ShowMessage.success(
                                      context,
                                      'Updated "${item.productName}" stock to $previewStock.',
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ShowMessage.error(context, 'Failed to update stock: $e');
                                  }
                                } finally {
                                  if (ctx.mounted) {
                                    setSheetState(() => isSaving = false);
                                  }
                                }
                              },
                        icon: isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined, size: 18),
                        label: Text(
                          isSaving ? 'Saving...' : 'Save Stock Adjustment',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),

                    // Product Recent Movements
                    const SizedBox(height: 16),
                    Text(
                      'Recent Stock History',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    StreamBuilder<List<InventoryMovement>>(
                      stream: _controller.getProductMovementsStream(item.id, limit: 5),
                      builder: (context, snap) {
                        final movements = snap.data ?? [];
                        if (movements.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No stock movements recorded for this product yet.',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        }
                        return Column(
                          children: movements
                              .map((m) => _buildMovementTile(m, colorScheme, compact: true))
                              .toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showOverallHistorySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  Row(
                    children: [
                      Icon(Icons.history_rounded, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Stock Movement History',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  Expanded(
                    child: StreamBuilder<List<InventoryMovement>>(
                      stream: _controller.getRecentMovementsStream(limit: 60),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final logs = snapshot.data ?? [];
                        if (logs.isEmpty) {
                          return Center(
                            child: Text(
                              'No stock movements recorded yet.',
                              style: TextStyle(color: colorScheme.onSurfaceVariant),
                            ),
                          );
                        }
                        return ListView.separated(
                          controller: scrollController,
                          itemCount: logs.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            return _buildMovementTile(logs[index], colorScheme);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMovementTile(
    InventoryMovement m,
    ColorScheme colorScheme, {
    bool compact = false,
  }) {
    final isPositive = m.delta >= 0;
    final deltaColor = isPositive ? const Color(0xFF15803D) : colorScheme.error;
    final deltaText = isPositive ? '+${m.delta}' : '${m.delta}';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 5 : 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: deltaColor.withValues(alpha: 0.12),
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
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!compact)
                  Text(
                    m.productName,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  '${m.reason}${m.notes.isNotEmpty ? ' • ${m.notes}' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: compact ? FontWeight.w600 : FontWeight.normal,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${m.previousStock} → ${m.newStock} • ${_dateFormat.format(m.createdAt.toDate())}',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Inventory',
        subtitle: 'Selecta & Other Products Stock',
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, color: Colors.white),
            tooltip: 'Stock Movement History',
            onPressed: _showOverallHistorySheet,
          ),
        ],
      ),
      body: StreamBuilder<List<InventoryItem>>(
        stream: _controller.getActiveInventoryStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load inventory: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final allItems = snapshot.data ?? [];
          final summary = _controller.computeSummary(allItems);
          final filteredItems = _applyFilters(allItems);
          final isFiltered = _searchQuery.isNotEmpty || _selectedFilter != 'All';
          final isKeyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

          return Column(
            children: [
              // ── Summary KPI Banner (hidden while keyboard is open to maximize list space) ──
              if (!isKeyboardVisible) _buildSummaryBanner(summary, colorScheme),

              // ── Search Bar ───────────────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(16, isKeyboardVisible ? 12 : 4, 16, 6),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search active inventory...',
                    hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                    prefixIcon: Icon(Icons.search, size: 20, color: colorScheme.primary),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                    ),
                  ),
                ),
              ),

              // ── Filter Chips ─────────────────────────────────────────────────
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _buildFilterChip('All', null, colorScheme),
                    const SizedBox(width: 8),
                    _buildFilterChip('Selecta', null, colorScheme),
                    const SizedBox(width: 8),
                    _buildFilterChip('Other', null, colorScheme),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'Low Stock',
                      summary.lowStockCount > 0 ? summary.lowStockCount : null,
                      colorScheme,
                      alertColor: const Color(0xFFD97706),
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'Out of Stock',
                      summary.outOfStockCount > 0 ? summary.outOfStockCount : null,
                      colorScheme,
                      alertColor: colorScheme.error,
                    ),
                  ],
                ),
              ),

              // ── Count & Reset Header ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isFiltered
                          ? 'Showing ${filteredItems.length} of ${allItems.length} active products'
                          : '${allItems.length} active product${allItems.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (isFiltered)
                      InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: _resetFilters,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.filter_alt_off_outlined,
                                size: 14,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Reset',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Categorized Product List (Sequence copied from BookOrderPage) ─
              Expanded(
                child: allItems.isEmpty
                    ? _buildEmptyState(
                        title: 'No Active Products Found',
                        subtitle:
                            'Activate products in Selecta Products or Other Products to manage their stock here.',
                        showReset: false,
                      )
                    : filteredItems.isEmpty
                        ? _buildEmptyState(
                            title: 'No Matching Inventory',
                            subtitle: 'Try adjusting your search or filter selection.',
                            showReset: true,
                          )
                        : Builder(
                            builder: (context) {
                              final entries = _buildGroupedEntries(filteredItems, colorScheme);
                              return ListView.builder(
                                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                                itemCount: entries.length,
                                itemBuilder: (context, index) {
                                  final entry = entries[index];
                                  if (entry is _InventoryHeaderEntry) {
                                    return _buildCategorySectionHeader(
                                      title: entry.title,
                                      count: entry.count,
                                      icon: entry.icon,
                                      accentColor: entry.accentColor,
                                      colorScheme: colorScheme,
                                    );
                                  } else if (entry is _InventoryCardEntry) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _buildInventoryCard(entry.item, colorScheme),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(
    String filter,
    int? count,
    ColorScheme colorScheme, {
    Color? alertColor,
  }) {
    final isSelected = _selectedFilter == filter;
    final effectiveColor = alertColor ?? colorScheme.primary;
    final hasCount = count != null && count > 0;

    return FilterChip(
      selected: isSelected,
      label: Text(
        hasCount ? '$filter ($count)' : filter,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: isSelected || hasCount ? FontWeight.bold : FontWeight.w500,
          color: isSelected
              ? colorScheme.onPrimary
              : (hasCount ? effectiveColor : colorScheme.onSurface),
        ),
      ),
      selectedColor: effectiveColor,
      backgroundColor: hasCount && !isSelected
          ? effectiveColor.withValues(alpha: 0.1)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected
              ? effectiveColor
              : (hasCount
                  ? effectiveColor.withValues(alpha: 0.4)
                  : colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onSelected: (_) => setState(() => _selectedFilter = filter),
    );
  }

  Widget _buildSummaryBanner(InventorySummary summary, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _isSummaryExpanded = !_isSummaryExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.analytics_outlined,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Overview',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('•', style: TextStyle(color: colorScheme.outline)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${summary.totalUnits} units  •  Cost: ${_currencyFormat.format(summary.totalCostValue)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _isSummaryExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_isSummaryExpanded) ...[
            Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      label: 'Total Units',
                      value: '${summary.totalUnits}',
                      sublabel: summary.totalReservedUnits > 0
                          ? '${summary.totalAvailableUnits} avail • ${summary.totalReservedUnits} reserved'
                          : '${summary.totalProducts} active items',
                      icon: Icons.inventory_2_outlined,
                      accent: colorScheme.primary,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  Expanded(
                    child: _buildMetricTile(
                      label: 'Cost Value',
                      value: _currencyFormat.format(summary.totalCostValue),
                      sublabel: 'Buying value',
                      icon: Icons.shopping_bag_outlined,
                      accent: const Color(0xFF2563EB),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  Expanded(
                    child: _buildMetricTile(
                      label: 'Retail Value',
                      value: _currencyFormat.format(summary.totalRetailValue),
                      sublabel: 'Selling value',
                      icon: Icons.sell_outlined,
                      accent: const Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required String sublabel,
    required IconData icon,
    required Color accent,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: accent),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
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
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            sublabel,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  int _compareProducts(InventoryItem a, InventoryItem b) {
    return Helperfunctions.compareBySrpAndName(
      nameA: a.productName,
      priceA: a.sellingPrice,
      nameB: b.productName,
      priceB: b.sellingPrice,
    );
  }

  Widget _buildCategorySectionHeader({
    required String title,
    required int count,
    required IconData icon,
    required Color accentColor,
    required ColorScheme colorScheme,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: accentColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                color: accentColor,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count ${count == 1 ? 'item' : 'items'}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_InventoryListEntry> _buildGroupedEntries(
    List<InventoryItem> filtered,
    ColorScheme colorScheme,
  ) {
    final selectaFiltered = filtered
        .where((i) => i.source == InventoryProductSource.selecta)
        .toList()
      ..sort(_compareProducts);
    final otherFiltered = filtered
        .where((i) => i.source != InventoryProductSource.selecta)
        .toList()
      ..sort(_compareProducts);

    final caseProducts = selectaFiltered
        .where((i) => i.category.trim().toLowerCase().contains('case'))
        .toList();
    final pieceProducts = selectaFiltered
        .where((i) => !i.category.trim().toLowerCase().contains('case'))
        .toList();

    final entries = <_InventoryListEntry>[];

    // 1. Selecta: By Case
    if (caseProducts.isNotEmpty) {
      entries.add(
        _InventoryHeaderEntry(
          title: 'By Case',
          count: caseProducts.length,
          icon: Icons.all_inbox_rounded,
          accentColor: const Color(0xFFD97706),
        ),
      );
      for (final p in caseProducts) {
        entries.add(_InventoryCardEntry(p));
      }
    }

    // 2. Selecta: By Piece
    if (pieceProducts.isNotEmpty) {
      entries.add(
        _InventoryHeaderEntry(
          title: 'By Piece',
          count: pieceProducts.length,
          icon: Icons.icecream_outlined,
          accentColor: colorScheme.primary,
        ),
      );
      for (final p in pieceProducts) {
        entries.add(_InventoryCardEntry(p));
      }
    }

    // 3. Other Products at the very bottom
    if (otherFiltered.isNotEmpty) {
      entries.add(
        _InventoryHeaderEntry(
          title: 'Other Products',
          count: otherFiltered.length,
          icon: Icons.inventory_2_outlined,
          accentColor: const Color(0xFF475569),
        ),
      );
      for (final p in otherFiltered) {
        entries.add(_InventoryCardEntry(p));
      }
    }

    return entries;
  }

  Widget _buildInventoryCard(InventoryItem item, ColorScheme colorScheme) {
    final bool isLow = item.isLowStock;
    final bool isOut = item.isOutOfStock;
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
        onTap: () => _showAdjustStockSheet(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CachedProductImage(
                imageUrl: item.imageUrl,
                isActive: !isOut,
                size: 54,
                borderRadius: 10,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.productName,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: isOut ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 3,
                      children: [
                        Text(
                          'Sell: ${_currencyFormat.format(item.sellingPrice)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ),
                        ),
                        Text('•', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                        Text(
                          'Buy: ${_currencyFormat.format(item.buyingPrice)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (isOut) ...[
                          Text('•', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: colorScheme.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Out of Stock',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.error,
                              ),
                            ),
                          ),
                        ] else if (isLow) ...[
                          Text('•', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD97706).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Low Stock',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFB45309),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (item.reservedQuantity > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${item.availableQuantity} available • ${item.reservedQuantity} in pending picklist',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7C3AED),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Quick Stepper Controls (-  Qty  +)
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(9),
                      ),
                      onTap: item.stockQuantity > 0
                          ? () => _handleQuickStep(item, -1)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Icon(
                          Icons.remove_rounded,
                          size: 18,
                          color: item.stockQuantity > 0
                              ? colorScheme.onSurface
                              : colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    Container(
                      constraints: const BoxConstraints(minWidth: 36),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      child: Text(
                        '${item.stockQuantity}',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: stockColor,
                        ),
                      ),
                    ),
                    InkWell(
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(9),
                      ),
                      onTap: () => _handleQuickStep(item, 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceChip(InventoryProductSource source, ColorScheme colorScheme) {
    final isSelecta = source == InventoryProductSource.selecta;
    final chipColor = isSelecta ? colorScheme.primary : const Color(0xFF7C3AED);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        source.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: chipColor,
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required String title,
    required String subtitle,
    required bool showReset,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                size: 40,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            if (showReset) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _resetFilters,
                icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                label: const Text('Reset Filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

sealed class _InventoryListEntry {}

class _InventoryHeaderEntry extends _InventoryListEntry {
  _InventoryHeaderEntry({
    required this.title,
    required this.count,
    required this.icon,
    required this.accentColor,
  });
  final String title;
  final int count;
  final IconData icon;
  final Color accentColor;
}

class _InventoryCardEntry extends _InventoryListEntry {
  _InventoryCardEntry(this.item);
  final InventoryItem item;
}
