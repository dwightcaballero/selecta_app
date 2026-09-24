import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/views/pages/dashboard/credit_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

enum CreditSort {
  highestAmount('Highest Credit', Icons.arrow_downward),
  lowestAmount('Lowest Credit', Icons.arrow_upward),
  oldest('Oldest First (Aging)', Icons.history),
  newest('Newest First', Icons.calendar_today);

  const CreditSort(this.label, this.icon);
  final String label;
  final IconData icon;
}

class CreditlistPage extends StatefulWidget {
  const CreditlistPage({super.key});

  @override
  State<CreditlistPage> createState() => _CreditlistPageState();
}

class _CreditlistPageState extends State<CreditlistPage> {
  final DeliveryService db = DeliveryService();
  bool isDealer = true;

  late final Stream<QuerySnapshot> _creditStream;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  CreditSort _selectedSort = CreditSort.highestAmount;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _creditStream = db.getListDeliveryWithCredit();
    prefetchData();
  }

  void prefetchData() async {
    isDealer = await KVariables.getIsDealer();
    if (mounted) setState(() {});
  }

  Widget _buildSummaryCard({
    required double totalCredit,
    required int totalAccounts,
    required double filteredCredit,
    required int filteredCount,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFiltered = _searchQuery.isNotEmpty && filteredCount != totalAccounts;

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
                    isFiltered ? 'Filtered Outstanding Credit' : 'Total Outstanding Credit',
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(isFiltered ? filteredCredit : totalCredit),
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(isFiltered ? 'Matching' : 'Stores', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    Text(
                      isFiltered ? '$filteredCount / $totalAccounts' : '$totalAccounts',
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
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.filter_alt_outlined, size: 13, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(
                    'Overall: ${Helperfunctions.formatDoubleAmountForDisplay(totalCredit)} ($totalAccounts stores)',
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
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
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
          ),
          const SizedBox(width: 8),
          PopupMenuButton<CreditSort>(
            tooltip: 'Sort credits',
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
            itemBuilder: (context) => CreditSort.values.map((sort) {
              final isSelected = sort == _selectedSort;
              return PopupMenuItem<CreditSort>(
                value: sort,
                child: Row(
                  children: [
                    Icon(
                      sort.icon,
                      size: 18,
                      color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      sort.label,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? colorScheme.primary : null,
                      ),
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

  Widget _buildCreditCard({required String deliveryID, required Delivery delivery}) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasRemarks = delivery.remarks.trim().isNotEmpty;

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
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.credit_card_outlined, color: colorScheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      delivery.storeName,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_month_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          delivery.deliveryDate != null
                              ? Helperfunctions.formatDateForDisplay(delivery.deliveryDate!.toDate())
                              : 'No Date',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Order Total: ${Helperfunctions.formatDoubleAmountForDisplay(delivery.orderAmount)}',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                    if (hasRemarks) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.notes, size: 12, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              delivery.remarks,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
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
                    Helperfunctions.formatDoubleAmountForDisplay(delivery.creditAmount),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Unpaid',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
              if (isDealer) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 20, color: colorScheme.onSurfaceVariant),
              ],
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
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              'All Credits Settled!',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              'There are no pending or unpaid credits recorded.',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSearchResultsState() {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'No stores matching "$_searchQuery"',
              style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
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
            'Unable to load credit list',
            style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppbar(title: 'Credit List', subtitle: 'Unpaid Store Accounts'),
      body: StreamBuilder<QuerySnapshot>(
        stream: _creditStream,
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

          // Calculate total outstanding amount
          final totalCredit = allDocs.fold<double>(
            0.0,
            (sum, doc) => sum + ((doc.data() as Delivery).creditAmount),
          );

          final filteredDocs = allDocs.where((doc) {
            final delivery = doc.data() as Delivery;
            if (_searchQuery.isEmpty) return true;
            return delivery.storeName.toLowerCase().contains(_searchQuery.toLowerCase());
          }).toList();

          // Apply selected sort
          filteredDocs.sort((a, b) {
            final delA = a.data() as Delivery;
            final delB = b.data() as Delivery;
            switch (_selectedSort) {
              case CreditSort.highestAmount:
                return delB.creditAmount.compareTo(delA.creditAmount);
              case CreditSort.lowestAmount:
                return delA.creditAmount.compareTo(delB.creditAmount);
              case CreditSort.oldest:
                final dateA = delA.deliveryDate?.toDate() ?? DateTime(1970);
                final dateB = delB.deliveryDate?.toDate() ?? DateTime(1970);
                return dateA.compareTo(dateB);
              case CreditSort.newest:
                final dateA = delA.deliveryDate?.toDate() ?? DateTime(1970);
                final dateB = delB.deliveryDate?.toDate() ?? DateTime(1970);
                return dateB.compareTo(dateA);
            }
          });

          final filteredCredit = filteredDocs.fold<double>(
            0.0,
            (sum, doc) => sum + ((doc.data() as Delivery).creditAmount),
          );

          return Column(
            children: [
              // 1. Total Outstanding Summary Header
              _buildSummaryCard(
                totalCredit: totalCredit,
                totalAccounts: allDocs.length,
                filteredCredit: filteredCredit,
                filteredCount: filteredDocs.length,
              ),

              // 2. Search & Sort Bar
              _buildSearchAndFilterBar(),

              // 3. Filtered Credits List
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
}
