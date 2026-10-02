import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/proof_of_visit.dart';
import 'package:selecta_ops/services/proof_of_visit_service.dart';
import 'package:selecta_ops/views/pages/sidebar/store_profile_page.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/views/widgets/shimmer_loading.dart';

enum GalleryDateFilter {
  all('All Time', null),
  today('Today', 1),
  past7Days('Past 7 Days', 7),
  past30Days('Past 30 Days', 30);

  final String label;
  final int? days;
  const GalleryDateFilter(this.label, this.days);
}

/// Centralized Proof of Visit & Store Visit Photo Gallery.
///
/// Aggregates field proof-of-visit photos across all store visits and salesmen:
/// - Realtime Firestore stream from proof_of_visit collection.
/// - Filter by Store, Date Range (Today, 7d, 30d, All), or Salesman.
/// - Pinch-to-zoom full-screen viewer with store metadata and notes.
/// - 1-tap navigation directly to Store 360° Profile.
class ProofOfVisitGalleryPage extends StatefulWidget {
  final String? initialStoreFilter;

  const ProofOfVisitGalleryPage({super.key, this.initialStoreFilter});

  @override
  State<ProofOfVisitGalleryPage> createState() => _ProofOfVisitGalleryPageState();
}

class _ProofOfVisitGalleryPageState extends State<ProofOfVisitGalleryPage> {
  final ProofOfVisitService _service = ProofOfVisitService();
  final TextEditingController _searchController = TextEditingController();

