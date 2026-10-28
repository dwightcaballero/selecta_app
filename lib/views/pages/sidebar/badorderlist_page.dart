import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/badorder_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/responsive.dart';
import 'package:selecta_ops/models/badorder.dart';
import 'package:selecta_ops/models/badorder_batch.dart';
import 'package:selecta_ops/views/pages/sidebar/badorder_batch_create_page.dart';
import 'package:selecta_ops/views/pages/sidebar/badorder_batch_detail_page.dart';
import 'package:selecta_ops/views/pages/sidebar/badorder_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';
import 'package:selecta_ops/views/pages/sidebar/badorder_form_page.dart';
import 'package:intl/intl.dart';

class BadOrderlistPage extends StatefulWidget {
  const BadOrderlistPage({super.key});

  @override
  State<BadOrderlistPage> createState() => _BadOrderlistPageState();
}

class _BadOrderlistPageState extends State<BadOrderlistPage> with SingleTickerProviderStateMixin {
  final BadOrderController _controller = BadOrderController();

  late final TabController _tabController;
  late final Stream<QuerySnapshot<BadOrder>> _badOrdersStream;
  late final Stream<QuerySnapshot<BadOrderBatch>> _batchesStream;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  String _selectedPeriod = 'All'; // 'All' or 'This Month'
  String _selectedStatus = 'All'; // 'All', 'Store Pullout', 'Warehouse Pullout', 'Settled'
  String _selectedRefund = 'All'; // 'All', 'Store Refunded', 'Store Not Refunded'
  bool _isDealer = false;

  String? _selectedBadOrderId;
  BadOrder? _selectedBadOrder;
  String? _selectedBatchId;
  BadOrderBatch? _selectedBatch;

