import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/hapistore_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/responsive.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/views/pages/sidebar/hapistore_page.dart';
import 'package:selecta_ops/views/pages/sidebar/store_profile_page.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:url_launcher/url_launcher.dart';

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

  /// 1-tap phone dialer action
  Future<void> _makePhoneCall(String phoneNumber) async {
    final clean = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    if (clean.isEmpty) {
      if (mounted) ShowMessage.error(context, 'No valid phone number to call.');
      return;
    }
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) ShowMessage.error(context, 'Could not open phone dialer.');
    }
  }

  /// 1-tap SMS messaging action
  Future<void> _sendSms(String phoneNumber) async {
    final clean = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    if (clean.isEmpty) {
      if (mounted) ShowMessage.error(context, 'No valid phone number to message.');
      return;
    }
    final uri = Uri.parse('sms:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) ShowMessage.error(context, 'Could not open messaging app.');
    }
  }

  /// 1-tap Google Maps directions action
  Future<void> _openDirections(Hapistore store) async {
    if (store.latitude != null && store.longitude != null) {
      final lat = store.latitude!;
      final lng = store.longitude!;
      final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    if (store.storeAddress.isNotEmpty) {
      final query = Uri.encodeComponent('${store.storeName}, ${store.storeAddress}');
      final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    if (mounted) {
      ShowMessage.alert(
        context,
        title: 'Location Unavailable',
        message: 'No GPS coordinates or valid address registered for this store.',
        icon: Icons.location_off_outlined,
      );
    }
  }

  /// Builds the top search bar with sleek rounded design
  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2430) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: _onSearchChanged,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: 'Search by store name, address, or contact...',
            hintStyle: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
            ),
            prefixIcon: Icon(Icons.search_rounded, size: 21, color: colorScheme.primary),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                  )
                : null,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }

  /// Builds the horizontal PJP filter day chips with clear active pills
  Widget _buildPjpFilterChips() {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 40,
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
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF334155)),
              ),
            ),
            selectedColor: colorScheme.primary,
            backgroundColor: isDark ? const Color(0xFF1E2430) : Colors.white,
            checkmarkColor: Colors.white,
            showCheckmark: false,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isSelected ? colorScheme.primary : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            elevation: isSelected ? 2 : 0,
            pressElevation: 1,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isFiltered ? 'Showing $filteredCount of $totalCount stores' : '$totalCount stores registered',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          if (isFiltered)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: _resetFilters,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_alt_off_rounded, size: 13, color: colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Clear Filter',
                      style: TextStyle(
                        fontSize: 11.5,
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

  String _getStoreInitials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return 'ST';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
  }

  /// Store item card with details and 1-tap action buttons (Message, Call, Directions)
  Widget _buildStoreCard({
    required String hapistoreID,
    required Hapistore hapistore,
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasGps = hapistore.latitude != null && hapistore.longitude != null;
    final hasUsername = hapistore.username != null && hapistore.username!.trim().isNotEmpty;
    final hasContact = hapistore.storeContact.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: isDark ? 0.3 : 0.15)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.55),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
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
                // Top Row: Avatar + Store Name + Trailing icon
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Brand squircle avatar
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [colorScheme.primary.withValues(alpha: 0.35), colorScheme.primary.withValues(alpha: 0.15)]
                              : [colorScheme.primary.withValues(alpha: 0.18), colorScheme.primary.withValues(alpha: 0.06)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _getStoreInitials(hapistore.storeName),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: colorScheme.primary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Store Title & Optional Plain Username
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hapistore.storeName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (hasUsername) ...[
                            const SizedBox(height: 3),
                            Text(
                              '@${hapistore.username}',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (isSelected)
                      Icon(Icons.check_circle, size: 22, color: colorScheme.primary)
                    else if (_isDealer)
                      Icon(Icons.chevron_right, size: 22, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  ],
                ),
                const SizedBox(height: 12),

                // Divider line
                Divider(
                  height: 1,
                  thickness: 0.6,
                  color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.4),
                ),
                const SizedBox(height: 10),

                // Bottom Row: 1-Tap Action Buttons (Message, Call, Directions)
                Row(
                  children: [
                    // 1-Tap Action: Message
                    if (hasContact)
                      Tooltip(
                        message: 'Send SMS to ${hapistore.storeName}',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _sendSms(hapistore.storeContact),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.blue.shade900.withValues(alpha: 0.3) : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isDark ? Colors.blue.shade700 : Colors.blue.shade200,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.sms_outlined, size: 13, color: isDark ? Colors.blue.shade300 : Colors.blue.shade700),
                                const SizedBox(width: 5),
                                Text(
                                  'Message',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (hasContact) ...[
                      const SizedBox(width: 8),
                      // 1-Tap Action: Call
                      Tooltip(
                        message: 'Call ${hapistore.storeName}',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _makePhoneCall(hapistore.storeContact),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.green.shade900.withValues(alpha: 0.3) : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isDark ? Colors.green.shade700 : Colors.green.shade200,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.phone, size: 13, color: isDark ? Colors.green.shade300 : Colors.green.shade700),
                                const SizedBox(width: 5),
                                Text(
                                  'Call',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.green.shade300 : Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    // 1-Tap Action: Directions
                    if (hasGps)
                      Tooltip(
                        message: 'Navigate to ${hapistore.storeName}',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _openDirections(hapistore),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.orange.shade900.withValues(alpha: 0.3) : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isDark ? Colors.orange.shade700 : Colors.orange.shade200,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.directions, size: 13, color: isDark ? Colors.orange.shade300 : Colors.orange.shade800),
                                const SizedBox(width: 5),
                                Text(
                                  'Directions',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.orange.shade300 : Colors.orange.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
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
