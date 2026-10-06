import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Modal dialog allowing the user to search and select a Selecta catalog product.
class SupplierOosProductPickerDialog extends StatefulWidget {
  final List<SelectaProduct> products;
  final String? initialQuery;
  final String title;

  const SupplierOosProductPickerDialog({
    super.key,
    required this.products,
    this.initialQuery,
    this.title = 'Select Selecta Product',
  });

  static Future<SelectaProduct?> show({
    required BuildContext context,
    required List<SelectaProduct> products,
    String? initialQuery,
    String title = 'Select Selecta Product',
  }) {
    return showDialog<SelectaProduct>(
      context: context,
      builder: (ctx) => SupplierOosProductPickerDialog(
        products: products,
        initialQuery: initialQuery,
        title: title,
      ),
    );
  }

  @override
  State<SupplierOosProductPickerDialog> createState() => _SupplierOosProductPickerDialogState();
}

class _SupplierOosProductPickerDialogState extends State<SupplierOosProductPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _searchController.text = widget.initialQuery!.trim();
      _searchQuery = widget.initialQuery!.trim().toLowerCase();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SelectaProduct> get _filteredProducts {
    final query = _searchQuery.trim().toLowerCase();
    final list = widget.products.where((p) {
      if (query.isEmpty) return true;
      final name = p.productName.toLowerCase();
      final code = p.itemCode.toLowerCase();
      final cat = p.category.toLowerCase();
      return name.contains(query) || code.contains(query) || cat.contains(query);
    }).toList();

    // Sort by SRP ascending, then name
    list.sort((a, b) => Helperfunctions.compareBySrpAndName(
          nameA: a.productName,
          priceA: a.sellingPrice,
          nameB: b.productName,
          priceB: b.sellingPrice,
        ));

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final results = _filteredProducts;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.inventory_2_outlined, color: colorScheme.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Search field
              TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search by product name or item code...',
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val.trim().toLowerCase());
                },
              ),
              const SizedBox(height: 8),

              // Item Count
              Text(
                'Showing ${results.length} Selecta product(s) sorted by SRP',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
              const Divider(height: 16),

              // Results List
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                            const SizedBox(height: 8),
                            Text(
                              'No matching Selecta products found.',
                              style: TextStyle(color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: results.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (ctx, index) {
                          final product = results[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            leading: CachedProductImage(
                              imageUrl: product.imageUrl,
                              isActive: product.isActive,
                              size: 44,
                            ),
                            title: Text(
                              product.productName,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Row(
                              children: [
                                if (product.itemCode.isNotEmpty) ...[
                                  Text(
                                    product.itemCode,
                                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                if (product.category.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      product.category,
                                      style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Text(
                              _currencyFormat.format(product.sellingPrice),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                            onTap: () => Navigator.pop(context, product),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