  GalleryDateFilter _dateFilter = GalleryDateFilter.all;
  String? _selectedStore;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialStoreFilter != null && widget.initialStoreFilter!.isNotEmpty) {
      _selectedStore = widget.initialStoreFilter;
    }
    _searchController.addListener(() {
      if (mounted) setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Proof of Visit Photo Gallery',
        actions: [
          if (_selectedStore != null || _dateFilter != GalleryDateFilter.all || _searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.filter_alt_off_outlined),
              tooltip: 'Reset Filters',
              onPressed: () {
                setState(() {
                  _selectedStore = null;
                  _dateFilter = GalleryDateFilter.all;
                  _searchController.clear();
                });
              },
            ),
        ],
      ),
      body: StreamBuilder<List<ProofOfVisit>>(
        stream: _service.getAllProofsOfVisitStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.8,
              ),
              itemCount: 6,
              itemBuilder: (_, _) => const ShimmerBox(width: double.infinity, height: double.infinity, borderRadius: 14),
            );
          }

          final allVisits = snapshot.data!;
          final uniqueStores = {'All Stores', ...allVisits.map((v) => v.storeName).where((s) => s.isNotEmpty)};

          // Compute Date Cutoff
          DateTime? cutoffDate;
          final now = DateTime.now();
          if (_dateFilter == GalleryDateFilter.today) {
            cutoffDate = DateTime(now.year, now.month, now.day, 0, 0, 0);
          } else if (_dateFilter.days != null) {
            cutoffDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: _dateFilter.days!));
          }

          // Filter records
          final filtered = allVisits.where((visit) {
            // Store filter
            if (_selectedStore != null && _selectedStore != 'All Stores') {
              if (visit.storeName != _selectedStore) return false;
            }

            // Date filter
            if (cutoffDate != null) {
              final visitDt = visit.visitDate.toDate();
              if (visitDt.isBefore(cutoffDate)) return false;
            }

            // Search query (notes, storeName, takenBy)
            if (_searchQuery.isNotEmpty) {
              final text = '${visit.storeName} ${visit.takenBy} ${visit.notes}'.toLowerCase();
              if (!text.contains(_searchQuery)) return false;
            }

            return true;
          }).toList();

          // Metrics
          final todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0);
          final photosTodayCount = allVisits.where((v) => v.visitDate.toDate().isAfter(todayStart)).length;
          final uniqueStoresCount = allVisits.map((v) => v.storeName).toSet().length;

          return Column(
            children: [
              // Summary Metrics Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                color: isDark ? const Color(0xFF1E2430) : colorScheme.surface,
                child: Row(
                  children: [
                    _buildMetricChip(
                      icon: Icons.photo_library_rounded,
                      label: 'Total Photos',
                      value: '${allVisits.length}',
                      color: colorScheme.primary,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildMetricChip(
                      icon: Icons.today_rounded,
                      label: 'Photos Today',
                      value: '$photosTodayCount',
                      color: Colors.green,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildMetricChip(
                      icon: Icons.storefront_rounded,
                      label: 'Stores Visited',
                      value: '$uniqueStoresCount',
                      color: Colors.orange.shade700,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),

              // Search & Filter Bar
              Container(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                color: isDark ? const Color(0xFF1E2430) : colorScheme.surface,
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by store, agent, or note keyword...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => _searchController.clear(),
                              )
                            : null,
                        filled: true,
                        fillColor: isDark ? const Color(0xFF141822) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Date Filter Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: GalleryDateFilter.values.map((f) {
                          final isSelected = _dateFilter == f;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(f.label, style: const TextStyle(fontSize: 12)),
                              selected: isSelected,
                              onSelected: (val) {
                                if (val) setState(() => _dateFilter = f);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),

              // Filter info row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF171B24) : colorScheme.surfaceContainerLowest,
                  border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF28303F) : colorScheme.outlineVariant.withValues(alpha: 0.3))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Showing ${filtered.length} photos',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                    ),
                    if (uniqueStores.length > 2)
                      DropdownButton<String>(
                        value: _selectedStore ?? 'All Stores',
                        isDense: true,
                        underline: const SizedBox(),
                        style: TextStyle(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.w600),
                        items: uniqueStores.map((s) {
                          return DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis));
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedStore = val == 'All Stores' ? null : val;
                          });
                        },
                      ),
                  ],
                ),
              ),

              // Photo Grid
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_library_outlined, size: 54, color: colorScheme.outlineVariant),
                            const SizedBox(height: 12),
                            Text(
                              'No visit photos found',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Capture photos during store PJP visits to view them here.',
                              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          return _buildPhotoCard(context, filtered[index], isDark, colorScheme);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetricChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.2 : 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(fontSize: 10, color: isDark ? Colors.white70 : Colors.black54),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoCard(BuildContext context, ProofOfVisit visit, bool isDark, ColorScheme colorScheme) {
    final dateFormat = DateFormat('MMM d, yyyy • h:mm a');
    final formattedDate = dateFormat.format(visit.visitDate.toDate());

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? const Color(0xFF28303F) : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        onTap: () => _openPhotoDetailModal(context, visit),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Preview
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedProductImage(
                    imageUrl: visit.imageUrl,
                    size: double.infinity,
                    borderRadius: 0,
                  ),
                  // Agent Badge
                  if (visit.takenBy.isNotEmpty)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person, size: 11, color: Colors.white),
                            const SizedBox(width: 3),
                            Text(
                              visit.takenBy,
                              style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Card Footer
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    visit.storeName,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 12, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          formattedDate,
                          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (visit.notes.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      visit.notes,
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87, fontStyle: FontStyle.italic),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FULL SCREEN INTERACTIVE PHOTO VIEWER
  // ═══════════════════════════════════════════════════════════════════════════

  void _openPhotoDetailModal(BuildContext context, ProofOfVisit visit) {
    final dateFormat = DateFormat('MMMM d, yyyy • h:mm a');
    final formattedDate = dateFormat.format(visit.visitDate.toDate());

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              // Zoomable Image
              Center(
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: CachedProductImage(
                    imageUrl: visit.imageUrl,
                    size: double.infinity,
                    borderRadius: 0,
                  ),
                ),
              ),

              // Top Bar with Close
              Positioned(
                top: 40,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.black.withValues(alpha: 0.6),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.6),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.storefront_outlined, size: 18),
                      label: const Text('Store 360° Profile'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StoreProfilePage(storeName: visit.storeName),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Bottom Metadata Overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.85),
                        Colors.black,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        visit.storeName,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.event_outlined, size: 14, color: Colors.white70),
                          const SizedBox(width: 6),
                          Text(
                            formattedDate,
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          if (visit.takenBy.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            const Icon(Icons.person_outline, size: 14, color: Colors.white70),
                            const SizedBox(width: 4),
                            Text(
                              visit.takenBy,
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ],
                      ),
                      if (visit.notes.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            visit.notes,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
