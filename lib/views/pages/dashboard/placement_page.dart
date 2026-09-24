import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/data.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/placement.dart';
import 'package:flutter_app/services/placement_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class PlacementPage extends StatefulWidget {
  final Placement placement;
  const PlacementPage({super.key, required this.placement});

  @override
  State<PlacementPage> createState() => _PlacementPageState();
}

class _PlacementPageState extends State<PlacementPage> {
  late Placement _currentPlacement;
  List<KPlacement> listPlacement = [];
  bool _isSaving = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _setupInitialPlacement();
    _initData();
  }

  void _setupInitialPlacement() {
    final now = DateTime.now();
    final placementDate = widget.placement.deliveryDate.toDate();
    final isSameMonth = placementDate.year == now.year && placementDate.month == now.month;

    if (isSameMonth && widget.placement.id.isNotEmpty) {
      _currentPlacement = widget.placement;
    } else {
      // Month rolled over or blank: start clean for the current month
      _currentPlacement = Placement.empty().copyWith(
        storeName: widget.placement.storeName,
        deliveryDate: Timestamp.now(),
      );
    }
  }

  Future<void> _initData() async {
    prefetchData();

    // Query for existing record for the current month for this store
    if (_currentPlacement.storeName.isNotEmpty) {
      try {
        final existing = await PlacementService().getPlacementByStoreAndDate(
          _currentPlacement.storeName,
          DateTime.now(),
        );
        if (mounted) {
          setState(() {
            if (existing != null) {
              _currentPlacement = existing;
            }
            prefetchData();
            _isLoading = false;
          });
          return;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void prefetchData() {
    listPlacement = KData.getListPlacement();
    for (var record in listPlacement) {
      switch (record.itemCode) {
        case 'cotc1':
          record.isPlaced = _currentPlacement.cotc1;
          record.isPlacedFromDB = _currentPlacement.cotc1;
          break;
        case 'cotc2':
          record.isPlaced = _currentPlacement.cotc2;
          record.isPlacedFromDB = _currentPlacement.cotc2;
          break;
        case 'cotc3':
          record.isPlaced = _currentPlacement.cotc3;
          record.isPlacedFromDB = _currentPlacement.cotc3;
          break;
        case 'cotc4':
          record.isPlaced = _currentPlacement.cotc4;
          record.isPlacedFromDB = _currentPlacement.cotc4;
          break;
        case 'cotc5':
          record.isPlaced = _currentPlacement.cotc5;
          record.isPlacedFromDB = _currentPlacement.cotc5;
          break;
        case 'cotc6':
          record.isPlaced = _currentPlacement.cotc6;
          record.isPlacedFromDB = _currentPlacement.cotc6;
          break;
        case 'cotc7':
          record.isPlaced = _currentPlacement.cotc7;
          record.isPlacedFromDB = _currentPlacement.cotc7;
          break;
        case 'cotc8':
          record.isPlaced = _currentPlacement.cotc8;
          record.isPlacedFromDB = _currentPlacement.cotc8;
          break;
        case 'cotc9':
          record.isPlaced = _currentPlacement.cotc9;
          record.isPlacedFromDB = _currentPlacement.cotc9;
          break;
        case 'cotc10':
          record.isPlaced = _currentPlacement.cotc10;
          record.isPlacedFromDB = _currentPlacement.cotc10;
          break;
        case 'cotc11':
          record.isPlaced = _currentPlacement.cotc11;
          record.isPlacedFromDB = _currentPlacement.cotc11;
          break;
        case 'cotc12':
          record.isPlaced = _currentPlacement.cotc12;
          record.isPlacedFromDB = _currentPlacement.cotc12;
          break;
      }
    }
  }

  void _toggleProduct(int index) {
    if (_isSaving) return;
    final item = listPlacement[index];

    // Do NOT allow unplacing items that were already placed and saved for this month
    if (item.isPlacedFromDB) {
      ShowMessage.error(
        context,
        '${item.itemName} is already placed for this month and cannot be unplaced.',
      );
      return;
    }

    setState(() {
      item.isPlaced = !item.isPlaced;
    });
  }

  void _placeAllRemaining() {
    if (_isSaving) return;
    setState(() {
      for (final item in listPlacement) {
        item.isPlaced = true;
      }
    });
  }

  Future<void> _savePlacement() async {
    if (_isSaving) return;

    final newlyPlacedCount = listPlacement.where((p) => p.isPlaced && !p.isPlacedFromDB).length;
    if (newlyPlacedCount == 0 && _currentPlacement.id.isNotEmpty) {
      ShowMessage.error(context, 'No new products to place.');
      return;
    }

    final currentMonthLabel = DateFormat('MMMM yyyy').format(DateTime.now());
    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Confirm Placement',
      message: 'Place $newlyPlacedCount product(s) for [${_currentPlacement.storeName}] for $currentMonthLabel?\n\n'
          'Note: Placed products cannot be unplaced until the end of the month.',
      confirmText: 'Place & Save',
      icon: Icons.check_circle_outline,
    );

    if (!confirmed || !mounted) return;

    setState(() => _isSaving = true);

    try {
      final placedCount = listPlacement.where((p) => p.isPlaced).length;
      final isFinished = listPlacement.isNotEmpty && placedCount == listPlacement.length;

      bool getFlag(String code) => listPlacement.where((p) => p.itemCode == code).firstOrNull?.isPlaced ?? false;

      final updated = _currentPlacement.copyWith(
        deliveryDate: Timestamp.now(), // Ensure deliveryDate is within current month
        cotc1: getFlag('cotc1'),
        cotc2: getFlag('cotc2'),
        cotc3: getFlag('cotc3'),
        cotc4: getFlag('cotc4'),
        cotc5: getFlag('cotc5'),
        cotc6: getFlag('cotc6'),
        cotc7: getFlag('cotc7'),
        cotc8: getFlag('cotc8'),
        cotc9: getFlag('cotc9'),
        cotc10: getFlag('cotc10'),
        cotc11: getFlag('cotc11'),
        cotc12: getFlag('cotc12'),
        isFinished: isFinished,
        progressCount: placedCount,
      );

      await PlacementService().savePlacement(updated);

      await Helperfunctions.logTransaction(
        'Placement Update - ${updated.storeName}',
        'Placed $placedCount of ${listPlacement.length} products for $currentMonthLabel.',
        LogAction.update,
      );

      if (!mounted) return;

      setState(() {
        _currentPlacement = updated;
        // Lock all placed products for the rest of the month
        for (final item in listPlacement) {
          if (item.isPlaced) {
            item.isPlacedFromDB = true;
          }
        }
      });

      ShowMessage.success(context, 'Successfully saved placement checklist for [${updated.storeName}]!');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ShowMessage.error(context, 'Failed to save placement checklist: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
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
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isFinished ? Icons.task_alt_rounded : Icons.storefront_outlined,
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
                      _currentPlacement.storeName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isFinished ? 'All products placed ($currentMonthLabel)' : 'Placement in progress ($currentMonthLabel)',
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
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
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$placedCount of $totalCount products placed',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
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
    final unplacedCount = listPlacement.where((p) => !p.isPlaced).length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monthly Product Checklist',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              'Placed products are locked for the month',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        if (unplacedCount > 0)
          FilledButton.tonalIcon(
            onPressed: _placeAllRemaining,
            icon: const Icon(Icons.done_all_rounded, size: 16),
            label: const Text('Place All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            ),
          ),
      ],
    );
  }

  Widget _buildProductCard(BuildContext context, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final placement = listPlacement[index];
    final isPlaced = placement.isPlaced;
    final isLocked = placement.isPlacedFromDB;
    final statusColor = isPlaced ? colorScheme.primary : colorScheme.error;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: isLocked
          ? colorScheme.primary.withValues(alpha: 0.08)
          : (isPlaced ? colorScheme.primary.withValues(alpha: 0.04) : colorScheme.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isLocked
              ? colorScheme.primary.withValues(alpha: 0.45)
              : (isPlaced ? colorScheme.primary.withValues(alpha: 0.3) : colorScheme.outlineVariant.withValues(alpha: 0.65)),
          width: isPlaced ? 1.4 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggleProduct(index),
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
                child: Image.asset(
                  placement.itemImagePath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.icecream_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      placement.itemName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 3),
                    if (isLocked)
                      Row(
                        children: [
                          Icon(Icons.lock_rounded, size: 12, color: colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Placed • Locked for this month',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    else if (isPlaced)
                      Text(
                        'Placed • Pending save',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.tertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text(
                        'Not placed • Tap to place',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isLocked)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded, size: 13, color: colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Placed',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Checkbox(
                  value: isPlaced,
                  activeColor: colorScheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  onChanged: (_) => _toggleProduct(index),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final newlyPlacedCount = listPlacement.where((p) => p.isPlaced && !p.isPlacedFromDB).length;
    final placedCount = listPlacement.where((p) => p.isPlaced).length;

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Placement',
        subtitle: _currentPlacement.storeName,
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else if (newlyPlacedCount > 0)
            IconButton(
              icon: const Icon(Icons.save_rounded, color: Colors.white),
              tooltip: 'Save placement',
              onPressed: _savePlacement,
            ),
        ],
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
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: FilledButton.icon(
            onPressed: (_isSaving || newlyPlacedCount == 0) ? null : _savePlacement,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(newlyPlacedCount > 0 ? Icons.check_circle_rounded : Icons.lock_rounded),
            label: Text(
              _isSaving
                  ? 'Saving Placement...'
                  : (newlyPlacedCount > 0
                      ? 'Save Placement ($newlyPlacedCount new product${newlyPlacedCount > 1 ? 's' : ''})'
                      : (placedCount == listPlacement.length
                          ? 'All Products Placed (Locked)'
                          : 'Placement Saved ($placedCount/12 Placed)')),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
    );
  }
}
