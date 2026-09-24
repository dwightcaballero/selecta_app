import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/purchaseorder.dart';
import 'package:flutter_app/services/purchaseorder_service.dart';
import 'package:flutter_app/views/pages/dashboard/overpayment_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

enum OverpaymentSort {
  highestAmount('Highest Amount', Icons.arrow_downward),
  lowestAmount('Lowest Amount', Icons.arrow_upward),
  newest('Newest First', Icons.calendar_today),
  oldest('Oldest First', Icons.history);

  const OverpaymentSort(this.label, this.icon);
  final String label;
  final IconData icon;
}

class OverpaymentlistPage extends StatefulWidget {
  const OverpaymentlistPage({super.key});

  @override
  State<OverpaymentlistPage> createState() => _OverpaymentlistPageState();
}

class _OverpaymentlistPageState extends State<OverpaymentlistPage> {
  final PurchaseOrderService db = PurchaseOrderService();

  late final Stream<QuerySnapshot> _overpaymentsStream;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  OverpaymentSort _selectedSort = OverpaymentSort.highestAmount;

  @override
  void initState() {
    super.initState();
    _overpaymentsStream = db.getListPurchaseOrdersNotYetSettled();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied to clipboard'), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating));
  }

  Widget _buildSummaryCard({
    required double totalOverpayment,
    required int totalCount,
    required double filteredOverpayment,
    required int filteredCount,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFiltered = _searchQuery.isNotEmpty && filteredCount != totalCount;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.8)],
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
                  Text(
                    isFiltered ? 'Filtered Total Overpayment' : 'Total Outstanding Overpayment',
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(isFiltered ? filteredOverpayment : totalOverpayment),
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: [
                    Text(isFiltered ? 'Matching' : 'Pending', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    Text(
                      isFiltered ? '$filteredCount / $totalCount' : '$totalCount',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isFiltered) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.filter_alt_outlined, size: 13, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(
                    'Overall: ${Helperfunctions.formatDoubleAmountForDisplay(totalOverpayment)} ($totalCount total orders)',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search invoice or creator...',
                hintStyle: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
                prefixIcon: Icon(Icons.search, size: 20, color: colorScheme.primary),
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
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<OverpaymentSort>(
            tooltip: 'Sort overpayments',
            icon: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Icon(Icons.sort, color: colorScheme.primary, size: 20),
            ),
            initialValue: _selectedSort,
            onSelected: (sort) => setState(() => _selectedSort = sort),
            itemBuilder: (context) => OverpaymentSort.values.map((sort) {
              final isSelected = sort == _selectedSort;
              return PopupMenuItem<OverpaymentSort>(
                value: sort,
                child: Row(
                  children: [
                    Icon(sort.icon, size: 18, color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Text(
                      sort.label,
                      style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? colorScheme.primary : null),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildOverpaymentCard({required String purchaseOrderId, required Purchaseorder purchaseOrder}) {
    final colorScheme = Theme.of(context).colorScheme;
    final invoiceNumber = purchaseOrder.invoiceNumber.trim().isEmpty ? 'No invoice number' : purchaseOrder.invoiceNumber;
    final hasImage = purchaseOrder.imagePath.trim().isNotEmpty;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Helperfunctions.navigateTo(context, OverpaymentPage(purchaseorderID: purchaseOrderId, purchaseorder: purchaseOrder)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.account_balance_wallet_outlined, color: colorScheme.primary, size: 22),
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
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (purchaseOrder.invoiceNumber.trim().isNotEmpty) ...[
                          const SizedBox(width: 4),
                          InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () => _copyToClipboard(purchaseOrder.invoiceNumber, 'Invoice number'),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(Icons.copy, size: 14, color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                        if (hasImage) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.receipt_long, size: 11, color: colorScheme.primary),
                                const SizedBox(width: 2),
                                Text(
                                  'Receipt',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_month_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          Helperfunctions.formatTimestampForDisplay(purchaseOrder.orderDate),
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Order: ${Helperfunctions.formatDoubleAmountForDisplay(purchaseOrder.orderAmount)} • Inv: ${Helperfunctions.formatDoubleAmountForDisplay(purchaseOrder.invoiceAmount)}',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(purchaseOrder.overpayment),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Pending',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 20, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.green),
            ),
            const SizedBox(height: 16),
            Text(
              'No Outstanding Overpayments',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              'All purchase-order overpayments have been settled.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: colorScheme.error, size: 40),
          const SizedBox(height: 8),
          Text(
            'Unable to load overpayments',
            style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppbar(title: 'Overpayments', subtitle: 'Outstanding Purchase-Order Balances'),
      body: StreamBuilder<QuerySnapshot>(
        stream: _overpaymentsStream,
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) return _buildErrorState();
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final allDocs = snapshot.data?.docs ?? [];
          if (allDocs.isEmpty) return _buildEmptyState();

          final totalOverpayment = allDocs.fold<double>(0.0, (sum, doc) => sum + ((doc.data() as Purchaseorder).overpayment));

          final filteredDocs = allDocs.where((doc) {
            final po = doc.data() as Purchaseorder;
            if (_searchQuery.isEmpty) return true;
            return po.invoiceNumber.toLowerCase().contains(_searchQuery) || po.createdBy.toLowerCase().contains(_searchQuery);
          }).toList();

          // Apply selected sort
          filteredDocs.sort((a, b) {
            final poA = a.data() as Purchaseorder;
            final poB = b.data() as Purchaseorder;
            switch (_selectedSort) {
              case OverpaymentSort.highestAmount:
                return poB.overpayment.compareTo(poA.overpayment);
              case OverpaymentSort.lowestAmount:
                return poA.overpayment.compareTo(poB.overpayment);
              case OverpaymentSort.newest:
                return poB.orderDate.compareTo(poA.orderDate);
              case OverpaymentSort.oldest:
                return poA.orderDate.compareTo(poB.orderDate);
            }
          });

          final filteredOverpayment = filteredDocs.fold<double>(0.0, (sum, doc) => sum + ((doc.data() as Purchaseorder).overpayment));

          return Column(
            children: [
              _buildSummaryCard(
                totalOverpayment: totalOverpayment,
                totalCount: allDocs.length,
                filteredOverpayment: filteredOverpayment,
                filteredCount: filteredDocs.length,
              ),
              _buildSearchAndFilterBar(),
              Expanded(
                child: filteredDocs.isEmpty
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'No overpayments matching "$_searchQuery"',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: filteredDocs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          return _buildOverpaymentCard(purchaseOrderId: doc.id, purchaseOrder: doc.data() as Purchaseorder);
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
