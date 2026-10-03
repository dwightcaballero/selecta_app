import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/proof_of_visit.dart';
import 'package:selecta_ops/services/proof_of_visit_service.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/imageviewer_page.dart';

enum PjpHistoryFilter {
  all('All'),
  thisMonth('This Month'),
  past7Days('Past 7 Days'),
  withPhoto('With Photo');

  final String label;
  const PjpHistoryFilter(this.label);
}

/// A comprehensive chronological history of all completed PJP store visits.
///
/// Features:
/// - Real-time Firestore stream updates
/// - Filter chips (All, This Month, Past 7 Days, With Photo)
/// - Instant search by store name or salesman
/// - Top summary stats (Total visits, unique stores, photo count)
/// - Sleek skeleton loading animations
/// - Detailed visit bottom sheet with copy & fullscreen photo options
class PjpHistoryPage extends StatefulWidget {
  /// Optional search text to prefill (e.g. a store name) when opening the page.
  final String? initialSearchQuery;

  const PjpHistoryPage({super.key, this.initialSearchQuery});

  @override
  State<PjpHistoryPage> createState() => _PjpHistoryPageState();
}

class _PjpHistoryPageState extends State<PjpHistoryPage> with SingleTickerProviderStateMixin {
  final ProofOfVisitService _service = ProofOfVisitService();
  final TextEditingController _searchController = TextEditingController();

  StreamSubscription<List<ProofOfVisit>>? _subscription;
  List<ProofOfVisit> _allVisits = [];
  List<ProofOfVisit> _filteredVisits = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  PjpHistoryFilter _activeFilter = PjpHistoryFilter.all;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    final initialQuery = widget.initialSearchQuery?.trim() ?? '';
    if (initialQuery.isNotEmpty) {
      _searchController.text = initialQuery;
      _searchQuery = initialQuery.toLowerCase();
    }

