import 'package:barcode_widget/barcode_widget.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart' hide Barcode;
import 'package:selecta_ops/models/other_product.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/services/other_product_service.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:selecta_ops/views/pages/dashboard/book_order_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/views/widgets/shimmer_loading.dart';

enum CatalogSortOption {
  nameAsc('Name (A-Z)'),
  nameDesc('Name (Z-A)'),
  priceAsc('Price (Low to High)'),
  priceDesc('Price (High to Low)'),
  marginDesc('Highest Margin %'),
  stockDesc('Stock Available');

  final String label;
  const CatalogSortOption(this.label);
}

enum CatalogViewMode {
  cards,
  table,
}

/// Unified Product item used for catalog browsing & price list comparison.
class CatalogItem {
  final String id;
  final String name;
  final String itemCode;
  final String category;
  final String imageUrl;
  final double buyingPrice;
  final double sellingPrice;
  final int stockQuantity;
  final bool isSelecta;
  final bool isActive;

  const CatalogItem({
    required this.id,
    required this.name,
    required this.itemCode,
    required this.category,
    required this.imageUrl,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.stockQuantity,
    required this.isSelecta,
    required this.isActive,
  });

  double get margin => sellingPrice - buyingPrice;
  double get marginPercent =>
      buyingPrice > 0 ? ((sellingPrice - buyingPrice) / buyingPrice) * 100 : 0.0;
  double get grossMarginRatio =>
      sellingPrice > 0 ? ((sellingPrice - buyingPrice) / sellingPrice) * 100 : 0.0;
  bool get isOutOfStock => stockQuantity <= 0;
  bool get isLowStock => stockQuantity > 0 && stockQuantity <= 10;
}

/// Searchable Product Catalog & Price List Reference Screen.
///
/// Designed for Salesmen and Dealers for quick field reference during store visits:
/// - Realtime search across Selecta Ice Cream and Other Products.
/// - Live wholesale cost (Buying Price), Suggested Retail Price (SRP), and Profit Margin %.
/// - Category filter chips and Brand switchers.
/// - Integrated Barcode scanner & Barcode display for quick store verification.
/// - Card view and Compact Price Sheet Table view.
class ProductCatalogPage extends StatefulWidget {
  const ProductCatalogPage({super.key});

  @override
  State<ProductCatalogPage> createState() => _ProductCatalogPageState();
}

