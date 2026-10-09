import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/controllers/badorder_controller.dart';
import 'package:selecta_ops/controllers/selecta_product_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/badorder.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/views/pages/sidebar/badorder_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class BadOrderlistPage extends StatefulWidget {
  const BadOrderlistPage({super.key});

  @override
  State<BadOrderlistPage> createState() => _BadOrderlistPageState();
}

class _BadOrderlistPageState extends State<BadOrderlistPage> {
  final BadOrderController _controller = BadOrderController();

  late final Stream<QuerySnapshot<BadOrder>> _badOrdersStream;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  String _selectedPeriod = 'All'; // 'All' or 'This Month'
  String _selectedStatus = 'All'; // 'All', 'Store Pullout', 'Warehouse Pullout', 'Settled'
  bool _isDealer = false;

  @override
  void initState() {
    super.initState();
    _badOrdersStream = _controller.getBadOrdersStream();
    _controller.checkIsDealer().then((dealer) {
      if (mounted) setState(() => _isDealer = dealer);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _openByCaseConfigModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => const _ByCaseConfigBottomSheet(),
    );
  }

  Widget _buildSummaryCard({required double totalAmount, required int totalCount}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _selectedPeriod == 'This Month'
                    ? 'Bad Orders (${DateFormat('MMMM').format(DateTime.now())})'
                    : 'Total Bad Orders (Active)',
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                Helperfunctions.formatDoubleAmountForDisplay(totalAmount),
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                const Text('Records', style: TextStyle(color: Colors.white70, fontSize: 11)),
                Text(
                  '$totalCount',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips({required int allCount, required int thisMonthCount}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          ChoiceChip(
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            label: Text('All Records ($allCount)', style: const TextStyle(fontSize: 12)),
            selected: _selectedPeriod == 'All',
            onSelected: (_) => setState(() => _selectedPeriod = 'All'),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            label: Text('This Month ($thisMonthCount)', style: const TextStyle(fontSize: 12)),
            selected: _selectedPeriod == 'This Month',
            onSelected: (_) => setState(() => _selectedPeriod = 'This Month'),
          ),
          const SizedBox(width: 12),
          Container(height: 18, width: 1, color: Colors.grey.shade300),
          const SizedBox(width: 12),
          ChoiceChip(
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            label: const Text('All Statuses', style: TextStyle(fontSize: 12)),
            selected: _selectedStatus == 'All',
            onSelected: (_) => setState(() => _selectedStatus = 'All'),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            label: const Text('Store Pullout', style: TextStyle(fontSize: 12)),
            selected: _selectedStatus == BadOrderStatus.storePullout,
            onSelected: (_) => setState(() => _selectedStatus = BadOrderStatus.storePullout),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            label: const Text('Warehouse Pullout', style: TextStyle(fontSize: 12)),
            selected: _selectedStatus == BadOrderStatus.warehousePullout,
            onSelected: (_) => setState(() => _selectedStatus = BadOrderStatus.warehousePullout),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            label: const Text('Settled', style: TextStyle(fontSize: 12)),
            selected: _selectedStatus == BadOrderStatus.settled,
            onSelected: (_) => setState(() => _selectedStatus = BadOrderStatus.settled),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: SizedBox(
        height: 40,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: (val) => setState(() => _searchQuery = val.trim()),
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search by store, product, or notes...',
            hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
            prefixIcon: Icon(Icons.search, size: 18, color: colorScheme.primary),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case BadOrderStatus.storePullout:
        return Colors.orange.shade700;
      case BadOrderStatus.warehousePullout:
        return Colors.blue.shade700;
      case BadOrderStatus.settled:
        return Colors.green.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  Widget _buildBadOrderCard({required String badorderID, required BadOrder badorder}) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _getStatusColor(badorder.status);
    final hasImage = badorder.imagePath.trim().isNotEmpty;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Helperfunctions.navigateTo(
          context,
          BadOrderPage(recID: badorderID, badorder: badorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Photo thumbnail or default icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: hasImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: badorder.imagePath.startsWith('http')
                            ? Image.network(
                                badorder.imagePath,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Icon(Icons.broken_image, size: 22, color: colorScheme.primary),
                              )
                            : Image.file(
                                File(badorder.imagePath),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Icon(Icons.broken_image, size: 22, color: colorScheme.primary),
                              ),
                      )
                    : Icon(Icons.remove_shopping_cart_outlined, color: colorScheme.primary, size: 22),
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
                            badorder.hapistore,
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badorder.status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          '${badorder.items.length} item${badorder.items.length == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.calendar_month_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          Helperfunctions.formatTimestampForDisplay(badorder.badorderDate),
                          style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    if (badorder.notes.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        badorder.notes,
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(badorder.totalAmount),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 44),
            ),
            const SizedBox(height: 16),
            const Text('No Bad Orders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'No damaged or expired goods recorded.\nBad orders can be recorded by salesmen during delivery.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSearchResultsState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty ? 'No records matching "$_searchQuery"' : 'No records found for this filter',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _selectedPeriod = 'All';
                _selectedStatus = 'All';
              });
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Reset filters'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Bad Orders',
        subtitle: 'Damaged & Expired Products',
        actions: [
          if (_isDealer)
            IconButton(
              tooltip: 'Configure By Case B.O. Prices',
              icon: const Icon(Icons.tune_outlined),
              onPressed: _openByCaseConfigModal,
            ),
        ],
      ),
      floatingActionButton: _isDealer
          ? FloatingActionButton.extended(
              onPressed: _openByCaseConfigModal,
              icon: const Icon(Icons.tune, color: Colors.white),
              label: const Text('By Case Pricing', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              backgroundColor: Theme.of(context).colorScheme.primary,
            )
          : null,
      body: StreamBuilder<QuerySnapshot<BadOrder>>(
        stream: _badOrdersStream,
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot<BadOrder>> snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load bad orders. Please try again.'));
          }
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];
          final filterResult = _controller.filterBadOrders(
            docs: allDocs,
            selectedPeriod: _selectedPeriod,
            searchQuery: _searchQuery,
            now: now,
            statusFilter: _selectedStatus,
          );
          final filteredDocs = filterResult.filteredDocs;
          final periodTotalAmount = filterResult.periodTotalAmount;
          final thisMonthCount = filterResult.thisMonthCount;

          if (filterResult.allCount == 0 && _searchQuery.isEmpty && _selectedStatus == 'All') {
            return _buildEmptyState();
          }

          return Column(
            children: [
              _buildSummaryCard(
                totalAmount: periodTotalAmount,
                totalCount: _selectedPeriod == 'All' ? filterResult.allCount : thisMonthCount,
              ),
              _buildFilterChips(
                allCount: filterResult.allCount,
                thisMonthCount: thisMonthCount,
              ),
              _buildSearchBar(),
              const SizedBox(height: 4),
              Expanded(
                child: filteredDocs.isEmpty
                    ? _buildNoSearchResultsState()
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, _isDealer ? 80 : 20),
                        itemCount: filteredDocs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final badorder = filteredDocs[index].data();
                          final badorderID = filteredDocs[index].id;
                          return _buildBadOrderCard(badorderID: badorderID, badorder: badorder);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Bottom sheet modal for dealers to view and configure `badOrderPricePerPiece`
/// on "By Case" Selecta products.
class _ByCaseConfigBottomSheet extends StatefulWidget {
  const _ByCaseConfigBottomSheet();

  @override
  State<_ByCaseConfigBottomSheet> createState() => _ByCaseConfigBottomSheetState();
}

class _ByCaseConfigBottomSheetState extends State<_ByCaseConfigBottomSheet> {
  final SelectaProductController _productController = SelectaProductController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showEditPriceDialog(SelectaProduct product) {
    final textController = TextEditingController(
      text: product.badOrderPricePerPiece != null && product.badOrderPricePerPiece! > 0
          ? product.badOrderPricePerPiece!.toStringAsFixed(2)
          : '',
    );

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Set B.O. Price Per Piece'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              'Case Buying Price: ${Helperfunctions.formatDoubleAmountForDisplay(product.buyingPrice)}',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: textController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Bad Order Price per Piece',
                prefixText: '₱ ',
                border: OutlineInputBorder(),
                hintText: 'e.g. 8.00',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final val = double.tryParse(textController.text.trim()) ?? 0.0;
              if (val <= 0) {
                ShowMessage.error(dialogCtx, 'Please enter a price greater than 0.');
                return;
              }
              Navigator.pop(dialogCtx);
              try {
                await _productController.updateBadOrderPricePerPiece(product.id, val);
                if (mounted) {
                  ShowMessage.success(context, 'Updated B.O. price for ${product.productName} to ₱${val.toStringAsFixed(2)}');
                }
              } catch (e) {
                if (mounted) {
                  ShowMessage.error(context, 'Failed to update price: $e');
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'By Case Bad Order Pricing',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Set the individual piece price for By Case products during pullout.',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Search box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search By Case products...',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const Divider(height: 1),
          // Stream of products
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _productController.getProductsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                final caseProducts = docs
                    .map((d) => SelectaProduct.fromSnapshot(d))
                    .where((p) => p.category == 'By Case')
                    .where((p) => _searchQuery.isEmpty || p.productName.toLowerCase().contains(_searchQuery))
                    .toList();

                if (caseProducts.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text('No "By Case" Selecta products found.'),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: caseProducts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final product = caseProducts[index];
                    final isConfigured = product.badOrderPricePerPiece != null && product.badOrderPricePerPiece! > 0;

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isConfigured ? Colors.green.shade200 : Colors.red.shade200,
                          width: 1.2,
                        ),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: product.imageUrl.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    product.imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(Icons.icecream, color: Colors.purple),
                                  ),
                                )
                              : const Icon(Icons.icecream, color: Colors.purple),
                        ),
                        title: Text(product.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Case Cost: ${Helperfunctions.formatDoubleAmountForDisplay(product.buyingPrice)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 2),
                            Text.rich(
                              TextSpan(
                                text: 'B.O. Piece: ',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                                children: [
                                  TextSpan(
                                    text: isConfigured
                                        ? '₱${product.badOrderPricePerPiece!.toStringAsFixed(2)} / pc'
                                        : 'Not Configured',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isConfigured ? Colors.green.shade700 : Colors.red.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        trailing: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          ),
                          onPressed: () => _showEditPriceDialog(product),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.edit, size: 14),
                              const SizedBox(width: 4),
                              Text(isConfigured ? 'Edit' : 'Set Price', style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
