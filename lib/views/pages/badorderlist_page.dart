import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/badorder.dart';
import 'package:flutter_app/services/badorder_service.dart';
import 'package:flutter_app/views/pages/badorder_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

class BadOrderlistPage extends StatefulWidget {
  const BadOrderlistPage({super.key});

  @override
  State<BadOrderlistPage> createState() => _BadOrderlistPageState();
}

class _BadOrderlistPageState extends State<BadOrderlistPage> {
  final BadOrderService db = BadOrderService();
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
      appBar: const CustomAppbar(title: 'Bad Orders', subtitle: 'Damaged & Expired Products'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Helperfunctions.navigateTo(context, BadOrderPage(recID: '', badorder: BadOrder.empty())),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Record',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.getListBadOrder(),
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

          // Calculate total losses and filter list
          double totalBadOrderAmount = 0;
          final List<QueryDocumentSnapshot> filteredDocs = [];

          for (var doc in allDocs) {
            final badorder = doc.data() as BadOrder;
            totalBadOrderAmount += badorder.badorderAmount;
            if (_searchQuery.isEmpty ||
                badorder.hapistore.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                badorder.description.toLowerCase().contains(_searchQuery.toLowerCase())) {
              filteredDocs.add(doc);
            }
          }

          return Column(
            children: [
              // 1. KPI Summary Header
              _buildSummaryCard(totalAmount: totalBadOrderAmount, totalCount: allDocs.length),

              // 2. Search Bar
              _buildSearchBar(),

              // 3. Bad Orders List
              Expanded(
                child: filteredDocs.isEmpty
                    ? _buildNoSearchResultsState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                        itemCount: filteredDocs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final badorder = filteredDocs[index].data() as BadOrder;
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

  Widget _buildSummaryCard({required double totalAmount, required int totalCount}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.red.shade700, Colors.deepOrange.shade600], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Total Bad Order Amount',
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

  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val.trim()),
        decoration: InputDecoration(
          hintText: 'Search by store name or description...',
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

  Widget _buildBadOrderCard({required String badorderID, required BadOrder badorder}) {
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
        onTap: () => Helperfunctions.navigateTo(context, BadOrderPage(recID: badorderID, badorder: badorder)),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.remove_shopping_cart_outlined, color: Colors.red, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      badorder.hapistore,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (badorder.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        badorder.description,
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
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
                          Helperfunctions.formatTimestampForDisplay(badorder.badorderDate),
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
                    Helperfunctions.formatDoubleAmountForDisplay(badorder.badorderAmount),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: const Text(
                      'Bad Order',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
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
              child: const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 50),
            ),
            const SizedBox(height: 16),
            const Text('No Bad Orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'No damaged or expired goods recorded yet.',
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
            Text('No records matching "$_searchQuery"', style: const TextStyle(fontWeight: FontWeight.bold)),
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
          Text('Unable to load bad orders'),
        ],
      ),
    );
  }
}
