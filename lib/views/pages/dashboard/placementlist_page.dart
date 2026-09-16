import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/services/placement_service.dart';
import 'package:flutter_app/models/placement.dart';
import 'package:flutter_app/views/pages/dashboard/placement_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

enum _PlacementSort { storeNameAscending, storeNameDescending, progressCountAscending, progressCountDescending }

class PlacementlistPage extends StatefulWidget {
  const PlacementlistPage({super.key});

  @override
  State<PlacementlistPage> createState() => _PlacementlistPageState();
}

class _PlacementlistPageState extends State<PlacementlistPage> {
  int _currentIndex = 0;
  List<Placement> listPlacement = [];
  _PlacementSort _sort = _PlacementSort.storeNameAscending;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  Future<void> prefetchData() async {
    if (mounted) setState(() => _isLoading = true);
    final placements = await PlacementService.getListPlacementForAllStores();
    if (!mounted) return;
    setState(() {
      listPlacement = placements;
      _isLoading = false;
    });
  }

  List<Placement> _filteredAndSorted(bool isFinished) {
    List<Placement> filtered = listPlacement.where((placement) => placement.isFinished == isFinished).toList();
    filtered.sort(_compareStores);
    return filtered;
  }

  int _compareStores(Placement first, Placement second) {
    final comparison = switch (_sort) {
      _PlacementSort.storeNameAscending ||
      _PlacementSort.storeNameDescending => first.storeName.toLowerCase().compareTo(second.storeName.toLowerCase()),
      _PlacementSort.progressCountAscending || _PlacementSort.progressCountDescending => first.progressCount.compareTo(second.progressCount),
    };

    return switch (_sort) {
      _PlacementSort.storeNameDescending || _PlacementSort.progressCountDescending => -comparison,
      _ => comparison,
    };
  }

  void _openPlacement(Placement placement) async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => PlacementPage(placement: placement)));
    prefetchData();
  }

  Widget _buildSortMenu() {
    return PopupMenuButton<_PlacementSort>(
      icon: const Icon(Icons.sort_rounded, color: Colors.white),
      tooltip: 'Sort placements',
      onSelected: (sort) => setState(() => _sort = sort),
      itemBuilder: (context) => [
        _buildSortOption(_PlacementSort.storeNameAscending, 'Store Name', true),
        _buildSortOption(_PlacementSort.storeNameDescending, 'Store Name', false),
        _buildSortOption(_PlacementSort.progressCountAscending, 'Progress Count', true),
        _buildSortOption(_PlacementSort.progressCountDescending, 'Progress Count', false),
      ],
    );
  }

  PopupMenuItem<_PlacementSort> _buildSortOption(_PlacementSort sort, String label, bool ascending) {
    return PopupMenuItem(
      value: sort,
      child: Row(
        children: [
          Icon(ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text('$label (${ascending ? 'Ascending' : 'Descending'})')),
          if (_sort == sort) const Icon(Icons.check_rounded, size: 18),
        ],
      ),
    );
  }

  Widget _placementListView(bool isFinished) {
    List<Placement> placements = _filteredAndSorted(isFinished);
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (placements.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(isFinished ? 'No completed placements' : 'No incomplete placements', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Placements will appear here when available.', style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    final totalProgress = placements.fold<int>(0, (sum, placement) => sum + placement.progressCount);
    final averageProgress = totalProgress / placements.length;
    final statusColor = isFinished ? colorScheme.primary : colorScheme.tertiary;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: placements.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildSummaryBanner(count: placements.length, averageProgress: averageProgress, isFinished: isFinished, statusColor: statusColor);
        }

        final placement = placements[index - 1];
        final progress = (placement.progressCount / 12).clamp(0.0, 1.0);

        return Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
          ),
          child: InkWell(
            onTap: () => _openPlacement(placement),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                        child: Icon(isFinished ? Icons.check_circle_outline : Icons.storefront_outlined, color: statusColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(placement.storeName, style: KTextStyle.titleTextStyle, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 3),
                            Text(
                              isFinished ? 'Placement complete' : 'Placement in progress',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${placement.progressCount}/12',
                        style: TextStyle(fontWeight: FontWeight.bold, color: statusColor),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 20, color: colorScheme.onSurfaceVariant),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
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
    );
  }

  Widget _buildSummaryBanner({required int count, required double averageProgress, required bool isFinished, required Color statusColor}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(isFinished ? Icons.task_alt_rounded : Icons.pending_actions_rounded, color: statusColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFinished ? 'Completed placements' : 'Placements requiring attention',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 3),
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
              Text('Average progress', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 3),
              Text(
                '${averageProgress.toStringAsFixed(1)}/12',
                style: TextStyle(fontWeight: FontWeight.bold, color: statusColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(title: 'Placement List', actions: [_buildSortMenu()]),
      body: Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0), child: _placementListView(_currentIndex == 0)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.check_circle_outline), selectedIcon: Icon(Icons.check_circle), label: 'Complete'),
          NavigationDestination(icon: Icon(Icons.radio_button_unchecked), selectedIcon: Icon(Icons.pending_outlined), label: 'Incomplete'),
        ],
      ),
    );
  }
}
