import 'package:flutter/material.dart';
import 'package:flutter_app/controllers/placement_controller.dart';
import 'package:flutter_app/data/data.dart';
import 'package:flutter_app/models/placement.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

/// Read-only presentation view for inspecting store product placement status.
///
/// Data hydration, best seller resolution, and month validation
/// are managed by [PlacementController].
class PlacementPage extends StatefulWidget {
  final Placement placement;
  const PlacementPage({super.key, required this.placement});

  @override
  State<PlacementPage> createState() => _PlacementPageState();
}

class _PlacementPageState extends State<PlacementPage> {
  final PlacementController _controller = PlacementController();
  late Placement _currentPlacement;
  List<KPlacement> listPlacement = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentPlacement = _controller.resolveInitialPlacement(widget.placement);
    _initData();
  }

  Future<void> _initData() async {
    if (_currentPlacement.storeName.isNotEmpty) {
      try {
        final existing = await _controller.getExistingPlacementForCurrentMonth(_currentPlacement.storeName);
        if (existing != null) {
          _currentPlacement = existing;
        }
      } catch (_) {}
    }

    final loaded = await _controller.loadBestSellerPlacements(placement: _currentPlacement);
    if (mounted) {
      setState(() {
        listPlacement = loaded;
        _isLoading = false;
      });
    }
  }

  Future<void> prefetchData() async {
    final loaded = await _controller.loadBestSellerPlacements(placement: _currentPlacement);
    if (mounted) {
      setState(() {
        listPlacement = loaded;
      });
    }
  }

  Widget _buildProgressHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final placedCount = listPlacement.where((p) => p.isPlaced).length;
    final totalCount = listPlacement.length;
    final isFinished = totalCount > 0 && placedCount == totalCount;
    final progress = totalCount > 0 ? (placedCount / totalCount).clamp(0.0, 1.0) : 0.0;
    final statusColor = isFinished ? colorScheme.primary : colorScheme.tertiary;
    final currentMonthLabel = DateFormat('MMMM yyyy').format(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(isFinished ? Icons.task_alt_rounded : Icons.storefront_outlined, color: statusColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentPlacement.storeName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isFinished ? 'All products placed ($currentMonthLabel)' : 'Placement status ($currentMonthLabel)',
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                child: Text(
                  '$placedCount/$totalCount',
                  style: TextStyle(fontWeight: FontWeight.bold, color: statusColor, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: progress, minHeight: 7, backgroundColor: colorScheme.surfaceContainerHighest, color: statusColor),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$placedCount of $totalCount products placed', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
              Text(
                '${(progress * 100).toInt()}%',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Monthly Product Checklist',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          'Read-only view of products placed for the current month',
          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildProductCard(BuildContext context, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final placement = listPlacement[index];
    final isPlaced = placement.isPlaced;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: isPlaced ? colorScheme.primary.withValues(alpha: 0.05) : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isPlaced ? colorScheme.primary.withValues(alpha: 0.35) : colorScheme.outlineVariant.withValues(alpha: 0.65),
          width: isPlaced ? 1.4 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
              ),
              child: placement.itemImagePath.startsWith('http')
                  ? Image.network(
                      placement.itemImagePath,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Icon(Icons.icecream_outlined, color: colorScheme.onSurfaceVariant),
                    )
                  : Image.asset(
                      placement.itemImagePath,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Icon(Icons.icecream_outlined, color: colorScheme.onSurfaceVariant),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(placement.itemName, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  if (isPlaced)
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, size: 12, color: colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Placed for this month',
                          style: TextStyle(fontSize: 11, color: colorScheme.primary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Icon(Icons.radio_button_unchecked_rounded, size: 12, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          'Not placed',
                          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isPlaced)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_rounded, size: 13, color: colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Placed',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close_rounded, size: 13, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      'Unplaced',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(
        title: 'Placement',
        subtitle: _currentPlacement.storeName,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: listPlacement.length + 2,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) return _buildProgressHeader(context);
                if (index == 1) return _buildChecklistHeader(context);
                return _buildProductCard(context, index - 2);
              },
            ),
    );
  }
}
