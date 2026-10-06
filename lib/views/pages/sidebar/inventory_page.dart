import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/inventory_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/inventory/adjust_stock_sheet.dart';
import 'package:selecta_ops/views/widgets/inventory/floating_stocks_sheet.dart';
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
  String _selectedFilter = 'All'; // 'All', 'By Piece', 'By Case', 'Other', 'Floating', 'Needs Restock', 'Low Stock', 'Out of Stock'

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
      final matchesSearch = _searchQuery.isEmpty || item.productName.toLowerCase().contains(_searchQuery);
      if (!matchesSearch) return false;

      return switch (_selectedFilter) {
        'By Piece' => item.source == InventoryProductSource.selecta && !item.category.trim().toLowerCase().contains('case'),
        'By Case' => item.source == InventoryProductSource.selecta && item.category.trim().toLowerCase().contains('case'),
        'Other' => item.source == InventoryProductSource.other,
        'Incoming' => item.incomingQuantity > 0,
        'Reserved' => item.reservedQuantity > 0,
        'Needs Restock' => item.isNeedsRestock,
        'Low Stock' => item.isLowStock,
        'Out of Stock' => item.isOutOfStock,
        _ => true,
      };
    }).toList();
  }

  Future<void> _showAdjustStockSheet(InventoryItem item) async {
    await AdjustStockSheet.show(context: context, item: item, controller: _controller, currencyFormat: _currencyFormat, dateFormat: _dateFormat);
    return;
  }

  void _showOverallHistorySheet() {
    InventoryMovementsSheet.show(context: context, controller: _controller, dateFormat: _dateFormat);
  }

  void _showFloatingStocksSheet([String? initialProductId]) {
    FloatingStocksSheet.show(context: context, controller: _controller, initialProductId: initialProductId);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<List<InventoryItem>>(
      stream: _controller.getActiveInventoryStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Scaffold(
            appBar: CustomAppbar(title: 'Inventory', subtitle: 'Selecta & Other Products Stock'),
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: const CustomAppbar(title: 'Inventory', subtitle: 'Selecta & Other Products Stock'),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Failed to load inventory: ${snapshot.error}', textAlign: TextAlign.center),
              ),
            ),
          );
        }

        final allItems = (snapshot.data ?? []).where((item) => item.isActive).toList();
        final summary = _controller.computeSummary(allItems);
        final floatingCount = allItems.where((i) => i.incomingQuantity > 0 || i.reservedQuantity > 0).length;
        final filteredItems = _applyFilters(allItems);
        final isKeyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

        return Scaffold(
          appBar: CustomAppbar(
            title: 'Inventory',
            subtitle: allItems.isEmpty
                ? 'Selecta & Other Products Stock'
                : '${summary.totalUnits} units • Cost: ${_currencyFormat.format(summary.totalCostValue)}',
            actions: [_buildAppbarMenu(summary, floatingCount, colorScheme)],
          ),
          body: Column(
            children: [
              // ── Search Bar ───────────────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(16, isKeyboardVisible ? 12 : 8, 16, 6),
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
                      borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
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
                    _buildFilterChip('By Piece', null, colorScheme),
                    const SizedBox(width: 8),
                    _buildFilterChip('By Case', null, colorScheme),
                    const SizedBox(width: 8),
                    _buildFilterChip('Other', null, colorScheme),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'Incoming',
                      summary.totalIncomingUnits > 0 ? summary.totalIncomingUnits : null,
                      colorScheme,
                      alertColor: const Color(0xFF0284C7),
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'Reserved',
                      summary.totalReservedUnits > 0 ? summary.totalReservedUnits : null,
                      colorScheme,
                      alertColor: const Color(0xFF7C3AED),
                    ),
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

              // ── Categorized Product List (Sequence copied from BookOrderPage) ─
              Expanded(
                child: allItems.isEmpty
                    ? _buildEmptyState(
                        title: 'No Active Products Found',
                        subtitle: 'Activate products in Selecta Products or Other Products to manage their stock here.',
                        showReset: false,
                      )
                    : filteredItems.isEmpty
                    ? _buildEmptyState(title: 'No Matching Inventory', subtitle: 'Try adjusting your search or filter selection.', showReset: true)
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
                                return Padding(padding: const EdgeInsets.only(bottom: 8), child: _buildInventoryCard(entry.item, colorScheme));
                              }
                              return const SizedBox.shrink();
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
  }

  Widget _buildFilterChip(String filter, int? count, ColorScheme colorScheme, {Color? alertColor}) {
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
          color: isSelected ? colorScheme.onPrimary : (hasCount ? effectiveColor : colorScheme.onSurface),
        ),
      ),
      selectedColor: effectiveColor,
      backgroundColor: hasCount && !isSelected ? effectiveColor.withValues(alpha: 0.1) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? effectiveColor : (hasCount ? effectiveColor.withValues(alpha: 0.4) : colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onSelected: (_) => setState(() => _selectedFilter = filter),
    );
  }

  Widget _buildAppbarMenu(InventorySummary summary, int floatingCount, ColorScheme colorScheme) {
    final hasAlert = floatingCount > 0 || summary.needsRestockCount > 0;

    return PopupMenuButton<String>(
      tooltip: 'Inventory Options',
      icon: Badge(
        isLabelVisible: hasAlert,
        smallSize: 8,
        backgroundColor: floatingCount > 0 ? const Color(0xFF7C3AED) : const Color(0xFFE11D48),
        child: const Icon(Icons.more_vert_rounded, color: Colors.white),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (action) {
        switch (action) {
          case 'overview':
            _showOverviewSheet(summary);
            break;
          case 'floating':
            _showFloatingStocksSheet();
            break;
          case 'history':
            _showOverallHistorySheet();
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'overview',
          child: Row(
            children: [
              Icon(Icons.analytics_outlined, size: 20, color: colorScheme.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Inventory Overview', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'floating',
          child: Row(
            children: [
              const Icon(Icons.sync_alt_rounded, size: 20, color: Color(0xFF7C3AED)),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Incoming & Reserved Stocks', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (floatingCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFF7C3AED).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    '$floatingCount',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7C3AED)),
                  ),
                ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'history',
          child: Row(
            children: [
              Icon(Icons.history_rounded, size: 20, color: Colors.grey),
              SizedBox(width: 12),
              Text('Movement History', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  void _showOverviewSheet(InventorySummary summary) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.analytics_outlined, color: colorScheme.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Inventory Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(
                            '${summary.totalProducts} active product${summary.totalProducts == 1 ? '' : 's'}',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 18),

              // Valuation Cards Row
              Row(
                children: [
                  Expanded(
                    child: _buildOverviewMetricCard(
                      label: 'Cost Value',
                      value: _currencyFormat.format(summary.totalCostValue),
                      subtitle: 'Buying price cost',
                      icon: Icons.shopping_bag_outlined,
                      accentColor: const Color(0xFF2563EB),
                      colorScheme: colorScheme,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildOverviewMetricCard(
                      label: 'Retail Value',
                      value: _currencyFormat.format(summary.totalRetailValue),
                      subtitle: 'Selling price revenue',
                      icon: Icons.sell_outlined,
                      accentColor: const Color(0xFF15803D),
                      colorScheme: colorScheme,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Potential Margin Tile
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.trending_up_rounded, color: Color(0xFF0D9488), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Potential Gross Margin',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0D9488)),
                          ),
                          Text(
                            _currencyFormat.format(summary.estimatedMarginValue),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              const Text('Stock Breakdown', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              _buildStockBreakdownTile(
                title: 'On-Hand Units',
                value: '${summary.totalUnits} units',
                subtitle: 'Physical stock across all products',
                icon: Icons.inventory_2_outlined,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 8),
              if (summary.totalIncomingUnits > 0 || summary.totalReservedUnits > 0) ...[
                _buildStockBreakdownTile(
                  title: 'Incoming & Reserved Stock',
                  value: '${summary.totalIncomingUnits} incoming • ${summary.totalReservedUnits} reserved',
                  subtitle: '${summary.totalAvailableUnits} available stock',
                  icon: Icons.sync_alt_rounded,
                  color: const Color(0xFF7C3AED),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showFloatingStocksSheet();
                  },
                ),
                const SizedBox(height: 8),
              ],
              if (summary.needsRestockCount > 0) ...[
                _buildStockBreakdownTile(
                  title: 'Needs Restock',
                  value: '${summary.needsRestockCount} products',
                  subtitle: '${summary.outOfStockCount} out of stock • ${summary.lowStockCount} low stock',
                  icon: Icons.warning_amber_rounded,
                  color: const Color(0xFFE11D48),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _selectedFilter = 'Needs Restock');
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverviewMetricCard({
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: accentColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStockBreakdownTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 1),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            Text(
              value,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: color),
            ),
            if (onTap != null) ...[const SizedBox(width: 4), Icon(Icons.chevron_right_rounded, size: 18, color: color)],
          ],
        ),
      ),
    );
  }

  int _compareProducts(InventoryItem a, InventoryItem b) {
    if (_selectedFilter == 'Needs Restock') {
      if (a.isOutOfStock != b.isOutOfStock) {
        return a.isOutOfStock ? -1 : 1;
      }
    }
    return Helperfunctions.compareBySrpAndName(nameA: a.productName, priceA: a.sellingPrice, nameB: b.productName, priceB: b.sellingPrice);
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
            decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 20, color: accentColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: accentColor, letterSpacing: 0.2),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
            decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(12)),
            child: Text(
              '$count ${count == 1 ? 'item' : 'items'}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  List<_InventoryListEntry> _buildGroupedEntries(List<InventoryItem> filtered, ColorScheme colorScheme) {
    final selectaFiltered = filtered.where((i) => i.source == InventoryProductSource.selecta).toList()..sort(_compareProducts);
    final otherFiltered = filtered.where((i) => i.source != InventoryProductSource.selecta).toList()..sort(_compareProducts);

    final caseProducts = selectaFiltered.where((i) => i.category.trim().toLowerCase().contains('case')).toList();
    final pieceProducts = selectaFiltered.where((i) => !i.category.trim().toLowerCase().contains('case')).toList();

    final entries = <_InventoryListEntry>[];

    // 1. Selecta: By Case
    if (caseProducts.isNotEmpty) {
      entries.add(
        _InventoryHeaderEntry(title: 'By Case', count: caseProducts.length, icon: Icons.all_inbox_rounded, accentColor: const Color(0xFFD97706)),
      );
      for (final p in caseProducts) {
        entries.add(_InventoryCardEntry(p));
      }
    }

    // 2. Selecta: By Piece
    if (pieceProducts.isNotEmpty) {
      entries.add(
        _InventoryHeaderEntry(title: 'By Piece', count: pieceProducts.length, icon: Icons.icecream_outlined, accentColor: colorScheme.primary),
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
      onTapFloating: (item.incomingQuantity > 0 || item.reservedQuantity > 0) ? () => _showFloatingStocksSheet(item.id) : null,
    );
  }

  Widget _buildEmptyState({required String title, required String subtitle, required bool showReset}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(Icons.inventory_2_outlined, size: 40, color: colorScheme.primary),
            ),
            const SizedBox(height: 18),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
  _InventoryHeaderEntry({required this.title, required this.count, required this.icon, required this.accentColor});
  final String title;
  final int count;
  final IconData icon;
  final Color accentColor;
}

class _InventoryCardEntry extends _InventoryListEntry {
  _InventoryCardEntry(this.item);
  final InventoryItem item;
}
