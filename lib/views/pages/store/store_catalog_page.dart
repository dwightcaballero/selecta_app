import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/store_cart_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:selecta_ops/views/pages/store/store_cart_page.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Store Catalog View for browsing and adding products to order.
/// Strictly enforces stock badge visibility ('Available' / 'Out of stock')
/// without exposing any inventory quantities to store users.
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
      final list = await _productService.getAllSelectaProductList();
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
      appBar: AppBar(
        title: const Text('Product Catalog'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadProducts,
            tooltip: 'Refresh Products',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search products or flavors...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),

          // Categories Filter Chips
          if (_categories.length > 1)
            SizedBox(
              height: 44,
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
                  );
                },
              ),
            ),
          const SizedBox(height: 8),

          // Products List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 54, color: colorScheme.outlineVariant),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty ? 'No products match "$_searchQuery"' : 'No products available.',
                              style: TextStyle(color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadProducts,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
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

                            final isOutOfStock = product.isOutOfStock;
                            final currentQtyInCart = _cart.getQuantity(prodId, selectedPkg);

                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: currentQtyInCart > 0
                                      ? colorScheme.primary.withValues(alpha: 0.6)
                                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                                  width: currentQtyInCart > 0 ? 1.5 : 1,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Image
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: CachedProductImage(
                                        imageUrl: product.imageUrl,
                                        size: 72,
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  product.productName,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              // Stock availability badge (NO numeric quantity!)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: isOutOfStock
                                                      ? Colors.red.withValues(alpha: isDark ? 0.25 : 0.12)
                                                      : Colors.green.withValues(alpha: isDark ? 0.25 : 0.12),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  isOutOfStock ? 'Out of stock' : 'Available',
                                                  style: TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: isOutOfStock ? Colors.red : Colors.green,
                                                  ),
                                                ),
                                              ),
                                            ],
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
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                                                        fontWeight: FontWeight.bold,
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
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                                                        fontWeight: FontWeight.bold,
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
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w800,
                                                  color: colorScheme.primary,
                                                ),
                                              ),

                                              // Add / Stepper
                                              if (isOutOfStock)
                                                const Text(
                                                  'Temporarily Unavailable',
                                                  style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                                                )
                                              else if (currentQtyInCart > 0)
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(Icons.remove_circle_outline, size: 22),
                                                      padding: EdgeInsets.zero,
                                                      constraints: const BoxConstraints(),
                                                      onPressed: () {
                                                        _cart.setQuantity(prodId, selectedPkg, currentQtyInCart - 1);
                                                      },
                                                    ),
                                                    Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                                      child: Text(
                                                        '$currentQtyInCart',
                                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.add_circle, size: 22),
                                                      padding: EdgeInsets.zero,
                                                      constraints: const BoxConstraints(),
                                                      onPressed: () {
                                                        _cart.setQuantity(prodId, selectedPkg, currentQtyInCart + 1);
                                                      },
                                                    ),
                                                  ],
                                                )
                                              else
                                                ElevatedButton.icon(
                                                  icon: const Icon(Icons.add_shopping_cart, size: 16),
                                                  label: const Text('Add'),
                                                  style: ElevatedButton.styleFrom(
                                                    visualDensity: VisualDensity.compact,
                                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                color: colorScheme.primary,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Icon(Icons.shopping_bag_outlined, color: colorScheme.onPrimary),
                    const SizedBox(width: 10),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_cart.totalItemCount} items (${_cart.lineCount} products)',
                          style: TextStyle(color: colorScheme.onPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          'Est. ${_currency.format(_cart.subtotal)}',
                          style: TextStyle(color: colorScheme.onPrimary.withValues(alpha: 0.9), fontSize: 12),
                        ),
                      ],
                    ),
                    const Spacer(),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.onPrimary,
                        foregroundColor: colorScheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const StoreCartPage()),
                        );
                      },
                      child: const Row(
                        children: [
                          Text('View Cart', style: TextStyle(fontWeight: FontWeight.bold)),
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
