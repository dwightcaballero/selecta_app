import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/configuration.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/configuration_service.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/views/pages/sidebar/configuration_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

enum StoreSortOption {
  nameAsc('Name (A - Z)'),
  nameDesc('Name (Z - A)'),
  openingDateDesc('Opening Date (Newest)'),
  openingDateAsc('Opening Date (Oldest)'),
  surveyDateDesc('Survey Date (Latest)');

  final String label;
  const StoreSortOption(this.label);
}

class MerchBlitzPage extends StatefulWidget {
  const MerchBlitzPage({super.key});

  @override
  State<MerchBlitzPage> createState() => _MerchBlitzPageState();
}

class _MerchBlitzPageState extends State<MerchBlitzPage> {
  final ConfigurationService _configService = ConfigurationService();
  final HapiStoreService _hapiStoreService = HapiStoreService();

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  StoreSortOption _sortOption = StoreSortOption.nameAsc;
  int _selectedTabIndex = 0; // 0 = Not Surveyed, 1 = Surveyed
  bool _isDealer = false;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
  }

  Future<void> _checkUserRole() async {
    final isDealer = await KVariables.getIsDealer();
    if (mounted) {
      setState(() => _isDealer = isDealer);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime _startOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day, 0, 0, 0);
  DateTime _endOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day, 23, 59, 59, 999);

  bool _isTodayInBlitz(DateTime start, DateTime end) {
    final now = DateTime.now();
    final s = _startOfDay(start);
    final e = _endOfDay(end);
    return !now.isBefore(s) && !now.isAfter(e);
  }

  bool _isSurveyed(Hapistore store, DateTime start, DateTime end) {
    if (store.lastMerchBlitzDate == null) return false;
    final visitDate = store.lastMerchBlitzDate!.toDate();
    final s = _startOfDay(start);
    final e = _endOfDay(end);
    return !visitDate.isBefore(s) && !visitDate.isAfter(e);
  }

  Future<void> _confirmMarkSurveyed(String storeId, Hapistore store) async {
    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Complete Survey',
      message: 'Are you sure "${store.storeName}" has finished the Merch Blitz survey?',
      confirmText: 'Mark as Surveyed',
      icon: Icons.assignment_turned_in_rounded,
    );

    if (confirmed) {
      try {
        await _hapiStoreService.updateLastMerchBlitzDate(storeId, Timestamp.now());
        if (mounted) {
          ShowMessage.success(context, '"${store.storeName}" marked as surveyed!');
        }
      } catch (e) {
        if (mounted) {
          ShowMessage.error(context, 'Failed to update store: $e');
        }
      }
    }
  }

  Future<void> _confirmResetSurvey(String storeId, Hapistore store) async {
    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Reset Survey Status',
      message: 'Do you want to reset "${store.storeName}" back to Not Surveyed?',
      confirmText: 'Reset',
      isDestructive: true,
      icon: Icons.undo_rounded,
    );

    if (confirmed) {
      try {
        await _hapiStoreService.updateLastMerchBlitzDate(storeId, null);
        if (mounted) {
          ShowMessage.success(context, 'Survey status reset for "${store.storeName}".');
        }
      } catch (e) {
        if (mounted) {
          ShowMessage.error(context, 'Failed to update store: $e');
        }
      }
    }
  }

  Widget _buildScheduleCard({required DateTime startDate, required DateTime endDate, required bool isActive}) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFmt = DateFormat('EEE, d MMM yyyy');

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isActive ? const Color(0xFF0284C7).withValues(alpha: 0.35) : colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isActive ? const Color(0xFF0284C7) : colorScheme.onSurfaceVariant).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.campaign_outlined,
                    size: 20,
                    color: isActive ? const Color(0xFF0284C7) : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Merch Blitz Schedule',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.green.withValues(alpha: 0.12) : Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isActive ? Colors.green.withValues(alpha: 0.4) : Colors.orange.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive ? Colors.green : Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isActive ? 'Active Today' : 'Inactive',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isActive ? Colors.green.shade700 : Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isDealer) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ConfigurationPage()),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.edit_calendar_rounded, size: 16, color: colorScheme.primary),
                    ),
                  ),
                ],
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildDateInfoTile(
                    label: 'Start Date',
                    value: dateFmt.format(startDate),
                    icon: Icons.calendar_today_outlined,
                  ),
                ),
                Container(
                  height: 36,
                  width: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                ),
                Expanded(
                  child: _buildDateInfoTile(
                    label: 'End Date',
                    value: dateFmt.format(endDate),
                    icon: Icons.event_available_outlined,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateInfoTile({required String label, required String value, required IconData icon}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoActiveBlitzState({required DateTime startDate, required DateTime endDate}) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFmt = DateFormat('MMM d, yyyy');

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.event_busy_rounded, size: 48, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Active Merch Blitz Task for Today',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'The Merch Blitz campaign is scheduled between ${dateFmt.format(startDate)} and ${dateFmt.format(endDate)}. Store surveys will only be accessible while the campaign is actively underway.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant, height: 1.4),
            ),
            if (_isDealer) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ConfigurationPage()),
                  );
                },
                icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                label: const Text('Update Merch Blitz Schedule', style: TextStyle(fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndSortBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search stores...',
                hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                filled: true,
                fillColor: colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<StoreSortOption>(
            initialValue: _sortOption,
            tooltip: 'Sort Stores',
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (option) => setState(() => _sortOption = option),
            itemBuilder: (context) => StoreSortOption.values.map((option) {
              return PopupMenuItem<StoreSortOption>(
                value: option,
                child: Row(
                  children: [
                    Icon(
                      _sortOption == option ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      size: 18,
                      color: _sortOption == option ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Text(option.label, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              );
            }).toList(),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: Icon(Icons.sort_rounded, color: colorScheme.primary, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreCard({
    required String storeId,
    required Hapistore store,
    required bool isSurveyed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSurveyed
              ? Colors.green.withValues(alpha: 0.3)
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (!isSurveyed) {
            _confirmMarkSurveyed(storeId, store);
          } else {
            _confirmResetSurvey(storeId, store);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: (isSurveyed ? Colors.green : const Color(0xFF0284C7)).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isSurveyed ? Icons.check_circle_outline_rounded : Icons.storefront_outlined,
                      color: isSurveyed ? Colors.green : const Color(0xFF0284C7),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.storeName,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (store.storeAddress.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  store.storeAddress,
                                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
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
                  const SizedBox(width: 8),
                  if (!isSurveyed)
                    FilledButton.tonalIcon(
                      onPressed: () => _confirmMarkSurveyed(storeId, store),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('Survey', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.done_all_rounded, size: 15, color: Colors.green),
                          SizedBox(width: 4),
                          Text(
                            'Surveyed',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (isSurveyed && store.lastMerchBlitzDate != null) ...[
                const Divider(height: 18),
                Row(
                  children: [
                    Icon(Icons.history_toggle_off_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      'Surveyed on: ${DateFormat('EEE, d MMM yyyy • h:mm a').format(store.lastMerchBlitzDate!.toDate())}',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(50, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _confirmResetSurvey(storeId, store),
                      child: const Text('Undo', style: TextStyle(fontSize: 11, color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<QueryDocumentSnapshot> _filterAndSortStores({
    required List<QueryDocumentSnapshot> docs,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final filtered = docs.where((doc) {
      final raw = doc.data();
      final store = raw is Hapistore ? raw : Hapistore.fromJson(raw as Map<String, Object?>);

      final isStoreSurveyed = _isSurveyed(store, startDate, endDate);
      if (_selectedTabIndex == 0 && isStoreSurveyed) return false;
      if (_selectedTabIndex == 1 && !isStoreSurveyed) return false;

      if (_searchQuery.isNotEmpty) {
        final name = store.storeName.toLowerCase();
        final address = store.storeAddress.toLowerCase();
        final contact = store.storeContact.toLowerCase();
        if (!name.contains(_searchQuery) && !address.contains(_searchQuery) && !contact.contains(_searchQuery)) {
          return false;
        }
      }

      return true;
    }).toList();

    filtered.sort((a, b) {
      final rawA = a.data();
      final rawB = b.data();
      final storeA = rawA is Hapistore ? rawA : Hapistore.fromJson(rawA as Map<String, Object?>);
      final storeB = rawB is Hapistore ? rawB : Hapistore.fromJson(rawB as Map<String, Object?>);

      switch (_sortOption) {
        case StoreSortOption.nameAsc:
          return storeA.storeName.toLowerCase().compareTo(storeB.storeName.toLowerCase());
        case StoreSortOption.nameDesc:
          return storeB.storeName.toLowerCase().compareTo(storeA.storeName.toLowerCase());
        case StoreSortOption.openingDateDesc:
          final dateA = storeA.openingDate?.toDate() ?? DateTime(1970);
          final dateB = storeB.openingDate?.toDate() ?? DateTime(1970);
          return dateB.compareTo(dateA);
        case StoreSortOption.openingDateAsc:
          final dateA = storeA.openingDate?.toDate() ?? DateTime(2099);
          final dateB = storeB.openingDate?.toDate() ?? DateTime(2099);
          return dateA.compareTo(dateB);
        case StoreSortOption.surveyDateDesc:
          final dateA = storeA.lastMerchBlitzDate?.toDate() ?? DateTime(1970);
          final dateB = storeB.lastMerchBlitzDate?.toDate() ?? DateTime(1970);
          return dateB.compareTo(dateA);
      }
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Configuration?>(
      stream: _configService.getConfigurationStream(),
      builder: (context, configSnapshot) {
        final config = configSnapshot.data ?? Configuration.empty();
        final startDate = config.merchBlitzStartDate.toDate();
        final endDate = config.merchBlitzEndDate.toDate();
        final isActiveToday = _isTodayInBlitz(startDate, endDate);

        return StreamBuilder<QuerySnapshot>(
          stream: _hapiStoreService.getListHapiStoresAsStream(),
          builder: (context, storesSnapshot) {
            final allDocs = storesSnapshot.data?.docs ?? [];

            int notSurveyedCount = 0;
            int surveyedCount = 0;
            for (final doc in allDocs) {
              final raw = doc.data();
              final store = raw is Hapistore ? raw : Hapistore.fromJson(raw as Map<String, Object?>);
              if (_isSurveyed(store, startDate, endDate)) {
                surveyedCount++;
              } else {
                notSurveyedCount++;
              }
            }

            final visibleDocs = _filterAndSortStores(
              docs: allDocs,
              startDate: startDate,
              endDate: endDate,
            );

            return Scaffold(
              appBar: const CustomAppbar(
                title: 'Merch Blitz',
                subtitle: 'Store Merchandising Survey',
              ),
              body: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Read-only Start Date & End Date Schedule Card
                    _buildScheduleCard(startDate: startDate, endDate: endDate, isActive: isActiveToday),
                    const SizedBox(height: 8),

                    if (!isActiveToday)
                      Expanded(
                        child: _buildNoActiveBlitzState(startDate: startDate, endDate: endDate),
                      )
                    else ...[
                      // Search and Sort controls
                      _buildSearchAndSortBar(),

                      // Active list status / summary count
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                        child: Row(
                          children: [
                            Text(
                              _selectedTabIndex == 0 ? 'Not Surveyed Stores' : 'Surveyed Stores',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (_selectedTabIndex == 0 ? Colors.orange : Colors.green).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${visibleDocs.length} of ${_selectedTabIndex == 0 ? notSurveyedCount : surveyedCount}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _selectedTabIndex == 0 ? Colors.orange.shade800 : Colors.green.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),

                      // List of Stores
                      Expanded(
                        child: storesSnapshot.connectionState == ConnectionState.waiting
                            ? const Center(child: CircularProgressIndicator())
                            : visibleDocs.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(32.0),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _searchQuery.isNotEmpty
                                                ? Icons.search_off_rounded
                                                : (_selectedTabIndex == 0 ? Icons.check_circle_outline_rounded : Icons.pending_actions_rounded),
                                            size: 44,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            _searchQuery.isNotEmpty
                                                ? 'No stores match "$_searchQuery"'
                                                : (_selectedTabIndex == 0
                                                    ? 'All stores have been surveyed!'
                                                    : 'No stores surveyed yet.'),
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.only(top: 4, bottom: 20),
                                    itemCount: visibleDocs.length,
                                    itemBuilder: (context, index) {
                                      final doc = visibleDocs[index];
                                      final raw = doc.data();
                                      final store = raw is Hapistore ? raw : Hapistore.fromJson(raw as Map<String, Object?>);
                                      return _buildStoreCard(
                                        storeId: doc.id,
                                        store: store,
                                        isSurveyed: _selectedTabIndex == 1,
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ],
                ),
              ),
              bottomNavigationBar: isActiveToday
                  ? NavigationBar(
                      selectedIndex: _selectedTabIndex,
                      onDestinationSelected: (index) {
                        setState(() => _selectedTabIndex = index);
                      },
                      destinations: [
                        NavigationDestination(
                          icon: Badge(
                            isLabelVisible: notSurveyedCount > 0,
                            label: Text('$notSurveyedCount'),
                            child: const Icon(Icons.assignment_late_outlined),
                          ),
                          selectedIcon: Badge(
                            isLabelVisible: notSurveyedCount > 0,
                            label: Text('$notSurveyedCount'),
                            child: const Icon(Icons.assignment_late_rounded),
                          ),
                          label: 'Not Surveyed',
                        ),
                        NavigationDestination(
                          icon: Badge(
                            isLabelVisible: surveyedCount > 0,
                            label: Text('$surveyedCount'),
                            backgroundColor: Colors.green,
                            child: const Icon(Icons.task_alt_outlined),
                          ),
                          selectedIcon: Badge(
                            isLabelVisible: surveyedCount > 0,
                            label: Text('$surveyedCount'),
                            backgroundColor: Colors.green,
                            child: const Icon(Icons.task_alt_rounded),
                          ),
                          label: 'Surveyed',
                        ),
                      ],
                    )
                  : null,
            );
          },
        );
      },
    );
  }
}
