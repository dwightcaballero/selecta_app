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

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
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
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: colorScheme.primary.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))],
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
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
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
              Expanded(child: _buildSummaryMetric('Overpayment', totalOverpayment)),
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
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 3),
        Text(
          Helperfunctions.formatDoubleAmountForDisplay(amount),
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Search by invoice number...',
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
    );
  }

  Widget _buildOrderCard({required String orderId, required Purchaseorder order}) {
    final colorScheme = Theme.of(context).colorScheme;
    final invoiceNumber = order.invoiceNumber.trim().isEmpty ? 'No invoice number' : order.invoiceNumber;
    Color statusColor;
    String statusText;
    switch (order.isSettled) {
      case true:
        statusColor = Colors.green;
        statusText = 'Settled';
        break;
      case false:
        statusColor = Colors.red;
        statusText = 'With Overpayment';
        break;
      default:
        statusColor = Colors.grey;
        statusText = '';
    }

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Helperfunctions.navigateTo(context, PurchaseorderPage(purchaseorderID: orderId, purchaseorder: order)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.receipt_long_outlined, color: colorScheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoiceNumber,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_month_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          Helperfunctions.formatTimestampForDisplay(order.orderDate),
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      statusText,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Order', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(order.orderAmount),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                  const SizedBox(height: 2),
                  Text('Invoice', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(order.invoiceAmount),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 20, color: colorScheme.onSurfaceVariant),
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
            Icon(Icons.receipt_long_outlined, size: 50, color: Colors.grey),
            SizedBox(height: 16),
            Text('No Purchase Orders Yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text(
              'Tap the button below to add your first purchase order.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red, size: 40),
          SizedBox(height: 8),
          Text('Unable to load purchase orders'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppbar(title: 'Purchase Orders', subtitle: 'Invoices & Order Tracking'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Helperfunctions.navigateTo(context, PurchaseorderPage(purchaseorderID: '', purchaseorder: Purchaseorder.empty())),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Order',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.getListPurchaseordersAsStream(),
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState();
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];
          if (allDocs.isEmpty) {
            return _buildEmptyState();
          }

          double totalOrderAmount = 0;
          double totalInvoiceAmount = 0;
          double totalOverpayment = 0;
          for (final doc in allDocs) {
            final order = doc.data() as Purchaseorder;
            totalOrderAmount += order.orderAmount;
            totalInvoiceAmount += order.invoiceAmount;
            totalOverpayment += order.overpayment;
          }

          final filteredDocs = allDocs.where((doc) {
            final order = doc.data() as Purchaseorder;
            return _searchQuery.isEmpty || order.invoiceNumber.toLowerCase().contains(_searchQuery);
          }).toList();

          return Column(
            children: [
              _buildSummaryCard(
                totalOrderAmount: totalOrderAmount,
                totalInvoiceAmount: totalInvoiceAmount,
                totalOverpayment: totalOverpayment,
                totalCount: allDocs.length,
              ),
              _buildSearchBar(),
              Expanded(
                child: filteredDocs.isEmpty
                    ? Center(
                        child: Text('No orders matching "$_searchQuery"', style: const TextStyle(fontWeight: FontWeight.bold)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                        itemCount: filteredDocs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          return _buildOrderCard(orderId: doc.id, order: doc.data() as Purchaseorder);
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
