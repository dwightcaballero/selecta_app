import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/views/pages/dashboard/return_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

class ReturnlistPage extends StatefulWidget {
  const ReturnlistPage({super.key});

  @override
  State<ReturnlistPage> createState() => _ReturnlistPageState();
}

class _ReturnlistPageState extends State<ReturnlistPage> {
  final DeliveryService db = DeliveryService();

  late final Stream<QuerySnapshot> _returnsStream;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _returnsStream = db.getListDeliveryWithReturnStatus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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
              const Text(
                'Total Returned Value',
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
            hintText: 'Search by store name or remarks...',
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

  Widget _buildReturnCard({required String deliveryID, required Delivery delivery}) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayAmount = delivery.returnAmount > 0 ? delivery.returnAmount : delivery.orderAmount;
    final isPartialReturn = delivery.returnAmount > 0 && delivery.returnAmount != delivery.orderAmount;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Helperfunctions.navigateTo(context, ReturnPage(recID: deliveryID, delivery: delivery)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.assignment_return_outlined, color: colorScheme.primary, size: 20),
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
                            delivery.storeName,
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (delivery.imagePath.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.photo_outlined, size: 14, color: colorScheme.primary),
                        ],
                      ],
                    ),
                    if (delivery.remarks.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.notes_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              delivery.remarks,
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_month_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          Helperfunctions.formatTimestampForDisplay(delivery.lastupdatedDate),
                          style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
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
                    Helperfunctions.formatDoubleAmountForDisplay(displayAmount),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                  if (isPartialReturn) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Orig: ${Helperfunctions.formatDoubleAmountForDisplay(delivery.orderAmount)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
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
            const Text('No Returned Deliveries', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            'No returns matching "$_searchQuery"',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Reset search'),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppbar(title: 'Returned Orders', subtitle: 'Needs Redelivery or Review'),
      body: StreamBuilder<QuerySnapshot>(
        stream: _returnsStream,
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState();
          }
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
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
            final returnAmount = delivery.returnAmount > 0 ? delivery.returnAmount : delivery.orderAmount;
            totalReturnedAmount += returnAmount;
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
}
