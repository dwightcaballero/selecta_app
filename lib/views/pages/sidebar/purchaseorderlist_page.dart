import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/purchaseorder.dart';
import 'package:flutter_app/services/purchaseorder_service.dart';
import 'package:flutter_app/views/pages/sidebar/purchaseorder_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

class PurchaseorderlistPage extends StatefulWidget {
  const PurchaseorderlistPage({super.key});

  @override
  State<PurchaseorderlistPage> createState() => _PurchaseorderlistPageState();
}

class _PurchaseorderlistPageState extends State<PurchaseorderlistPage> {
  final PurchaseOrderService db = PurchaseOrderService();

  late final Stream<QuerySnapshot> _ordersStream;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _ordersStream = db.getListPurchaseordersAsStream();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Widget _buildSummaryCard({
    required double totalOrderAmount,
    required double totalInvoiceAmount,
    required double totalOverpayment,
    required int totalCount,
  }) {
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
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Purchase Orders',
                    style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(totalOrderAmount),
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
                    const Text('Orders', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    Text(
                      '$totalCount',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: Colors.white24, height: 1),
          ),
          Row(
            children: [
              Expanded(child: _buildSummaryMetric('Invoice Total', totalInvoiceAmount)),
              Expanded(child: _buildSummaryMetric('Net Overpayment', totalOverpayment)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryMetric(String label, double amount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
        const SizedBox(height: 3),
        Text(
          Helperfunctions.formatDoubleAmountForDisplay(amount),
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildFilterChips({
    required int totalCount,
    required int pendingCount,
    required int overpaymentCount,
    required int settledCount,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _buildChoiceChip('All', 'All ($totalCount)'),
          const SizedBox(width: 8),
          _buildChoiceChip('Pending', 'Awaiting Invoice ($pendingCount)', color: Colors.orange.shade800),
          const SizedBox(width: 8),
          _buildChoiceChip('Overpayment', 'Overpayment ($overpaymentCount)', color: Colors.red.shade700),
          const SizedBox(width: 8),
          _buildChoiceChip('Settled', 'Settled ($settledCount)', color: Colors.green.shade700),
        ],
      ),
    );
  }

  Widget _buildChoiceChip(String key, String label, {Color? color}) {
    final isSelected = _selectedFilter == key;
    final theme = Theme.of(context);

    return ChoiceChip(
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected
              ? theme.colorScheme.onPrimary
              : (color ?? theme.colorScheme.onSurfaceVariant),
        ),
      ),
      selected: isSelected,
      selectedColor: color ?? theme.colorScheme.primary,
      onSelected: (_) => setState(() => _selectedFilter = key),
    );
  }

  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SizedBox(
        height: 40,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search invoice number or date...',
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

  Widget _buildOrderCard({required String orderId, required Purchaseorder order}) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool hasInvoice = order.invoiceNumber.trim().isNotEmpty;
    final String invoiceNumber = hasInvoice ? order.invoiceNumber : 'Awaiting Invoice';
    final dateStr = Helperfunctions.formatTimestampForDisplay(order.orderDate);
    final bool hasAttachment = order.imagePath.isNotEmpty;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (!hasInvoice || order.invoiceAmount == 0) {
      statusColor = Colors.orange.shade800;
      statusText = 'Awaiting Invoice';
      statusIcon = Icons.hourglass_top_outlined;
    } else if (order.isSettled == true) {
      statusColor = Colors.green.shade700;
      statusText = 'Settled';
      statusIcon = Icons.check_circle_outline;
    } else if (order.overpayment > 0) {
      statusColor = Colors.red.shade700;
      statusText = 'Overpayment: ${Helperfunctions.formatDoubleAmountForDisplay(order.overpayment)}';
      statusIcon = Icons.warning_amber_rounded;
    } else {
      statusColor = Colors.blue.shade700;
      statusText = 'Invoiced (Balanced)';
      statusIcon = Icons.verified_outlined;
    }

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
          PurchaseorderPage(purchaseorderID: orderId, purchaseorder: order),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.receipt_long_outlined, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            invoiceNumber,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: hasInvoice ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                              fontStyle: hasInvoice ? FontStyle.normal : FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasAttachment) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.attach_file, size: 14, color: colorScheme.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_month_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(dateStr, style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(statusIcon, size: 13, color: statusColor),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            statusText,
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: statusColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Order Target', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(order.orderAmount),
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                  const SizedBox(height: 3),
                  Text('Invoice Amount', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                  Text(
                    order.invoiceAmount > 0
                        ? Helperfunctions.formatDoubleAmountForDisplay(order.invoiceAmount)
                        : '—',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: order.invoiceAmount > 0 ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                    ),
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
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text('No Purchase Orders Yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text(
              'Tap the "Add Order" button below to create your first purchase order.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54),
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
          Icon(Icons.search_off, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'No orders match "$_searchQuery"'
                : 'No orders match the selected filter',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _selectedFilter = 'All';
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
    return Scaffold(
      appBar: const CustomAppbar(title: 'Purchase Orders', subtitle: 'Invoices & Order Tracking'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Helperfunctions.navigateTo(
          context,
          PurchaseorderPage(purchaseorderID: '', purchaseorder: Purchaseorder.empty()),
        ),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _ordersStream,
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load purchase orders. Please try again.'));
          }
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];
          if (allDocs.isEmpty) {
            return _buildEmptyState();
          }

          double totalOrderAmount = 0;
          double totalInvoiceAmount = 0;
          double totalOverpayment = 0;
          int pendingCount = 0;
          int overpaymentCount = 0;
          int settledCount = 0;

          for (final doc in allDocs) {
            final order = doc.data() as Purchaseorder;
            totalOrderAmount += order.orderAmount;
            totalInvoiceAmount += order.invoiceAmount;
            totalOverpayment += order.overpayment;

            final hasInvoice = order.invoiceNumber.trim().isNotEmpty && order.invoiceAmount > 0;
            if (!hasInvoice) {
              pendingCount++;
            } else if (order.isSettled == true) {
              settledCount++;
            } else if (order.overpayment > 0) {
              overpaymentCount++;
            }
          }

          final filteredDocs = allDocs.where((doc) {
            final order = doc.data() as Purchaseorder;
            final hasInvoice = order.invoiceNumber.trim().isNotEmpty && order.invoiceAmount > 0;

            bool matchesFilter = true;
            if (_selectedFilter == 'Pending') {
              matchesFilter = !hasInvoice;
            } else if (_selectedFilter == 'Overpayment') {
              matchesFilter = order.overpayment > 0 && order.isSettled != true;
            } else if (_selectedFilter == 'Settled') {
              matchesFilter = order.isSettled == true;
            }

            final dateStr = Helperfunctions.formatTimestampForDisplay(order.orderDate).toLowerCase();
            final matchesSearch = _searchQuery.isEmpty ||
                order.invoiceNumber.toLowerCase().contains(_searchQuery) ||
                dateStr.contains(_searchQuery);

            return matchesFilter && matchesSearch;
          }).toList();

          return Column(
            children: [
              _buildSummaryCard(
                totalOrderAmount: totalOrderAmount,
                totalInvoiceAmount: totalInvoiceAmount,
                totalOverpayment: totalOverpayment,
                totalCount: allDocs.length,
              ),
              _buildFilterChips(
                totalCount: allDocs.length,
                pendingCount: pendingCount,
                overpaymentCount: overpaymentCount,
                settledCount: settledCount,
              ),
              _buildSearchBar(),
              const SizedBox(height: 4),
              Expanded(
                child: filteredDocs.isEmpty
                    ? _buildNoSearchResultsState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                        itemCount: filteredDocs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          return _buildOrderCard(
                            orderId: doc.id,
                            order: doc.data() as Purchaseorder,
                          );
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
