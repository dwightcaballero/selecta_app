import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/controllers/inventory_controller.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Modal dialog for warehouse physical cycle counts.
/// Records exact physical counts, computes discrepancies/variances,
/// and logs an audited [MovementType.count_correction].
/// Supports blind counts (hiding system stock) and multi-round recount enforcement.
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
  bool _blindCountEnabled = true;
  int _recountThreshold = 5;
  int _currentRound = 1;
  int? _firstRoundCount;
  bool _isLoadingConfig = true;

  @override
  void initState() {
    super.initState();
    _countController = TextEditingController();
    _notesController = TextEditingController();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await ConfigurationService().getConfiguration();
      if (mounted) {
        setState(() {
          _blindCountEnabled = config.blindCountEnabled;
          _recountThreshold = config.recountThreshold;
          _isLoadingConfig = false;
          if (!_blindCountEnabled) {
            _countController.text = widget.item.stockQuantity.toString();
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _blindCountEnabled = false;
          _isLoadingConfig = false;
          _countController.text = widget.item.stockQuantity.toString();
        });
      }
    }
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
    final countedVal = int.tryParse(_countController.text.trim());
    final isNegative = countedVal != null && countedVal < 0;
    final variance = countedVal != null ? countedVal - item.stockQuantity : 0;

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
          Expanded(
            child: Text(
              _currentRound == 2 ? 'Cycle Count: Recount (Round 2)' : 'Physical Cycle Count',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          if (_blindCountEnabled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Blind Count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
      content: _isLoadingConfig
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_currentRound == 2) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade700),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 20, color: Colors.amber.shade800),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Variance exceeded threshold ($_recountThreshold units). Please recount physical inventory for Round 2 verification.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

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
                            if (_blindCountEnabled)
                              Row(
                                children: [
                                  Icon(Icons.visibility_off_outlined, size: 13, color: colorScheme.outline),
                                  const SizedBox(width: 4),
                                  Text(
                                    'System Stock: Hidden (Blind Count)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              )
                            else
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
                      labelText: _currentRound == 2
                          ? 'Round 2 Recounted Quantity'
                          : 'Actual Physical Count',
                      hintText: 'Enter counted units in warehouse',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Non-blind variance banner
                  if (!_blindCountEnabled && countedVal != null) ...[
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
                  ],

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
          onPressed: isNegative || _countController.text.trim().isEmpty
              ? null
              : () async {
                  final parsedVal = int.tryParse(_countController.text.trim());
                  if (parsedVal == null) return;

                  final v = parsedVal - item.stockQuantity;

                  // Recount enforcement: if Round 1 exceeds threshold in blind count mode
                  if (_blindCountEnabled && _currentRound == 1 && v.abs() > _recountThreshold) {
                    setState(() {
                      _currentRound = 2;
                      _firstRoundCount = parsedVal;
                      _countController.clear();
                    });
                    if (context.mounted) {
                      ShowMessage.warning(
                        context,
                        'Count discrepancy exceeds $_recountThreshold units. Recount required for Round 2 verification.',
                      );
                    }
                    return;
                  }

                  try {
                    final notes = _currentRound == 2
                        ? 'Round 1: $_firstRoundCount, Round 2: $parsedVal. ${_notesController.text.trim()}'.trim()
                        : _notesController.text.trim();

                    await widget.controller.submitCycleCount(
                      item: item,
                      countedQuantity: parsedVal,
                      notes: notes,
                      isBlind: _blindCountEnabled,
                      countRound: _currentRound,
                      systemQuantityAtStart: item.stockQuantity,
                    );
                    if (context.mounted) Navigator.pop(context);
                    if (context.mounted) {
                      ShowMessage.success(
                        context,
                        'Cycle count submitted for "${item.productName}". Stock updated to $parsedVal.',
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ShowMessage.error(context, 'Failed to submit cycle count: $e');
                    }
                  }
                },
          child: Text(_currentRound == 2 ? 'Submit Recount' : 'Record Count'),
        ),
      ],
    );
  }
}
