import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/hapistore_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/responsive.dart';
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
  String? _selectedStoreId;
  Hapistore? _selectedStore;

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
    final isTabletLandscape = ScreenSize.isTabletLandscape(context);

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

        if (filteredDocs.isEmpty) {
          return _buildNoSearchResultsState();
        }

        if (isTabletLandscape) {
          final docExists = _selectedStoreId != null && filteredDocs.any((d) => d.id == _selectedStoreId);
          if (!docExists) {
            final firstDoc = filteredDocs.first;
            final raw = firstDoc.data();
            final firstStore = raw is Hapistore ? raw : Hapistore.fromJson(raw as Map<String, Object?>);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _selectedStoreId != firstDoc.id) {
                setState(() {
                  _selectedStoreId = firstDoc.id;
                  _selectedStore = firstStore;
                });
              }
            });
          }
        }

        return Column(
          children: [
            _buildSummaryHeader(filteredDocs.length, allDocs.length),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 80),
                itemCount: filteredDocs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final rawData = filteredDocs[index].data();
                  final hapistore = rawData is Hapistore ? rawData : Hapistore.fromJson(rawData as Map<String, Object?>);
                  final hapistoreID = filteredDocs[index].id;
                  final isSelected = isTabletLandscape && _selectedStoreId == hapistoreID;
                  return _buildStoreCard(
                    hapistoreID: hapistoreID,
                    hapistore: hapistore,
                    isSelected: isSelected,
                    onTap: isTabletLandscape
                        ? () {
                            setState(() {
                              _selectedStoreId = hapistoreID;
                              _selectedStore = hapistore;
                            });
                          }
                        : null,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// Store item card with details, PJP chip, and action buttons
  Widget _buildStoreCard({
    required String hapistoreID,
    required Hapistore hapistore,
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasGps = hapistore.latitude != null && hapistore.longitude != null;
    final hasPjp = hapistore.pjpSchedule != null && hapistore.pjpSchedule!.trim().isNotEmpty;

    return Card(
      elevation: 0,
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: isDark ? 0.25 : 0.12)
          : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isSelected
            ? BorderSide(color: colorScheme.primary, width: 2)
            : BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap ??
            () {
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
                  if (isSelected) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.check_circle, size: 20, color: colorScheme.primary),
                  ] else if (_isDealer) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 20, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                  ],
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

  /// Tablet landscape store profile & 360 preview card
  Widget _buildTabletStoreProfilePreview(
    ColorScheme colorScheme,
    Hapistore? store,
    String? storeId,
  ) {
    if (store == null || storeId == null) {
      return Card(
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(0, 8, 16, 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_outlined, size: 56, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 14),
              Text(
                'Select a store to view 360° details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                'View address, contacts, PJP schedules, and operations.',
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
              ),
            ],
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasGps = store.latitude != null && store.longitude != null;
    final hasPjp = store.pjpSchedule != null && store.pjpSchedule!.trim().isNotEmpty;

    String? formattedOpening;
    if (store.openingDate != null) {
      formattedOpening = DateFormat('MMM d, yyyy').format(store.openingDate!.toDate());
    }

    String? formattedLastVisit;
    if (store.lastPjpVisit != null) {
      formattedLastVisit = DateFormat('MMM d, yyyy • h:mm a').format(store.lastPjpVisit!.toDate());
    }

    String? formattedLastBlitz;
    if (store.lastMerchBlitzDate != null) {
      formattedLastBlitz = DateFormat('MMM d, yyyy').format(store.lastMerchBlitzDate!.toDate());
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(0, 8, 16, 24),
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
            // Store Header Card
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
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.storefront, color: colorScheme.primary, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.storeName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (hasPjp)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.blue.shade900.withValues(alpha: 0.4) : Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: isDark ? Colors.blue.shade700 : Colors.blue.shade200, width: 0.8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.calendar_today_outlined, size: 11, color: isDark ? Colors.blue.shade300 : Colors.blue.shade700),
                                    const SizedBox(width: 4),
                                    Text(
                                      'PJP: ${store.pjpSchedule}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (hasGps)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.green.shade300, width: 0.8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.location_on, size: 11, color: Colors.green),
                                    SizedBox(width: 4),
                                    Text(
                                      'GPS Pinned',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.green),
                                    ),
                                  ],
                                ),
                              ),
                            if (store.merchBlitzStatus != null && store.merchBlitzStatus!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.deepPurple.shade300, width: 0.8),
                                ),
                                child: Text(
                                  store.merchBlitzStatus!,
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.deepPurple.shade700),
                                ),
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

            // Section 1: Store Contact & Location Details
            const Text('Contact & Location', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.place_outlined, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Address', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 2),
                            Text(
                              store.storeAddress.isNotEmpty ? store.storeAddress : 'No address provided',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Icon(Icons.phone_outlined, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Contact Number', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 2),
                            Text(
                              store.storeContact.isNotEmpty ? store.storeContact : 'No contact provided',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                            ),
                          ],
                        ),
                      ),
                      if (store.storeContact.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          tooltip: 'Copy contact',
                          onPressed: () => _copyToClipboard(store.storeContact, 'contact number'),
                        ),
                    ],
                  ),
                  if (hasGps) ...[
                    const Divider(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.my_location, size: 18, color: Colors.teal),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Coordinates', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 2),
                              Text(
                                '${store.latitude!.toStringAsFixed(5)}, ${store.longitude!.toStringAsFixed(5)}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Section 2: Route & Operations Info
            const Text('Operational Profile', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('PJP Schedule', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 2),
                            Text(
                              store.pjpSchedule ?? 'Unscheduled',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: store.pjpSchedule != null ? colorScheme.primary : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (store.pjpSequence != null)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Route Stop #', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 2),
                              Text(
                                '#${store.pjpSequence}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (formattedOpening != null) ...[
                    const Divider(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Opening Date', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 2),
                              Text(formattedOpening, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (formattedLastVisit != null) ...[
                    const Divider(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Last PJP Visit', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 2),
                              Text(formattedLastVisit, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (formattedLastBlitz != null) ...[
                    const Divider(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Last Merch Blitz', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 2),
                              Text(formattedLastBlitz, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                if (_isDealer) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HapiStorePage(
                            hapiStoreID: storeId,
                            hapistore: store,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit Store', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                ],
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
                          builder: (_) => StoreProfilePage(
                            hapiStoreID: storeId,
                            hapistore: store,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text(
                      'View 360° Profile',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
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
    final isTabletLandscape = ScreenSize.isTabletLandscape(context);
    final colorScheme = Theme.of(context).colorScheme;

    final masterListColumn = Column(
      children: [
        _buildSearchBar(),
        _buildPjpFilterChips(),
        const SizedBox(height: 4),
        Expanded(child: _buildStoreListView()),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
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
        body: isTabletLandscape
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: masterListColumn),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: _buildTabletStoreProfilePreview(
                      colorScheme,
                      _selectedStore,
                      _selectedStoreId,
                    ),
                  ),
                ],
              )
            : masterListColumn,
      ),
    );
  }
}
