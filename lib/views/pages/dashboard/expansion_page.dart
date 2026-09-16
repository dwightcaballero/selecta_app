import 'package:flutter/material.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

class ExpansionPage extends StatefulWidget {
  const ExpansionPage({super.key});

  @override
  State<ExpansionPage> createState() => _ExpansionPageState();
}

class _ExpansionPageState extends State<ExpansionPage> {
  static const int monthlyTarget = 8;

  List<Hapistore> storesThisMonth = [];
  int totalExpansionThisMonth = 0;
  int totalExpansionPastThreeMonths = 0;
  bool isLoading = true;
  Object? loadError;

  @override
  void initState() {
    super.initState();
    prefetchData();
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
    return firstDate.compareTo(secondDate);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppbar(title: 'Expansion', subtitle: 'Store growth performance'),
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
                      _buildMetricRow('Opened this month', '$totalExpansionThisMonth', Icons.storefront_outlined),
                      _buildMetricRow(
                        'Remaining to target',
                        '${(monthlyTarget - totalExpansionThisMonth).clamp(0, monthlyTarget)}',
                        Icons.flag_outlined,
                        valueColor: totalExpansionThisMonth >= monthlyTarget ? Theme.of(context).colorScheme.primary : null,
                      ),
                      _buildMetricRow('Opened in past 3 months', '$totalExpansionPastThreeMonths', Icons.date_range_outlined),
                      _buildMetricRow('Monthly average', (totalExpansionPastThreeMonths / 3).toStringAsFixed(1), Icons.trending_up_outlined),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildStoreSection(),
                ],
              ),
      ),
    );
  }

  Widget _buildProgressSummary() {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = (totalExpansionThisMonth / monthlyTarget).clamp(0.0, 1.0).toDouble();
    final targetReached = totalExpansionThisMonth >= monthlyTarget;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(targetReached ? Icons.celebration_outlined : Icons.store_mall_directory_outlined, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('This month', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(
                      targetReached ? 'Target reached' : '$totalExpansionThisMonth of $monthlyTarget stores',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: colorScheme.surface, color: colorScheme.primary),
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Column(
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
          ...children,
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, IconData icon, {Color? valueColor}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
    return _buildSection(
      title: 'Stores Opened This Month',
      icon: Icons.store_outlined,
      children: storesThisMonth.isEmpty
          ? [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Align(alignment: Alignment.centerLeft, child: Text('No stores opened this month')),
              ),
            ]
          : storesThisMonth.map(_buildStoreRow).toList(),
    );
  }

  Widget _buildStoreRow(Hapistore store) {
    final colorScheme = Theme.of(context).colorScheme;
    final openingDate = store.openingDate?.toDate();
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
        child: Icon(Icons.storefront_outlined, size: 18, color: colorScheme.primary),
      ),
      title: Text(store.storeName.isEmpty ? 'Unnamed store' : store.storeName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(
        openingDate == null ? 'Opening date unavailable' : MaterialLocalizations.of(context).formatMediumDate(openingDate),
        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
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
          child: TextButton.icon(onPressed: prefetchData, icon: const Icon(Icons.refresh), label: const Text('Try again')),
        ),
      ],
    );
  }
}
