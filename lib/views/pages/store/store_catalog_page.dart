import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/store_cart_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:selecta_ops/views/pages/store/store_cart_page.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Store Catalog View for browsing and adding products to order.
/// Stores can order all products regardless of warehouse inventory stock.
/// Inactive products are automatically hidden from the catalog.
class StoreCatalogPage extends StatefulWidget {
  const StoreCatalogPage({super.key});

  @override
  State<StoreCatalogPage> createState() => _StoreCatalogPageState();
}

class _StoreCatalogPageState extends State<StoreCatalogPage> {
  final SelectaProductService _productService = SelectaProductService();
  final StoreCartController _cart = StoreCartController();
  final TextEditingController _searchController = TextEditingController();

  final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  List<SelectaProduct> _products = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedCategory = 'All';

  // Per-product packaging selection: productId -> packaging string ('Piece' | 'Case')
  final Map<String, String> _selectedPackaging = {};

  @override
  void initState() {
    super.initState();
    _cart.addListener(_onCartChanged);
    _loadProducts();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cart.removeListener(_onCartChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      final rawList = await _productService.getAllSelectaProductList();
      final list = rawList.where((p) => p.isActive).toList();
      list.sort((a, b) => Helperfunctions.compareProducts(
            nameA: a.productName,
            priceA: a.sellingPrice,
            nameB: b.productName,
            priceB: b.sellingPrice,
            productIdA: a.id,
            productIdB: b.id,
            categoryA: a.category,
            categoryB: b.category,
          ));

      if (mounted) {
        setState(() {
          _products = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<String> get _categories {
    final set = <String>{'All'};
    for (final p in _products) {
      if (p.category.trim().isNotEmpty) {
        set.add(p.category.trim());
      }
    }
    return set.toList();
  }

  List<SelectaProduct> get _filteredProducts {
    return _products.where((p) {
      if (_selectedCategory != 'All' && p.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final name = p.productName.toLowerCase();
        final flavor = p.flavor.toLowerCase();
        if (!name.contains(query) && !flavor.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Product Catalog',
        subtitle: 'Browse & Add to Order',
        showBackButton: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadProducts,
            tooltip: 'Refresh Products',
          ),
        ],
      ),
      body: Column(
        children: [
          // Sleek Floating Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2430) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: 'Search products or flavors...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                  ),
                  prefixIcon: Icon(Icons.search_rounded, size: 21, color: colorScheme.primary),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
            ),
          ),

          // Categories Filter Chips
          if (_categories.length > 1)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _categories.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final cat = _categories[idx];
                  final isSelected = _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected ? Colors.white : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                    ),
                    backgroundColor: isDark ? const Color(0xFF1E2430) : Colors.white,
                    selectedColor: colorScheme.primary,
                    side: BorderSide(
                      color: isSelected
                          ? colorScheme.primary
                          : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  );
                },
              ),
            ),
          const SizedBox(height: 6),

          // Products List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.inventory_2_outlined, size: 36, color: colorScheme.outline),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty ? 'No products match "$_searchQuery"' : 'No products available',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Try checking your search spelling or change category filter.',
                                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadProducts,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                          itemCount: _filteredProducts.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, idx) {
                            final product = _filteredProducts[idx];
                            final prodId = product.id;
                            final hasCase = product.piecesPerCase != null && product.piecesPerCase! > 1;
                            final selectedPkg = _selectedPackaging[prodId] ?? 'Piece';
                            final isPiece = selectedPkg == 'Piece';

                            final unitPrice = isPiece
                                ? product.sellingPrice
                                : product.sellingPrice * (product.piecesPerCase ?? 1);

                            final currentQtyInCart = _cart.getQuantity(prodId, selectedPkg);
                            final isInCart = currentQtyInCart > 0;

                            final cardBorderColor = isInCart
                                ? colorScheme.primary
                                : (isDark ? const Color(0xFF384152) : const Color(0xFFE2E8F0));
                            final cardBgColor = isInCart
                                ? colorScheme.primary.withValues(alpha: isDark ? 0.12 : 0.04)
                                : (isDark ? const Color(0xFF1E2430) : Colors.white);

                            return Container(
                              decoration: BoxDecoration(
                                color: cardBgColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: cardBorderColor,
                                  width: isInCart ? 1.6 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Product Image
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: CachedProductImage(
                                        imageUrl: product.imageUrl,
                                        size: 72,
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Info & Actions
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            product.productName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14.5,
                                            ),
                                          ),
                                          if (product.flavor.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              product.flavor,
                                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                            ),
                                          ],
                                          const SizedBox(height: 8),

                                          // Packaging selector (Piece vs Case)
                                          if (hasCase) ...[
                                            Row(
                                              children: [
                                                InkWell(
                                                  onTap: () => setState(() => _selectedPackaging[prodId] = 'Piece'),
                                                  borderRadius: BorderRadius.circular(6),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                                    decoration: BoxDecoration(
                                                      color: isPiece
                                                          ? colorScheme.primary
                                                          : colorScheme.surfaceContainerHighest,
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      'Piece',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                        color: isPiece ? colorScheme.onPrimary : colorScheme.onSurface,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                InkWell(
                                                  onTap: () => setState(() => _selectedPackaging[prodId] = 'Case'),
                                                  borderRadius: BorderRadius.circular(6),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                                    decoration: BoxDecoration(
                                                      color: !isPiece
                                                          ? colorScheme.primary
                                                          : colorScheme.surfaceContainerHighest,
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      'Case (${product.piecesPerCase} pcs)',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                        color: !isPiece ? colorScheme.onPrimary : colorScheme.onSurface,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                          ],

                                          // Price & Cart actions
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                _currency.format(unitPrice),
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w800,
                                                  color: colorScheme.primary,
                                                ),
                                              ),

                                              // Add / Stepper
                                              if (isInCart)
                                                Container(
                                                  decoration: BoxDecoration(
                                                    color: colorScheme.surfaceContainerHighest,
                                                    borderRadius: BorderRadius.circular(20),
                                                    border: Border.all(
                                                      color: isDark ? const Color(0xFF384152) : const Color(0xFFCBD5E1),
                                                    ),
                                                  ),
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      IconButton(
                                                        icon: const Icon(Icons.remove_rounded, size: 18),
                                                        padding: EdgeInsets.zero,
                                                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                                        onPressed: () {
                                                          _cart.setQuantity(prodId, selectedPkg, currentQtyInCart - 1);
                                                        },
                                                      ),
                                                      Padding(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                                        child: Text(
                                                          '$currentQtyInCart',
                                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                                        ),
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(Icons.add_rounded, size: 18),
                                                        padding: EdgeInsets.zero,
                                                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                                        onPressed: () {
                                                          _cart.setQuantity(prodId, selectedPkg, currentQtyInCart + 1);
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              else
                                                FilledButton.icon(
                                                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                                                  label: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700)),
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor: colorScheme.primary,
                                                    foregroundColor: Colors.white,
                                                    visualDensity: VisualDensity.compact,
                                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                  ),
                                                  onPressed: () {
                                                    _cart.addItem(product, selectedPkg, quantity: 1);
                                                  },
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),

      // Docked Cart Floating Banner
      bottomSheet: _cart.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2430) : colorScheme.primary,
                border: Border(
                  top: BorderSide(
                    color: isDark ? const Color(0xFF384152) : colorScheme.primary.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.18),
                    blurRadius: 14,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_cart.totalItemCount} items (${_cart.lineCount} products)',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                        Text(
                          'Est. ${_currency.format(_cart.subtotal)}',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: isDark ? const Color(0xFF0F172A) : colorScheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const StoreCartPage()),
                        );
                      },
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('View Cart', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward_rounded, size: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