  List<QueryDocumentSnapshot<BadOrder>> _cachedAllBadOrders = [];
  int _cachedBatchesCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _badOrdersStream = _controller.getBadOrdersStream();
    _batchesStream = _controller.getBatchesStream();
    _controller.checkIsDealer().then((dealer) {
      if (mounted) setState(() => _isDealer = dealer);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _openAddBadOrderPage() {
    Helperfunctions.navigateTo(context, const BadOrderFormPage());
  }

  void _openCreateBatchPage() {
    final pending = _cachedAllBadOrders.where((doc) {
      final bo = doc.data();
      return bo.isNewRecord &&
          bo.items.isNotEmpty &&
          bo.status == BadOrderStatus.storePullout &&
          (bo.batchId == null || bo.batchId!.isEmpty);
    }).toList();

    if (pending.isEmpty) {
      ShowMessage.info(context, 'There are no pending store bad orders in the warehouse freezer to batch.');
      return;
    }

    Helperfunctions.navigateTo(
      context,
      BadOrderBatchCreatePage(
        pendingOrders: pending,
        existingBatchCount: _cachedBatchesCount,
      ),
    );
  }

  int get _secondaryFilterCount {
    int count = 0;
    if (_selectedPeriod != 'All') count++;
    if (_selectedRefund != 'All') count++;
    return count;
  }

  void _openFilterModal({
    required int allCount,
    required int thisMonthCount,
    required int storeRefundedCount,
    required int storeNotRefundedCount,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        String tempPeriod = _selectedPeriod;
        String tempRefund = _selectedRefund;

        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;

            return Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Filter Records',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              tempPeriod = 'All';
                              tempRefund = 'All';
                            });
                          },
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Time Period',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          label: Text('All Time ($allCount)', style: const TextStyle(fontSize: 12)),
                          selected: tempPeriod == 'All',
                          onSelected: (_) => setModalState(() => tempPeriod = 'All'),
                        ),
                        ChoiceChip(
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          label: Text('This Month ($thisMonthCount)', style: const TextStyle(fontSize: 12)),
                          selected: tempPeriod == 'This Month',
                          onSelected: (_) => setModalState(() => tempPeriod = 'This Month'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Store Refund Status',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          label: const Text('All', style: TextStyle(fontSize: 12)),
                          selected: tempRefund == 'All',
                          onSelected: (_) => setModalState(() => tempRefund = 'All'),
                        ),
                        ChoiceChip(
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(Icons.check_circle_outline, size: 14, color: Colors.green),
                          label: Text('Store Refunded ($storeRefundedCount)', style: const TextStyle(fontSize: 12)),
                          selected: tempRefund == 'Store Refunded',
                          onSelected: (_) => setModalState(() => tempRefund = 'Store Refunded'),
                        ),
                        ChoiceChip(
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(Icons.schedule, size: 14, color: Colors.amber.shade800),
                          label: Text('Store Not Refunded ($storeNotRefundedCount)', style: const TextStyle(fontSize: 12)),
                          selected: tempRefund == 'Store Not Refunded',
                          onSelected: (_) => setModalState(() => tempRefund = 'Store Not Refunded'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _selectedPeriod = tempPeriod;
                            _selectedRefund = tempRefund;
                          });
                          Navigator.pop(modalCtx);
                        },
                        child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _buildCompactSummary({
    required double totalAmount,
    required int totalCount,
    required int unrefundedCount,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _selectedPeriod == 'This Month'
                      ? 'Bad Orders (${DateFormat('MMMM').format(DateTime.now())})'
                      : 'Total Bad Orders',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  Helperfunctions.formatDoubleAmountForDisplay(totalAmount),
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.45)),
                ),
                child: Text(
                  '$totalCount record${totalCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (unrefundedCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule, size: 12, color: Colors.amber.shade900),
                      const SizedBox(width: 3),
                      Text(
                        '$unrefundedCount unrefunded',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar({required VoidCallback onOpenFilter}) {
    final colorScheme = Theme.of(context).colorScheme;
    final filterCount = _secondaryFilterCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 6.0, 16.0, 4.0),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search store, product, or notes...',
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
          ),
          const SizedBox(width: 8),
          Badge(
            isLabelVisible: filterCount > 0,
            label: Text('$filterCount', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            child: IconButton.outlined(
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                side: BorderSide(
                  color: filterCount > 0
                      ? colorScheme.primary
                      : colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
                backgroundColor: filterCount > 0
                    ? colorScheme.primary.withValues(alpha: 0.1)
                    : Colors.transparent,
              ),
              icon: Icon(
                Icons.filter_list_rounded,
                size: 20,
                color: filterCount > 0 ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              tooltip: 'Filter Records',
              onPressed: onOpenFilter,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final statuses = [
      'All',
      BadOrderStatus.storePullout,
      BadOrderStatus.warehousePullout,
      BadOrderStatus.settled,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: statuses.map((status) {
          final isSelected = _selectedStatus == status;
          final label = status == 'All' ? 'All Status' : status;
          return Padding(
            padding: const EdgeInsets.only(right: 6.0),
            child: ChoiceChip(
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              label: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedStatus = status),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActiveFiltersBar() {
    final hasActiveSecondary = _secondaryFilterCount > 0;
    if (!hasActiveSecondary) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (_selectedPeriod != 'All') ...[
              InputChip(
                visualDensity: VisualDensity.compact,
                label: const Text('This Month', style: TextStyle(fontSize: 11)),
                onDeleted: () => setState(() => _selectedPeriod = 'All'),
              ),
              const SizedBox(width: 6),
            ],
            if (_selectedRefund != 'All') ...[
              InputChip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  _selectedRefund == 'Store Refunded' ? 'Store Refunded' : 'Store Not Refunded',
                  style: const TextStyle(fontSize: 11),
                ),
                onDeleted: () => setState(() => _selectedRefund = 'All'),
              ),
              const SizedBox(width: 6),
            ],
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                minimumSize: const Size(40, 24),
              ),
              onPressed: () => setState(() {
                _selectedPeriod = 'All';
                _selectedRefund = 'All';
              }),
              child: const Text('Reset', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case BadOrderStatus.storePullout:
        return Colors.orange.shade700;
      case BadOrderStatus.warehousePullout:
        return Colors.blue.shade700;
      case BadOrderStatus.settled:
        return Colors.green.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  String _getDateGroup(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recordDate = DateTime(date.year, date.month, date.day);

    final diffDays = today.difference(recordDate).inDays;
    if (diffDays == 0) {
      return 'Today';
    } else if (diffDays == 1) {
      return 'Yesterday';
    } else if (date.year == now.year && date.month == now.month) {
      return 'Earlier This Month';
    } else {
      return DateFormat('MMMM yyyy').format(date);
    }
  }

  Widget _buildSectionHeader(String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12.0, bottom: 6.0),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
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

  Widget _buildBadOrderCard({
    required String badorderID,
    required BadOrder badorder,
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _getStatusColor(badorder.status);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: isSelected ? colorScheme.primaryContainer.withValues(alpha: 0.15) : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap ?? () => Helperfunctions.navigateTo(context, BadOrderPage(recID: badorderID, badorder: badorder)),
        child: Stack(
          children: [
            // Status left accent stripe
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Main information
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Line 1: Store Name & Total Amount
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: Text(
                                badorder.hapistore,
                                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              Helperfunctions.formatDoubleAmountForDisplay(badorder.totalAmount),
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.primary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Line 2: Meta (date + item count)
                        Text(
                          '${Helperfunctions.formatTimestampForDisplay(badorder.badorderDate)} • ${badorder.items.length} item${badorder.items.length == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        // Line 3: Status & Refund Badges in a Wrap to prevent any overflow
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // Status Pill
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                badorder.status,
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: statusColor),
                              ),
                            ),
                            if (badorder.batchNumber != null && badorder.batchNumber!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.inventory_2_outlined, size: 10, color: Colors.blue.shade700),
                                    const SizedBox(width: 3),
                                    Text(
                                      badorder.batchNumber!,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (badorder.status == BadOrderStatus.storePullout)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  'In Warehouse',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade800,
                                  ),
                                ),
                              ),
                            // Compact Refund Indicator
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: badorder.isStoreRefunded
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    badorder.isStoreRefunded ? Icons.check : Icons.schedule,
                                    size: 10,
                                    color: badorder.isStoreRefunded ? Colors.green.shade700 : Colors.amber.shade900,
                                  ),
                                  const SizedBox(width: 2.5),
                                  Text(
                                    badorder.isStoreRefunded ? 'Refunded' : 'Unrefunded',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: badorder.isStoreRefunded ? Colors.green.shade800 : Colors.amber.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        // Line 3: Notes (only if present)
                        if (badorder.notes.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.notes_rounded, size: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  badorder.notes,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, size: 18, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                ],
              ),
            ),
          ],
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
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 44),
            ),
            const SizedBox(height: 16),
            const Text('No Bad Orders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'No damaged or expired goods recorded.\nBad orders can be recorded by salesmen and dealers.',
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
            _searchQuery.isNotEmpty ? 'No records matching "$_searchQuery"' : 'No records found for this filter',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _selectedPeriod = 'All';
                _selectedStatus = 'All';
                _selectedRefund = 'All';
              });
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Reset filters'),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchesTab() {
    return StreamBuilder<QuerySnapshot<BadOrderBatch>>(
      stream: _batchesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Unable to load warehouse batches.'));
        }
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final batches = snapshot.data?.docs ?? [];
        _cachedBatchesCount = batches.length;

        if (batches.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.warehouse_outlined, color: Colors.blue.shade700, size: 44),
                  ),
                  const SizedBox(height: 16),
                  const Text('No Warehouse Batches', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                    'When the supplier conducts a pullout of accumulated bad orders from your warehouse, create a batch here to track pullout slips and supplier refund settlements.',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                  if (_isDealer) ...[
                    const SizedBox(height: 16),
                    AsyncFilledButton.icon(
                      onPressed: _openCreateBatchPage,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Create First Warehouse Batch', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        final totalSubmitted = batches.fold<double>(0.0, (acc, b) => acc + b.data().totalBatchAmount);
        final totalCredited = batches.fold<double>(0.0, (acc, b) => acc + (b.data().supplierRefundAmount ?? 0.0));
        final settledCount = batches.where((b) => b.data().isSettled).length;
        final pendingCount = batches.length - settledCount;

        if (ScreenSize.isTabletLandscape(context) && batches.isNotEmpty) {
          if (_selectedBatchId == null || !batches.any((b) => b.id == _selectedBatchId)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _selectedBatchId = batches.first.id;
                  _selectedBatch = batches.first.data();
                });
              }
            });
          }
        }

        final listContent = ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Batches', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('${batches.length} batch${batches.length == 1 ? '' : 'es'}',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text('$settledCount settled • $pendingCount awaiting CM',
                            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                  Container(height: 36, width: 1, color: Colors.grey.shade300),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Supplier Credited', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          Helperfunctions.formatDoubleAmountForDisplay(totalCredited),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                        ),
                        const SizedBox(height: 2),
                        Text('Submitted: ${Helperfunctions.formatDoubleAmountForDisplay(totalSubmitted)}',
                            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ...batches.map((doc) {
              final batch = doc.data();
              final isSelected = ScreenSize.isTabletLandscape(context) && doc.id == _selectedBatchId;
              return _buildBatchCard(
                batchId: doc.id,
                batch: batch,
                isSelected: isSelected,
                onTap: ScreenSize.isTabletLandscape(context)
                    ? () => setState(() {
                          _selectedBatchId = doc.id;
                          _selectedBatch = batch;
                        })
                    : null,
              );
            }),
          ],
        );

        if (!ScreenSize.isTabletLandscape(context)) {
          return listContent;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: listContent),
            Expanded(
              flex: 5,
              child: _buildTabletBatchPreview(_selectedBatch, _selectedBatchId),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBatchCard({
    required String batchId,
    required BadOrderBatch batch,
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSettled = batch.isSettled;
    final statusColor = isSettled ? Colors.green.shade700 : Colors.blue.shade700;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: isSelected ? colorScheme.primaryContainer.withValues(alpha: 0.15) : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap ??
            () {
              Helperfunctions.navigateTo(
                context,
                BadOrderBatchDetailPage(batchId: batchId, batch: batch),
              );
            },
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 18, color: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        batch.batchNumber,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      batch.status,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Pullout: ${Helperfunctions.formatDateForDisplay(batch.pulloutDate.toDate())}',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  if (batch.supplierRefNo.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text('• Slip: ${batch.supplierRefNo}',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${batch.badOrderIds.length} store pullouts (${batch.totalItemsCount} items)',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(batch.totalBatchAmount),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                ],
              ),
              if (isSettled) ...[
                const Divider(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 14, color: Colors.green.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'CM: ${batch.supplierCreditMemoNo} • Credited: ${Helperfunctions.formatDoubleAmountForDisplay(batch.supplierRefundAmount ?? batch.totalBatchAmount)}'
                          '${batch.varianceAmount.abs() > 0.01 ? " (${batch.varianceAmount >= 0 ? '+' : ''}${Helperfunctions.formatDoubleAmountForDisplay(batch.varianceAmount)})" : ""}',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const Divider(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.schedule, size: 14, color: Colors.amber.shade900),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Awaiting Supplier Credit Memo / Refund${_isDealer ? ' (Tap to settle)' : ''}',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabletBadOrderPreview(BadOrder? bo, String? boId) {
    final colorScheme = Theme.of(context).colorScheme;
    if (bo == null || boId == null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(0, 8, 16, 16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.assignment_late_outlined, size: 56, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text(
                'Select a bad order record',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                'View pullout details and damaged SKU breakdown',
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      );
    }

    final statusColor = _getStatusColor(bo.status);

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 16, 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        bo.hapistore,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      Helperfunctions.formatDoubleAmountForDisplay(bo.totalAmount),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          'Pulled out: ${Helperfunctions.formatTimestampForDisplay(bo.badorderDate)}',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        bo.status,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: bo.isStoreRefunded
                            ? Colors.green.withValues(alpha: 0.12)
                            : Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        bo.isStoreRefunded ? 'Refunded' : 'Unrefunded',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: bo.isStoreRefunded ? Colors.green.shade800 : Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                if (bo.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Note: ${bo.notes}',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),

          // Items List
          Expanded(
            child: bo.items.isEmpty
                ? Center(
                    child: Text('No damaged items recorded', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                  )
                : ListView.separated(
                    primary: false,
                    padding: const EdgeInsets.all(16),
                    itemCount: bo.items.length,
                    separatorBuilder: (_, index) => const Divider(height: 12),
                    itemBuilder: (context, index) {
                      final item = bo.items[index];
                      return Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.ac_unit, size: 18, color: colorScheme.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.productName,
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${item.category} • ${Helperfunctions.formatDoubleAmountForDisplay(item.pricePerPiece)} each',
                                  style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${item.quantity} pcs',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                Helperfunctions.formatDoubleAmountForDisplay(item.subtotal),
                                style: TextStyle(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
          ),

          // Action button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: AsyncFilledButton.icon(
              onPressed: () {
                Helperfunctions.navigateTo(context, BadOrderPage(recID: boId, badorder: bo));
              },
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open Bad Order Details & Actions', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletBatchPreview(BadOrderBatch? batch, String? batchId) {
    final colorScheme = Theme.of(context).colorScheme;
    if (batch == null || batchId == null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(0, 12, 16, 16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined, size: 56, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text(
                'Select a warehouse batch',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                'View supplier pullout slip and refund memo details',
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      );
    }

    final isSettled = batch.isSettled;
    final statusColor = isSettled ? Colors.green.shade700 : Colors.blue.shade700;

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 12, 16, 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 20, color: statusColor),
                        const SizedBox(width: 8),
                        Text(
                          batch.batchNumber,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        batch.status,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Pullout Date: ${Helperfunctions.formatDateForDisplay(batch.pulloutDate.toDate())}${batch.supplierRefNo.isNotEmpty ? " • Slip: ${batch.supplierRefNo}" : ""}',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Financial Breakdown
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              batch.isLegacyBasis ? 'Expected Total (Legacy)' : 'Expected Supplier Refund',
                              style: const TextStyle(fontSize: 13),
                            ),
                            Text(
                              Helperfunctions.formatDoubleAmountForDisplay(batch.totalBatchAmount),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        if (batch.totalStoreRefundAmount != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Stores Refunded', style: TextStyle(fontSize: 13)),
                              Text(
                                Helperfunctions.formatDoubleAmountForDisplay(batch.totalStoreRefundAmount!),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Supplier Credited Amount', style: TextStyle(fontSize: 13)),
                            Text(
                              batch.supplierRefundAmount != null
                                  ? Helperfunctions.formatDoubleAmountForDisplay(batch.supplierRefundAmount!)
                                  : 'Pending',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: batch.supplierRefundAmount != null ? Colors.green.shade800 : Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ),
                        if (batch.supplierRefundAmount != null) ...[
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Variance', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text(
                                '${batch.varianceAmount >= 0 ? '+' : ''}${Helperfunctions.formatDoubleAmountForDisplay(batch.varianceAmount)}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: batch.varianceAmount.abs() < 0.01
                                      ? Colors.green.shade800
                                      : (batch.varianceAmount < 0 ? Colors.red.shade700 : Colors.blue.shade700),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Batch Stats
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Store Pullouts', style: TextStyle(fontSize: 11, color: Colors.blue.shade800)),
                              const SizedBox(height: 2),
                              Text('${batch.badOrderIds.length}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total Items', style: TextStyle(fontSize: 11, color: Colors.purple.shade800)),
                              const SizedBox(height: 2),
                              Text('${batch.totalItemsCount}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.purple.shade900)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (isSettled && batch.supplierCreditMemoNo.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade300, width: 0.8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.receipt_long, size: 20, color: Colors.green.shade700),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Credit Memo Number', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                Text(batch.supplierCreditMemoNo, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Action button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: AsyncFilledButton.icon(
              onPressed: () {
                Helperfunctions.navigateTo(
                  context,
                  BadOrderBatchDetailPage(batchId: batchId, batch: batch),
                );
              },
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(
                isSettled ? 'View Batch & Items' : 'Manage Batch & Settle Memo',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final pendingCount = _cachedAllBadOrders.where((doc) {
      final bo = doc.data();
      return bo.isNewRecord &&
          bo.items.isNotEmpty &&
          bo.status == BadOrderStatus.storePullout &&
          (bo.batchId == null || bo.batchId!.isEmpty);
    }).length;

    Widget? fab;
    if (_tabController.index == 0) {
      if (_isDealer && pendingCount > 0) {
        fab = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.extended(
              heroTag: 'batchPulloutFab',
              onPressed: _openCreateBatchPage,
              icon: const Icon(Icons.warehouse_outlined, color: Colors.white),
              label: Text(
                'Batch Pullout ($pendingCount)',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.blue.shade700,
            ),
            const SizedBox(width: 8),
            FloatingActionButton.extended(
              heroTag: 'addStorePulloutFab',
              onPressed: _openAddBadOrderPage,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Record',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          ],
        );
      } else {
        fab = FloatingActionButton.extended(
          heroTag: 'addStorePulloutFab',
          onPressed: _openAddBadOrderPage,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text(
            'Add Bad Order Record',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        );
      }
    } else {
      if (_isDealer) {
        fab = FloatingActionButton.extended(
          heroTag: 'newBatchFab',
          onPressed: _openCreateBatchPage,
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text(
            'New Warehouse Batch${pendingCount > 0 ? ' ($pendingCount pending)' : ''}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.blue.shade700,
        );
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
        appBar: CustomAppbar(
          title: 'Bad Orders',
          subtitle: 'Damaged & Expired Products',
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(
                icon: Icon(Icons.storefront_outlined, size: 18),
                text: 'Store Pullouts',
              ),
              Tab(
                icon: Icon(Icons.warehouse_outlined, size: 18),
                text: 'Warehouse Batches',
              ),
            ],
          ),
        ),
        floatingActionButton: fab,
        body: TabBarView(
          controller: _tabController,
          children: [
            // Tab 0: Store Pullouts
            StreamBuilder<QuerySnapshot<BadOrder>>(
              stream: _badOrdersStream,
              builder: (BuildContext context, AsyncSnapshot<QuerySnapshot<BadOrder>> snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Unable to load bad orders. Please try again.'));
                }
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allDocs = snapshot.data?.docs ?? [];
                _cachedAllBadOrders = allDocs;

                final filterResult = _controller.filterBadOrders(
                  docs: allDocs,
                  selectedPeriod: _selectedPeriod,
                  searchQuery: _searchQuery,
                  now: now,
                  statusFilter: _selectedStatus,
                  refundFilter: _selectedRefund,
                );
                final filteredDocs = filterResult.filteredDocs;
                final periodTotalAmount = filterResult.periodTotalAmount;
                final thisMonthCount = filterResult.thisMonthCount;

                if (filterResult.allCount == 0 && _searchQuery.isEmpty && _selectedStatus == 'All' && _selectedRefund == 'All') {
                  return _buildEmptyState();
                }

                if (ScreenSize.isTabletLandscape(context) && filteredDocs.isNotEmpty) {
                  if (_selectedBadOrderId == null || !filteredDocs.any((d) => d.id == _selectedBadOrderId)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _selectedBadOrderId = filteredDocs.first.id;
                          _selectedBadOrder = filteredDocs.first.data();
                        });
                      }
                    });
                  }
                }

                // Build grouped list items with section headers
                final List<_BadOrderListItem> listItems = [];
                String? lastGroup;
                for (final doc in filteredDocs) {
                  final group = _getDateGroup(doc.data().badorderDate);
                  if (group != lastGroup) {
                    lastGroup = group;
                    listItems.add(_BadOrderListItem.header(group));
                  }
                  listItems.add(_BadOrderListItem.doc(doc));
                }

                final listWidget = Column(
                  children: [
                    _buildCompactSummary(
                      totalAmount: periodTotalAmount,
                      totalCount: _selectedPeriod == 'All' ? filterResult.allCount : thisMonthCount,
                      unrefundedCount: filterResult.storeNotRefundedCount,
                    ),
                    _buildSearchBar(
                      onOpenFilter: () => _openFilterModal(
                        allCount: filterResult.allCount,
                        thisMonthCount: thisMonthCount,
                        storeRefundedCount: filterResult.storeRefundedCount,
                        storeNotRefundedCount: filterResult.storeNotRefundedCount,
                      ),
                    ),
                    _buildStatusBar(),
                    _buildActiveFiltersBar(),
                    const SizedBox(height: 4),
                    Expanded(
                      child: filteredDocs.isEmpty
                          ? _buildNoSearchResultsState()
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                              itemCount: listItems.length,
                              itemBuilder: (context, index) {
                                final item = listItems[index];
                                if (item.header != null) {
                                  return _buildSectionHeader(item.header!);
                                }
                                final doc = item.doc!;
                                final isSelected = ScreenSize.isTabletLandscape(context) && doc.id == _selectedBadOrderId;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: _buildBadOrderCard(
                                    badorderID: doc.id,
                                    badorder: doc.data(),
                                    isSelected: isSelected,
                                    onTap: ScreenSize.isTabletLandscape(context)
                                        ? () => setState(() {
                                              _selectedBadOrderId = doc.id;
                                              _selectedBadOrder = doc.data();
                                            })
                                        : null,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );

                if (!ScreenSize.isTabletLandscape(context)) {
                  return listWidget;
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: listWidget),
                    Expanded(
                      flex: 5,
                      child: _buildTabletBadOrderPreview(_selectedBadOrder, _selectedBadOrderId),
                    ),
                  ],
                );
              },
            ),

            // Tab 1: Warehouse Batches
            _buildBatchesTab(),
          ],
        ),
      ),
    );
  }
}

/// Helper model for grouped list rendering with date headers
class _BadOrderListItem {
  final String? header;
  final QueryDocumentSnapshot<BadOrder>? doc;

  _BadOrderListItem.header(this.header) : doc = null;
  _BadOrderListItem.doc(this.doc) : header = null;
}

