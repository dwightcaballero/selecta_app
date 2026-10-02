import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/inventory_controller.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/views/widgets/inventory/inventory_movements_sheet.dart';

/// Modal bottom sheet for adjusting stock quantities (Stock In, Stock Out, Set Exact)
/// with audit reasons, optional notes, and embedded recent movement logs.
class AdjustStockSheet extends StatefulWidget {
  final InventoryItem item;
  final InventoryController controller;
  final NumberFormat currencyFormat;
  final DateFormat dateFormat;

  const AdjustStockSheet({
    super.key,
    required this.item,
    required this.controller,
    required this.currencyFormat,
    required this.dateFormat,
  });

  static Future<void> show({
    required BuildContext context,
    required InventoryItem item,
    required InventoryController controller,
    required NumberFormat currencyFormat,
    required DateFormat dateFormat,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => AdjustStockSheet(
        item: item,
        controller: controller,
        currencyFormat: currencyFormat,
        dateFormat: dateFormat,
      ),
    );
  }

  @override
  State<AdjustStockSheet> createState() => _AdjustStockSheetState();
}

class _AdjustStockSheetState extends State<AdjustStockSheet> {
  String _mode = 'add'; // 'add', 'deduct', 'set'
  late final TextEditingController _qtyController;
  late final TextEditingController _thresholdController;
  late final TextEditingController _notesController;
  String _selectedReason = 'Restock / PO';
  bool _isSaving = false;

  static const _reasonsByMode = <String, List<String>>{
    'add': ['Restock / PO', 'Return from Store', 'Physical Audit', 'Manual Adjustment'],
    'deduct': ['Delivery / Sale', 'Bad Order', 'Physical Audit', 'Manual Adjustment'],
    'set': ['Physical Audit', 'Initial Stock', 'Manual Adjustment'],
  };

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(text: '1');
    _thresholdController = TextEditingController(
      text: widget.item.lowStockThreshold.toString(),
    );
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _thresholdController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Widget _buildSourceChip(InventoryProductSource source, ColorScheme colorScheme) {
    final isSelecta = source == InventoryProductSource.selecta;
    final chipColor = isSelecta ? colorScheme.primary : const Color(0xFF7C3AED);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isSelecta ? 'Selecta' : 'Other Brand',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: chipColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = widget.item;
    final inputVal = int.tryParse(_qtyController.text.trim()) ?? 0;
    final previewStock = switch (_mode) {
      'add' => item.stockQuantity + (inputVal > 0 ? inputVal : 0),
      'deduct' => (item.stockQuantity - (inputVal > 0 ? inputVal : 0)).clamp(0, 999999),
      _ => inputVal.clamp(0, 999999),
    };
    final previewDelta = previewStock - item.stockQuantity;
    final reasons = _reasonsByMode[_mode]!;
    if (!reasons.contains(_selectedReason)) {
      _selectedReason = reasons.first;
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Product Header
            Row(
              children: [
                CachedProductImage(
                  imageUrl: item.imageUrl,
                  isActive: true,
                  size: 48,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildSourceChip(item.source, colorScheme),
                          const SizedBox(width: 6),
                          Text(
                            'Current Stock: ${item.stockQuantity}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.productName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Mode Selector (Add / Deduct / Set Exact)
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'add',
                  icon: Icon(Icons.add_circle_outline, size: 18),
                  label: Text('Stock In (+)'),
                ),
                ButtonSegment(
                  value: 'deduct',
                  icon: Icon(Icons.remove_circle_outline, size: 18),
                  label: Text('Stock Out (-)'),
                ),
                ButtonSegment(
                  value: 'set',
                  icon: Icon(Icons.fact_check_outlined, size: 18),
                  label: Text('Exact (=)'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (newSelection) {
                setState(() {
                  _mode = newSelection.first;
                  if (_mode == 'set') {
                    _qtyController.text = item.stockQuantity.toString();
                  } else if (_qtyController.text == item.stockQuantity.toString()) {
                    _qtyController.text = '1';
                  }
                  _selectedReason = _reasonsByMode[_mode]!.first;
                });
              },
            ),
            const SizedBox(height: 14),

            // Quantity Input + Quick Presets
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _qtyController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: _mode == 'set' ? 'New Exact Stock' : 'Quantity',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _thresholdController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Low Alert ≤',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Preset quantity buttons
            if (_mode != 'set')
              Wrap(
                spacing: 8,
                children: [1, 5, 10, 20, 50].map((preset) {
                  return ActionChip(
                    label: Text(
                      '${_mode == 'add' ? '+' : '-'}$preset',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() {
                        _qtyController.text = preset.toString();
                      });
                    },
                  );
                }).toList(),
              ),
            const SizedBox(height: 10),

            // Reason Chips
            Text(
              'Reason',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: reasons.map((reason) {
                final isSelected = _selectedReason == reason;
                return ChoiceChip(
                  label: Text(
                    reason,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? Colors.white : colorScheme.onSurface,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: colorScheme.primary,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _selectedReason = reason),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),

            // Optional Notes
            TextField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: 'Notes / Reference (Optional)',
                hintText: 'e.g. PO #1024 or Store Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Preview Banner + Save Button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Resulting Stock: ${item.stockQuantity} → $previewStock '
                    '(${previewDelta >= 0 ? '+$previewDelta' : '$previewDelta'})',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    widget.currencyFormat.format(previewStock * item.sellingPrice),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSaving
                    ? null
                    : () async {
                        setState(() => _isSaving = true);
                        try {
                          final newThreshold = int.tryParse(
                                _thresholdController.text.trim(),
                              ) ??
                              item.lowStockThreshold;
                          await widget.controller.updateStock(
                            item: item,
                            newStockQuantity: previewStock,
                            newLowStockThreshold: newThreshold,
                            reason: _selectedReason,
                            notes: _notesController.text,
                          );
                          if (context.mounted) Navigator.pop(context);
                          if (context.mounted) {
                            ShowMessage.success(
                              context,
                              'Updated "${item.productName}" stock to $previewStock.',
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ShowMessage.error(context, 'Failed to update stock: $e');
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _isSaving = false);
                          }
                        }
                      },
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
                label: const Text('Save Stock Adjustment'),
              ),
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Embedded Product Movement History
            Text(
              'Recent Stock History',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            StreamBuilder<List<InventoryMovement>>(
              stream: widget.controller.getProductMovementsStream(item.id, limit: 5),
              builder: (context, snap) {
                final movements = snap.data ?? [];
                if (movements.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No stock movements recorded for this product yet.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return Column(
                  children: movements
                      .map((m) => InventoryMovementTile(
                            movement: m,
                            dateFormat: widget.dateFormat,
                            compact: true,
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
