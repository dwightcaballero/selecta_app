import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/pjp_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Interactive bottom sheet presenting ordering recommendations for a store:
/// 1. Unplaced Selecta products for the current calendar month.
/// 2. Out of stock products for today at the depot/warehouse.
class StoreRecommendationsModal extends StatefulWidget {
  final String storeName;
  final VoidCallback? onProceedToBookOrder;
  final String? actionButtonLabel;
  final PjpController? controller;

  const StoreRecommendationsModal({
    super.key,
    required this.storeName,
    this.onProceedToBookOrder,
    this.actionButtonLabel,
    this.controller,
  });

  /// Static helper to display the store recommendations bottom sheet modal.
  static Future<void> show({
    required BuildContext context,
    required String storeName,
    VoidCallback? onProceedToBookOrder,
    String? actionButtonLabel,
    PjpController? controller,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StoreRecommendationsModal(
        storeName: storeName,
        onProceedToBookOrder: onProceedToBookOrder,
        actionButtonLabel: actionButtonLabel,
        controller: controller,
      ),
    );
  }

  @override
  State<StoreRecommendationsModal> createState() => _StoreRecommendationsModalState();
}

class _StoreRecommendationsModalState extends State<StoreRecommendationsModal> with SingleTickerProviderStateMixin {
  late final PjpController _controller;
  late final TabController _tabController;
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  StoreRecommendationsResult? _result;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? PjpController();
    _tabController = TabController(length: 2, vsync: this);
    _loadRecommendations();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecommendations() async {
    setState(() => _isLoading = true);
    final res = await _controller.getStoreRecommendations(widget.storeName);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _result = res;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentMonthLabel = DateFormat('MMMM yyyy').format(DateTime.now());

    final unplacedCount = _result?.unplacedCount ?? 0;
    final oosCount = _result?.outOfStockCount ?? 0;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Drag Handle ──────────────────────────────────────────────────
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Header ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.auto_awesome_rounded, color: Colors.amber.shade900, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Store Recommendations',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${widget.storeName} • $currentMonthLabel',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Search & Filter ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: 'Search products...',
                  hintStyle: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                ),
              ),
            ),
          ),

          // ── Tab Bar ──────────────────────────────────────────────────────
          TabBar(
            controller: _tabController,
            labelColor: colorScheme.primary,
            unselectedLabelColor: colorScheme.onSurfaceVariant,
            indicatorColor: colorScheme.primary,
            indicatorWeight: 2.5,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            tabs: [
              Tab(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 15),
                      const SizedBox(width: 4),
                      const Text('To Book'),
                      if (!_isLoading) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: unplacedCount > 0 ? Colors.green.shade100 : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$unplacedCount',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: unplacedCount > 0 ? Colors.green.shade800 : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Tab(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.do_not_disturb_on_outlined, size: 15),
                      const SizedBox(width: 4),
                      const Text('Out of Stock'),
                      if (!_isLoading) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: oosCount > 0 ? Colors.red.shade100 : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$oosCount',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: oosCount > 0 ? Colors.red.shade800 : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── Tab View Content ─────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildUnplacedTab(colorScheme),
                      _buildOutOfStockTab(colorScheme),
                    ],
                  ),
          ),

          // ── Bottom Action Bar ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4))),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onProceedToBookOrder?.call();
                  },
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                  label: Text(
                    widget.actionButtonLabel ?? 'Proceed to Book Order',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 1: Unplaced Recommended Products ─────────────────────────────────
  Widget _buildUnplacedTab(ColorScheme colorScheme) {
    final allItems = (_result?.unplacedRecommendations ?? []).toList()
      ..sort((a, b) => Helperfunctions.compareBySrpAndName(
            nameA: a.productName,
            priceA: a.sellingPrice,
            nameB: b.productName,
            priceB: b.sellingPrice,
          ));
    final filtered = _searchQuery.isEmpty
        ? allItems
        : allItems.where((i) => i.productName.toLowerCase().contains(_searchQuery)).toList();

    return RefreshIndicator(
      onRefresh: _loadRecommendations,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Informational guide banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.blue.shade700, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Recommended Selecta products that have NOT been placed in this store this month. Prioritize booking these to complete monthly store placement.',
                    style: TextStyle(fontSize: 11.5, color: Colors.blue.shade900, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (filtered.isEmpty)
            _buildEmptyState(
              icon: Icons.check_circle_outline_rounded,
              iconColor: Colors.green,
              title: _searchQuery.isEmpty ? 'All Recommended Products Placed!' : 'No matching products',
              subtitle: _searchQuery.isEmpty
                  ? 'All core placement products have already been ordered or placed for this store this month.'
                  : 'Try searching with a different product name.',
            )
          else
            ...filtered.map((item) => _buildUnplacedItemCard(item, colorScheme)),
        ],
      ),
    );
  }

  Widget _buildUnplacedItemCard(StoreRecommendationItem item, ColorScheme colorScheme) {
    final bool isOOS = item.isOutOfStock;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isOOS
              ? Colors.red.withValues(alpha: 0.3)
              : colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: isOOS ? 1.2 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            // Thumbnail
            if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
              CachedProductImage(imageUrl: item.imageUrl!, size: 50, borderRadius: 8)
            else if (item.itemImagePath != null && item.itemImagePath!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(item.itemImagePath!, width: 50, height: 50, fit: BoxFit.cover),
              )
            else
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.icecream_outlined, color: colorScheme.onSurfaceVariant, size: 24),
              ),
            const SizedBox(width: 12),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.productName,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (item.sellingPrice > 0)
                    Text(
                      _currencyFormat.format(item.sellingPrice),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  const SizedBox(height: 4),

                  // Status chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      // Best Seller badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded, size: 11, color: Color(0xFFD97706)),
                            SizedBox(width: 2),
                            Text(
                              'Target Placement',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                            ),
                          ],
                        ),
                      ),

                      // Depot stock status
                      if (isOOS)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 11, color: Colors.red.shade700),
                              const SizedBox(width: 2),
                              Text(
                                'Out of Stock at Depot',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.red.shade700),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_rounded, size: 11, color: Colors.green.shade700),
                              const SizedBox(width: 2),
                              Text(
                                '${item.availableStock} in stock',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.green.shade700),
                              ),
                            ],
                          ),
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
  }

  // ── Tab 2: Out of Stock (Avoid Today) ────────────────────────────────────
  Widget _buildOutOfStockTab(ColorScheme colorScheme) {
    final allItems = (_result?.outOfStockProducts ?? []).toList()
      ..sort((a, b) => Helperfunctions.compareBySrpAndName(
            nameA: a.productName,
            priceA: a.sellingPrice,
            nameB: b.productName,
            priceB: b.sellingPrice,
          ));
    final filtered = _searchQuery.isEmpty
        ? allItems
        : allItems.where((i) => i.productName.toLowerCase().contains(_searchQuery)).toList();

    return RefreshIndicator(
      onRefresh: _loadRecommendations,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Warning guide banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Products with 0 available stock at the warehouse today. Avoid taking orders for these products to prevent delivery shortages.',
                    style: TextStyle(fontSize: 11.5, color: Colors.red.shade900, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (filtered.isEmpty)
            _buildEmptyState(
              icon: Icons.check_circle_rounded,
              iconColor: Colors.green,
              title: _searchQuery.isEmpty ? 'No Out of Stock Products!' : 'No matching products',
              subtitle: _searchQuery.isEmpty
                  ? 'All active catalog items currently have available stock today.'
                  : 'Try searching with a different product name.',
            )
          else
            ...filtered.map((item) => _buildOutOfStockItemCard(item, colorScheme)),
        ],
      ),
    );
  }

  Widget _buildOutOfStockItemCard(InventoryItem item, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            // Thumbnail
            CachedProductImage(imageUrl: item.imageUrl, isActive: false, size: 50, borderRadius: 8),
            const SizedBox(width: 12),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        _currencyFormat.format(item.sellingPrice),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.source == InventoryProductSource.selecta ? '• Selecta' : '• Other Product',
                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Out of stock pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cancel_outlined, size: 11, color: Colors.red.shade700),
                        const SizedBox(width: 3),
                        Text(
                          '0 Available Today',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.red.shade700),
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
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: iconColor),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
