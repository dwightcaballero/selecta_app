import 'package:flutter/material.dart';
import 'package:flutter_app/models/inventory_movement.dart';
import 'package:flutter_app/services/gemini_ai_service.dart';
import 'package:flutter_app/views/widgets/cached_product_image.dart';
import 'package:intl/intl.dart';

/// Modal bottom sheet that prompts the admin to resolve ambiguous or truncated
/// product names detected by the AI on supplier receipts.
class ProductDisambiguationSheet extends StatefulWidget {
  final List<AmbiguousPoItem> ambiguousItems;
  final List<InventoryItem> allInventory;
  final Future<void> Function(
    AmbiguousPoItem item,
    InventoryItem selectedProduct,
    bool rememberMapping,
  ) onConfirm;
  final void Function(AmbiguousPoItem item)? onSkip;

  const ProductDisambiguationSheet({
    super.key,
    required this.ambiguousItems,
    required this.allInventory,
    required this.onConfirm,
    this.onSkip,
  });

  static Future<void> show(
    BuildContext context, {
    required List<AmbiguousPoItem> ambiguousItems,
    required List<InventoryItem> allInventory,
    required Future<void> Function(
      AmbiguousPoItem item,
      InventoryItem selectedProduct,
      bool rememberMapping,
    ) onConfirm,
    void Function(AmbiguousPoItem item)? onSkip,
  }) async {
    if (ambiguousItems.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ProductDisambiguationSheet(
        ambiguousItems: ambiguousItems,
        allInventory: allInventory,
        onConfirm: onConfirm,
        onSkip: onSkip,
      ),
    );
  }

  @override
  State<ProductDisambiguationSheet> createState() => _ProductDisambiguationSheetState();
}

class _ProductDisambiguationSheetState extends State<ProductDisambiguationSheet> {
  final NumberFormat _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final TextEditingController _catalogSearchController = TextEditingController();

  int _currentIndex = 0;
  InventoryItem? _selectedItem;
  bool _rememberMapping = true;
  String _searchFilter = '';

  AmbiguousPoItem get _currentItem => widget.ambiguousItems[_currentIndex];

  @override
  void initState() {
    super.initState();
    _initCurrentItemSelection();
  }

  void _initCurrentItemSelection() {
    _selectedItem = null;
    _catalogSearchController.clear();
    _searchFilter = '';
  }

  @override
  void dispose() {
    _catalogSearchController.dispose();
    super.dispose();
  }

  void _handleConfirm() async {
    if (_selectedItem == null) return;
    final item = _currentItem;
    final selected = _selectedItem!;
    final remember = _rememberMapping;

    await widget.onConfirm(item, selected, remember);

    if (_currentIndex + 1 < widget.ambiguousItems.length) {
      setState(() {
        _currentIndex++;
        _initCurrentItemSelection();
      });
    } else {
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _handleSkip() {
    widget.onSkip?.call(_currentItem);
    if (_currentIndex + 1 < widget.ambiguousItems.length) {
      setState(() {
        _currentIndex++;
        _initCurrentItemSelection();
      });
    } else {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final item = _currentItem;
    final total = widget.ambiguousItems.length;

    final List<InventoryItem> searchResults = _searchFilter.trim().isEmpty
        ? []
        : widget.allInventory
            .where((inv) =>
                inv.productName.toLowerCase().contains(_searchFilter.toLowerCase()) ||
                inv.itemCode.toLowerCase().contains(_searchFilter.toLowerCase()) ||
                inv.category.toLowerCase().contains(_searchFilter.toLowerCase()))
            .take(15)
            .toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle & Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.psychology_alt_outlined, color: Colors.amber.shade900, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Clarify Scanned Products',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Item ${_currentIndex + 1} of $total requires confirmation',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_currentIndex + 1}/$total',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Scanned snippet highlight box
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.amber.shade400.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 16, color: Colors.amber.shade900),
                              const SizedBox(width: 6),
                              Text(
                                'PRINTED ON INVOICE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '"${item.rawText}"',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Chip(
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                avatar: const Icon(Icons.inventory_2_outlined, size: 14),
                                label: Text('Qty: ${item.quantity}'),
                              ),
                              if (item.detectedUnitPrice > 0)
                                Chip(
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  avatar: const Icon(Icons.payments_outlined, size: 14),
                                  label: Text('Cost: ${_currency.format(item.detectedUnitPrice)}'),
                                ),
                            ],
                          ),
                          if (item.reason.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              '💡 AI note: ${item.reason}',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'Search Selecta product:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Immediate searchbox for Selecta products
                    TextField(
                      controller: _catalogSearchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search product name or code...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchFilter.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setState(() {
                                    _searchFilter = '';
                                    _catalogSearchController.clear();
                                  });
                                },
                              )
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onChanged: (val) => setState(() => _searchFilter = val),
                    ),
                    const SizedBox(height: 8),

                    // Currently selected product
                    if (_selectedItem != null) ...[
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Selected Product:',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _buildProductSelectionCard(_selectedItem!, true, colorScheme),
                      const SizedBox(height: 10),
                    ],

                    // Search Results
                    if (searchResults.isNotEmpty) ...[
                      Text(
                        'Matching Products (${searchResults.length}):',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...searchResults.map((res) {
                        final isSelected = _selectedItem?.id == res.id;
                        return _buildProductSelectionCard(res, isSelected, colorScheme);
                      }),
                    ] else if (_searchFilter.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.search_off_rounded, size: 36, color: colorScheme.outline),
                              const SizedBox(height: 6),
                              Text(
                                'No matching products found for "$_searchFilter"',
                                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else if (_selectedItem == null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            'Type in the search box to find and select the product.',
                            style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 6),

                    // Remember mapping switch (Active Learning)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _rememberMapping,
                      onChanged: (val) => setState(() => _rememberMapping = val),
                      title: const Text(
                        'Remember this mapping',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      subtitle: Text(
                        'Future scans will recognize "${item.rawText}" automatically without asking.',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                      secondary: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.auto_awesome, size: 18, color: colorScheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1),
            // Bottom Action Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _handleSkip,
                    child: const Text('Skip Item'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _selectedItem == null ? null : _handleConfirm,
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(_currentIndex + 1 < total ? 'Confirm & Next' : 'Confirm & Apply'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductSelectionCard(
    InventoryItem product,
    bool isSelected,
    ColorScheme colorScheme,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: () => setState(() => _selectedItem = product),
        leading: CachedProductImage(
          imageUrl: product.imageUrl,
          size: 46,
        ),
        title: Text(
          product.productName,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Row(
          children: [
            Text(
              _currency.format(product.buyingPrice),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
                fontSize: 12,
              ),
            ),
            if (product.category.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                '• ${product.category}',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ],
            if (product.itemCode.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                '• Code: ${product.itemCode}',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
        trailing: Radio<String>(
          value: product.id,
          groupValue: _selectedItem?.id,
          onChanged: (_) => setState(() => _selectedItem = product),
        ),
      ),
    );
  }
}
