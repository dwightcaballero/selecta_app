import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/expenses_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/expenses.dart';
import 'package:selecta_ops/views/pages/sidebar/expenses_page.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';

class ExpenselistPage extends StatefulWidget {
  const ExpenselistPage({super.key});

  @override
  State<ExpenselistPage> createState() => _ExpenselistPageState();
}

class _ExpenselistPageState extends State<ExpenselistPage> with SingleTickerProviderStateMixin {
  // Controller managing expense streams, filtering, and data aggregation
  final ExpensesController _controller = ExpensesController();

  late final Stream<QuerySnapshot> _expensesStream;
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  String _searchQuery = '';
  String _selectedPeriod = 'All'; // 'All', 'Today', 'This Week', or 'This Month'
  bool _isDealer = false;
  int _currentTabIndex = 0; // 0: Salesman, 1: Dealer

  @override
  void initState() {
    super.initState();
    _expensesStream = _controller.getExpensesStream();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging || _tabController.index != _currentTabIndex) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
      }
    });
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final isDealer = await _controller.checkIsDealer();
    if (mounted) {
      setState(() {
        _isDealer = isDealer;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  String get _currentExpenseType =>
      _currentTabIndex == 0 ? ExpenseType.salesman : ExpenseType.dealer;

  Widget _buildSummaryCard({
    required double totalAmount,
    required double cashAmount,
    required double onlineAmount,
    required int totalCount,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSalesmanTab = _currentTabIndex == 0;
    final String category = isSalesmanTab ? 'Salesman Expenses' : 'Dealer Operating Expenses';
    final String periodLabel = switch (_selectedPeriod) {
      'Today' => '$category (Today - ${DateFormat('MMM dd').format(DateTime.now())})',
      'This Week' => '$category (This Week)',
      'This Month' => '$category (${DateFormat('MMMM yyyy').format(DateTime.now())})',
      _ => isSalesmanTab
          ? 'Total Salesman Expenses (All Time)'
          : 'Total Dealer Operating Expenses (All Time)',
    };

    final gradientColors = isSalesmanTab
        ? [Colors.deepOrange.shade600, Colors.orange.shade800]
        : [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.85)];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (isSalesmanTab ? Colors.orange : colorScheme.primary).withValues(alpha: 0.25),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      periodLabel,
                      style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        Helperfunctions.formatDoubleAmountForDisplay(totalAmount),
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    const Text('Entries', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    Text(
                      '$totalCount',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!isSalesmanTab && totalCount > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.payments_outlined, color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Cash: ${Helperfunctions.formatDoubleAmountForDisplay(cashAmount)}',
                            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 12, width: 1, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 4)),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.account_balance_outlined, color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Online: ${Helperfunctions.formatDoubleAmountForDisplay(onlineAmount)}',
                            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodChips({
    required int allCount,
    required int todayCount,
    required int thisWeekCount,
    required int thisMonthCount,
  }) {
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
            label: Text('Today ($todayCount)', style: const TextStyle(fontSize: 12)),
            selected: _selectedPeriod == 'Today',
            onSelected: (_) => setState(() => _selectedPeriod = 'Today'),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            label: Text('This Week ($thisWeekCount)', style: const TextStyle(fontSize: 12)),
            selected: _selectedPeriod == 'This Week',
            onSelected: (_) => setState(() => _selectedPeriod = 'This Week'),
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
            hintText: 'Search expenses by description...',
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

  Widget _buildExpenseCard({required String expenseID, required Expenses expense}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSalesmanExpense = expense.isSalesmanExpense;
    final isOnline = expense.isOnline;

    final leadingColor = isSalesmanExpense ? Colors.orange : colorScheme.primary;
    final leadingIcon = isSalesmanExpense ? Icons.lunch_dining_outlined : Icons.local_gas_station_outlined;

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
          ExpensesPage(
            recID: expenseID,
            expense: expense,
            initialExpenseType: expense.expenseType,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: leadingColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(leadingIcon, color: leadingColor, size: 20),
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
                            expense.description,
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isOnline ? Colors.blue : Colors.green).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isOnline ? 'Online' : 'Cash',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isOnline ? Colors.blue.shade800 : Colors.green.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_month_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          Helperfunctions.formatTimestampForDisplay(expense.expenseDate),
                          style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                        ),
                        if (expense.createdBy.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.person_outline, size: 13, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              expense.createdBy,
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
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
                    Helperfunctions.formatDoubleAmountForDisplay(expense.expenseAmount),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: leadingColor),
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
    final isSalesmanTab = _currentTabIndex == 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: (isSalesmanTab ? Colors.orange : Colors.green).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSalesmanTab ? Icons.lunch_dining_outlined : Icons.check_circle_outline_rounded,
                color: isSalesmanTab ? Colors.orange : Colors.green,
                size: 44,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isSalesmanTab ? 'No Salesman Expenses Recorded' : 'No Dealer Expenses Recorded',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              isSalesmanTab
                  ? 'Tap "Add Salesman Expense" to log driver snacks and meals.'
                  : (_isDealer
                      ? 'Tap "Add Dealer Expense" to log operations, fuel, or repairs.'
                      : 'Dealer operations expenses will appear here once recorded.'),
              style: const TextStyle(fontSize: 13, color: Colors.black54),
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
            _searchQuery.isNotEmpty ? 'No expenses matching "$_searchQuery"' : 'No expenses found for this period',
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

  Widget? _buildFloatingActionButton() {
    final isSalesmanTab = _currentTabIndex == 0;

    // In dealer tab, salesmen cannot create dealer expenses
    if (!isSalesmanTab && !_isDealer) {
      return null;
    }

    final buttonLabel = isSalesmanTab
        ? (_isDealer ? 'Add Salesman Expense' : 'Add Expense')
        : 'Add Dealer Expense';

    return FloatingActionButton.extended(
      onPressed: () => Helperfunctions.navigateTo(
        context,
        ExpensesPage(
          recID: '',
          expense: Expenses.empty(
            expenseType: isSalesmanTab ? ExpenseType.salesman : ExpenseType.dealer,
          ),
          initialExpenseType: isSalesmanTab ? ExpenseType.salesman : ExpenseType.dealer,
        ),
      ),
      icon: const Icon(Icons.add, color: Colors.white),
      label: Text(buttonLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      backgroundColor: isSalesmanTab ? Colors.orange.shade800 : Theme.of(context).colorScheme.primary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Expenses',
        subtitle: 'Salesman (Snacks) & Dealer (Ops/Gas)',
        bottom: TabBar(
          controller: _tabController,
          indicatorWeight: 3,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(icon: Icon(Icons.lunch_dining_outlined), text: 'Salesman Expenses'),
            Tab(icon: Icon(Icons.storefront_outlined), text: 'Dealer Expenses'),
          ],
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
      body: StreamBuilder<QuerySnapshot>(
        stream: _expensesStream,
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load expenses list. Please try again.'));
          }
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];
          final filterResult = _controller.filterExpenses(
            docs: allDocs,
            selectedExpenseType: _currentExpenseType,
            selectedPeriod: _selectedPeriod,
            searchQuery: _searchQuery,
            now: now,
          );
          final filteredDocs = filterResult.filteredDocs;
          final periodTotalAmount = filterResult.periodTotalAmount;
          final periodCashAmount = filterResult.periodCashAmount;
          final periodOnlineAmount = filterResult.periodOnlineAmount;
          final thisMonthCount = filterResult.thisMonthCount;
          final allCount = filterResult.allCount;

          if (allCount == 0 && _searchQuery.isEmpty) {
            return Column(
              children: [
                _buildSummaryCard(
                  totalAmount: 0,
                  cashAmount: 0,
                  onlineAmount: 0,
                  totalCount: 0,
                ),
                Expanded(child: _buildEmptyState()),
              ],
            );
          }

          return Column(
            children: [
              _buildSummaryCard(
                totalAmount: periodTotalAmount,
                cashAmount: periodCashAmount,
                onlineAmount: periodOnlineAmount,
                totalCount: switch (_selectedPeriod) {
                  'Today' => filterResult.todayCount,
                  'This Week' => filterResult.thisWeekCount,
                  'This Month' => filterResult.thisMonthCount,
                  _ => allCount,
                },
              ),
              _buildPeriodChips(
                allCount: allCount,
                todayCount: filterResult.todayCount,
                thisWeekCount: filterResult.thisWeekCount,
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
                          final expense = filteredDocs[index].data() as Expenses;
                          final expenseID = filteredDocs[index].id;
                          return _buildExpenseCard(expenseID: expenseID, expense: expense);
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
