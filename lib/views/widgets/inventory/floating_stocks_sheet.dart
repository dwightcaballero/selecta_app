import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/inventory_controller.dart';
import 'package:selecta_ops/models/floating_stock.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Modal bottom sheet allowing dealers to inspect floating stocks (Going In from POs
/// and Going Out from reserved store orders).
class FloatingStocksSheet extends StatefulWidget {
  final InventoryController controller;
  final String? initialProductId;

  const FloatingStocksSheet({
    super.key,
    required this.controller,
    this.initialProductId,
  });

  static Future<void> show({
    required BuildContext context,
    required InventoryController controller,
    String? initialProductId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => FloatingStocksSheet(
        controller: controller,
        initialProductId: initialProductId,
      ),
    );
  }

  @override
  State<FloatingStocksSheet> createState() => _FloatingStocksSheetState();
}

class _FloatingStocksSheetState extends State<FloatingStocksSheet> {
  final TextEditingController _searchController = TextEditingController();
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy');
  final DateFormat _dateTimeFormat = DateFormat('MMM d, h:mm a');

  int _selectedTab = 0; // 0: By Product, 1: Going In (POs), 2: Going Out (Deliveries)
  String _searchQuery = '';
  final Set<String> _expandedItemIds = {};
  final Set<String> _settlingDeliveryIds = {};

