import 'package:flutter/material.dart';
import 'package:flutter_app/models/placement.dart';
import 'package:flutter_app/services/placement_service.dart';
import 'package:flutter_app/views/pages/dashboard/placement_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

enum _PlacementSort {
  storeNameAscending,
  storeNameDescending,
  progressCountAscending,
  progressCountDescending,
  dateDescending,
}

class PlacementlistPage extends StatefulWidget {
  const PlacementlistPage({super.key});

  @override
  State<PlacementlistPage> createState() => _PlacementlistPageState();
}

class _PlacementlistPageState extends State<PlacementlistPage> {
  int _currentIndex = 0; // 0 = Complete, 1 = Incomplete
  List<Placement> listPlacement = [];
  _PlacementSort _sort = _PlacementSort.storeNameAscending;
  bool _isLoading = true;
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final placements = await PlacementService.getListPlacementForAllStores();
      if (!mounted) return;
      setState(() {
        listPlacement = placements;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load placements: $e';
          _isLoading = false;
        });
      }
    }
  }

  int get _completedCount => listPlacement.where((p) => p.isFinished).length;
  int get _incompleteCount => listPlacement.where((p) => !p.isFinished).length;

  List<Placement> _filteredAndSorted(bool isFinished) {
    List<Placement> filtered = listPlacement.where((p) {
      final matchesStatus = p.isFinished == isFinished;
      final matchesSearch = _searchQuery.isEmpty ||
          p.storeName.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesStatus && matchesSearch;
    }).toList();

    filtered.sort(_compareStores);
    return filtered;
  }

  int _compareStores(Placement first, Placement second) {
    final comparison = switch (_sort) {
      _PlacementSort.storeNameAscending ||
      _PlacementSort.storeNameDescending =>
        first.storeName.toLowerCase().compareTo(second.storeName.toLowerCase()),
      _PlacementSort.progressCountAscending ||
      _PlacementSort.progressCountDescending =>
        first.progressCount.compareTo(second.progressCount),
      _PlacementSort.dateDescending =>
        first.deliveryDate.compareTo(second.deliveryDate),
    };

    return switch (_sort) {
      _PlacementSort.storeNameDescending ||
      _PlacementSort.progressCountDescending ||
      _PlacementSort.dateDescending =>
        -comparison,
      _ => comparison,
    };
  }

  void _openPlacement(Placement placement) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PlacementPage(placement: placement)),
    );
    prefetchData();
  }

  Widget _buildSortMenu() {
    return PopupMenuButton<_PlacementSort>(
      icon: const Icon(Icons.sort_rounded, color: Colors.white),
      tooltip: 'Sort placements',
      onSelected: (sort) => setState(() => _sort = sort),
      itemBuilder: (context) => [
        _buildSortOption(_PlacementSort.storeNameAscending, 'Store Name', 'A to Z', Icons.sort_by_alpha_rounded),
        _buildSortOption(_PlacementSort.storeNameDescending, 'Store Name', 'Z to A', Icons.sort_by_alpha_rounded),
        _buildSortOption(_PlacementSort.progressCountDescending, 'Progress', 'Highest first', Icons.trending_up_rounded),
        _buildSortOption(_PlacementSort.progressCountAscending, 'Progress', 'Lowest first', Icons.trending_down_rounded),
        _buildSortOption(_PlacementSort.dateDescending, 'Delivery Date', 'Most recent', Icons.calendar_today_rounded),
      ],
    );
  }

  PopupMenuItem<_PlacementSort> _buildSortOption(
    _PlacementSort sort,
    String label,
    String subtitle,
    IconData icon,
  ) {
    final isSelected = _sort == sort;
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuItem(
      value: sort,
      child: Row(
        children: [
          Icon(icon, size: 20, color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? colorScheme.primary : null,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (isSelected) Icon(Icons.check_rounded, size: 18, color: colorScheme.primary),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _searchQuery = value.trim()),
          decoration: InputDecoration(
            hintText: 'Search store by name...',
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
            prefixIcon: Icon(Icons.search_rounded, color: colorScheme.onSurfaceVariant, size: 22),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonLoading() {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, _) => Container(
        height: 104,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 140,
                        height: 16,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 90,
                        height: 12,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isFinished) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_searchQuery.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 56, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'No stores found',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'No store matching "$_searchQuery"',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Clear search'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFinished ? Icons.assignment_turned_in_outlined : Icons.pending_actions_outlined,
              size: 56,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              isFinished ? 'No completed placements' : 'No incomplete placements',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              isFinished
                  ? 'Completed store placements will appear here.'
                  : 'Great job! All store placements are currently complete.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBanner({
    required int count,
    required double averageProgress,
    required bool isFinished,
    required Color statusColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final averagePercent = (averageProgress / 12 * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isFinished ? Icons.task_alt_rounded : Icons.pending_actions_rounded,
              color: statusColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFinished ? 'Completed Placements' : 'Incomplete Placements',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count ${count == 1 ? 'store' : 'stores'}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(isFinished ? 'Overall Rate' : 'Avg Progress', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isFinished
                      ? '$count/${_completedCount + _incompleteCount} (${((count / ((_completedCount + _incompleteCount) == 0 ? 1 : (_completedCount + _incompleteCount))) * 100).round()}%)'
                      : '${averageProgress.toStringAsFixed(1)}/12 ($averagePercent%)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: statusColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _placementListView(bool isFinished) {
    if (_isLoading) {
      return _buildSkeletonLoading();
    }

    final placements = _filteredAndSorted(isFinished);
    final colorScheme = Theme.of(context).colorScheme;

    if (placements.isEmpty) {
      return _buildEmptyState(isFinished);
    }

    final totalProgress = placements.fold<int>(0, (sum, p) => sum + p.progressCount);
    final averageProgress = totalProgress / placements.length;
    final statusColor = isFinished ? colorScheme.primary : colorScheme.tertiary;

    return RefreshIndicator(
      onRefresh: prefetchData,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: placements.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildSummaryBanner(
              count: placements.length,
              averageProgress: averageProgress,
              isFinished: isFinished,
              statusColor: statusColor,
            );
          }

          final placement = placements[index - 1];
          final progress = (placement.progressCount / 12).clamp(0.0, 1.0);
          final progressPercent = (progress * 100).round();
          final formattedDate = DateFormat('MMM d, yyyy').format(placement.deliveryDate.toDate());

          return Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: InkWell(
              onTap: () => _openPlacement(placement),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
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
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isFinished ? Icons.check_circle_rounded : Icons.storefront_rounded,
                            color: statusColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                placement.storeName,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.event_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                                  const SizedBox(width: 4),
                                  Text(
                                    formattedDate,
                                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('•', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
                                  const SizedBox(width: 8),
                                  Text(
                                    isFinished ? 'Complete' : 'In Progress',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${placement.progressCount}/12 ($progressPercent%)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: statusColor,
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
                        minHeight: 6,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompleteTab = _currentIndex == 0;
    final totalPlacements = _completedCount + _incompleteCount;
    final overallPercent = totalPlacements == 0 ? 0 : ((_completedCount / totalPlacements) * 100).round();

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Placement List',
        subtitle: isCompleteTab
            ? 'Completed • $overallPercent% of stores finished'
            : 'Pending • $_incompleteCount stores need follow-up',
        actions: [_buildSortMenu()],
      ),
      body: _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 44, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 10),
                    Text(_errorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: prefetchData,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                _buildSearchBar(),
                Expanded(
                  child: _placementListView(isCompleteTab),
                ),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: !_isLoading && _completedCount > 0,
              label: Text('$_completedCount'),
              child: const Icon(Icons.check_circle_outline_rounded),
            ),
            selectedIcon: Badge(
              isLabelVisible: !_isLoading && _completedCount > 0,
              label: Text('$_completedCount'),
              child: const Icon(Icons.check_circle_rounded),
            ),
            label: 'Complete',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: !_isLoading && _incompleteCount > 0,
              label: Text('$_incompleteCount'),
              child: const Icon(Icons.pending_actions_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: !_isLoading && _incompleteCount > 0,
              label: Text('$_incompleteCount'),
              child: const Icon(Icons.pending_actions_rounded),
            ),
            label: 'Incomplete',
          ),
        ],
      ),
    );
  }
}
