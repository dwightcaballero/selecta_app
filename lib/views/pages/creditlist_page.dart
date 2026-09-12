import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/views/pages/credit_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

class CreditlistPage extends StatefulWidget {
  const CreditlistPage({super.key});

  @override
  State<CreditlistPage> createState() => _CreditlistPageState();
}

class _CreditlistPageState extends State<CreditlistPage> {
  final DeliveryService db = DeliveryService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool isDealer = true;

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void prefetchData() async {
    isDealer = await KVariables.getIsDealer();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppbar(title: 'Credit List', subtitle: 'Unpaid Store Accounts'),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.getListDeliveryWithCredit(),
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

          // Calculate total outstanding amount
          double totalCredit = 0;
          final List<QueryDocumentSnapshot> filteredDocs = [];

          for (var doc in allDocs) {
            final delivery = doc.data() as Delivery;
            totalCredit += delivery.creditAmount;
            if (_searchQuery.isEmpty || delivery.storeName.toLowerCase().contains(_searchQuery.toLowerCase())) {
              filteredDocs.add(doc);
            }
          }

          return Column(
            children: [
              // 1. Total Outstanding Summary Header
              _buildSummaryCard(totalCredit: totalCredit, totalAccounts: allDocs.length),

              // 2. Search Bar
              _buildSearchBar(),

              // 3. Filtered Credits List
              Expanded(
                child: filteredDocs.isEmpty
                    ? _buildNoSearchResultsState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: filteredDocs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final delivery = filteredDocs[index].data() as Delivery;
                          final deliveryID = filteredDocs[index].id;
                          return _buildCreditCard(deliveryID: deliveryID, delivery: delivery);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard({required double totalCredit, required int totalAccounts}) {
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Total Outstanding Credit',
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                Helperfunctions.formatDoubleAmountForDisplay(totalCredit),
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
            child: Column(
              children: [
                const Text('Stores', style: TextStyle(color: Colors.white70, fontSize: 11)),
                Text(
                  '$totalAccounts',
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
          hintText: 'Search by store name...',
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

  Widget _buildCreditCard({required String deliveryID, required Delivery delivery}) {
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
        onTap: isDealer
            ? () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreditPage(recID: deliveryID, delivery: delivery),
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.credit_card_outlined, color: Colors.purple, size: 22),
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
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_month_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          delivery.deliveryDate != null ? Helperfunctions.formatDateForDisplay(delivery.deliveryDate!.toDate()) : 'No Date',
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
                    Helperfunctions.formatDoubleAmountForDisplay(delivery.creditAmount),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.purple),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: const Text(
                      'Unpaid',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                  ),
                ],
              ),
              if (isDealer) ...[const SizedBox(width: 6), Icon(Icons.chevron_right, size: 20, color: colorScheme.onSurfaceVariant)],
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
            const Text('All Credits Settled!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'There are no pending or unpaid credits recorded.',
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
            Text('No stores matching "$_searchQuery"', style: const TextStyle(fontWeight: FontWeight.bold)),
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
          Text('Unable to load credit list'),
        ],
      ),
    );
  }
}
