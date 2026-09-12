import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/views/pages/return_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

class ReturnlistPage extends StatefulWidget {
  const ReturnlistPage({super.key});

  @override
  State<ReturnlistPage> createState() => _ReturnlistPageState();
}

class _ReturnlistPageState extends State<ReturnlistPage> {
  final DeliveryService db = DeliveryService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppbar(title: 'Returned Orders', subtitle: 'Needs Redelivery or Review'),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.getListDeliveryWithReturnStatus(),
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

          // Calculate total returned value and apply search filter
          double totalReturnedAmount = 0;
          final List<QueryDocumentSnapshot> filteredDocs = [];

          for (var doc in allDocs) {
            final delivery = doc.data() as Delivery;
            totalReturnedAmount += delivery.orderAmount;
            if (_searchQuery.isEmpty ||
                delivery.storeName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                delivery.remarks.toLowerCase().contains(_searchQuery.toLowerCase())) {
              filteredDocs.add(doc);
            }
          }

          return Column(
            children: [
              // 1. Summary Card
              _buildSummaryCard(totalAmount: totalReturnedAmount, totalCount: allDocs.length),

              // 2. Search Bar
              _buildSearchBar(),

              // 3. Returned Orders List
              Expanded(
                child: filteredDocs.isEmpty
                    ? _buildNoSearchResultsState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: filteredDocs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final delivery = filteredDocs[index].data() as Delivery;
                          final deliveryID = filteredDocs[index].id;
                          return _buildReturnCard(deliveryID: deliveryID, delivery: delivery);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard({required double totalAmount, required int totalCount}) {
    Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.orange.shade700, Colors.deepOrange.shade600], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Total Returned Amount',
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
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
    );
  }

  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val.trim()),
        decoration: InputDecoration(
          hintText: 'Search by store name or remarks...',
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

  Widget _buildReturnCard({required String deliveryID, required Delivery delivery}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Helperfunctions.navigateTo(context, ReturnPage(recID: deliveryID, delivery: delivery)),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.assignment_return_outlined, color: Colors.deepOrange, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      delivery.storeName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (delivery.remarks.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Reason: ${delivery.remarks}',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_month_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          Helperfunctions.formatTimestampForDisplay(delivery.lastupdatedDate),
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
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
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(delivery.orderAmount),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                    child: const Text(
                      'Returned',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                    ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.task_alt_rounded, color: Colors.green, size: 50),
            ),
            const SizedBox(height: 16),
            const Text('No Returned Deliveries', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'All delivery transactions have been completed without returns.',
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
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text('No returns matching "$_searchQuery"', style: const TextStyle(fontWeight: FontWeight.bold)),
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
          Text('Unable to load return list'),
        ],
      ),
    );
  }
}