  Future<void> _promptSettleDelivery(FloatingTransaction tx) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          icon: Icon(Icons.sync_problem_rounded, color: Colors.amber.shade800, size: 36),
          title: const Text(
            'Settle Delivery Stock',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to manually settle floating stock for ${tx.title} (${tx.subtitle})?',
                style: const TextStyle(fontSize: 13.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Text(
                  'This will permanently deduct physical stock, release held reservations (${tx.totalUnits} units), and record an audit log. Use this for delivered orders left unsettled by older app versions.',
                  style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade800),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Settle Stock'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      setState(() => _settlingDeliveryIds.add(tx.id));
      try {
        await widget.controller.settleSingleDelivery(tx.id);
        if (mounted) {
          ShowMessage.success(context, 'Inventory for ${tx.title} settled successfully!');
        }
      } catch (e) {
        if (mounted) {
          ShowMessage.error(context, 'Failed to settle delivery: $e');
        }
      } finally {
        if (mounted) {
          setState(() => _settlingDeliveryIds.remove(tx.id));
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialProductId != null && widget.initialProductId!.isNotEmpty) {
      _expandedItemIds.add(widget.initialProductId!);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    setState(() => _searchQuery = val.trim().toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) {
        return StreamBuilder<FloatingStockData>(
          stream: widget.controller.getFloatingStockStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to load floating stocks: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final data = snapshot.data ?? FloatingStockData.empty;

            return Column(
              children: [
                // ── Drag Handle ─────────────────────────────────────────────
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // ── Header Title & Close Button ─────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.sync_alt_rounded,
                          color: Color(0xFF7C3AED),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Floating Stocks',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              'Live incoming orders & outgoing reservations',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
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

                // ── KPI Summary Cards ───────────────────────────────────────
                _buildKpiBanner(data, colorScheme),

                // ── Tab / Segmented Switcher ────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: 0,
                          label: Text(
                            'By Product (${data.affectedProductCount})',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          icon: const Icon(Icons.inventory_2_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: 1,
                          label: Text(
                            'Going In (${data.totalIncomingUnits})',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          icon: const Icon(Icons.arrow_downward_rounded, size: 16, color: Color(0xFF0284C7)),
                        ),
                        ButtonSegment(
                          value: 2,
                          label: Text(
                            'Going Out (${data.totalReservedUnits})',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          icon: const Icon(Icons.arrow_upward_rounded, size: 16, color: Color(0xFF7C3AED)),
                        ),
                      ],
                      selected: {_selectedTab},
                      onSelectionChanged: (set) {
                        setState(() => _selectedTab = set.first);
                      },
                    ),
                  ),
                ),

                // ── Search Bar ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: _selectedTab == 0
                          ? 'Search products with floating stock...'
                          : _selectedTab == 1
                              ? 'Search PO # or supplier...'
                              : 'Search store name, route, or status...',
                      hintStyle: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                      prefixIcon: Icon(Icons.search, size: 18, color: colorScheme.primary),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: colorScheme.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                    ),
                  ),
                ),

                const Divider(height: 12),

                // ── Active Tab Content ──────────────────────────────────────
                Expanded(
                  child: switch (_selectedTab) {
                    0 => _buildProductList(data.products, colorScheme, scrollController),
                    1 => _buildTransactionList(
                        data.incomingTransactions,
                        isIncoming: true,
                        colorScheme: colorScheme,
                        scrollController: scrollController,
                      ),
                    2 => _buildTransactionList(
                        data.outgoingTransactions,
                        isIncoming: false,
                        colorScheme: colorScheme,
                        scrollController: scrollController,
                      ),
                    _ => const SizedBox.shrink(),
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── KPI Summary Banner ───────────────────────────────────────────────────
  Widget _buildKpiBanner(FloatingStockData data, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          // Going In (Incoming POs)
          Expanded(
            child: _buildMetricTile(
              label: 'Going In',
              value: '+${data.totalIncomingUnits}',
              sublabel: '${data.incomingOrderCount} active PO${data.incomingOrderCount == 1 ? '' : 's'}',
              icon: Icons.arrow_circle_down_rounded,
              color: const Color(0xFF0284C7),
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          // Going Out (Reserved Deliveries)
          Expanded(
            child: _buildMetricTile(
              label: 'Going Out',
              value: '-${data.totalReservedUnits}',
              sublabel: '${data.outgoingOrderCount} reserved order${data.outgoingOrderCount == 1 ? '' : 's'}',
              icon: Icons.arrow_circle_up_rounded,
              color: const Color(0xFF7C3AED),
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          // Net Floating
          Expanded(
            child: _buildMetricTile(
              label: 'Net Balance',
              value: '${data.netFloatingUnits >= 0 ? '+' : ''}${data.netFloatingUnits}',
              sublabel: '${data.affectedProductCount} SKUs affected',
              icon: Icons.balance_rounded,
              color: data.netFloatingUnits >= 0 ? const Color(0xFF15803D) : const Color(0xFFD97706),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required String sublabel,
    required IconData icon,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            sublabel,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Tab 0: By Product View ───────────────────────────────────────────────
  Widget _buildProductList(
    List<FloatingProductItem> products,
    ColorScheme colorScheme,
    ScrollController scrollController,
  ) {
    final filtered = products.where((p) {
      if (_searchQuery.isEmpty) return true;
      return p.productName.toLowerCase().contains(_searchQuery) ||
          p.incomingSources.any((s) => s.title.toLowerCase().contains(_searchQuery)) ||
          p.outgoingSources.any((s) => s.title.toLowerCase().contains(_searchQuery));
    }).toList();

    if (filtered.isEmpty) {
      return _buildEmptyState(
        icon: Icons.inventory_2_outlined,
        title: _searchQuery.isEmpty ? 'No Floating Stock' : 'No Matching Products',
        subtitle: _searchQuery.isEmpty
            ? 'There are currently no active incoming POs or outgoing reserved orders.'
            : 'Try adjusting your search query.',
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final item = filtered[index];
        final isExpanded = _expandedItemIds.contains(item.productId);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isExpanded
                  ? colorScheme.primary.withValues(alpha: 0.6)
                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedItemIds.remove(item.productId);
                    } else {
                      _expandedItemIds.add(item.productId);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CachedProductImage(
                        imageUrl: item.imageUrl,
                        isActive: true,
                        size: 44,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            // Quick Quantity Badges
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _buildBadge(
                                  'Physical: ${item.stockQuantity}',
                                  colorScheme.onSurfaceVariant,
                                  colorScheme.surfaceContainerHighest,
                                ),
                                if (item.incomingQuantity > 0)
                                  _buildBadge(
                                    '+${item.incomingQuantity} Going In',
                                    const Color(0xFF0284C7),
                                    const Color(0xFF0284C7).withValues(alpha: 0.12),
                                  ),
                                if (item.reservedQuantity > 0)
                                  _buildBadge(
                                    '-${item.reservedQuantity} Going Out',
                                    const Color(0xFF7C3AED),
                                    const Color(0xFF7C3AED).withValues(alpha: 0.12),
                                  ),
                                _buildBadge(
                                  'Avail: ${item.availableQuantity}',
                                  const Color(0xFF15803D),
                                  const Color(0xFF15803D).withValues(alpha: 0.12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),

              // ── Expanded Transaction Breakdown for SKU ────────────────────
              if (isExpanded) ...[
                const Divider(height: 1),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.incomingSources.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.arrow_downward_rounded, size: 14, color: Color(0xFF0284C7)),
                            const SizedBox(width: 4),
                            Text(
                              'Going In Transactions (${item.incomingSources.length})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0284C7),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ...item.incomingSources.map((s) => _buildSourceRefTile(s, colorScheme)),
                        const SizedBox(height: 10),
                      ],
                      if (item.outgoingSources.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.arrow_upward_rounded, size: 14, color: Color(0xFF7C3AED)),
                            const SizedBox(width: 4),
                            Text(
                              'Going Out Reservations (${item.outgoingSources.length})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF7C3AED),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ...item.outgoingSources.map((s) => _buildSourceRefTile(s, colorScheme)),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSourceRefTile(FloatingSourceRef ref, ColorScheme colorScheme) {
    final isIncoming = ref.isIncoming;
    final accent = isIncoming ? const Color(0xFF0284C7) : const Color(0xFF7C3AED);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${isIncoming ? '+' : '-'}${ref.quantity}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ref.title,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${ref.subtitle} • ${_dateTimeFormat.format(ref.date)}',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Builder(
            builder: (_) {
              final isUnsettled = !isIncoming && ref.status.toLowerCase().contains('unsettled');
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isUnsettled
                      ? Colors.amber.shade100
                      : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  ref.status,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isUnsettled ? Colors.amber.shade900 : colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Tab 1 & Tab 2: Document/Transaction View ─────────────────────────────
  Widget _buildTransactionList(
    List<FloatingTransaction> transactions, {
    required bool isIncoming,
    required ColorScheme colorScheme,
    required ScrollController scrollController,
  }) {
    final filtered = transactions.where((tx) {
      if (_searchQuery.isEmpty) return true;
      return tx.title.toLowerCase().contains(_searchQuery) ||
          tx.subtitle.toLowerCase().contains(_searchQuery) ||
          tx.status.toLowerCase().contains(_searchQuery) ||
          tx.items.any((i) => i.productName.toLowerCase().contains(_searchQuery));
    }).toList();

    if (filtered.isEmpty) {
      return _buildEmptyState(
        icon: isIncoming ? Icons.local_shipping_outlined : Icons.shopping_cart_outlined,
        title: _searchQuery.isEmpty
            ? (isIncoming ? 'No Incoming Purchase Orders' : 'No Reserved Orders')
            : 'No Matching Transactions',
        subtitle: _searchQuery.isEmpty
            ? (isIncoming
                ? 'All purchase orders have been replenished into physical stock.'
                : 'There are no store orders currently reserving floating inventory.')
            : 'Try adjusting your search query.',
      );
    }

    final accent = isIncoming ? const Color(0xFF0284C7) : const Color(0xFF7C3AED);

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final tx = filtered[index];
        final isExpanded = _expandedItemIds.contains(tx.id);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isExpanded
                  ? accent.withValues(alpha: 0.6)
                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedItemIds.remove(tx.id);
                    } else {
                      _expandedItemIds.add(tx.id);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isIncoming ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                          color: accent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    tx.title,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${isIncoming ? '+' : '-'}${tx.totalUnits} units',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: accent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${tx.subtitle} • ${_dateFormat.format(tx.date)}',
                                    style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (!isIncoming) ...[
                                  const SizedBox(width: 6),
                                  Builder(
                                    builder: (_) {
                                      final isUnsettled = tx.status.toLowerCase().contains('unsettled') ||
                                          tx.status.toLowerCase() == 'delivered' ||
                                          tx.status.toLowerCase() == 'returned';
                                      return _buildBadge(
                                        tx.status,
                                        isUnsettled ? Colors.amber.shade900 : colorScheme.onSurfaceVariant,
                                        isUnsettled ? Colors.amber.shade100 : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),

              // Expanded Item Breakdown
              if (isExpanded) ...[
                const Divider(height: 1),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Items in this ${isIncoming ? 'Purchase Order' : 'Order'} (${tx.items.length}):',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...tx.items.map((i) {
                        final qty = i.pickedQuantity > 0 ? i.pickedQuantity : i.orderedQuantity;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  i.productName,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '$qty ${i.category.isNotEmpty ? i.category.toLowerCase() : "units"}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: accent,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (!isIncoming) ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        Builder(
                          builder: (context) {
                            final isUnsettled = tx.status.toLowerCase().contains('unsettled') ||
                                tx.status.toLowerCase() == 'delivered' ||
                                tx.status.toLowerCase() == 'returned';
                            final isSettling = _settlingDeliveryIds.contains(tx.id);

                            return SizedBox(
                              width: double.maxFinite,
                              child: FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: isUnsettled
                                      ? Colors.amber.shade100
                                      : colorScheme.primaryContainer.withValues(alpha: 0.5),
                                  foregroundColor: isUnsettled
                                      ? Colors.amber.shade900
                                      : colorScheme.primary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                                onPressed: isSettling ? null : () => _promptSettleDelivery(tx),
                                icon: isSettling
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: isUnsettled ? Colors.amber.shade900 : colorScheme.primary,
                                        ),
                                      )
                                    : Icon(
                                        isUnsettled ? Icons.sync_problem_rounded : Icons.check_circle_outline,
                                        size: 18,
                                      ),
                                label: Text(
                                  isSettling
                                      ? 'Settling delivery stock...'
                                      : (isUnsettled
                                          ? 'Settle & Deduct Order Stock (${tx.totalUnits} units)'
                                          : 'Release / Settle Order Stock'),
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildBadge(String text, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: colorScheme.primary),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
