import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/views/widgets/imageviewer_page.dart';

class PoReconciliationHeader extends StatelessWidget {
  final bool isNewRecord;
  final TextEditingController orderNumberController;
  final DateTime selectedOrderDate;
  final VoidCallback onPickOrderDate;
  final ValueChanged<String>? onOrderNumberChanged;
  final double docTotalAmountRead;
  final int docTotalUnitsRead;
  final double currentListTotalCost;
  final int currentListUnits;
  final int currentListCount;
  final bool showDetailsCard;
  final VoidCallback onToggleDetailsCard;
  final List<File> pickedImages;
  final String networkImagePath;
  final File? pickedImage;
  final bool isAnalyzingWithAi;
  final String? aiExtractionSummary;
  final void Function({required bool append, required List<InventoryItem> allInventory}) onShowImageSourcePicker;
  final void Function(int index) onRemoveImage;
  final NumberFormat currencyFormat;
  final List<InventoryItem> allInventory;

  const PoReconciliationHeader({
    super.key,
    required this.isNewRecord,
    required this.orderNumberController,
    required this.selectedOrderDate,
    required this.onPickOrderDate,
    this.onOrderNumberChanged,
    required this.docTotalAmountRead,
    required this.docTotalUnitsRead,
    required this.currentListTotalCost,
    required this.currentListUnits,
    required this.currentListCount,
    required this.showDetailsCard,
    required this.onToggleDetailsCard,
    required this.pickedImages,
    required this.networkImagePath,
    this.pickedImage,
    required this.isAnalyzingWithAi,
    this.aiExtractionSummary,
    required this.onShowImageSourcePicker,
    required this.onRemoveImage,
    required this.currencyFormat,
    required this.allInventory,
  });

  Widget _buildDateField({
    required BuildContext context,
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        child: Text(
          DateFormat('MMM dd, yyyy').format(date),
          style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasDocTotal = docTotalAmountRead > 0;
    final double diff = (currentListTotalCost - docTotalAmountRead).abs();
    final bool isTotalMatch = hasDocTotal && diff < 0.05;
    final bool isUnitsMatch = docTotalUnitsRead > 0 && currentListUnits == docTotalUnitsRead;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.receipt_long_rounded, size: 20, color: Colors.orange.shade800),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isNewRecord ? 'Purchase Order Document' : 'PO #${orderNumberController.text}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        isNewRecord ? 'Document Verification Mode' : '🟡 Pending — Awaiting invoice arrival',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(showDetailsCard ? Icons.expand_less : Icons.expand_more),
                  onPressed: onToggleDetailsCard,
                ),
              ],
            ),
            if (showDetailsCard) ...[
              const Divider(height: 18),

              // Screenshots / Pages Preview Strip
              if (pickedImages.isNotEmpty) ...[
                SizedBox(
                  height: 82,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: pickedImages.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      if (i == pickedImages.length) {
                        return InkWell(
                          onTap: isAnalyzingWithAi ? null : () => onShowImageSourcePicker(append: true, allInventory: allInventory),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 65,
                            decoration: BoxDecoration(
                              border: Border.all(color: colorScheme.outlineVariant),
                              borderRadius: BorderRadius.circular(10),
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined, size: 22, color: colorScheme.primary),
                                const SizedBox(height: 2),
                                Text(
                                  '+ Add Page',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final file = pickedImages[i];
                      return Stack(
                        children: [
                          GestureDetector(
                            onTap: () => Helperfunctions.navigateTo(
                              context,
                              ImageViewerPage(image: file, networkImagePath: ''),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 65,
                                height: 82,
                                color: Colors.black12,
                                child: Image.file(file, fit: BoxFit.cover),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 2,
                            left: 2,
                            right: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Page ${i + 1}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: GestureDetector(
                              onTap: isAnalyzingWithAi ? null : () => onRemoveImage(i),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                                child: const Icon(Icons.close, size: 12, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Scan Action Button
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isAnalyzingWithAi ? null : () => onShowImageSourcePicker(append: false, allInventory: allInventory),
                      icon: const Icon(Icons.document_scanner_outlined, size: 18),
                      label: Text(
                        pickedImages.isNotEmpty
                            ? 'Re-scan / Replace (${pickedImages.length} ${pickedImages.length == 1 ? "page" : "pages"})'
                            : (networkImagePath.isNotEmpty ? 'Re-scan Document' : 'Scan / Upload Screenshots'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  if (pickedImages.isNotEmpty || networkImagePath.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'View Document',
                      icon: const Icon(Icons.fullscreen_rounded, size: 20),
                      onPressed: () => Helperfunctions.navigateTo(
                        context,
                        ImageViewerPage(image: pickedImage, networkImagePath: networkImagePath),
                      ),
                    ),
                  ],
                ],
              ),

              if (isAnalyzingWithAi) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          pickedImages.length > 1
                              ? 'Sedy AI is reading ${pickedImages.length} screenshots & matching catalog...'
                              : 'Sedy AI is reading document & matching catalog...',
                          style: TextStyle(fontSize: 12.5, color: colorScheme.primary, fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (aiExtractionSummary != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          aiExtractionSummary!,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // Document vs Verified List Comparison Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isTotalMatch
                      ? Colors.green.withValues(alpha: 0.08)
                      : hasDocTotal
                          ? Colors.amber.withValues(alpha: 0.1)
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isTotalMatch
                        ? Colors.green.shade400
                        : hasDocTotal
                            ? Colors.amber.shade600
                            : colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isTotalMatch
                                  ? Icons.check_circle_rounded
                                  : hasDocTotal
                                      ? Icons.warning_amber_rounded
                                      : Icons.receipt_outlined,
                              size: 18,
                              color: isTotalMatch
                                  ? Colors.green.shade800
                                  : hasDocTotal
                                      ? Colors.amber.shade900
                                      : colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isTotalMatch
                                  ? 'DOCUMENT TOTALS MATCH'
                                  : hasDocTotal
                                      ? 'TOTALS MISMATCH'
                                      : 'DOCUMENT TOTALS',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: isTotalMatch
                                    ? Colors.green.shade800
                                    : hasDocTotal
                                        ? Colors.amber.shade900
                                        : colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        if (hasDocTotal && !isTotalMatch)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade200,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Diff: ${currencyFormat.format(diff)}',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // AI Read Column
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Document (Read by AI)', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 2),
                              Text(
                                hasDocTotal ? currencyFormat.format(docTotalAmountRead) : '—',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                              ),
                              Text(
                                docTotalUnitsRead > 0 ? '$docTotalUnitsRead units read' : '—',
                                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 38, color: colorScheme.outlineVariant),
                        // Current Verified List Column
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Current Verified List', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                                const SizedBox(height: 2),
                                Text(
                                  currencyFormat.format(currentListTotalCost),
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: colorScheme.primary),
                                ),
                                Text(
                                  '$currentListCount items • $currentListUnits units',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isUnitsMatch ? FontWeight.bold : FontWeight.normal,
                                    color: isUnitsMatch ? Colors.green.shade700 : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              // Document References Row (P.O. Number & P.O. Date)
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: orderNumberController,
                      decoration: InputDecoration(
                        labelText: 'P.O. Number',
                        hintText: 'e.g. PO-2026-001 or HM30471505',
                        prefixIcon: const Icon(Icons.tag, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      textCapitalization: TextCapitalization.characters,
                      onChanged: onOrderNumberChanged,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildDateField(
                      context: context,
                      label: 'P.O. Date',
                      date: selectedOrderDate,
                      onTap: onPickOrderDate,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
