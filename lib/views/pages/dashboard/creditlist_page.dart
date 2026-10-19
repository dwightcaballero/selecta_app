import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/credit_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/responsive.dart';
import 'package:selecta_ops/views/pages/dashboard/credit_page.dart';
import 'package:selecta_ops/views/pages/sidebar/store_profile_page.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';

/// Presentation view displaying the list of all stores with outstanding credits.
///
/// Purely responsible for rendering UI widgets. Data streaming, role checking,
/// metric computation, filtering, and sorting are handled by [CreditController],
/// while direct database calls are managed in the service layer.
class CreditlistPage extends StatefulWidget {
  const CreditlistPage({super.key});

  @override
  State<CreditlistPage> createState() => _CreditlistPageState();
}

class _CreditlistPageState extends State<CreditlistPage> {
  /// Controller managing credit business logic and calculations.
  final CreditController _controller = CreditController();

  /// Whether the active user is a dealer (determines navigation to settlement page).
  bool isDealer = true;

  /// Firestore stream providing real-time credit updates.
  late final Stream<QuerySnapshot> _creditStream;

  /// Controllers for the search input.
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  /// Current search query string.
  String _searchQuery = '';

  /// Currently selected sorting option.
  CreditSort _selectedSort = CreditSort.highestAmount;

  /// Currently selected aging filter.
  final CreditAgingFilter _selectedAging = CreditAgingFilter.all;

  /// Currently selected credit record for tablet dual-pane preview.
  String? _selectedRecordId;
  CreditRecord? _selectedRecord;

  @override
  void initState() {
    super.initState();
    _creditStream = _controller.getCreditDeliveriesStream();
    _prefetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Fetches the user role to check dealer privileges.
  Future<void> _prefetchData() async {
    final dealer = await _controller.checkIsDealer();
    if (mounted) {
      setState(() => isDealer = dealer);
    }
  }

  // ==========================================
  // UI Building Blocks
  // ==========================================

  /// Builds the top card displaying total outstanding credit and account counts.
  Widget _buildSummaryCard(CreditListMetrics metrics) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFiltered = metrics.isFiltered && (_searchQuery.isNotEmpty || _selectedAging != CreditAgingFilter.all);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
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
              // Outstanding credit amounts
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isFiltered ? 'Filtered Outstanding Credit' : 'Total Outstanding Credit',
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(isFiltered ? metrics.filteredCredit : metrics.totalCredit),
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),

