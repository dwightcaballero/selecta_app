import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/views/pages/sidebar/hapistore_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

class HapiStoreListPage extends StatefulWidget {
  const HapiStoreListPage({super.key});

  @override
  State<HapiStoreListPage> createState() => _HapiStoreListPageState();
}

class _HapiStoreListPageState extends State<HapiStoreListPage> {
  final HapiStoreService db = HapiStoreService();

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

  void prefetchData() async {
    _isDealer = await KVariables.getIsDealer();
    if (mounted) setState(() {});
  }

  void _onSearchChanged(String text) {
    setState(() {
      _searchQuery = text.trim().toLowerCase();
    });
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedPjpDay = 'All';
    });
  }

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

  Widget _buildStoreListView() {
    return StreamBuilder<QuerySnapshot>(
      stream: db.getListHapiStoresAsStream(),
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

        // In-memory multi-field filtering
        final filteredDocs = allDocs.where((doc) {
          final hapistore = doc.data() is Hapistore ? doc.data() as Hapistore : Hapistore.fromJson(doc.data() as Map<String, Object?>);

          // 1. PJP filter
          if (_selectedPjpDay != 'All') {
            if (_selectedPjpDay == 'Unscheduled') {
              if (hapistore.pjpSchedule != null && hapistore.pjpSchedule!.trim().isNotEmpty) {
                return false;
              }
            } else {
              if (hapistore.pjpSchedule?.trim().toLowerCase() != _selectedPjpDay.toLowerCase()) {
                return false;
              }
            }
          }

          // 2. Multi-field search filter (name, address, contact)
          if (_searchQuery.isNotEmpty) {
            final nameMatch = hapistore.storeName.toLowerCase().contains(_searchQuery);
            final addressMatch = hapistore.storeAddress.toLowerCase().contains(_searchQuery);
            final contactMatch = hapistore.storeContact.contains(_searchQuery);
            if (!nameMatch && !addressMatch && !contactMatch) {
              return false;
            }
          }

          return true;
        }).toList();

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
        onTap: _isDealer
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HapiStorePage(hapiStoreID: hapistoreID, hapistore: hapistore),
                  ),
                );
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.storefront_outlined, color: colorScheme.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hapistore.storeName,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        // Badges Row: PJP Day + GPS status
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            // PJP Badge
                            if (hasPjp)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: isDark ? 0.25 : 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.calendar_month_outlined, size: 12, color: isDark ? Colors.lightBlueAccent : Colors.blue.shade700),
                                    const SizedBox(width: 4),
                                    Text(
                                      hapistore.pjpSequence != null
                                          ? '${hapistore.pjpSchedule} • #${hapistore.pjpSequence! + 1}'
                                          : hapistore.pjpSchedule!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.lightBlueAccent : Colors.blue.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  'No PJP',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),

                            // GPS Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: hasGps
                                    ? Colors.green.withValues(alpha: isDark ? 0.25 : 0.1)
                                    : Colors.amber.withValues(alpha: isDark ? 0.25 : 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: (hasGps ? Colors.green : Colors.amber).withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    hasGps ? Icons.location_on_rounded : Icons.location_off_outlined,
                                    size: 12,
                                    color: hasGps
                                        ? (isDark ? Colors.greenAccent : Colors.green.shade700)
                                        : (isDark ? Colors.amberAccent : Colors.amber.shade900),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    hasGps ? 'GPS Pin' : 'No GPS',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: hasGps
                                          ? (isDark ? Colors.greenAccent : Colors.green.shade800)
                                          : (isDark ? Colors.amberAccent : Colors.amber.shade900),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_isDealer) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right, size: 20, color: colorScheme.onSurfaceVariant),
                  ],
                ],
              ),

              // Contact & Address Details
              if (hapistore.storeContact.isNotEmpty || hapistore.storeAddress.isNotEmpty) ...[
                const SizedBox(height: 10),
                Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
                const SizedBox(height: 8),
              ],

              // Contact Row with tap to copy
              if (hapistore.storeContact.isNotEmpty)
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _copyToClipboard(hapistore.storeContact, 'contact number'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(Icons.phone_outlined, size: 14, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          hapistore.storeContact,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.copy_rounded, size: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                      ],
                    ),
                  ),
                ),

              // Address Row
              if (hapistore.storeAddress.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.location_on_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        hapistore.storeAddress,
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
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

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.storefront_outlined, color: colorScheme.primary, size: 48),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Hapi Stores Yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Add stores to start managing deliveries, PJP routes, orders, and settlements.',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSearchResultsState() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'No stores found',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No results matching "$_searchQuery"'
                  : 'No stores scheduled for $_selectedPjpDay',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reset Filters'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: colorScheme.error, size: 40),
          const SizedBox(height: 8),
          const Text('Unable to load stores list', style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppbar(
        title: 'Hapi Stores',
        subtitle: 'Store Directory & Contacts',
      ),
      floatingActionButton: _isDealer
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HapiStorePage(hapiStoreID: '', hapistore: Hapistore.empty()),
                  ),
                );
              },
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Store',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
            )
          : null,
      body: Column(
        children: [
          // 1. Search Bar
          _buildSearchBar(),

          // 2. PJP Schedule Filter Chips
          _buildPjpFilterChips(),

          const SizedBox(height: 4),

          // 3. Stores List
          Expanded(child: _buildStoreListView()),
        ],
      ),
    );
  }
}
