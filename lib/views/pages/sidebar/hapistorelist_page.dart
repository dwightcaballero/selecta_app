import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/controllers/hapistore_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/views/pages/sidebar/hapistore_page.dart';
import 'package:selecta_ops/views/pages/sidebar/store_profile_page.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';

/// Presentation page for displaying, filtering, and navigating Hapi Stores.
class HapiStoreListPage extends StatefulWidget {
  const HapiStoreListPage({super.key});

  @override
  State<HapiStoreListPage> createState() => _HapiStoreListPageState();
}

class _HapiStoreListPageState extends State<HapiStoreListPage> {
  // Controller managing business logic and streams
  final HapiStoreController _controller = HapiStoreController();

  bool _isDealer = true;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  String _selectedPjpDay = 'All';

  static const List<Map<String, String>> _pjpFilterDays = [
    {'key': 'All', 'label': 'All'},
    {'key': PjpScheduleDays.monday, 'label': 'Mon'},
    {'key': PjpScheduleDays.tuesday, 'label': 'Tue'},
    {'key': PjpScheduleDays.wednesday, 'label': 'Wed'},
    {'key': PjpScheduleDays.thursday, 'label': 'Thu'},
    {'key': PjpScheduleDays.friday, 'label': 'Fri'},
    {'key': PjpScheduleDays.saturday, 'label': 'Sat'},
    {'key': PjpScheduleDays.sunday, 'label': 'Sun'},
    {'key': 'Unscheduled', 'label': 'No PJP'},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  /// Initial load of user role state
  void prefetchData() async {
    final isDealer = await _controller.checkIsDealer();
    if (mounted) {
      setState(() {
        _isDealer = isDealer;
      });
    }
  }

  /// Handles search query input changes
  void _onSearchChanged(String text) {
    setState(() {
      _searchQuery = text.trim().toLowerCase();
    });
  }

  /// Resets all filter and search controls
  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedPjpDay = 'All';
    });
  }

  /// Helper to copy contact or details to clipboard
  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Copied $label to clipboard'),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Builds the top search bar
  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Search by store name, address, or contact...',
          hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          prefixIcon: Icon(Icons.search, size: 20, color: colorScheme.primary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  /// Builds the horizontal PJP filter day chips
  Widget _buildPjpFilterChips() {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _pjpFilterDays.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _pjpFilterDays[index];
          final isSelected = _selectedPjpDay == filter['key'];

          return FilterChip(
            selected: isSelected,
            label: Text(
              filter['label']!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
              ),
            ),
            selectedColor: colorScheme.primary,
            backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            checkmarkColor: colorScheme.onPrimary,
            showCheckmark: false,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            onSelected: (selected) {
              setState(() {
                _selectedPjpDay = selected ? filter['key']! : 'All';
              });
            },
          );
        },
      ),
    );
  }

  /// Builds the summary header showing count statistics
  Widget _buildSummaryHeader(int filteredCount, int totalCount) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFiltered = _searchQuery.isNotEmpty || _selectedPjpDay != 'All';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            isFiltered ? 'Showing $filteredCount of $totalCount stores' : '$totalCount stores registered',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (isFiltered)
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: _resetFilters,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_alt_off_outlined, size: 14, color: colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Reset',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Builds the real-time stream list of stores
  Widget _buildStoreListView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _controller.getHapiStoresStream(),
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

        // Delegate filtering logic to controller
        final filteredDocs = _controller.filterStores(
          docs: allDocs,
          selectedPjpDay: _selectedPjpDay,
          searchQuery: _searchQuery,
        );

        return Column(
          children: [
            _buildSummaryHeader(filteredDocs.length, allDocs.length),
            Expanded(
              child: filteredDocs.isEmpty
                  ? _buildNoSearchResultsState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 80),
                      itemCount: filteredDocs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final rawData = filteredDocs[index].data();
                        final hapistore = rawData is Hapistore ? rawData : Hapistore.fromJson(rawData as Map<String, Object?>);
                        final hapistoreID = filteredDocs[index].id;
                        return _buildStoreCard(hapistoreID: hapistoreID, hapistore: hapistore);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  /// Store item card with details, PJP chip, and action buttons
  Widget _buildStoreCard({required String hapistoreID, required Hapistore hapistore}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasGps = hapistore.latitude != null && hapistore.longitude != null;
    final hasPjp = hapistore.pjpSchedule != null && hapistore.pjpSchedule!.trim().isNotEmpty;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StoreProfilePage(hapiStoreID: hapistoreID, hapistore: hapistore),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Store Header: Name + Status chips
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.storefront_outlined, size: 20, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hapistore.storeName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (hasPjp) ...[
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.blue.shade900.withValues(alpha: 0.4) : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isDark ? Colors.blue.shade700 : Colors.blue.shade200,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.calendar_today_outlined, size: 10, color: isDark ? Colors.blue.shade300 : Colors.blue.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  hapistore.pjpSchedule!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (hasGps)
                    Tooltip(
                      message: 'GPS Coordinates set',
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.location_on, size: 16, color: Colors.green),
                      ),
                    ),
                  if (_isDealer)
                    Icon(Icons.chevron_right, size: 20, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                ],
              ),
              const SizedBox(height: 10),

              // Address Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.place_outlined, size: 15, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      hapistore.storeAddress,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Contact Number Row with quick copy
              Row(
                children: [
                  Icon(Icons.phone_outlined, size: 15, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    hapistore.storeContact,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _copyToClipboard(hapistore.storeContact, 'contact number'),
                    child: Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: Icon(Icons.copy_outlined, size: 13, color: colorScheme.primary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Empty state when no stores exist in Firestore
  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text('No Hapi Stores yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
          const SizedBox(height: 6),
          Text('Tap the + button below to add your first store.', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  /// State when search/filter returns zero results
  Widget _buildNoSearchResultsState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_outlined, size: 52, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 14),
            const Text(
              'No matching stores',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'No stores matched your current search or day filter.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
              label: const Text('Clear Filters'),
            ),
          ],
        ),
      ),
    );
  }

  /// Error state on stream error
  Widget _buildErrorState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: colorScheme.error),
          const SizedBox(height: 12),
          Text('Failed to load stores', style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppbar(
        title: 'Hapi Stores',
        subtitle: 'Store Masterlist & Schedules',
      ),
      floatingActionButton: _isDealer
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HapiStorePage(
                      hapiStoreID: '',
                      hapistore: Hapistore.empty(),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Store'),
            )
          : null,
      body: Column(
        children: [
          _buildSearchBar(),
          _buildPjpFilterChips(),
          const SizedBox(height: 4),
          Expanded(child: _buildStoreListView()),
        ],
      ),
    );
  }
}
