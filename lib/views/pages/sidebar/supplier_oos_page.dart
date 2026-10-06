import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/models/supplier_oos_log.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:selecta_ops/services/supplier_oos_service.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/supplier_oos/supplier_oos_product_card.dart';
import 'package:selecta_ops/views/widgets/supplier_oos/supplier_oos_scan_dialog.dart';
import 'package:selecta_ops/views/widgets/supplier_oos/supplier_oos_summary_card.dart';

/// Supplier Out of Stock page monitoring how many days Selecta products
/// were unavailable from the supplier depot, with streak insights, calendar history,
/// and AI-assisted inventory scanning.
class SupplierOosPage extends StatefulWidget {
  const SupplierOosPage({super.key});

  @override
  State<SupplierOosPage> createState() => _SupplierOosPageState();
}

class _SupplierOosPageState extends State<SupplierOosPage> {
  final SelectaProductService _productService = SelectaProductService();
  final SupplierOosService _oosService = SupplierOosService();

  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

  late DateTime _selectedMonth;
  String _searchQuery = '';
  String _selectedFilter = 'oos'; // 'oos', 'streak', 'in_stock', 'all'

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onPreviousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  void _onNextMonth() {
    final now = DateTime.now();
    final next = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    if (!next.isAfter(DateTime(now.year, now.month))) {
      setState(() {
        _selectedMonth = next;
      });
    }
  }

  List<ProductOosSummary> _filterSummaries(List<ProductOosSummary> summaries) {
    var filtered = summaries.where((s) {
      // Search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final name = s.product.productName.toLowerCase();
        final code = s.product.itemCode.toLowerCase();
        final cat = s.product.category.toLowerCase();
        if (!name.contains(q) && !code.contains(q) && !cat.contains(q)) {
          return false;
        }
      }

      // Filter chips
      return switch (_selectedFilter) {
        'oos' => s.isCurrentlyOos,
        'streak' => s.currentStreak > 0 || s.monthOosDays > 0,
        'in_stock' => s.latestStatus == SupplierProductDayStatus.inStock,
        _ => true,
      };
    }).toList();

    // Default sorting is by SRP ascending (as required and identical to book order page)
    // If filtering by streak, order highest streak first
    if (_selectedFilter == 'streak') {
      filtered.sort((a, b) {
        final streakComp = b.currentStreak.compareTo(a.currentStreak);
        if (streakComp != 0) return streakComp;
        return Helperfunctions.compareBySrpAndName(
          nameA: a.product.productName,
          priceA: a.product.sellingPrice,
          nameB: b.product.productName,
          priceB: b.product.sellingPrice,
        );
      });
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final monthStr = DateFormat('MMMM yyyy').format(_selectedMonth);

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Supplier Out of Stock',
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'About Supplier OOS Tracker',
            onPressed: () => _showAboutDialog(context),
          ),
        ],
      ),
      floatingActionButton: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _productService.getProductsStream(),
        builder: (context, snapshot) {
          final products = (snapshot.data?.docs ?? [])
              .map((d) => SelectaProduct.fromJson(d.id, d.data()))
              .toList();

          return FloatingActionButton.extended(
            onPressed: products.isNotEmpty
                ? () {
                    SupplierOosScanDialog.show(
                      context: context,
                      products: products,
                      oosService: _oosService,
                    );
                  }
                : null,
            icon: const Icon(Icons.document_scanner_rounded),
            label: const Text('Scan Supplier Stock'),
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
          );
        },
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _productService.getProductsStream(),
        builder: (context, prodSnapshot) {
          if (prodSnapshot.connectionState == ConnectionState.waiting && !prodSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allSelectaProducts = (prodSnapshot.data?.docs ?? [])
              .map((d) => SelectaProduct.fromJson(d.id, d.data()))
              .toList();

          if (allSelectaProducts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 54, color: colorScheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  const Text('No Selecta products found in catalog.', style: TextStyle(fontSize: 16)),
                ],
              ),
            );
          }

          return StreamBuilder<List<SupplierOosLog>>(
            stream: _oosService.getLogsStreamForMonth(_selectedMonth.year, _selectedMonth.month),
            builder: (context, logSnapshot) {
              final monthLogs = logSnapshot.data ?? [];

              // Compute product summaries, sorted by SRP ascending
              final allSummaries = _oosService.computeSummaries(
                products: allSelectaProducts,
                monthLogs: monthLogs,
              );

              final filteredSummaries = _filterSummaries(allSummaries);
              final oosCount = allSummaries.where((s) => s.isCurrentlyOos).length;
              final streakCount = allSummaries.where((s) => s.currentStreak > 0 || s.monthOosDays > 0).length;

              return Column(
                children: [
                  // KPI Header Card
                  SupplierOosSummaryCard(
                    summaries: allSummaries,
                    selectedMonth: _selectedMonth,
                    totalScansRecorded: monthLogs.length,
                    formattedMonth: monthStr,
                    onPreviousMonth: _onPreviousMonth,
                    onNextMonth: _onNextMonth,
                  ),

                  // Search & Filter Section
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Search bar
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search Selecta product or category...',
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: isDark ? const Color(0xFF1E2430) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                            ),
                          ),
                          onChanged: (val) {
                            setState(() => _searchQuery = val.trim());
                          },
                        ),
                        const SizedBox(height: 8),

                        // Filter Chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildFilterChip('Currently OOS ($oosCount)', 'oos', isError: true),
                              const SizedBox(width: 8),
                              _buildFilterChip('With OOS Streaks ($streakCount)', 'streak'),
                              const SizedBox(width: 8),
                              _buildFilterChip('In Stock at Depot', 'in_stock'),
                              const SizedBox(width: 8),
                              _buildFilterChip('All Products (${allSummaries.length})', 'all'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Product Count Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Showing ${filteredSummaries.length} products (sorted by SRP)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (monthLogs.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, size: 12, color: Colors.orange.shade800),
                                const SizedBox(width: 4),
                                Text(
                                  'No scans in $monthStr',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Product List
                  Expanded(
                    child: filteredSummaries.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.filter_list_off_rounded, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                                const SizedBox(height: 10),
                                Text(
                                  _selectedFilter == 'oos'
                                      ? 'No products currently out of stock.'
                                      : 'No products match your search or filter.',
                                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 88, top: 4),
                            itemCount: filteredSummaries.length,
                            itemBuilder: (ctx, index) {
                              final item = filteredSummaries[index];
                              return SupplierOosProductCard(
                                summary: item,
                                currencyFormat: _currencyFormat,
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, {bool isError = false}) {
    final isSelected = _selectedFilter == value;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      visualDensity: VisualDensity.compact,
      selectedColor: isError ? Colors.red.withValues(alpha: 0.2) : colorScheme.primary.withValues(alpha: 0.18),
      side: BorderSide(
        color: isSelected
            ? (isError ? Colors.red : colorScheme.primary)
            : colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
      onSelected: (_) => setState(() => _selectedFilter = value),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.event_busy_outlined, color: Colors.blue),
            SizedBox(width: 10),
            Text('Supplier OOS Monitoring', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This page tracks how many days Selecta products are out of stock from the supplier depot.\n\n'
              '• Products are sorted by SRP (same as Book Order).\n'
              '• Upload 1 or more images of the supplier stock sheet to scan daily availability.\n'
              '• Undelivered items (0 delivered) reconciled from Purchase Orders are automatically recorded.\n'
              '• Tap the calendar on any product to view monthly availability and copy an official supplier concern note.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
