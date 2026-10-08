import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/scout_route_track.dart';
import 'package:selecta_ops/services/scout_tracking_service.dart';

/// Modal sheet displaying recorded route history, recency freshness tiers,
/// and allowing dealers to mark old routes (>3 months) for re-scouting.
class ScoutRouteHistorySheet extends StatefulWidget {
  final List<ScoutRouteSession> routes;
  final Function(ScoutRouteSession route) onFocusRoute;

  const ScoutRouteHistorySheet({
    super.key,
    required this.routes,
    required this.onFocusRoute,
  });

  @override
  State<ScoutRouteHistorySheet> createState() => _ScoutRouteHistorySheetState();
}

class _ScoutRouteHistorySheetState extends State<ScoutRouteHistorySheet> {
  final ScoutTrackingService _trackingService = ScoutTrackingService();
  String _filter = 'All'; // 'All', 'Fresh', 'Aging', 'Due'

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final freshCount = widget.routes.where((r) => r.recencyTier == RecencyTier.fresh || r.recencyTier == RecencyTier.live).length;
    final agingCount = widget.routes.where((r) => r.recencyTier == RecencyTier.aging).length;
    final dueCount = widget.routes.where((r) => r.recencyTier == RecencyTier.stale || r.needsRescout).length;

    final filteredList = widget.routes.where((r) {
      if (_filter == 'Fresh') return r.recencyTier == RecencyTier.fresh || r.recencyTier == RecencyTier.live;
      if (_filter == 'Aging') return r.recencyTier == RecencyTier.aging;
      if (_filter == 'Due') return r.recencyTier == RecencyTier.stale || r.needsRescout;
      return true;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.alt_route_rounded, color: Color(0xFF0284C7), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Route History & Recency', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    Text(
                      '${widget.routes.length} total recorded runs',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Summary Tier Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All', 'All (${widget.routes.length})', null),
                const SizedBox(width: 8),
                _buildFilterChip('Fresh', 'Fresh <30d ($freshCount)', const Color(0xFF0284C7)),
                const SizedBox(width: 8),
                _buildFilterChip('Aging', 'Aging 1-3m ($agingCount)', const Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                _buildFilterChip('Due', 'Due Re-scout >3m ($dueCount)', const Color(0xFFEF4444)),
              ],
            ),
          ),
          const Divider(height: 20),

          // List of routes
          Expanded(
            child: filteredList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.route_outlined, size: 40, color: colorScheme.outline),
                        const SizedBox(height: 8),
                        Text('No routes matching "$_filter"', style: TextStyle(color: colorScheme.outline)),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: filteredList.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (ctx, index) {
                      final route = filteredList[index];
                      final tier = route.recencyTier;
                      final isOverdue = tier == RecencyTier.stale || route.needsRescout;

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isOverdue
                              ? const Color(0xFFEF4444).withValues(alpha: 0.05)
                              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isOverdue
                                ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                                : colorScheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Date & Salesman
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        DateFormat('MMMM d, yyyy • h:mm a').format(route.startedAt),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'By ${route.salesmanName}',
                                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Recency Badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: tier.badgeBg,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: tier.color.withValues(alpha: 0.4)),
                                      ),
                                      child: Text(
                                        route.ageLabel,
                                        style: TextStyle(
                                          color: tier.color,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 19, color: Color(0xFFEF4444)),
                                      tooltip: 'Delete Route',
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _confirmDeleteRoute(context, route),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Metrics
                            Row(
                              children: [
                                _buildMetricItem(Icons.straighten_rounded, route.formattedDistance),
                                const SizedBox(width: 14),
                                _buildMetricItem(Icons.timer_outlined, route.formattedDuration),
                                const SizedBox(width: 14),
                                _buildMetricItem(Icons.gps_fixed_rounded, '${route.points.length} GPS pts'),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Actions: Focus on Map + Mark for Re-Scout
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)),
                                  ),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    widget.onFocusRoute(route);
                                  },
                                  icon: const Icon(Icons.center_focus_strong_rounded, size: 14),
                                  label: const Text('View on Map', style: TextStyle(fontSize: 11.5)),
                                ),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    foregroundColor: route.needsRescout
                                        ? const Color(0xFFEF4444)
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                  onPressed: () async {
                                    final newVal = !route.needsRescout;
                                    await _trackingService.toggleMarkForRescout(route.id, newVal);
                                    setState(() {});
                                  },
                                  icon: Icon(
                                    route.needsRescout ? Icons.flag_rounded : Icons.outlined_flag_rounded,
                                    size: 15,
                                    color: route.needsRescout ? const Color(0xFFEF4444) : null,
                                  ),
                                  label: Text(
                                    route.needsRescout ? 'Marked for Re-Scout' : 'Mark for Re-Scout',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: route.needsRescout ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, Color? color) {
    final isSelected = _filter == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _filter = key);
      },
      selectedColor: color?.withValues(alpha: 0.2) ?? Theme.of(context).colorScheme.primaryContainer,
      labelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected && color != null ? color : null,
      ),
    );
  }

  Widget _buildMetricItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11.5, color: Colors.grey, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Future<void> _confirmDeleteRoute(BuildContext ctx, ScoutRouteSession route) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 8),
            Text('Delete Route?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete this route recorded by ${route.salesmanName} on ${DateFormat('MMM d, yyyy h:mm a').format(route.startedAt)}? This is useful if the route was started accidentally.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _trackingService.deleteRoute(route.id);
      if (mounted) {
        setState(() {
          widget.routes.removeWhere((r) => r.id == route.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Route successfully deleted'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
