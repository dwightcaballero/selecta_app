import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/purchaseorder_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/purchaseorder.dart';
import 'package:selecta_ops/views/pages/sidebar/purchaseorder_page.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

/// Presentation page for displaying, filtering, and sorting purchase orders.
class PurchaseorderlistPage extends StatefulWidget {
  const PurchaseorderlistPage({super.key});

  @override
  State<PurchaseorderlistPage> createState() => _PurchaseorderlistPageState();
}

class _PurchaseorderlistPageState extends State<PurchaseorderlistPage> {
  // Controller managing business logic and streams
  final PurchaseOrderController _controller = PurchaseOrderController();

  late final Stream<QuerySnapshot> _ordersStream;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  String _selectedFilter = 'All';
  String _sortBy = 'newest'; // 'newest', 'oldest', 'amount_high', 'amount_low'

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _isAllMonths = false;

  @override
  void initState() {
    super.initState();
    _ordersStream = _controller.getPurchaseOrdersStream();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Increments or decrements month selection
  void _changeMonth(int delta) {
    setState(() {
      _isAllMonths = false;
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
  }

  /// Dialog for selecting year and month
  Future<void> _pickMonthYear() async {
    final now = DateTime.now();
    int tempYear = _selectedMonth.year;

    await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setDialogState(() => tempYear--)),
                  Text('$tempYear', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  IconButton(icon: const Icon(Icons.chevron_right), onPressed: tempYear >= now.year ? null : () => setDialogState(() => tempYear++)),
                ],
              ),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(12, (index) {
                        final monthNum = index + 1;
                        final isFuture = tempYear == now.year && monthNum > now.month;
                        final isSelected = !_isAllMonths && tempYear == _selectedMonth.year && monthNum == _selectedMonth.month;
                        final monthName = DateFormat('MMM').format(DateTime(tempYear, monthNum));

                        return SizedBox(
                          width: 60,
                          height: 38,
                          child: ChoiceChip(
                            showCheckmark: false,
                            label: Center(
                              child: Text(monthName, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                            ),
                            selected: isSelected,
                            onSelected: isFuture
                                ? null
                                : (_) {
                                    setState(() {
                                      _isAllMonths = false;
                                      _selectedMonth = DateTime(tempYear, monthNum);
                                    });
                                    Navigator.pop(dialogCtx, true);
                                  },
                          ),
                        );
                      }),
                    ),
                    const Divider(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _isAllMonths = true;
                          });
                          Navigator.pop(dialogCtx, false);
                        },
                        icon: const Icon(Icons.all_inclusive_rounded, size: 16),
                        label: const Text('View All Months'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Horizontal bar allowing month-by-month navigation
  Widget _buildMonthNavigator() {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final bool isCurrentMonth = !_isAllMonths && _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    final String displayText = _isAllMonths ? 'All Months' : DateFormat('MMMM yyyy').format(_selectedMonth);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous month',
            onPressed: () => _changeMonth(-1),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _pickMonthYear,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_isAllMonths ? Icons.all_inclusive_rounded : Icons.calendar_month_outlined, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      displayText,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, size: 18, color: colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next month',
            onPressed: isCurrentMonth ? null : () => _changeMonth(1),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// Search and sort toolbar
  Widget _buildSearchAndSortBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Search invoice # or date...',
                  hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                  prefixIcon: Icon(Icons.search, size: 19, color: colorScheme.primary),
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
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Sort Orders',
            initialValue: _sortBy,
            onSelected: (val) => setState(() => _sortBy = val),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            child: Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: _sortBy != 'newest' ? colorScheme.primary.withValues(alpha: 0.12) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _sortBy != 'newest' ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Icon(Icons.sort_rounded, size: 20, color: _sortBy != 'newest' ? colorScheme.primary : colorScheme.onSurfaceVariant),
            ),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'newest',
                child: Row(children: [Icon(Icons.arrow_downward_rounded, size: 16), SizedBox(width: 8), Text('Date: Newest First')]),
              ),
              const PopupMenuItem(
                value: 'oldest',
                child: Row(children: [Icon(Icons.arrow_upward_rounded, size: 16), SizedBox(width: 8), Text('Date: Oldest First')]),
              ),
              const PopupMenuItem(
                value: 'amount_high',
                child: Row(children: [Icon(Icons.trending_down_rounded, size: 16), SizedBox(width: 8), Text('Amount: Highest First')]),
              ),
              const PopupMenuItem(
                value: 'amount_low',
                child: Row(children: [Icon(Icons.trending_up_rounded, size: 16), SizedBox(width: 8), Text('Amount: Lowest First')]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Status filter chips
  Widget _buildFilterChips({required int totalCount, required int pendingCount, required int overpaymentCount, required int settledCount}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          _buildChoiceChip('All', 'All ($totalCount)'),
          const SizedBox(width: 8),
          _buildChoiceChip('Pending', 'Pending ($pendingCount)', dotColor: Colors.orange.shade800),
          const SizedBox(width: 8),
          _buildChoiceChip('Overpayment', 'Overpayment ($overpaymentCount)', dotColor: Colors.red.shade700),
          const SizedBox(width: 8),
          _buildChoiceChip('Settled', 'Settled ($settledCount)', dotColor: Colors.green.shade700),
        ],
      ),
    );
  }

  Widget _buildChoiceChip(String key, String label, {Color? dotColor}) {
    final isSelected = _selectedFilter == key;
    final theme = Theme.of(context);

    return ChoiceChip(
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      avatar: dotColor != null
          ? Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            )
          : null,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      selected: isSelected,
      selectedColor: theme.colorScheme.primary,
      onSelected: (_) => setState(() => _selectedFilter = key),
    );
  }

  Widget _buildMonthHeader(String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Row(
        children: [
          Icon(Icons.calendar_month_outlined, size: 14, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, letterSpacing: 0.3, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4))),
        ],
      ),
    );
  }

  /// Order card with status indicators, amounts, and navigation
  Widget _buildOrderCard({required String orderId, required Purchaseorder order}) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isInvoiced = order.status == 'invoiced' || order.status == 'confirmed';
    final bool isPending = order.status == 'pending' || !isInvoiced;

    final String poNumber = order.poNumber.isNotEmpty ? order.poNumber : (isPending ? order.invoiceNumber : '');
    final String invoiceNumber = order.invoiceNumber.trim();

    final orderDateStr = Helperfunctions.formatTimestampForDisplay(order.orderDate);
    final invoiceDateStr = Helperfunctions.formatTimestampForDisplay(order.invoiceDate);

    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    if (isPending) {
      badgeColor = Colors.orange.shade800;
      badgeText = 'Pending';
      badgeIcon = Icons.hourglass_top_rounded;
    } else if (order.isSettled == true) {
      badgeColor = Colors.green.shade700;
      badgeText = 'Settled';
      badgeIcon = Icons.check_circle_outline_rounded;
    } else if (order.overpayment > 0) {
      badgeColor = Colors.red.shade700;
      badgeText = 'Overpaid: ${Helperfunctions.formatDoubleAmountForDisplay(order.overpayment)}';
      badgeIcon = Icons.arrow_outward_rounded;
    } else {
      badgeColor = Colors.blue.shade700;
      badgeText = 'Invoiced';
      badgeIcon = Icons.receipt_outlined;
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top line: Date and Status Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 12, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            isPending ? 'P.O. Date: $orderDateStr' : 'Inv Date: $invoiceDateStr',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(badgeIcon, size: 12, color: badgeColor),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              badgeText,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Main row: PO / Invoice # and Order target amount
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isInvoiced
                              ? (invoiceNumber.isNotEmpty ? 'Invoice #$invoiceNumber' : 'PO #${poNumber.isNotEmpty ? poNumber : order.invoiceNumber}')
                              : (poNumber.isNotEmpty ? 'PO #$poNumber' : 'Pending PO'),
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isInvoiced && order.invoiceAmount > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Invoiced: ${Helperfunctions.formatDoubleAmountForDisplay(order.invoiceAmount)}',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                        ] else if (isPending) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Awaiting invoice arrival',
                            style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: Colors.orange.shade800),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Helperfunctions.formatDoubleAmountForDisplay(order.orderAmount),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: colorScheme.primary),
                      ),
                      Text('Order Target', style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 18, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final String monthName = _isAllMonths ? 'All Time' : DateFormat('MMMM yyyy').format(_selectedMonth);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4), shape: BoxShape.circle),
              child: Icon(Icons.receipt_long_outlined, size: 40, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text('No Orders for $monthName', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'No purchase orders recorded for this month. Tap "Add Order" below to create one.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSearchResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            Text(
              _searchQuery.isNotEmpty ? 'No orders match "$_searchQuery"' : 'No orders match the selected filter',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 10),
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
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppbar(title: 'Restock (PO)', subtitle: 'Restock from Selecta • Invoices & Tracking'),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () {
          Helperfunctions.navigateTo(
            context,
            PurchaseorderPage(
              purchaseorderID: '',
              purchaseorder: Purchaseorder.empty(),
            ),
          );
        },
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Order',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
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

          // 1. Filter documents by selected month via controller
          final monthDocs = _controller.filterByMonth(docs: allDocs, selectedMonth: _selectedMonth, isAllMonths: _isAllMonths);

          // 2. Compute metrics via controller
          final counts = _controller.calculateCounts(monthDocs);

          // 3. Filter by search query, category chips, and sort via controller
          final filteredDocs = _controller.filterAndSortOrders(
            docs: monthDocs,
            selectedFilter: _selectedFilter,
            searchQuery: _searchQuery,
            sortBy: _sortBy,
          );

          final bool isDateSorted = _sortBy == 'newest' || _sortBy == 'oldest';

          return Column(
            children: [
              // Month Selector Bar
              _buildMonthNavigator(),

              // Search & Sort Bar
              _buildSearchAndSortBar(),

              // Filter Chips for the current month
              _buildFilterChips(
                totalCount: counts.total,
                pendingCount: counts.pending,
                overpaymentCount: counts.overpayment,
                settledCount: counts.settled,
              ),

              // Scrollable Content
              Expanded(
                child: monthDocs.isEmpty
                    ? _buildEmptyState()
                    : filteredDocs.isEmpty
                    ? _buildNoSearchResultsState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 88),
                        itemCount: filteredDocs.length,
                        separatorBuilder: (_, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          final order = doc.data() as Purchaseorder;

                          // If viewing all months and sorted by date, group with month headers
                          if (_isAllMonths && isDateSorted) {
                            final currentMonth = DateFormat('MMMM yyyy').format(order.orderDate.toDate());
                            final bool showMonthHeader =
                                index == 0 ||
                                DateFormat('MMMM yyyy').format((filteredDocs[index - 1].data() as Purchaseorder).orderDate.toDate()) != currentMonth;

                            if (showMonthHeader) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildMonthHeader(currentMonth),
                                  _buildOrderCard(orderId: doc.id, order: order),
                                ],
                              );
                            }
                          }

                          return _buildOrderCard(orderId: doc.id, order: order);
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
