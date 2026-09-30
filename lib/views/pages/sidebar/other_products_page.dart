import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/controllers/other_product_controller.dart';
import 'package:flutter_app/models/other_product.dart';
import 'package:flutter_app/views/pages/sidebar/other_product_form_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/cached_product_image.dart';
import 'package:intl/intl.dart';

/// Other Products catalog page — list, search, add, edit, delete, toggle active.
class OtherProductsPage extends StatefulWidget {
  const OtherProductsPage({super.key});

  @override
  State<OtherProductsPage> createState() => _OtherProductsPageState();
}

class _OtherProductsPageState extends State<OtherProductsPage> {
  final OtherProductController _controller = OtherProductController();
  final TextEditingController _searchController = TextEditingController();
  final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  String _searchQuery = '';
  String _filterStatus = 'All'; // 'All', 'Active', 'Inactive'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    setState(() => _searchQuery = text.trim().toLowerCase());
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _filterStatus = 'All';
    });
  }

  List<QueryDocumentSnapshot<OtherProduct>> _applyFilters(List<QueryDocumentSnapshot<OtherProduct>> docs) {
    return docs.where((doc) {
      final p = doc.data();
      final matchesSearch = _searchQuery.isEmpty || p.productName.toLowerCase().contains(_searchQuery);
      final matchesStatus = _filterStatus == 'All' || (_filterStatus == 'Active' && p.isActive) || (_filterStatus == 'Inactive' && !p.isActive);
      return matchesSearch && matchesStatus;
    }).toList();
  }

  Future<void> _navigateToForm({String? productId, OtherProduct? product}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OtherProductFormPage(productId: productId, existingProduct: product),
      ),
    );
  }

  Future<void> _toggleActive(String productId, String name, bool currentlyActive) async {
    try {
      await _controller.toggleActive(productId, !currentlyActive);
      if (mounted) {
        ShowMessage.success(context, '"$name" is now ${!currentlyActive ? 'Active' : 'Inactive'}.');
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to update status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const CustomAppbar(
        title: 'Other Products',
        subtitle: 'Dealer Other Products Catalog',
      ),
      body: Column(
        children: [
          // ── Search Bar ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search other products...',
                hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                prefixIcon: Icon(Icons.search, size: 20, color: colorScheme.primary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'Clear search',
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

          // ── Status Filter Chips ──────────────────────────────────────────
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final status = const ['All', 'Active', 'Inactive'][index];
                final isSelected = _filterStatus == status;
                return FilterChip(
                  selected: isSelected,
                  label: Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                    ),
                  ),
                  selectedColor: colorScheme.primary,
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  checkmarkColor: colorScheme.onPrimary,
                  showCheckmark: false,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  onSelected: (_) => setState(() => _filterStatus = status),
                );
              },
            ),
          ),

          // ── Products List ────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot<OtherProduct>>(
              stream: _controller.getProductsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _buildErrorState(snapshot.error.toString());
                }

                final allDocs = snapshot.data?.docs ?? [];
                final filtered = _applyFilters(allDocs);

                if (allDocs.isEmpty) {
                  return _buildEmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No Products Yet',
                    subtitle: 'Tap the + button to add your first product to the catalog.',
                  );
                }

                final isFiltered = _searchQuery.isNotEmpty || _filterStatus != 'All';

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isFiltered
                                ? 'Showing ${filtered.length} of ${allDocs.length} products'
                                : '${allDocs.length} product${allDocs.length == 1 ? '' : 's'} in catalog',
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
                                    Icon(Icons.filter_alt_off_outlined, size: 14, color: colorScheme.primary),
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
                    Expanded(
                      child: filtered.isEmpty
                          ? _buildEmptyState(
                              icon: Icons.search_off_rounded,
                              title: 'No Results Found',
                              subtitle: 'Try adjusting your search or filter to find products.',
                              showResetButton: true,
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 88),
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final doc = filtered[index];
                                return _buildProductCard(doc);
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToForm(),
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('Add Product', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildProductCard(QueryDocumentSnapshot<OtherProduct> doc) {
    final product = doc.data();
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = product.isActive;
    final isPositiveMargin = product.margin >= 0;
    final marginColor = isPositiveMargin ? const Color(0xFF15803D) : colorScheme.error;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _navigateToForm(productId: doc.id, product: product),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _buildProductImage(product.imageUrl, isActive),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.productName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            currencyFormat.format(product.buyingPrice),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isActive ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            currencyFormat.format(product.sellingPrice),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: product.sellingPrice > 0 && product.buyingPrice > 0
                              ? Text(
                                  '${currencyFormat.format(product.margin)} (${isPositiveMargin ? '+' : ''}${product.marginPercent.round()}%)',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: isActive ? marginColor : colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _toggleActive(doc.id, product.productName, product.isActive),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38,
                  height: 22,
                  decoration: BoxDecoration(
                    color: isActive ? colorScheme.primary : colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Align(
                    alignment: isActive ? Alignment.centerRight : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(2.5),
                      child: Container(
                        width: 17,
                        height: 17,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductImage(String imageUrl, bool isActive) {
    return CachedProductImage(imageUrl: imageUrl, isActive: isActive);
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle, bool showResetButton = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(icon, size: 40, color: colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            if (showResetButton) ...[
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

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Something went wrong', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
