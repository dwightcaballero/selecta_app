import 'package:flutter/material.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/models/placement_pair.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Admin dialog for configuring paired placement products/SKUs.
///
/// When two products are paired, delivering either product to a store
/// will automatically mark BOTH products as placed for that store's monthly placement target.
class PlacementPairsDialog extends StatefulWidget {
  const PlacementPairsDialog({super.key});

  /// Static helper to display the placement pairs configuration modal sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const PlacementPairsDialog(),
    );
  }

  @override
  State<PlacementPairsDialog> createState() => _PlacementPairsDialogState();
}

class _PlacementPairsDialogState extends State<PlacementPairsDialog> {
  final ConfigurationService _configService = ConfigurationService();
  final SelectaProductService _productService = SelectaProductService();

  Configuration? _config;
  List<PlacementPair> _pairs = [];
  List<SelectaProduct> _allProducts = [];
  bool _isLoading = true;
  bool _isSaving = false;

  String? _selectedProduct1;
  String? _selectedProduct2;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final config = await _configService.getConfiguration();
      final bestSellers = await _productService.getBestSellerProducts();
      final allDocs = await _productService.getAllProducts();

      final fullCatalog = allDocs
          .map((doc) => SelectaProduct.fromJson(doc.id, doc.data()))
          .where((p) => p.isActive && p.productName.trim().isNotEmpty)
          .toList();

      // Deduplicate by product name
      final Map<String, SelectaProduct> prodMap = {};
      for (final p in bestSellers) {
        prodMap[p.productName.trim().toLowerCase()] = p;
      }
      for (final p in fullCatalog) {
        final key = p.productName.trim().toLowerCase();
        if (!prodMap.containsKey(key)) {
          prodMap[key] = p;
        }
      }

      final combinedList = prodMap.values.toList()
        ..sort((a, b) {
          final aIsBest = ProductTag.isBestSeller(a.tag);
          final bIsBest = ProductTag.isBestSeller(b.tag);
          if (aIsBest && !bIsBest) return -1;
          if (!aIsBest && bIsBest) return 1;
          return a.productName.compareTo(b.productName);
        });

      if (mounted) {
        setState(() {
          _config = config;
          _pairs = List<PlacementPair>.from(config.placementPairs);
          _allProducts = combinedList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ShowMessage.error(context, 'Failed to load configuration: $e');
      }
    }
  }

  SelectaProduct? _findProduct(String name) {
    final lower = name.trim().toLowerCase();
    for (final p in _allProducts) {
      if (p.productName.trim().toLowerCase() == lower) return p;
    }
    return null;
  }

