import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/controllers/inventory_controller.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Modal dialog for warehouse physical cycle counts.
/// Records exact physical counts, computes discrepancies/variances,
/// and logs an audited [MovementType.count_correction].
class CycleCountDialog extends StatefulWidget {
  final InventoryItem item;
  final InventoryController controller;

  const CycleCountDialog({
    super.key,
    required this.item,
    required this.controller,
  });

  static Future<void> show({
    required BuildContext context,
    required InventoryItem item,
    required InventoryController controller,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => CycleCountDialog(
        item: item,
        controller: controller,
      ),
    );
  }

  @override
  State<CycleCountDialog> createState() => _CycleCountDialogState();
}

class _CycleCountDialogState extends State<CycleCountDialog> {
  late final TextEditingController _countController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _countController = TextEditingController(text: widget.item.stockQuantity.toString());
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _countController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final colorScheme = Theme.of(context).colorScheme;
    final countedVal = int.tryParse(_countController.text.trim()) ?? item.stockQuantity;
    final isNegative = countedVal < 0;
    final variance = countedVal - item.stockQuantity;

    Color varianceColor = colorScheme.outline;
    String varianceLabel = 'No Variance (Matches System)';
    if (variance > 0) {
      varianceColor = const Color(0xFF15803D);
      varianceLabel = '+$variance Units (Surplus / Over)';
    } else if (variance < 0) {
      varianceColor = colorScheme.error;
      varianceLabel = '$variance Units (Deficit / Shortage)';
    }

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.fact_check_rounded, color: colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Physical Cycle Count',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product info
            Row(
              children: [
                CachedProductImage(
                  imageUrl: item.imageUrl,
                  isActive: true,
                  size: 44,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Recorded Stock: ${item.stockQuantity} units',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Actual Count Input
            TextField(
              controller: _countController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Actual Physical Count',
                hintText: 'Enter counted units in warehouse',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),

            // Variance banner
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: varianceColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: varianceColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    variance == 0 ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                    size: 18,
                    color: varianceColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Variance: $varianceLabel',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: varianceColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Notes / Location
            TextField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: 'Notes / Location (Optional)',
                hintText: 'e.g., Freezer 2, Shelf B count verified',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        AsyncFilledButton(
          onPressed: isNegative
              ? null
              : () async {
                  try {
                    await widget.controller.submitCycleCount(
                      item: item,
                      countedQuantity: countedVal,
                      notes: _notesController.text.trim(),
                    );
                    if (context.mounted) Navigator.pop(context);
                    if (context.mounted) {
                      ShowMessage.success(
                        context,
                        'Cycle count submitted for "${item.productName}". Stock updated to $countedVal.',
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ShowMessage.error(context, 'Failed to submit cycle count: $e');
                    }
                  }
                },
          child: const Text('Record Count'),
        ),
      ],
    );
  }
}
