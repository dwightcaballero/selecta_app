import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/po_extracted_line.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Modal dialog allowing dealers to manually select products and quantities
/// for a Purchase Order, organized with the exact same category grouping and
/// sort sequence as Book Order Page (Best Sellers -> By Case -> By Piece -> SRP Ascending).
class ManualPoProductPickerDialog extends StatefulWidget {
  final List<InventoryItem> allInventory;
  final List<PoExtractedLine> existingLines;
  final NumberFormat currencyFormat;

  const ManualPoProductPickerDialog({
    super.key,
    required this.allInventory,
    this.existingLines = const [],
    required this.currencyFormat,
  });

  static Future<List<PoExtractedLine>?> show({
    required BuildContext context,
    required List<InventoryItem> allInventory,
    List<PoExtractedLine> existingLines = const [],
    required NumberFormat currencyFormat,
  }) {
    return showModalBottomSheet<List<PoExtractedLine>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ManualPoProductPickerDialog(
        allInventory: allInventory,
        existingLines: existingLines,
        currencyFormat: currencyFormat,
      ),
    );
  }

  @override
  State<ManualPoProductPickerDialog> createState() => _ManualPoProductPickerDialogState();
}

class _ManualPoProductPickerDialogState extends State<ManualPoProductPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, int> _selectedQuantities = {};
  String _selectedCategory = 'all';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
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
    return Helperfunctions.compareBySrpAndName(
      nameA: a.productName,
      priceA: a.sellingPrice,
      nameB: b.productName,
      priceB: b.sellingPrice,
    );
  }

  Future<void> _promptDirectQuantityDialog(InventoryItem item) async {
    final currentQty = _selectedQuantities[item.id] ?? 0;
    final initialText = currentQty > 0 ? '$currentQty' : '';
    final controller = TextEditingController(text: initialText)
      ..selection = TextSelection(baseOffset: 0, extentOffset: initialText.length);

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
                'Buying Cost: ${widget.currencyFormat.format(item.buyingPrice)} • On-hand: ${item.stockQuantity} pcs',
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
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => controller.clear(),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
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

  void _onApply() {
    final Map<String, InventoryItem> invMap = {for (final i in widget.allInventory) i.id: i};

    // Partition and sort exactly matching Book Order Page
    final selectaCatalog = widget.allInventory
        .where((i) => i.source == InventoryProductSource.selecta)
        .toList();

    final bestSellerProducts = selectaCatalog.where((i) => ProductTag.isBestSeller(i.tag)).toList()..sort(_compareProducts);
    final nonBestSellerSelecta = selectaCatalog.where((i) => !ProductTag.isBestSeller(i.tag)).toList();
    final caseProducts = nonBestSellerSelecta.where((i) => i.category.trim().toLowerCase().contains('case')).toList()..sort(_compareProducts);
    final pieceProducts = nonBestSellerSelecta.where((i) => !i.category.trim().toLowerCase().contains('case')).toList()..sort(_compareProducts);

    final orderedCatalog = [
      ...bestSellerProducts,
      ...caseProducts,
      ...pieceProducts,
    ];

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

    // Include any other items not in Selecta sequence (edge case)
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

    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Filter items according to search query
    final selectaCatalog = widget.allInventory
        .where((i) => i.source == InventoryProductSource.selecta)
        .where((i) {
          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          return i.productName.toLowerCase().contains(q) || i.itemCode.toLowerCase().contains(q);
        })
        .toList();

    // Grouping identical to BookOrderPage
    final bestSellerProducts = selectaCatalog.where((i) => ProductTag.isBestSeller(i.tag)).toList()..sort(_compareProducts);
    final nonBestSeller = selectaCatalog.where((i) => !ProductTag.isBestSeller(i.tag)).toList();
    final caseProducts = nonBestSeller.where((i) => i.category.trim().toLowerCase().contains('case')).toList()..sort(_compareProducts);
    final pieceProducts = nonBestSeller.where((i) => !i.category.trim().toLowerCase().contains('case')).toList()..sort(_compareProducts);

    // Recommended Pre-Orders: Products where pre-orders exceed warehouse stock (shortage)
    // or leave remaining stock at or below lowStockThreshold
    final recommendedPreOrders = selectaCatalog
        .where((i) => i.isPreOrderRecommended)
        .toList()
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

    final Map<String, InventoryItem> invMap = {for (final i in widget.allInventory) i.id: i};
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

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Drag Handle ──────────────────────────────────────────────
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

          // ── Header ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.playlist_add_rounded, color: colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Manual Purchase Order',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Select products and order quantities',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // ── Search Bar ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search Selecta products...',
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),

          // ── Category Filter Chips ────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Row(
              children: [
                _buildFilterChip('all', 'All Products (${selectaCatalog.length})', Icons.grid_view_rounded),
                if (recommendedPreOrders.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _buildFilterChip('recommended', 'Recommended (${recommendedPreOrders.length})', Icons.auto_awesome_rounded, const Color(0xFF7C3AED)),
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
                          Text('No products found', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
            ),
          ),

          // ── Sticky Bottom Bar ────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).viewPadding.bottom),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -3)),
              ],
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
                        widget.currencyFormat.format(totalCost),
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colorScheme.primary),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: totalUnits > 0 ? _onApply : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: Text('Apply to P.O. ($totalUnits)'),
                ),
              ],
            ),
          ),
        ],
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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: accentColor),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: accentColor),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
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
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = items[index];
            final qty = _selectedQuantities[item.id] ?? 0;
            return _buildProductRow(item, qty);
          },
          childCount: items.length,
        ),
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
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: isSelected ? 1.4 : 1,
        ),
      ),
      color: isSelected ? colorScheme.primary.withValues(alpha: 0.04) : colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CachedProductImage(imageUrl: item.imageUrl, size: 44, borderRadius: 8),
            const SizedBox(width: 10),
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
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E8FF),
                        borderRadius: BorderRadius.circular(4),
                      ),
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
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(4),
                      ),
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
                        'Cost: ${widget.currencyFormat.format(item.buyingPrice)}',
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
                    InkWell(
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
                    InkWell(
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
                    InkWell(
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(18)),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() => _selectedQuantities[item.id] = qty + 1);
                      },
                      child: SizedBox(
                        width: 32,
                        height: 36,
                        child: Icon(Icons.add_rounded, size: 17, color: colorScheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
