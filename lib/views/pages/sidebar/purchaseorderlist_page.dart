import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/purchaseorder.dart';
import 'package:flutter_app/services/purchaseorder_service.dart';
import 'package:flutter_app/views/pages/sidebar/purchaseorder_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

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
  String _sortBy = 'newest'; // 'newest', 'oldest', 'amount_high', 'amount_low'

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _isAllMonths = false;

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

  void _changeMonth(int delta) {
    setState(() {
      _isAllMonths = false;
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
  }

  Future<void> _pickMonthYear() async {
    final now = DateTime.now();
    int tempYear = _selectedMonth.year;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final colorScheme = Theme.of(context).colorScheme;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setDialogState(() => tempYear--),
                  ),
                  Text('$tempYear', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: tempYear >= now.year ? null : () => setDialogState(() => tempYear++),
                  ),
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
                              child: Text(
                                monthName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
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

  Widget _buildMonthNavigator() {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final bool isCurrentMonth = !_isAllMonths && _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    final String label = _isAllMonths ? 'All Months' : DateFormat('MMMM yyyy').format(_selectedMonth);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 22),
            visualDensity: VisualDensity.compact,
            tooltip: 'Previous Month',
            onPressed: () => _changeMonth(-1),
          ),
          InkWell(
            onTap: _pickMonthYear,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_month_outlined, size: 17, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 18, color: colorScheme.onSurfaceVariant),
                  if (!isCurrentMonth && !_isAllMonths) ...[
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => setState(() {
                        _isAllMonths = false;
                        _selectedMonth = DateTime(now.year, now.month);
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'This Month',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 22),
            visualDensity: VisualDensity.compact,
            tooltip: 'Next Month',
            onPressed: (_isAllMonths || isCurrentMonth) ? null : () => _changeMonth(1),
          ),
        ],
      ),
    );
  }



  Widget _buildSearchAndSortBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
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
            icon: Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: _sortBy != 'newest'
                    ? colorScheme.primary.withValues(alpha: 0.12)
                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _sortBy != 'newest'
                      ? colorScheme.primary
                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Icon(
                Icons.sort_rounded,
                size: 20,
                color: _sortBy != 'newest' ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
            ),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'newest',
                child: Row(
                  children: [
                    Icon(Icons.arrow_downward_rounded, size: 16),
                    SizedBox(width: 8),
                    Text('Date: Newest First'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'oldest',
                child: Row(
                  children: [
                    Icon(Icons.arrow_upward_rounded, size: 16),
                    SizedBox(width: 8),
                    Text('Date: Oldest First'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'amount_high',
                child: Row(
                  children: [
                    Icon(Icons.trending_down_rounded, size: 16),
                    SizedBox(width: 8),
                    Text('Amount: Highest First'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'amount_low',
                child: Row(
                  children: [
                    Icon(Icons.trending_up_rounded, size: 16),
                    SizedBox(width: 8),
                    Text('Amount: Lowest First'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
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
      visualDensity: VisualDensity.compact,
      avatar: dotColor != null
          ? Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            )
          : null,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurfaceVariant,
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
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  /// Clean, breathable order card focused on clear hierarchy.
  Widget _buildOrderCard({required String orderId, required Purchaseorder order}) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool hasInvoice = order.invoiceNumber.trim().isNotEmpty && order.invoiceAmount > 0;
    final String invoiceNumber = hasInvoice ? order.invoiceNumber : (order.invoiceNumber.isNotEmpty ? order.invoiceNumber : 'Pending Invoice');
    final dateStr = Helperfunctions.formatTimestampForDisplay(order.orderDate);

    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    if (!hasInvoice) {
      badgeColor = Colors.orange.shade800;
      badgeText = 'Awaiting Invoice';
      badgeIcon = Icons.hourglass_top_rounded;
    } else if (order.isSettled == true) {
      badgeColor = Colors.green.shade700;
      badgeText = 'Settled';
      badgeIcon = Icons.verified_rounded;
    } else if (order.overpayment > 0) {
      badgeColor = Colors.red.shade700;
      badgeText = 'Overpaid: ${Helperfunctions.formatDoubleAmountForDisplay(order.overpayment)}';
      badgeIcon = Icons.warning_amber_rounded;
    } else {
      badgeColor = Colors.teal.shade700;
      badgeText = 'Balanced';
      badgeIcon = Icons.check_circle_outline_rounded;
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Helperfunctions.navigateTo(
          context,
          PurchaseorderPage(purchaseorderID: orderId, purchaseorder: order),
        ),
        onLongPress: () {
          if (order.invoiceNumber.trim().isNotEmpty) {
            Clipboard.setData(ClipboardData(text: order.invoiceNumber.trim()));
            HapticFeedback.lightImpact();
            ShowMessage.success(context, 'Copied invoice #${order.invoiceNumber.trim()} to clipboard');
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Date Pill & Status Pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 12, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        dateStr,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: badgeColor.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(badgeIcon, size: 12, color: badgeColor),
                        const SizedBox(width: 4),
                        Text(
                          badgeText,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Main Row: Invoice # (left) and Order Target Amount (right)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invoiceNumber,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: hasInvoice ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                            fontStyle: hasInvoice ? FontStyle.normal : FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (order.invoiceAmount > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Invoiced: ${Helperfunctions.formatDoubleAmountForDisplay(order.invoiceAmount)}',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
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
                      Text(
                        'Order Target',
                        style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant),
                      ),
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
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
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
              _searchQuery.isNotEmpty
                  ? 'No orders match "$_searchQuery"'
                  : 'No orders match the selected filter',
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
      appBar: const CustomAppbar(title: 'Purchase Orders', subtitle: 'Invoices & Monthly Tracking'),
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

          // 1. Filter documents by selected month (unless viewing all months)
          final monthDocs = allDocs.where((doc) {
            if (_isAllMonths) return true;
            final order = doc.data() as Purchaseorder;
            final orderDate = order.orderDate.toDate();
            return orderDate.year == _selectedMonth.year && orderDate.month == _selectedMonth.month;
          }).toList();

          int pendingCount = 0;
          int overpaymentCount = 0;
          int settledCount = 0;

          for (final doc in monthDocs) {
            final order = doc.data() as Purchaseorder;
            final hasInvoice = order.invoiceNumber.trim().isNotEmpty && order.invoiceAmount > 0;
            if (!hasInvoice) {
              pendingCount++;
            } else if (order.isSettled == true) {
              settledCount++;
            } else if (order.overpayment > 0) {
              overpaymentCount++;
            }
          }

          // 3. Filter by search query and category chips
          final filteredDocs = monthDocs.where((doc) {
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

          // 4. Apply dynamic sorting
          filteredDocs.sort((a, b) {
            final orderA = a.data() as Purchaseorder;
            final orderB = b.data() as Purchaseorder;
            switch (_sortBy) {
              case 'oldest':
                return orderA.orderDate.compareTo(orderB.orderDate);
              case 'amount_high':
                return orderB.orderAmount.compareTo(orderA.orderAmount);
              case 'amount_low':
                return orderA.orderAmount.compareTo(orderB.orderAmount);
              case 'newest':
              default:
                return orderB.orderDate.compareTo(orderA.orderDate);
            }
          });

          final bool isDateSorted = _sortBy == 'newest' || _sortBy == 'oldest';

          return Column(
            children: [
              // Month Selector Bar (< September 2026 >)
              _buildMonthNavigator(),

              // Search & Sort Bar
              _buildSearchAndSortBar(),

              // Filter Chips for the current month
              _buildFilterChips(
                totalCount: monthDocs.length,
                pendingCount: pendingCount,
                overpaymentCount: overpaymentCount,
                settledCount: settledCount,
              ),
              const SizedBox(height: 6),

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
                                final bool showMonthHeader = index == 0 ||
                                    DateFormat('MMMM yyyy').format((filteredDocs[index - 1].data() as Purchaseorder).orderDate.toDate()) != currentMonth;

                                if (showMonthHeader) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildMonthHeader(currentMonth),
                                      _buildOrderCard(
                                        orderId: doc.id,
                                        order: order,
                                      ),
                                    ],
                                  );
                                }
                              }

                              return _buildOrderCard(
                                orderId: doc.id,
                                order: order,
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
