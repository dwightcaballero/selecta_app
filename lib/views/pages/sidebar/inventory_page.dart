import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/inventory_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/inventory/adjust_stock_sheet.dart';
import 'package:selecta_ops/views/widgets/inventory/inventory_card.dart';
import 'package:selecta_ops/views/widgets/inventory/inventory_movements_sheet.dart';
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
  String _selectedFilter = 'All'; // 'All', 'Selecta', 'Other', 'Needs Restock', 'Low Stock', 'Out of Stock'
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
      if (!item.isActive) return false;
      final matchesSearch = _searchQuery.isEmpty ||
          item.productName.toLowerCase().contains(_searchQuery);
      if (!matchesSearch) return false;

      return switch (_selectedFilter) {
        'Selecta' => item.source == InventoryProductSource.selecta,
        'Other' => item.source == InventoryProductSource.other,
        'Needs Restock' => item.isNeedsRestock,
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
    await AdjustStockSheet.show(
      context: context,
      item: item,
      controller: _controller,
      currencyFormat: _currencyFormat,
      dateFormat: _dateFormat,
    );
    return;
  }


  void _showOverallHistorySheet() {
    InventoryMovementsSheet.show(
      context: context,
      controller: _controller,
      dateFormat: _dateFormat,
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

          final allItems = (snapshot.data ?? []).where((item) => item.isActive).toList();
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
                      'Needs Restock',
                      summary.needsRestockCount > 0 ? summary.needsRestockCount : null,
                      colorScheme,
                      alertColor: const Color(0xFFE11D48),
                    ),
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
                  if (summary.needsRestockCount > 0) ...[
                    GestureDetector(
                      onTap: () => setState(() => _selectedFilter = 'Needs Restock'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE11D48).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFE11D48).withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 13,
                              color: Color(0xFFE11D48),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${summary.needsRestockCount} restock',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFE11D48),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
                      sublabel: summary.totalIncomingUnits > 0
                          ? '${summary.totalUnits} on hand • ${summary.totalIncomingUnits} incoming'
                          : (summary.totalReservedUnits > 0
                              ? '${summary.totalAvailableUnits} avail • ${summary.totalReservedUnits} reserved'
                              : '${summary.totalProducts} active items'),
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
    if (_selectedFilter == 'Needs Restock') {
      if (a.isOutOfStock != b.isOutOfStock) {
        return a.isOutOfStock ? -1 : 1;
      }
    }
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
    return InventoryCard(
      item: item,
      currencyFormat: _currencyFormat,
      onTapCard: () => _showAdjustStockSheet(item),
      onQuickStep: (delta) => _handleQuickStep(item, delta),
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