class _ProductCatalogPageState extends State<ProductCatalogPage> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final shortCurrency = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

  late TabController _brandTabController;
  String _selectedCategory = 'All';
  CatalogSortOption _sortOption = CatalogSortOption.nameAsc;
  CatalogViewMode _viewMode = CatalogViewMode.cards;
  bool _onlyInStock = false;
  String _searchQuery = '';

  int _selectedBrandTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _brandTabController = TabController(length: 3, vsync: this);
    _brandTabController.addListener(() {
      if (mounted && _selectedBrandTabIndex != _brandTabController.index) {
        setState(() => _selectedBrandTabIndex = _brandTabController.index);
      }
    });
    _searchController.addListener(() {
      if (mounted) setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _brandTabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _openBarcodeScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.7,
          decoration: BoxDecoration(
            color: Theme.of(ctx).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              AppBar(
                title: const Text('Scan Product Barcode'),
                centerTitle: true,
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      MobileScanner(
                        onDetect: (capture) {
                          final barcodes = capture.barcodes;
                          for (final barcode in barcodes) {
                            final rawValue = barcode.rawValue;
                            if (rawValue != null && rawValue.isNotEmpty) {
                              Navigator.pop(ctx);
                              _searchController.text = rawValue;
                              ShowMessage.success(context, 'Scanned Barcode: $rawValue');
                              break;
                            }
                          }
                        },
                      ),
                      Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.redAccent, width: 2.5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Point camera at product barcode or SKU packaging',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Product Catalog & Price List',
        actions: [
          IconButton(
            icon: Icon(_viewMode == CatalogViewMode.cards ? Icons.table_chart_outlined : Icons.grid_view_rounded),
            tooltip: _viewMode == CatalogViewMode.cards ? 'Switch to Table View' : 'Switch to Cards View',
            onPressed: () {
              setState(() {
                _viewMode = _viewMode == CatalogViewMode.cards ? CatalogViewMode.table : CatalogViewMode.cards;
              });
            },
          ),
          PopupMenuButton<CatalogSortOption>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort Products',
            onSelected: (option) => setState(() => _sortOption = option),
            itemBuilder: (context) => CatalogSortOption.values.map((opt) {
              return PopupMenuItem(
                value: opt,
                child: Row(
                  children: [
                    if (_sortOption == opt)
                      Icon(Icons.check, size: 16, color: colorScheme.primary)
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Text(opt.label, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Scanner Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: isDark ? const Color(0xFF1E2430) : colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search product, barcode, SKU, category...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: isDark ? const Color(0xFF141822) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  onPressed: _openBarcodeScanner,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  tooltip: 'Scan Barcode',
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),

          // Brand Tabs (All, Selecta, Other)
          Container(
            color: isDark ? const Color(0xFF1E2430) : colorScheme.surface,
            child: TabBar(
              controller: _brandTabController,
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              indicatorColor: colorScheme.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(text: 'All Products'),
                Tab(text: 'Selecta Ice Cream'),
                Tab(text: 'Other Products'),
              ],
            ),
          ),

          // Stock Filter Toggle & Margin Reference Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF171B24) : colorScheme.surfaceContainerLowest,
              border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF28303F) : colorScheme.outlineVariant.withValues(alpha: 0.3))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    FilterChip(
                      label: const Text('In Stock Only', style: TextStyle(fontSize: 12)),
                      selected: _onlyInStock,
                      showCheckmark: true,
                      visualDensity: VisualDensity.compact,
                      onSelected: (val) => setState(() => _onlyInStock = val),
                    ),
                  ],
                ),
                Text(
                  'Pricing: Wholesale vs SRP (Retail)',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),

          // Product List / Table Stream
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection(SELECTA_PRODUCTS_COLLECTION_REF).snapshots(),
              builder: (context, selectaSnapshot) {
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection(OTHER_PRODUCTS_COLLECTION_REF).snapshots(),
                  builder: (context, otherSnapshot) {
                    if (!selectaSnapshot.hasData || !otherSnapshot.hasData) {
                      return ListView.builder(
                        itemCount: 6,
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (_, _) => const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: ShimmerBox(width: double.infinity, height: 90, borderRadius: 12),
                        ),
                      );
                    }

                    // Parse items
                    final List<CatalogItem> allItems = [];

                    // Selecta Products
                    for (final doc in selectaSnapshot.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final product = SelectaProduct.fromJson(doc.id, data);
                      if (!product.isActive) continue;

                      allItems.add(CatalogItem(
                        id: product.id,
                        name: product.productName,
                        itemCode: product.itemCode,
                        category: product.category.isNotEmpty ? product.category : 'Selecta',
                        imageUrl: product.imageUrl,
                        buyingPrice: product.buyingPrice,
                        sellingPrice: product.sellingPrice,
                        stockQuantity: product.stockQuantity,
                        isSelecta: true,
                        isActive: product.isActive,
                      ));
                    }

                    // Other Products
                    for (final doc in otherSnapshot.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final product = OtherProduct.fromJson(data);
                      if (!product.isActive) continue;

                      allItems.add(CatalogItem(
                        id: doc.id,
                        name: product.productName,
                        itemCode: doc.id,
                        category: 'Other Products',
                        imageUrl: product.imageUrl,
                        buyingPrice: product.buyingPrice,
                        sellingPrice: product.sellingPrice,
                        stockQuantity: product.stockQuantity,
                        isSelecta: false,
                        isActive: product.isActive,
                      ));
                    }

                    // Extract unique categories
                    final categories = {'All', ...allItems.map((e) => e.category).where((c) => c.isNotEmpty)};

                    // Filter by Brand Tab
                    var filtered = allItems.where((item) {
                      if (_selectedBrandTabIndex == 1 && !item.isSelecta) return false;
                      if (_selectedBrandTabIndex == 2 && item.isSelecta) return false;
                      return true;
                    }).toList();

                    // Filter by Category
                    if (_selectedCategory != 'All') {
                      filtered = filtered.where((item) => item.category == _selectedCategory).toList();
                    }

                    // Filter by In-Stock
                    if (_onlyInStock) {
                      filtered = filtered.where((item) => item.stockQuantity > 0).toList();
                    }

                    // Filter by Search
                    if (_searchQuery.isNotEmpty) {
                      filtered = filtered.where((item) {
                        return item.name.toLowerCase().contains(_searchQuery) ||
                            item.itemCode.toLowerCase().contains(_searchQuery) ||
                            item.category.toLowerCase().contains(_searchQuery);
                      }).toList();
                    }

                    // Sort items
                    filtered.sort((a, b) {
                      switch (_sortOption) {
                        case CatalogSortOption.nameAsc:
                          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                        case CatalogSortOption.nameDesc:
                          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
                        case CatalogSortOption.priceAsc:
                          return a.sellingPrice.compareTo(b.sellingPrice);
                        case CatalogSortOption.priceDesc:
                          return b.sellingPrice.compareTo(a.sellingPrice);
                        case CatalogSortOption.marginDesc:
                          return b.marginPercent.compareTo(a.marginPercent);
                        case CatalogSortOption.stockDesc:
                          return b.stockQuantity.compareTo(a.stockQuantity);
                      }
                    });

                    return Column(
                      children: [
                        // Category Filter Chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: categories.map((cat) {
                              final isSelected = _selectedCategory == cat;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(cat, style: const TextStyle(fontSize: 12)),
                                  selected: isSelected,
                                  onSelected: (val) {
                                    if (val) setState(() => _selectedCategory = cat);
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        // Results Count Bar
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${filtered.length} products found',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                              ),
                              Text(
                                'Sorted by: ${_sortOption.label}',
                                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),

                        // List content
                        Expanded(
                          child: filtered.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.inventory_2_outlined, size: 54, color: colorScheme.outlineVariant),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No matching products found',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Try adjusting your search or category filters.',
                                        style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                )
                              : _viewMode == CatalogViewMode.cards
                                  ? ListView.builder(
                                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                      itemCount: filtered.length,
                                      itemBuilder: (context, index) {
                                        return _buildProductCard(context, filtered[index], isDark, colorScheme);
                                      },
                                    )
                                  : _buildTableView(context, filtered, isDark, colorScheme),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CARD VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildProductCard(BuildContext context, CatalogItem item, bool isDark, ColorScheme colorScheme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? const Color(0xFF28303F) : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showProductDetailsModal(context, item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image
              CachedProductImage(
                imageUrl: item.imageUrl,
                size: 72,
                borderRadius: 10,
              ),
              const SizedBox(width: 14),

              // Product Info & Price Matrix
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category & Brand badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: item.isSelecta
                                ? colorScheme.primary.withValues(alpha: isDark ? 0.25 : 0.1)
                                : Colors.teal.withValues(alpha: isDark ? 0.25 : 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.isSelecta ? 'Selecta' : 'Other',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: item.isSelecta ? colorScheme.primary : Colors.teal,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.category,
                            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Stock Indicator
                        _buildStockBadge(item),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Product Name
                    Text(
                      item.name,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    if (item.itemCode.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Code/Barcode: ${item.itemCode}',
                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, fontFamily: 'monospace'),
                      ),
                    ],

                    const SizedBox(height: 8),

                    // Price & Margin Breakdown Grid
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF141822) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Dealer Cost', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                              Text(
                                currencyFormat.format(item.buyingPrice),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('SRP (Retail)', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                              Text(
                                currencyFormat.format(item.sellingPrice),
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Retailer Margin', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                              Row(
                                children: [
                                  Icon(Icons.arrow_upward_rounded, size: 12, color: Colors.green.shade600),
                                  Text(
                                    '+${item.marginPercent.toStringAsFixed(1)}%',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade600),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
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

  // ═══════════════════════════════════════════════════════════════════════════
  // TABLE VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTableView(BuildContext context, List<CatalogItem> items, bool isDark, ColorScheme colorScheme) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            isDark ? const Color(0xFF1E2430) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          columnSpacing: 18,
          columns: const [
            DataColumn(label: Text('Product Name', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Dealer Cost', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('SRP (Retail)', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Profit', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Margin %', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Stock', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: items.map((item) {
            return DataRow(
              onSelectChanged: (_) => _showProductDetailsModal(context, item),
              cells: [
                DataCell(
                  SizedBox(
                    width: 180,
                    child: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(Text(item.category, style: const TextStyle(fontSize: 12))),
                DataCell(Text(currencyFormat.format(item.buyingPrice), style: const TextStyle(fontSize: 12))),
                DataCell(
                  Text(
                    currencyFormat.format(item.sellingPrice),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                ),
                DataCell(
                  Text(
                    currencyFormat.format(item.margin),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade600),
                  ),
                ),
                DataCell(
                  Text(
                    '+${item.marginPercent.toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade600),
                  ),
                ),
                DataCell(_buildStockBadge(item)),
                DataCell(
                  IconButton(
                    icon: const Icon(Icons.info_outline, size: 20),
                    tooltip: 'View Specs',
                    onPressed: () => _showProductDetailsModal(context, item),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildStockBadge(CatalogItem item) {
    if (item.isOutOfStock) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: const Text(
          'Out of Stock',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red),
        ),
      );
    }
    if (item.isLowStock) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Text(
          'Low: ${item.stockQuantity}',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Text(
        'Stock: ${item.stockQuantity}',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade700),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRODUCT DETAIL & BARCODE MODAL
  // ═══════════════════════════════════════════════════════════════════════════

  void _showProductDetailsModal(BuildContext context, CatalogItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title & Close
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.category} • ${item.isSelecta ? "Selecta Ice Cream" : "Other Product"}',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Pricing Matrix Comparison Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E2430), const Color(0xFF141822)]
                        : [colorScheme.primaryContainer.withValues(alpha: 0.4), colorScheme.primaryContainer.withValues(alpha: 0.1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildDetailPriceColumn('Dealer Cost', item.buyingPrice, colorScheme.onSurface),
                        const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
                        _buildDetailPriceColumn('Suggested Retail', item.sellingPrice, colorScheme.primary),
                        const Icon(Icons.equalizer_rounded, size: 16, color: Colors.grey),
                        _buildDetailPriceColumn('Store Profit', item.margin, Colors.green.shade600),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Retailer Gross Margin', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                        Text(
                          '+${item.marginPercent.toStringAsFixed(1)}% Markup (${item.grossMarginRatio.toStringAsFixed(1)}% Margin)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Barcode display if barcode is available
              if (item.itemCode.isNotEmpty) ...[
                const Text('Product Barcode / SKU Code', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      BarcodeWidget(
                        barcode: Barcode.code128(),
                        data: item.itemCode,
                        width: double.infinity,
                        height: 60,
                        color: Colors.black,
                        drawText: true,
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        label: const Text('Copy Barcode Number', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: item.itemCode));
                          ShowMessage.success(context, 'Barcode ${item.itemCode} copied to clipboard.');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Quick Action: Book Order with this product
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: const Text('Create Order for Customer'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BookOrderPage()),
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

  Widget _buildDetailPriceColumn(String label, double amount, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          currencyFormat.format(amount),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