    _searchController.addListener(_onSearchChanged);
    _subscribeToHistory();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query != _searchQuery) {
      setState(() {
        _searchQuery = query;
        _applyFilters();
      });
    }
  }

  void _subscribeToHistory() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _subscription?.cancel();
    _subscription = _service.getAllProofsOfVisitStream().listen(
      (visits) {
        if (!mounted) return;
        setState(() {
          _allVisits = visits;
          _isLoading = false;
          _errorMessage = null;
          _applyFilters();
        });
      },
      onError: (e, s) {
        ErrorLogService.logError(
          page: 'PjpHistoryPage',
          action: 'Stream PJP Visit History',
          error: e,
          stackTrace: s,
        );
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load visit history. Please pull down to refresh.';
        });
        ShowMessage.error(context, 'Failed to load visit history.');
      },
    );
  }

  void _applyFilters() {
    final now = DateTime.now();
    final startOfCurrentMonth = DateTime(now.year, now.month, 1);
    final sevenDaysAgo = now.subtract(const Duration(days: 7));

    List<ProofOfVisit> result = _allVisits;

    // Apply quick filter chip
    switch (_activeFilter) {
      case PjpHistoryFilter.all:
        break;
      case PjpHistoryFilter.thisMonth:
        result = result.where((v) {
          final dt = v.visitDate.toDate();
          return dt.isAfter(startOfCurrentMonth) || dt.isAtSameMomentAs(startOfCurrentMonth);
        }).toList();
        break;
      case PjpHistoryFilter.past7Days:
        result = result.where((v) {
          final dt = v.visitDate.toDate();
          return dt.isAfter(sevenDaysAgo);
        }).toList();
        break;
      case PjpHistoryFilter.withPhoto:
        result = result.where((v) => v.imageUrl.isNotEmpty).toList();
        break;
    }

    // Apply text search
    if (_searchQuery.isNotEmpty) {
      result = result.where((v) {
        final store = v.storeName.toLowerCase();
        final taken = v.takenBy.toLowerCase();
        final notes = v.notes.toLowerCase();
        return store.contains(_searchQuery) || taken.contains(_searchQuery) || notes.contains(_searchQuery);
      }).toList();
    }

    _filteredVisits = result;
  }

  /// Groups visits by "Month Year" label.
  Map<String, List<ProofOfVisit>> _groupByMonth(List<ProofOfVisit> visits) {
    final Map<String, List<ProofOfVisit>> grouped = {};
    for (final visit in visits) {
      final label = DateFormat('MMMM yyyy').format(visit.visitDate.toDate());
      grouped.putIfAbsent(label, () => []).add(visit);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final grouped = _groupByMonth(_filteredVisits);
    final monthKeys = grouped.keys.toList();

    final uniqueStoresCount = _filteredVisits.map((v) => v.storeName).toSet().length;
    final photosCount = _filteredVisits.where((v) => v.imageUrl.isNotEmpty).length;

    return Scaffold(
      appBar: const CustomAppbar(
        title: 'PJP Visit History',
        subtitle: 'All completed store visits & verification photos',
      ),
      body: Column(
        children: [
          // ── Search & Filter Controls ────────────────────────────────────
          _buildSearchAndFilterBar(colorScheme),

          // ── Metric Summary Bar (when data loaded) ───────────────────────
          if (!_isLoading && _errorMessage == null && _allVisits.isNotEmpty)
            _buildStatsBar(colorScheme, uniqueStoresCount, photosCount),

          // ── Content Area ────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? _buildSkeletonList(colorScheme)
                : _errorMessage != null
                    ? _buildErrorState(colorScheme)
                    : _filteredVisits.isEmpty
                        ? _buildEmptyState(colorScheme)
                        : RefreshIndicator(
                            onRefresh: () async => _subscribeToHistory(),
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                              itemCount: monthKeys.length,
                              itemBuilder: (context, index) {
                                final month = monthKeys[index];
                                final visits = grouped[month]!;
                                return _buildMonthSection(month, visits, colorScheme);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search TextField
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search store, salesman, or notes...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            ),
          ),

          const SizedBox(height: 8),

          // Quick Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: PjpHistoryFilter.values.map((filter) {
                final isSelected = _activeFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text(filter.label),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                    ),
                    selectedColor: colorScheme.primary,
                    backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    checkmarkColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    side: BorderSide(
                      color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    onSelected: (selected) {
                      setState(() {
                        _activeFilter = filter;
                        _applyFilters();
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar(ColorScheme colorScheme, int uniqueStores, int photosCount) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Total Visits', '${_filteredVisits.length}', Icons.location_on_outlined, colorScheme),
          Container(width: 1, height: 28, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          _buildStatItem('Unique Stores', '$uniqueStores', Icons.storefront_outlined, colorScheme),
          Container(width: 1, height: 28, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          _buildStatItem('Photos', '$photosCount', Icons.camera_alt_outlined, colorScheme),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSkeletonList(ColorScheme colorScheme) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 5,
          itemBuilder: (context, index) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: _pulseAnimation.value),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 16,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: _pulseAnimation.value),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 140,
                          height: 12,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: _pulseAnimation.value),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 100,
                          height: 12,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: _pulseAnimation.value),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: colorScheme.error.withValues(alpha: 0.8)),
            const SizedBox(height: 16),
            Text(
              'Unable to load visit history',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage ?? 'An error occurred while connecting to the database.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _subscribeToHistory,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    final hasActiveFilter = _searchQuery.isNotEmpty || _activeFilter != PjpHistoryFilter.all;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasActiveFilter ? Icons.search_off_rounded : Icons.map_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              hasActiveFilter ? 'No matching visits found' : 'No visit history recorded yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              hasActiveFilter
                  ? 'Try modifying your search query or changing the filter chip.'
                  : 'Visits with photo verifications recorded during daily PJP will appear here.',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
              textAlign: TextAlign.center,
            ),
            if (hasActiveFilter) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                    _activeFilter = PjpHistoryFilter.all;
                    _applyFilters();
                  });
                },
                icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                label: const Text('Reset Filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSection(String month, List<ProofOfVisit> visits, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  month,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.4))),
              const SizedBox(width: 8),
              Text(
                '${visits.length} visit${visits.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        ...visits.map((visit) => _buildVisitCard(visit, colorScheme)),
      ],
    );
  }

  Widget _buildVisitCard(ProofOfVisit visit, ColorScheme colorScheme) {
    final visitDate = visit.visitDate.toDate();
    final dateLabel = DateFormat('EEE, MMM d, yyyy • h:mm a').format(visitDate);
    final hasPhoto = visit.imageUrl.isNotEmpty;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showVisitDetailSheet(visit, colorScheme),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Photo Thumbnail with tap-to-expand ──────────────────────
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: hasPhoto
                        ? Hero(
                            tag: 'pjp_visit_${visit.id.isNotEmpty ? visit.id : visit.imageUrl}',
                            child: Image.network(
                              visit.imageUrl,
                              width: 74,
                              height: 74,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => _buildNoPhotoPlaceholder(colorScheme, size: 74),
                            ),
                          )
                        : _buildNoPhotoPlaceholder(colorScheme, size: 74),
                  ),
                  if (hasPhoto)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: GestureDetector(
                        onTap: () => _openFullscreenPhoto(visit.imageUrl),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.fullscreen_rounded, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(width: 12),

              // ── Visit Info ──────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Store Name & Verified Badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            visit.storeName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasPhoto)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_rounded, size: 11, color: Colors.green),
                                SizedBox(width: 3),
                                Text(
                                  'Photo',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    // Date & Time
                    Row(
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 12, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            dateLabel,
                            style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    // Salesman Name
                    if (visit.takenBy.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.badge_outlined, size: 12, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              visit.takenBy,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Notes preview snippet
                    if (visit.notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          visit.notes,
                          style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 20, color: colorScheme.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoPhotoPlaceholder(ColorScheme colorScheme, {double size = 74}) {
    return Container(
      width: size,
      height: size,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt_outlined, size: size * 0.35, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 2),
          Text(
            'No Photo',
            style: TextStyle(fontSize: 9, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }

  void _openFullscreenPhoto(String imageUrl) {
    if (imageUrl.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageViewerPage(image: null, networkImagePath: imageUrl),
      ),
    );
  }

  void _showVisitDetailSheet(ProofOfVisit visit, ColorScheme colorScheme) {
    final visitDate = visit.visitDate.toDate();
    final dateStr = DateFormat('EEEE, MMMM d, yyyy • h:mm a').format(visitDate);
    final hasPhoto = visit.imageUrl.isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: hasPhoto ? 0.75 : 0.45,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Sheet Title
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            visit.storeName,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'PJP Visit Verification',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 20),
                      tooltip: 'Copy Store Name',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: visit.storeName));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Store name copied to clipboard'), duration: Duration(seconds: 1)),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Photo preview if available
                if (hasPhoto) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      children: [
                        Image.network(
                          visit.imageUrl,
                          width: double.infinity,
                          height: 220,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: 140,
                            color: colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: const Text('Failed to load image'),
                          ),
                        ),
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: FilledButton.tonalIcon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _openFullscreenPhoto(visit.imageUrl);
                            },
                            icon: const Icon(Icons.fullscreen_rounded, size: 18),
                            label: const Text('View Fullscreen'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Detail Items Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow(Icons.calendar_month_outlined, 'Visit Timestamp', dateStr, colorScheme),
                      const Divider(height: 20),
                      _buildDetailRow(
                        Icons.person_outline_rounded,
                        'Salesman / Field Rep',
                        visit.takenBy.isNotEmpty ? visit.takenBy : 'Not specified',
                        colorScheme,
                      ),
                      if (visit.notes.isNotEmpty) ...[
                        const Divider(height: 20),
                        _buildDetailRow(Icons.notes_rounded, 'Visit Notes', visit.notes, colorScheme),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Close Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String title, String value, ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