              // Store count badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: [
                    Text(isFiltered ? 'Matching' : 'Stores', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    Text(
                      isFiltered ? '${metrics.filteredCount} / ${metrics.totalAccounts}' : '${metrics.totalAccounts}',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Search / Aging filter context banner
          if (isFiltered) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.filter_alt_outlined, size: 13, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(
                    'Overall: ${Helperfunctions.formatDoubleAmountForDisplay(metrics.totalCredit)} (${metrics.totalAccounts} stores)',
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

  /// Builds the search textfield and sorting popup button.
  Widget _buildSearchAndFilterBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Row(
        children: [
          // Search text input
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

          // Sorting menu button
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
                    Icon(sort.icon, size: 18, color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Text(
                      sort.label,
                      style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? colorScheme.primary : null),
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

  /// Builds a subtle, color-coded aging badge indicating days outstanding.
  Widget _buildAgingBadge(int days) {
    final Color bgColor;
    final Color textColor;
    final String text;

    if (days <= 15) {
      bgColor = Colors.green.withValues(alpha: 0.12);
      textColor = Colors.green.shade800;
      text = '$days d';
    } else if (days <= 30) {
      bgColor = Colors.amber.withValues(alpha: 0.18);
      textColor = Colors.orange.shade900;
      text = '$days d Due';
    } else {
      bgColor = Colors.red.withValues(alpha: 0.14);
      textColor = Colors.red.shade800;
      text = '$days d Overdue';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(5)),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: textColor),
      ),
    );
  }

  /// Builds a clickable card representing an individual store's credit details.
  Widget _buildCreditCard(
    CreditRecord record, {
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final delivery = record.delivery;

    return Card(
      elevation: 0,
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: isDark ? 0.25 : 0.12)
          : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isSelected
            ? BorderSide(color: colorScheme.primary, width: 2.0)
            : BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap ??
            (isDealer
                ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreditPage(recID: record.id, delivery: delivery),
                    ),
                  )
                : null),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              // Store credit icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.credit_card_outlined, color: colorScheme.primary, size: 22),
              ),
              const SizedBox(width: 12),

              // Store name and delivery details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Full store name
                    InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StoreProfilePage(storeName: delivery.storeName))),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              delivery.storeName,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.store_rounded, size: 14, color: colorScheme.primary),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Row 2: Date
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_month_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          delivery.deliveryDate != null ? Helperfunctions.formatDateForDisplay(delivery.deliveryDate!.toDate()) : 'No Date',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Row 3: Credit amount alongside aging badge
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          Helperfunctions.formatDoubleAmountForDisplay(delivery.creditAmount),
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.primary),
                        ),
                        const SizedBox(width: 8),
                        _buildAgingBadge(record.agingDays),
                      ],
                    ),
                  ],
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 4),
                Icon(Icons.check_circle, size: 20, color: colorScheme.primary),
              ] else if (isDealer) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 20, color: colorScheme.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Tablet landscape live credit inspector & settlement preview card.
  Widget _buildTabletCreditPreview(ColorScheme colorScheme, CreditRecord? record) {
    if (record == null) {
      return Card(
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(0, 14, 16, 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.credit_card_outlined, size: 56, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 14),
              Text(
                'Select a credit account to review',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                'View aging, invoice details, and settle balance.',
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
              ),
            ],
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final delivery = record.delivery;
    final dateStr = delivery.deliveryDate != null
        ? Helperfunctions.formatDateForDisplay(delivery.deliveryDate!.toDate())
        : Helperfunctions.formatDateForDisplay(delivery.createdDate.toDate());

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(0, 14, 16, 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: SingleChildScrollView(
        primary: false,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Store & Status Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: isDark ? 0.15 : 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.store_rounded, color: colorScheme.primary, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          delivery.storeName,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _buildAgingBadge(record.agingDays),
                            const SizedBox(width: 8),
                            Icon(Icons.calendar_today_outlined, size: 12, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              dateStr,
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Financial Breakdown Card
            const Text('Financial Breakdown', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Outstanding Balance', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                      Text(
                        Helperfunctions.formatDoubleAmountForDisplay(delivery.creditAmount),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.primary),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Original Order Amount', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                      Text(
                        Helperfunctions.formatDoubleAmountForDisplay(delivery.orderAmount),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Cash Collected', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                      Text(
                        Helperfunctions.formatDoubleAmountForDisplay(delivery.cashAmount),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.green.shade700),
                      ),
                    ],
                  ),
                  if (delivery.onlineAmount > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Online Payment', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                        Text(
                          Helperfunctions.formatDoubleAmountForDisplay(delivery.onlineAmount),
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.blue.shade700),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Aging Period', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                      Text(
                        '${record.agingDays} days ago',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: record.agingDays > 30 ? Colors.red.shade700 : colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Line Items (if any exist)
            if (delivery.items.isNotEmpty) ...[
              Text('Delivered Items (${delivery.items.length})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: delivery.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 12, endIndent: 12),
                  itemBuilder: (context, idx) {
                    final item = delivery.items[idx];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.productName,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${item.effectiveQuantity} pcs',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            Helperfunctions.formatDoubleAmountForDisplay(item.lineTotal),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
            ],

            // Action Buttons
            Row(
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StoreProfilePage(storeName: delivery.storeName),
                      ),
                    );
                  },
                  icon: const Icon(Icons.storefront_outlined, size: 18),
                  label: const Text('Store Profile', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (isDealer) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CreditPage(recID: record.id, delivery: delivery),
                          ),
                        );
                      },
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text(
                        'Settle Credit',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Builds empty state when no credits exist in the system.
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
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), shape: BoxShape.circle),
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

  /// Builds empty state when search filters produce no matches.
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

  /// Builds the error state widget.
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
    final isTabletLandscape = ScreenSize.isTabletLandscape(context);
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
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

            // Delegate metric computation, filtering, and sorting to the controller
            final metrics = _controller.computeMetrics(docs: allDocs, searchQuery: _searchQuery, sort: _selectedSort, agingFilter: _selectedAging);

            if (isTabletLandscape && metrics.filteredRecords.isNotEmpty) {
              final exists = _selectedRecordId != null && metrics.filteredRecords.any((r) => r.id == _selectedRecordId);
              if (!exists) {
                final first = metrics.filteredRecords.first;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _selectedRecordId != first.id) {
                    setState(() {
                      _selectedRecordId = first.id;
                      _selectedRecord = first;
                    });
                  }
                });
              }
            }

            final listColumn = Column(
              children: [
                // 1. Total Outstanding Summary Header
                _buildSummaryCard(metrics),

                // 2. Search & Sort Bar
                _buildSearchAndFilterBar(),

                // 3. Filtered Credits List
                Expanded(
                  child: metrics.filteredRecords.isEmpty
                      ? _buildNoSearchResultsState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: metrics.filteredRecords.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final record = metrics.filteredRecords[index];
                            final isSelected = isTabletLandscape && _selectedRecordId == record.id;
                            return _buildCreditCard(
                              record,
                              isSelected: isSelected,
                              onTap: isTabletLandscape
                                  ? () {
                                      setState(() {
                                        _selectedRecordId = record.id;
                                        _selectedRecord = record;
                                      });
                                    }
                                  : null,
                            );
                          },
                        ),
                ),
              ],
            );

            if (isTabletLandscape) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: listColumn),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 5,
                    child: _buildTabletCreditPreview(colorScheme, _selectedRecord),
                  ),
                ],
              );
            }

            return listColumn;
          },
        ),
      ),
    );
  }
}
