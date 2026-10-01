import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/controllers/other_product_controller.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/other_product.dart';
import 'package:flutter_app/views/pages/sidebar/inventory_page.dart';
import 'package:flutter_app/views/pages/sidebar/other_product_form_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/cached_product_image.dart';
import 'package:intl/intl.dart';

/// Other Products catalog page — list, search, add, edit, delete, toggle active.
/// - **Dealer Mode**: Reads from `other_products` ([OtherProduct]).
///   Dealers can toggle active/inactive status and view product details in read-only mode.
/// - **Admin Mode**: Admins can Add, Edit, Delete, and toggle active status.
class OtherProductsPage extends StatefulWidget {
  final String userRole;

  const OtherProductsPage({
    super.key,
    this.userRole = 'Dealer',
  });

  @override
  State<OtherProductsPage> createState() => _OtherProductsPageState();
}

class _OtherProductsPageState extends State<OtherProductsPage> {
  final OtherProductController _controller = OtherProductController();
  final TextEditingController _searchController = TextEditingController();
  final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  String _searchQuery = '';
  String _filterStatus = 'All'; // 'All', 'Active', 'Inactive'

  bool get _isAdmin {
    final role = widget.userRole.trim().toLowerCase();
    return role == 'admin' || role == 'super admin' || role == 'superadmin';
  }

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
    final filtered = docs.where((doc) {
      final p = doc.data();
      final matchesSearch = _searchQuery.isEmpty || p.productName.toLowerCase().contains(_searchQuery);
      final matchesStatus = _filterStatus == 'All' || (_filterStatus == 'Active' && p.isActive) || (_filterStatus == 'Inactive' && !p.isActive);
      return matchesSearch && matchesStatus;
    }).toList();

    filtered.sort((a, b) {
      final pA = a.data();
      final pB = b.data();
      return Helperfunctions.compareBySrpAndName(
        nameA: pA.productName,
        priceA: pA.sellingPrice,
        nameB: pB.productName,
        priceB: pB.sellingPrice,
      );
    });

    return filtered;
  }

  Future<void> _navigateToForm({String? productId, OtherProduct? product}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OtherProductFormPage(
          productId: productId,
          existingProduct: product,
          isReadOnly: !_isAdmin, // Dealers view details in read-only mode
          userRole: widget.userRole,
        ),
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
      appBar: CustomAppbar(
        title: 'Other Products',
        subtitle: _isAdmin ? 'Admin Other Products Catalog' : 'Dealer Other Products Catalog',
        actions: [
          IconButton(
            icon: const Icon(Icons.warehouse_outlined, color: Colors.white, size: 20),
            tooltip: 'Manage Inventory',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const InventoryPage()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search Bar ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(fontSize: 14.5),
              decoration: InputDecoration(
                hintText: 'Search other products...',
                hintStyle: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
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
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
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
                              fontSize: 13,
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
                                    Icon(Icons.filter_alt_off_outlined, size: 15, color: colorScheme.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Reset',
                                      style: TextStyle(
                                        fontSize: 13,
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
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                              children: [
                                if (filtered.isNotEmpty) ...[
                                  _buildGroupHeader(
                                    title: 'Other Products',
                                    icon: Icons.inventory_2_outlined,
                                    color: colorScheme.onSurfaceVariant,
                                    count: filtered.length,
                                  ),
                                  ...filtered.map((doc) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _buildProductCard(doc),
                                  )),
                                ],
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _navigateToForm(),
              backgroundColor: colorScheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add Product', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  Widget _buildGroupHeader({
    required String title,
    required IconData icon,
    required Color color,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$count ${count == 1 ? "product" : "products"}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, thickness: 1),
        ],
      ),
    );
  }

  Widget _buildProductCard(QueryDocumentSnapshot<OtherProduct> doc) {
    final product = doc.data();
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = product.isActive;

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
            crossAxisAlignment: CrossAxisAlignment.center,
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
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        height: 1.25,
                        color: isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'Buy: ',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isActive ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          currencyFormat.format(product.buyingPrice),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: isActive ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Sell: ',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isActive ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          currencyFormat.format(product.sellingPrice),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggleActive(doc.id, product.productName, product.isActive),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 40,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isActive ? colorScheme.primary : colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Align(
                    alignment: isActive ? Alignment.centerRight : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(2.5),
                      child: Container(
                        width: 19,
                        height: 19,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 22, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductImage(String imageUrl, bool isActive) {
    return CachedProductImage(
      imageUrl: imageUrl,
      isActive: isActive,
      size: 48,
      borderRadius: 8,
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle, bool showResetButton = false}) {
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
