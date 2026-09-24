import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/badorder.dart';
import 'package:flutter_app/services/badorder_service.dart';
import 'package:flutter_app/views/pages/sidebar/badorder_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class BadOrderlistPage extends StatefulWidget {
  const BadOrderlistPage({super.key});

  @override
  State<BadOrderlistPage> createState() => _BadOrderlistPageState();
}

class _BadOrderlistPageState extends State<BadOrderlistPage> {
  final BadOrderService db = BadOrderService();

  late final Stream<QuerySnapshot> _badOrdersStream;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  String _selectedPeriod = 'All'; // 'All' or 'This Month'

  @override
  void initState() {
    super.initState();
    _badOrdersStream = db.getListBadOrder();
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
              Text(
                _selectedPeriod == 'This Month'
                    ? 'Bad Orders (${DateFormat('MMMM').format(DateTime.now())})'
                    : 'Total Bad Orders (All Time)',
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

  Widget _buildPeriodChips({required int allCount, required int thisMonthCount}) {
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
            hintText: 'Search by store name or description...',
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

  Widget _buildBadOrderCard({required String badorderID, required BadOrder badorder}) {
    final colorScheme = Theme.of(context).colorScheme;

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
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.remove_shopping_cart_outlined, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      badorder.hapistore,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (badorder.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        badorder.description,
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_month_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          Helperfunctions.formatTimestampForDisplay(badorder.badorderDate),
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
                    Helperfunctions.formatDoubleAmountForDisplay(badorder.badorderAmount),
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
              'No damaged or expired goods recorded.',
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
            _searchQuery.isNotEmpty ? 'No records matching "$_searchQuery"' : 'No records found for this period',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _selectedPeriod = 'All';
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
      appBar: const CustomAppbar(title: 'Bad Orders', subtitle: 'Damaged & Expired Products'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Helperfunctions.navigateTo(
          context,
          BadOrderPage(recID: '', badorder: BadOrder.empty()),
        ),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Record', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _badOrdersStream,
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load bad orders. Please try again.'));
          }
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];
          if (allDocs.isEmpty) {
            return _buildEmptyState();
          }

          int thisMonthCount = 0;
          double periodTotalAmount = 0;
          final List<QueryDocumentSnapshot> filteredDocs = [];

          for (var doc in allDocs) {
            final badorder = doc.data() as BadOrder;
            final date = badorder.badorderDate.toDate();
            final isThisMonth = date.year == now.year && date.month == now.month;

            if (isThisMonth) thisMonthCount++;

            final matchesPeriod = _selectedPeriod == 'All' || isThisMonth;
            final matchesSearch = _searchQuery.isEmpty ||
                badorder.hapistore.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                badorder.description.toLowerCase().contains(_searchQuery.toLowerCase());

            if (matchesPeriod) {
              periodTotalAmount += badorder.badorderAmount;
            }

            if (matchesPeriod && matchesSearch) {
              filteredDocs.add(doc);
            }
          }

          return Column(
            children: [
              _buildSummaryCard(
                totalAmount: periodTotalAmount,
                totalCount: _selectedPeriod == 'All' ? allDocs.length : thisMonthCount,
              ),
              _buildPeriodChips(
                allCount: allDocs.length,
                thisMonthCount: thisMonthCount,
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
}
