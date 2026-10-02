import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/inventory_controller.dart';
import 'package:selecta_ops/models/inventory_movement.dart';

/// Reusable tile rendering a single stock movement delta and details.
class InventoryMovementTile extends StatelessWidget {
  final InventoryMovement movement;
  final DateFormat dateFormat;
  final bool compact;

  const InventoryMovementTile({
    super.key,
    required this.movement,
    required this.dateFormat,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPositive = movement.delta >= 0;
    final deltaColor = isPositive ? const Color(0xFF15803D) : colorScheme.error;
    final deltaText = isPositive ? '+${movement.delta}' : '${movement.delta}';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 5 : 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: deltaColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              deltaText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: deltaColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!compact)
                  Text(
                    movement.productName,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  '${movement.reason}${movement.notes.isNotEmpty ? ' • ${movement.notes}' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: compact ? FontWeight.w600 : FontWeight.normal,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${movement.previousStock} → ${movement.newStock} • ${dateFormat.format(movement.createdAt.toDate())}',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet displaying the paginated/streamed list of recent stock movements.
class InventoryMovementsSheet {
  static void show({
    required BuildContext context,
    required InventoryController controller,
    required DateFormat dateFormat,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(Icons.history_rounded, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Stock Movement History',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  Expanded(
                    child: StreamBuilder<List<InventoryMovement>>(
                      stream: controller.getRecentMovementsStream(limit: 60),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final logs = snapshot.data ?? [];
                        if (logs.isEmpty) {
                          return Center(
                            child: Text(
                              'No stock movements recorded yet.',
                              style: TextStyle(color: colorScheme.onSurfaceVariant),
                            ),
                          );
                        }
                        return ListView.separated(
                          controller: scrollController,
                          itemCount: logs.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            return InventoryMovementTile(
                              movement: logs[index],
                              dateFormat: dateFormat,
                            );
                          },
                        );
                      },
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
}