  Future<void> _savePairs(List<PlacementPair> newPairs) async {
    if (_config == null) return;
    setState(() => _isSaving = true);
    try {
      final updatedConfig = _config!.copyWith(placementPairs: newPairs);
      await _configService.saveConfiguration(updatedConfig);
      await Helperfunctions.logTransaction(
        'Placement Pairs Config',
        'Updated placement product pairs: ${newPairs.map((p) => "${p.product1} <-> ${p.product2}").join(', ')}',
        LogAction.update,
        page: AppPages.configuration,
      );

      if (mounted) {
        setState(() {
          _config = updatedConfig;
          _pairs = newPairs;
          _isSaving = false;
          _selectedProduct1 = null;
          _selectedProduct2 = null;
        });
        ShowMessage.success(context, 'Placement pairs updated successfully.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ShowMessage.error(context, 'Failed to save pairs: $e');
      }
    }
  }

  void _addPair() {
    if (_selectedProduct1 == null || _selectedProduct2 == null) {
      ShowMessage.error(context, 'Please select both products to pair.');
      return;
    }
    if (_selectedProduct1!.trim().toLowerCase() == _selectedProduct2!.trim().toLowerCase()) {
      ShowMessage.error(context, 'Cannot pair a product with itself.');
      return;
    }

    final newPair = PlacementPair(product1: _selectedProduct1!, product2: _selectedProduct2!);

    if (_pairs.any((p) => p == newPair)) {
      ShowMessage.error(context, 'This product pair already exists.');
      return;
    }

    // Check if either product is already in another pair
    final alreadyPaired = _pairs.where((p) => p.matches(_selectedProduct1!) || p.matches(_selectedProduct2!)).toList();
    if (alreadyPaired.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Product Already Paired'),
          content: Text(
            'One of the selected products is already paired with another item (${alreadyPaired.first.product1} <-> ${alreadyPaired.first.product2}). Are you sure you want to add this link?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                final updated = List<PlacementPair>.from(_pairs)..add(newPair);
                _savePairs(updated);
              },
              child: const Text('Add Pair'),
            ),
          ],
        ),
      );
      return;
    }

    final updated = List<PlacementPair>.from(_pairs)..add(newPair);
    _savePairs(updated);
  }

  void _removePair(int index) {
    final pair = _pairs[index];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Pair'),
        content: Text('Unlink ${pair.product1} and ${pair.product2}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              final updated = List<PlacementPair>.from(_pairs)..removeAt(index);
              _savePairs(updated);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Widget _buildProductThumbnail(String productName) {
    final prod = _findProduct(productName);
    final imageUrl = prod?.imageUrl ?? '';
    final colorScheme = Theme.of(context).colorScheme;

    if (imageUrl.isNotEmpty) {
      return CachedProductImage(
        imageUrl: imageUrl,
        size: 38,
        borderRadius: 8,
      );
    }

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.icecream_outlined, size: 20, color: colorScheme.onSurfaceVariant),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
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

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.link_rounded, color: colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Placement Product Pairs',
                        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Admin Only Configuration',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
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

          const Divider(height: 1),

          // Body
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      // Explanation Banner
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, size: 20, color: colorScheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Pair 2 Best Seller SKUs for monthly store placement targets. If either product in a pair is delivered to a store, both products will automatically be marked as placed for that store.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Add Pair Card
                      Card(
                        elevation: 0,
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.add_link_rounded, size: 18, color: colorScheme.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Create New Pair',
                                    style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Product 1 Dropdown
                              DropdownButtonFormField<String>(
                                initialValue: _selectedProduct1,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'Select First Product',
                                  labelStyle: const TextStyle(fontSize: 13),
                                  prefixIcon: const Icon(Icons.looks_one_rounded, size: 20),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                ),
                                items: _allProducts.map((p) {
                                  final isBest = ProductTag.isBestSeller(p.tag);
                                  return DropdownMenuItem(
                                    value: p.productName,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            p.productName,
                                            style: const TextStyle(fontSize: 13),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isBest) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text('Best', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.orange)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) => setState(() => _selectedProduct1 = val),
                              ),

                              const SizedBox(height: 12),

                              // Product 2 Dropdown
                              DropdownButtonFormField<String>(
                                initialValue: _selectedProduct2,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'Select Second Product (Paired Counterpart)',
                                  labelStyle: const TextStyle(fontSize: 13),
                                  prefixIcon: const Icon(Icons.looks_two_rounded, size: 20),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                ),
                                items: _allProducts
                                    .where((p) => p.productName != _selectedProduct1)
                                    .map((p) {
                                  final isBest = ProductTag.isBestSeller(p.tag);
                                  return DropdownMenuItem(
                                    value: p.productName,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            p.productName,
                                            style: const TextStyle(fontSize: 13),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isBest) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text('Best', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.orange)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) => setState(() => _selectedProduct2 = val),
                              ),

                              const SizedBox(height: 14),

                              SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: FilledButton.icon(
                                  onPressed: _isSaving ? null : _addPair,
                                  icon: _isSaving
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.link_rounded, size: 18),
                                  label: const Text('Link Products as Pair', style: TextStyle(fontWeight: FontWeight.bold)),
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 22),

                      // Configured Pairs List Section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Active Placement Pairs (${_pairs.length})',
                            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (_pairs.isNotEmpty)
                            Text(
                              'Either places both',
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (_pairs.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.link_off_rounded, size: 40, color: colorScheme.onSurfaceVariant),
                              const SizedBox(height: 10),
                              const Text('No placement pairs configured yet.', style: TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(
                                'Select two products above to link them together.',
                                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _pairs.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final pair = _pairs[index];
                            return Card(
                              margin: EdgeInsets.zero,
                              elevation: 0,
                              color: colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.25)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    // Product 1
                                    _buildProductThumbnail(pair.product1),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        pair.product1,
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),

                                    // Linking icon
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primary.withValues(alpha: 0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.swap_horiz_rounded, size: 16, color: colorScheme.primary),
                                      ),
                                    ),

                                    // Product 2
                                    Expanded(
                                      child: Text(
                                        pair.product2,
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.end,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _buildProductThumbnail(pair.product2),

                                    // Delete action
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                                      tooltip: 'Remove pair',
                                      onPressed: () => _removePair(index),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
