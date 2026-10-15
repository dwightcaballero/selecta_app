import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/inventory_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/po_extracted_line.dart';
import 'package:selecta_ops/models/purchaseorder.dart';
import 'package:selecta_ops/views/pages/sidebar/purchaseorder_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Full-page product catalog for restock / Purchase Orders.
///
/// Provides dealers with an expansive, dedicated interface to browse products,
/// search, filter categories (Best Sellers, By Case, By Piece, Pre-order shortages),
/// and set purchase order quantities efficiently without the vertical constraints
/// and accidental dismissal issues of modal bottom sheets.
class PurchaseOrderCatalogPage extends StatefulWidget {
  final List<InventoryItem>? allInventory;
  final List<PoExtractedLine> existingLines;
  final bool isDirectCreationFlow;

  final InventoryController? inventoryController;

  const PurchaseOrderCatalogPage({
    super.key,
    this.allInventory,
    this.existingLines = const [],
    this.isDirectCreationFlow = true,
    this.inventoryController,
  });

  @override
  State<PurchaseOrderCatalogPage> createState() => _PurchaseOrderCatalogPageState();
}

class _PurchaseOrderCatalogPageState extends State<PurchaseOrderCatalogPage> {
  late final InventoryController? _inventoryController;
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  final Map<String, int> _selectedQuantities = {};
  String _selectedCategory = 'all';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.allInventory == null) {
      _inventoryController = widget.inventoryController ?? InventoryController();
    } else {
      _inventoryController = widget.inventoryController;
    }
    for (final line in widget.existingLines) {
      if (line.quantity > 0) {
        _selectedQuantities[line.productId] = line.quantity;
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _compareProducts(InventoryItem a, InventoryItem b) {
    return Helperfunctions.compareBySrpAndName(nameA: a.productName, priceA: a.sellingPrice, nameB: b.productName, priceB: b.sellingPrice);
  }

  Future<void> _promptDirectQuantityDialog(InventoryItem item) async {
    final currentQty = _selectedQuantities[item.id] ?? 0;
    final initialText = currentQty > 0 ? '$currentQty' : '';
    final controller = TextEditingController(text: initialText)..selection = TextSelection(baseOffset: 0, extentOffset: initialText.length);

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(item.productName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Buying Cost: ${_currencyFormat.format(item.buyingPrice)} • On-hand: ${item.stockQuantity} pcs',
                style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Order Quantity (pcs)',
                  hintText: 'Enter quantity',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  suffixIcon: IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => controller.clear()),
                ),
                onSubmitted: (val) {
                  final qty = int.tryParse(val.trim()) ?? 0;
                  Navigator.pop(ctx, qty);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final qty = int.tryParse(controller.text.trim()) ?? 0;
                Navigator.pop(ctx, qty);
              },
              child: const Text('Set Quantity'),
            ),
          ],
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        if (result <= 0) {
          _selectedQuantities.remove(item.id);
        } else {
          _selectedQuantities[item.id] = result;
        }
      });
    }
  }

  List<PoExtractedLine> _buildOrderLines(List<InventoryItem> allInventory) {
    final Map<String, InventoryItem> invMap = {for (final i in allInventory) i.id: i};

    final selectaCatalog = allInventory.where((i) => i.source == InventoryProductSource.selecta).toList();

    final bestSellerProducts = selectaCatalog.where((i) => ProductTag.isBestSeller(i.tag)).toList()..sort(_compareProducts);
    final nonBestSellerSelecta = selectaCatalog.where((i) => !ProductTag.isBestSeller(i.tag)).toList();
    final caseProducts = nonBestSellerSelecta.where((i) => i.category.trim().toLowerCase().contains('case')).toList()..sort(_compareProducts);
    final pieceProducts = nonBestSellerSelecta.where((i) => !i.category.trim().toLowerCase().contains('case')).toList()..sort(_compareProducts);

    final orderedCatalog = [...bestSellerProducts, ...caseProducts, ...pieceProducts];

    final List<PoExtractedLine> result = [];

    // Add selected products in catalog sequence
    for (final item in orderedCatalog) {
      final qty = _selectedQuantities[item.id] ?? 0;
      if (qty > 0) {
        result.add(
          PoExtractedLine(
            productId: item.id,
            productName: item.productName,
            imageUrl: item.imageUrl,
            productSource: item.source.key,
            category: item.category,
            tag: item.tag,
            buyingPrice: item.buyingPrice,
            sellingPrice: item.sellingPrice,
            quantity: qty,
            rawDocText: item.productName,
          ),
        );
      }
    }

    // Include any other items not in standard Selecta sequence (edge cases)
    for (final entry in _selectedQuantities.entries) {
      if (entry.value > 0 && !result.any((r) => r.productId == entry.key)) {
        final inv = invMap[entry.key];
        if (inv != null) {
          result.add(
            PoExtractedLine(
              productId: inv.id,
              productName: inv.productName,
              imageUrl: inv.imageUrl,
              productSource: inv.source.key,
              category: inv.category,
              tag: inv.tag,
              buyingPrice: inv.buyingPrice,
              sellingPrice: inv.sellingPrice,
              quantity: entry.value,
              rawDocText: inv.productName,
            ),
          );
        }
      }
    }

    return result;
  }

  void _onSubmit(List<InventoryItem> allInventory) {
    final lines = _buildOrderLines(allInventory);

    if (widget.isDirectCreationFlow) {
      if (lines.isEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text('No Items Selected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            content: const Text(
              'You have not selected any products yet.\n\nDo you want to proceed with a blank purchase order or stay in the catalog?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Stay in Catalog')),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PurchaseorderPage(purchaseorderID: '', purchaseorder: Purchaseorder.empty()),
                    ),
                  );
                },
                child: const Text('Proceed Blank P.O.'),
              ),
            ],
          ),
        );
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PurchaseorderPage(purchaseorderID: '', purchaseorder: Purchaseorder.empty(), initialLines: lines),
        ),
      );
    } else {
      Navigator.pop(context, lines);
    }
  }

  void _openScannerFlow() {
    if (widget.isDirectCreationFlow) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PurchaseorderPage(purchaseorderID: '', purchaseorder: Purchaseorder.empty(), initialOpenScanner: true),
        ),
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.allInventory != null) {
      final selectaOnly = widget.allInventory!.where((i) => i.source == InventoryProductSource.selecta).toList();
      return _buildScaffold(context, selectaOnly);
    }

    return StreamBuilder<List<InventoryItem>>(
      stream: _inventoryController?.getActiveInventoryStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return Scaffold(
            appBar: CustomAppbar(
              title: widget.isDirectCreationFlow ? 'Restock Catalog' : 'Manual Purchase Order',
              subtitle: widget.isDirectCreationFlow ? 'Select products & quantities for Purchase Order' : 'Update Purchase Order Items',
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final allInventory = (snapshot.data ?? []).where((i) => i.source == InventoryProductSource.selecta).toList();

        return _buildScaffold(context, allInventory);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, List<InventoryItem> allInventory) {
    final colorScheme = Theme.of(context).colorScheme;

    // Filter items according to search query
    final selectaCatalog = allInventory.where((i) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return i.productName.toLowerCase().contains(q) || i.itemCode.toLowerCase().contains(q);
    }).toList();

    // Grouping identical to BookOrderPage
    final bestSellerProducts = selectaCatalog.where((i) => ProductTag.isBestSeller(i.tag)).toList()..sort(_compareProducts);
    final nonBestSeller = selectaCatalog.where((i) => !ProductTag.isBestSeller(i.tag)).toList();
    final caseProducts = nonBestSeller.where((i) => i.category.trim().toLowerCase().contains('case')).toList()..sort(_compareProducts);
    final pieceProducts = nonBestSeller.where((i) => !i.category.trim().toLowerCase().contains('case')).toList()..sort(_compareProducts);

    // Recommended Pre-Orders: Products where pre-orders exceed warehouse stock (shortage)
    // or leave remaining stock at or below lowStockThreshold
    final recommendedPreOrders = selectaCatalog.where((i) => i.isPreOrderRecommended).toList()
      ..sort((a, b) {
        if (a.hasPreOrderShortage && !b.hasPreOrderShortage) return -1;
        if (!a.hasPreOrderShortage && b.hasPreOrderShortage) return 1;
        if (a.hasPreOrderShortage && b.hasPreOrderShortage) {
          final defA = a.preOrderShortage;
          final defB = b.preOrderShortage;
          if (defB != defA) return defB.compareTo(defA);
        } else {
          final remA = a.remainingStockAfterPreOrder;
          final remB = b.remainingStockAfterPreOrder;
          if (remA != remB) return remA.compareTo(remB);
        }
        return _compareProducts(a, b);
      });

    final Map<String, InventoryItem> invMap = {for (final i in allInventory) i.id: i};
    int totalSkus = 0;
    int totalUnits = 0;
    double totalCost = 0.0;

    _selectedQuantities.forEach((id, qty) {
      if (qty > 0) {
        totalSkus++;
        totalUnits += qty;
        final inv = invMap[id];
        if (inv != null) {
          totalCost += qty * inv.buyingPrice;
        }
      }
    });

    final hasSelectedItems = _selectedQuantities.values.any((qty) => qty > 0);

    return PopScope(
      canPop: !hasSelectedItems,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldDiscard = await ShowMessage.confirm(
          context,
          title: 'Discard Selections?',
          message: 'You have selected products in the catalog. Are you sure you want to go back and discard your selections?',
          confirmText: 'Discard',
          cancelText: 'Keep Editing',
          isDestructive: true,
          icon: Icons.warning_amber_rounded,
        );
        if (shouldDiscard && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: CustomAppbar(
          title: widget.isDirectCreationFlow ? 'Restock Catalog' : 'Manual Purchase Order',
          subtitle: widget.isDirectCreationFlow ? 'Restock from Selecta • Select Products' : 'Update Purchase Order Items',
          actions: [
            if (widget.isDirectCreationFlow)
              IconButton(
                icon: const Icon(Icons.document_scanner_outlined, color: Colors.white),
                tooltip: 'Scan Supplier Invoice / Document',
                onPressed: _openScannerFlow,
              ),
          ],
        ),
      bottomNavigationBar: _buildStickyBottomBar(
        context: context,
        totalSkus: totalSkus,
        totalUnits: totalUnits,
        totalCost: totalCost,
        allInventory: allInventory,
      ),
      body: Column(
        children: [
          // ── Search Bar ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search Selecta products or codes...',
                prefixIcon: const Icon(Icons.search, size: 20),
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
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),

          // ── Category Filter Chips ────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                _buildFilterChip('all', 'All Products (${selectaCatalog.length})', Icons.grid_view_rounded),
                if (recommendedPreOrders.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'recommended',
                    'Recommended (${recommendedPreOrders.length})',
                    Icons.auto_awesome_rounded,
                    const Color(0xFF7C3AED),
                  ),
                ],
                const SizedBox(width: 8),
                _buildFilterChip('best_sellers', 'Best Sellers (${bestSellerProducts.length})', Icons.star_rounded, Colors.amber.shade700),
                const SizedBox(width: 8),
                _buildFilterChip('by_case', 'By Case (${caseProducts.length})', Icons.all_inbox_rounded, Colors.orange.shade800),
                const SizedBox(width: 8),
                _buildFilterChip('by_piece', 'By Piece (${pieceProducts.length})', Icons.icecream_outlined, colorScheme.primary),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Grouped Product Catalog List ─────────────────────────────
          Expanded(
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                // 1. Recommended Pre-Orders placed at the VERY TOP
                if (_selectedCategory == 'all' || _selectedCategory == 'recommended')
                  if (recommendedPreOrders.isNotEmpty) ...[
                    _buildSliverHeader('Recommended Pre-Orders', recommendedPreOrders.length, Icons.auto_awesome_rounded, const Color(0xFF7C3AED)),
                    _buildSliverProductList(recommendedPreOrders),
                  ],

                // 2. Best Sellers
                if (_selectedCategory == 'all' || _selectedCategory == 'best_sellers')
                  if (bestSellerProducts.isNotEmpty) ...[
                    _buildSliverHeader('Best Sellers', bestSellerProducts.length, Icons.star_rounded, const Color(0xFFD97706)),
                    _buildSliverProductList(bestSellerProducts),
                  ],

                // 3. By Case
                if (_selectedCategory == 'all' || _selectedCategory == 'by_case')
                  if (caseProducts.isNotEmpty) ...[
                    _buildSliverHeader('By Case', caseProducts.length, Icons.all_inbox_rounded, const Color(0xFFEA580C)),
                    _buildSliverProductList(caseProducts),
                  ],

                // 4. By Piece
                if (_selectedCategory == 'all' || _selectedCategory == 'by_piece')
                  if (pieceProducts.isNotEmpty) ...[
                    _buildSliverHeader('By Piece', pieceProducts.length, Icons.icecream_outlined, colorScheme.primary),
                    _buildSliverProductList(pieceProducts),
                  ],

                if (selectaCatalog.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded, size: 48, color: colorScheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty ? 'No products match "$_searchQuery"' : 'No Selecta products found',
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildFilterChip(String key, String label, IconData icon, [Color? iconColor]) {
    final isSelected = _selectedCategory == key;
    final colorScheme = Theme.of(context).colorScheme;

    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      avatar: Icon(icon, size: 16, color: isSelected ? Colors.white : (iconColor ?? colorScheme.primary)),
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.white : colorScheme.onSurface,
      ),
      selectedColor: colorScheme.primary,
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      onSelected: (_) => setState(() => _selectedCategory = key),
    );
  }

  Widget _buildSliverHeader(String title, int count, IconData icon, Color accentColor) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Row(
          children: [
            Icon(icon, size: 17, color: accentColor),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: accentColor),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
              decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Text(
                '$count',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accentColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverProductList(List<InventoryItem> items) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = items[index];
          final qty = _selectedQuantities[item.id] ?? 0;
          return _buildProductRow(item, qty);
        }, childCount: items.length),
      ),
    );
  }

  Widget _buildProductRow(InventoryItem item, int qty) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = qty > 0;
    final isBestSeller = ProductTag.isBestSeller(item.tag);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.4), width: isSelected ? 1.5 : 1),
      ),
      color: isSelected ? colorScheme.primary.withValues(alpha: 0.04) : colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (!isSelected) {
            HapticFeedback.lightImpact();
            final initialQty = item.isPreOrderRecommended ? item.recommendedPreOrderOrderQuantity : 1;
            setState(() => _selectedQuantities[item.id] = initialQty);
          } else {
            _promptDirectQuantityDialog(item);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CachedProductImage(imageUrl: item.imageUrl, size: 48, borderRadius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.hasPreOrderShortage) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE9FE),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          'Shortage: ${item.preOrderShortage} (Pre-order: ${item.preOrderQuantity} > Stock: ${item.stockQuantity})',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6D28D9)),
                        ),
                      ),
                      const SizedBox(height: 2),
                    ] else if (item.isPreOrderRecommended) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE9FE),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          '⚠️ Low Stock Alert (Pre-order: ${item.preOrderQuantity}, Stock: ${item.stockQuantity} leaves ${item.remainingStockAfterPreOrder} ≤ ${item.lowStockThreshold})',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6D28D9)),
                        ),
                      ),
                      const SizedBox(height: 2),
                    ] else if (item.preOrderQuantity > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFFF3E8FF), borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          'Pre-order: ${item.preOrderQuantity}',
                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF7C3AED)),
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    if (isBestSeller) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(4)),
                        child: const Text(
                          'Best Seller',
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      item.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Cost: ${_currencyFormat.format(item.buyingPrice)}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colorScheme.primary),
                        ),
                        Text('•', style: TextStyle(color: colorScheme.outline)),
                        Text(
                          'Stock: ${item.stockQuantity}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: item.stockQuantity <= 0
                                ? colorScheme.error
                                : (item.isLowStock ? Colors.orange.shade800 : colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Stepper or Add button
              if (qty <= 0)
                FilledButton.tonal(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    final initialQty = item.isPreOrderRecommended ? item.recommendedPreOrderOrderQuantity : 1;
                    setState(() => _selectedQuantities[item.id] = initialQty);
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    minimumSize: const Size(60, 36),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  child: const Text('Add', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                )
              else
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colorScheme.primary.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              if (qty <= 1) {
                                _selectedQuantities.remove(item.id);
                              } else {
                                _selectedQuantities[item.id] = qty - 1;
                              }
                            });
                          },
                          child: SizedBox(
                            width: 32,
                            height: 36,
                            child: Icon(
                              qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                              size: 17,
                              color: qty == 1 ? colorScheme.error : colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          onTap: () => _promptDirectQuantityDialog(item),
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 32),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            alignment: Alignment.center,
                            child: Text(
                              '$qty',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                            ),
                          ),
                        ),
                      ),
                      Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(18)),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _selectedQuantities[item.id] = qty + 1);
                          },
                          child: SizedBox(width: 32, height: 36, child: Icon(Icons.add_rounded, size: 17, color: colorScheme.primary)),
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

  Widget _buildStickyBottomBar({
    required BuildContext context,
    required int totalSkus,
    required int totalUnits,
    required double totalCost,
    required List<InventoryItem> allInventory,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).viewPadding.bottom),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -3))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$totalSkus items • $totalUnits units',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                ),
                Text(
                  _currencyFormat.format(totalCost),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colorScheme.primary),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: () => _onSubmit(allInventory),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: Icon(widget.isDirectCreationFlow ? Icons.arrow_forward_rounded : Icons.check_rounded, size: 20),
            label: Text(
              widget.isDirectCreationFlow ? (totalUnits > 0 ? 'Proceed to P.O. ($totalUnits)' : 'Proceed to P.O.') : 'Apply to P.O. ($totalUnits)',
            ),
          ),
        ],
      ),
    );
  }
}
