import 'package:flutter/material.dart';
import 'package:flutter_app/data/data.dart';
import 'package:flutter_app/models/placement.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

class PlacementPage extends StatefulWidget {
  final Placement placement;
  const PlacementPage({super.key, required this.placement});

  @override
  State<PlacementPage> createState() => _PlacementPageState();
}

class _PlacementPageState extends State<PlacementPage> {
  List<KPlacement> listPlacement = [];

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  void prefetchData() {
    listPlacement = KData.getListPlacement();
    for (var record in listPlacement) {
      switch (record.itemCode) {
        case 'cotc1':
          if (widget.placement.cotc1) record.isPlaced = widget.placement.cotc1;
          break;
        case 'cotc2':
          if (widget.placement.cotc2) record.isPlaced = widget.placement.cotc2;
          break;
        case 'cotc3':
          if (widget.placement.cotc3) record.isPlaced = widget.placement.cotc3;
          break;
        case 'cotc4':
          if (widget.placement.cotc4) record.isPlaced = widget.placement.cotc4;
          break;
        case 'cotc5':
          if (widget.placement.cotc5) record.isPlaced = widget.placement.cotc5;
          break;
        case 'cotc6':
          if (widget.placement.cotc6) record.isPlaced = widget.placement.cotc6;
          break;
        case 'cotc7':
          if (widget.placement.cotc7) record.isPlaced = widget.placement.cotc7;
          break;
        case 'cotc8':
          if (widget.placement.cotc8) record.isPlaced = widget.placement.cotc8;
          break;
        case 'cotc9':
          if (widget.placement.cotc9) record.isPlaced = widget.placement.cotc9;
          break;
        case 'cotc10':
          if (widget.placement.cotc10) record.isPlaced = widget.placement.cotc10;
          break;
        case 'cotc11':
          if (widget.placement.cotc11) record.isPlaced = widget.placement.cotc11;
          break;
        case 'cotc12':
          if (widget.placement.cotc12) record.isPlaced = widget.placement.cotc12;
          break;
      }
    }
  }

  Widget _buildProgressHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = (widget.placement.progressCount / listPlacement.length).clamp(0.0, 1.0);
    final statusColor = widget.placement.isFinished ? colorScheme.primary : colorScheme.tertiary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
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
                child: Icon(widget.placement.isFinished ? Icons.task_alt_rounded : Icons.storefront_outlined, color: statusColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.placement.storeName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(
                      widget.placement.isFinished ? 'Placement completed' : 'Placement in progress',
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                '${widget.placement.progressCount}/${listPlacement.length}',
                style: TextStyle(fontWeight: FontWeight.bold, color: statusColor),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: progress, minHeight: 7, backgroundColor: colorScheme.surfaceContainerHighest, color: statusColor),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.placement.progressCount} of ${listPlacement.length} products placed',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, KPlacement placement) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = placement.isPlaced ? colorScheme.primary : colorScheme.error;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(10)),
              child: Image.asset(placement.itemImagePath, fit: BoxFit.contain),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(placement.itemName, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                Icon(placement.isPlaced ? Icons.check_circle_rounded : Icons.cancel_outlined, color: statusColor, size: 22),
                const SizedBox(height: 3),
                Text(
                  placement.isPlaced ? 'Placed' : 'Missing',
                  style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(title: 'Placement', subtitle: widget.placement.storeName),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: listPlacement.length + 2,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) return _buildProgressHeader(context);
          if (index == 1) {
            return Text('Product placement checklist', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold));
          }
          return _buildProductCard(context, listPlacement[index - 2]);
        },
      ),
    );
  }
}
