import 'package:flutter/material.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/views/pages/sidebar/transactionlist_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class ExpansionPage extends StatefulWidget {
  const ExpansionPage({super.key});

  @override
  State<ExpansionPage> createState() => _ExpansionPageState();
}

class _ExpansionPageState extends State<ExpansionPage> {
  static const int monthlyTarget = 8;

  List<Hapistore> storesThisMonth = [];
  List<Hapistore> storesPastThreeMonths = [];
  int totalExpansionThisMonth = 0;
  int totalExpansionPastThreeMonths = 0;
  bool isLoading = true;
  Object? loadError;

  int _selectedPeriod = 0; // 0 = This Month, 1 = Past 3 Months
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

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

  Future<void> prefetchData() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });

    try {
      final listHapiStores = await HapiStoreService.getListHapiStoresOpenedWithinPastThreeMonths();
      final listHapiStoresThisMonth = await HapiStoreService.getListHapiStoresWithOpeningDateInCurrentMonth();
      if (!mounted) return;

      setState(() {
        storesThisMonth = listHapiStoresThisMonth..sort(_sortByOpeningDate);
        storesPastThreeMonths = listHapiStores..sort(_sortByOpeningDate);
        totalExpansionPastThreeMonths = listHapiStores.length;
        totalExpansionThisMonth = listHapiStoresThisMonth.length;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        loadError = error;
      });
    }
  }

  int _sortByOpeningDate(Hapistore first, Hapistore second) {
    final firstDate = first.openingDate?.toDate();
    final secondDate = second.openingDate?.toDate();
    if (firstDate == null && secondDate == null) return first.storeName.compareTo(second.storeName);
    if (firstDate == null) return 1;
    if (secondDate == null) return -1;
    // Newest opening date first
    return secondDate.compareTo(firstDate);
  }

  List<Hapistore> get _currentStoreList {
    final list = _selectedPeriod == 0 ? storesThisMonth : storesPastThreeMonths;
    if (_searchQuery.trim().isEmpty) return list;
    final query = _searchQuery.trim().toLowerCase();
    return list.where((s) {
      final nameMatches = s.storeName.toLowerCase().contains(query);
      final addressMatches = s.storeAddress.toLowerCase().contains(query);
      return nameMatches || addressMatches;
    }).toList();
  }

  Widget _buildProgressSummary() {
    final colorScheme = Theme.of(context).colorScheme;
    final currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
    final progress = (totalExpansionThisMonth / monthlyTarget).clamp(0.0, 1.0).toDouble();
    final targetReached = totalExpansionThisMonth >= monthlyTarget;
    final surplus = totalExpansionThisMonth - monthlyTarget;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  targetReached ? Icons.celebration_outlined : Icons.store_mall_directory_outlined,
                  color: targetReached ? Colors.green : colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentMonth,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.primary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      targetReached
                          ? (surplus > 0 ? '$totalExpansionThisMonth stores (+$surplus over target!)' : 'Target reached! 🎉')
                          : '$totalExpansionThisMonth of $monthlyTarget stores',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Monthly target: $monthlyTarget stores',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (targetReached ? Colors.green : colorScheme.primary).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(progress * 100).round()}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: targetReached ? Colors.green : colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
              color: targetReached ? Colors.green : colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required IconData icon, required List<Widget> children}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, size: 19, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, IconData icon, {Color? valueColor}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor ?? colorScheme.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreSection() {
    final colorScheme = Theme.of(context).colorScheme;
    final stores = _currentStoreList;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Segmented Period Toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(Icons.store_outlined, size: 19, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'New Stores (${stores.length})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                segments: [
                  ButtonSegment<int>(
                    value: 0,
                    label: Text('This Month ($totalExpansionThisMonth)', style: const TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    label: Text('Past 3 Months ($totalExpansionPastThreeMonths)', style: const TextStyle(fontSize: 12)),
                  ),
                ],
                selected: {_selectedPeriod},
                onSelectionChanged: (val) {
                  setState(() => _selectedPeriod = val.first);
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by store name or address...',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          if (stores.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  _searchQuery.isNotEmpty
                      ? 'No stores match "$_searchQuery"'
                      : (_selectedPeriod == 0 ? 'No stores opened this month' : 'No stores opened in the past 3 months'),
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: stores.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) {
                final store = stores[index];
                return _buildStoreRow(store);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStoreRow(Hapistore store) {
    final colorScheme = Theme.of(context).colorScheme;
    final openingDate = store.openingDate?.toDate();
    final formattedDate = openingDate == null
        ? 'Opening date unavailable'
        : DateFormat('MMM d, yyyy').format(openingDate);

    return InkWell(
      onTap: () => Helperfunctions.navigateTo(context, TransactionListPage(storeName: store.storeName)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
              child: Icon(Icons.storefront_outlined, size: 18, color: colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    store.storeName.isEmpty ? 'Unnamed store' : store.storeName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 12, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        formattedDate,
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                      if (store.pjpSchedule != null && store.pjpSchedule!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text('•', style: TextStyle(color: colorScheme.outline, fontSize: 12)),
                        const SizedBox(width: 8),
                        Text(
                          store.pjpSchedule!,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colorScheme.primary),
                        ),
                      ],
                    ],
                  ),
                  if (store.storeAddress.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      store.storeAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: colorScheme.outline),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        Icon(Icons.cloud_off_outlined, size: 48, color: Theme.of(context).colorScheme.error),
        const SizedBox(height: 12),
        const Center(child: Text('Could not load expansion data', textAlign: TextAlign.center)),
        const SizedBox(height: 8),
        Center(
          child: FilledButton.tonalIcon(
            onPressed: prefetchData,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppbar(
        title: 'Expansion',
        subtitle: 'New store acquisition & growth',
      ),
      body: RefreshIndicator(
        onRefresh: prefetchData,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : loadError != null
                ? _buildErrorState()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      _buildProgressSummary(),
                      const SizedBox(height: 16),
                      _buildSection(
                        title: 'Expansion Overview',
                        icon: Icons.analytics_outlined,
                        children: [
                          _buildMetricRow('Opened this month', '$totalExpansionThisMonth stores', Icons.storefront_outlined),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          _buildMetricRow(
                            'Remaining to target',
                            '${(monthlyTarget - totalExpansionThisMonth).clamp(0, monthlyTarget)} stores',
                            Icons.flag_outlined,
                            valueColor: totalExpansionThisMonth >= monthlyTarget ? Colors.green : null,
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          _buildMetricRow('Opened in past 3 months', '$totalExpansionPastThreeMonths stores', Icons.date_range_outlined),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          _buildMetricRow(
                            'Monthly average',
                            '${(totalExpansionPastThreeMonths / 3).toStringAsFixed(1)} stores/mo',
                            Icons.trending_up_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildStoreSection(),
                    ],
                  ),
      ),
    );
  }
}
