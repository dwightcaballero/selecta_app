import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/po_extracted_line.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';
import 'package:selecta_ops/views/widgets/imageviewer_page.dart';

class PoPhase2ConfirmationCard extends StatelessWidget {
  final List<PoInvoiceDiscrepancyItem> comparisonDiscrepancies;
  final List<File> officialInvoiceImages;
  final bool isComparingWithAi;
  final void Function({required bool append, required List<InventoryItem> allInventory}) onShowOfficialInvoiceSourcePicker;
  final void Function(int index) onRemoveOfficialInvoiceImage;
  final TextEditingController officialInvoiceNumberController;
  final DateTime officialInvoiceDate;
  final VoidCallback onPickOfficialInvoiceDate;
  final TextEditingController officialInvoiceAmountController;
  final VoidCallback onInvoiceDetailsChanged;
  final double calculatedOverpayment;
  final NumberFormat currencyFormat;
  final List<PoExtractedLine> invoiceLines;
  final int invoiceSelectedTab;
  final ValueChanged<int> onTabChanged;
  final bool showMatchedItems;
  final VoidCallback onToggleMatchedItems;
  final void Function(int index, List<InventoryItem> allInventory, {required bool isInvoice}) onShowCorrectionDialog;
  final void Function(PoExtractedLine line) onQuantityDecrement;
  final void Function(PoExtractedLine line) onQuantityIncrement;
  final void Function(List<InventoryItem> allInventory, {required bool isInvoice}) onAddMissingLine;
  final List<InventoryItem> allInventory;

  const PoPhase2ConfirmationCard({
    super.key,
    required this.comparisonDiscrepancies,
    required this.officialInvoiceImages,
    required this.isComparingWithAi,
    required this.onShowOfficialInvoiceSourcePicker,
    required this.onRemoveOfficialInvoiceImage,
    required this.officialInvoiceNumberController,
    required this.officialInvoiceDate,
    required this.onPickOfficialInvoiceDate,
    required this.officialInvoiceAmountController,
    required this.onInvoiceDetailsChanged,
    required this.calculatedOverpayment,
    required this.currencyFormat,
    required this.invoiceLines,
    required this.invoiceSelectedTab,
    required this.onTabChanged,
    required this.showMatchedItems,
    required this.onToggleMatchedItems,
    required this.onShowCorrectionDialog,
    required this.onQuantityDecrement,
    required this.onQuantityIncrement,
    required this.onAddMissingLine,
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

    final shortages = comparisonDiscrepancies.where((d) => d.type == PoDiscrepancyType.shortage).toList();
    final missing = comparisonDiscrepancies.where((d) => d.type == PoDiscrepancyType.missing).toList();
    final excess = comparisonDiscrepancies.where((d) => d.type == PoDiscrepancyType.excess).toList();
    final extra = comparisonDiscrepancies.where((d) => d.type == PoDiscrepancyType.extra).toList();
    final matched = comparisonDiscrepancies.where((d) => d.type == PoDiscrepancyType.matched).toList();
    final int totalDiscrepancies = shortages.length + missing.length + excess.length + extra.length;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.teal.shade300, width: 1.5),
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
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.teal, Colors.green]),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.local_shipping_outlined, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Step 2: Attach Official Invoice & Stock Arrival', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                      Text('AI verifies invoice receipt items & reconciles with P.O.', style: TextStyle(fontSize: 11.5, color: Colors.teal)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 16),

            // Step 2 Invoice Pages Preview Strip
            if (officialInvoiceImages.isNotEmpty) ...[
              SizedBox(
                height: 75,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: officialInvoiceImages.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    if (i == officialInvoiceImages.length) {
                      return InkWell(
                        onTap: isComparingWithAi ? null : () => onShowOfficialInvoiceSourcePicker(append: true, allInventory: allInventory),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 60,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.teal.shade200),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.teal.withValues(alpha: 0.05),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_photo_alternate_outlined, size: 20, color: Colors.teal),
                              SizedBox(height: 2),
                              Text('+ Add', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal)),
                            ],
                          ),
                        ),
                      );
                    }

                    final file = officialInvoiceImages[i];
                    return Stack(
                      children: [
                        GestureDetector(
                          onTap: () => Helperfunctions.navigateTo(
                            context,
                            ImageViewerPage(image: file, networkImagePath: ''),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 60,
                              height: 75,
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
                              'P${i + 1}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: isComparingWithAi ? null : () => onRemoveOfficialInvoiceImage(i),
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

            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: isComparingWithAi ? null : () => onShowOfficialInvoiceSourcePicker(append: false, allInventory: allInventory),
                    icon: isComparingWithAi
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.document_scanner_outlined, size: 18),
                    label: Text(officialInvoiceImages.isEmpty
                        ? 'Scan / Upload Paper Invoice'
                        : 'Re-scan / Replace (${officialInvoiceImages.length} ${officialInvoiceImages.length == 1 ? "pg" : "pgs"})'),
                  ),
                ),
                if (officialInvoiceImages.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Add More Pages',
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                    onPressed: isComparingWithAi ? null : () => onShowOfficialInvoiceSourcePicker(append: true, allInventory: allInventory),
                  ),
                ],
              ],
            ),

            if (isComparingWithAi) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Sedy AI is reading invoice products and matching with catalog...',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.teal),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            const Text(
              'Supplier Official Invoice Details',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: officialInvoiceNumberController,
                    decoration: InputDecoration(
                      labelText: 'Official Invoice No.',
                      hintText: 'e.g. INV-100293',
                      prefixIcon: const Icon(Icons.receipt_outlined, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => onInvoiceDetailsChanged(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildDateField(
                    context: context,
                    label: 'Invoice Date',
                    date: officialInvoiceDate,
                    onTap: onPickOfficialInvoiceDate,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: officialInvoiceAmountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Official Invoice Total Amount',
                hintText: '0.00',
                prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (_) => onInvoiceDetailsChanged(),
            ),

            // ============================================================
            // Discrepancy & Overpayment Intelligence Section
            // ============================================================
            if (invoiceLines.isNotEmpty || comparisonDiscrepancies.isNotEmpty) ...[
              const SizedBox(height: 14),

              // Overpayment & Discrepancy Highlight Banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: calculatedOverpayment > 0
                      ? Colors.amber.shade50
                      : totalDiscrepancies > 0
                          ? Colors.orange.shade50
                          : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: calculatedOverpayment > 0
                        ? Colors.amber.shade300
                        : totalDiscrepancies > 0
                            ? Colors.orange.shade300
                            : Colors.green.shade300,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          calculatedOverpayment > 0
                              ? Icons.account_balance_wallet_outlined
                              : totalDiscrepancies > 0
                                  ? Icons.warning_amber_rounded
                                  : Icons.verified_rounded,
                          color: calculatedOverpayment > 0
                              ? Colors.amber.shade900
                              : totalDiscrepancies > 0
                                  ? Colors.orange.shade900
                                  : Colors.green.shade800,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            calculatedOverpayment > 0
                                ? 'Overpayment Credit: ${currencyFormat.format(calculatedOverpayment)}'
                                : totalDiscrepancies > 0
                                    ? 'Quantity Discrepancies Detected ($totalDiscrepancies items)'
                                    : 'Exact Match — No Discrepancies',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: calculatedOverpayment > 0
                                  ? Colors.amber.shade900
                                  : totalDiscrepancies > 0
                                      ? Colors.orange.shade900
                                      : Colors.green.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      calculatedOverpayment > 0
                          ? 'Dealer overpaid supplier by ${currencyFormat.format(calculatedOverpayment)} due to undelivered or shorted items. This amount is recorded as an overpayment credit and can be deducted from future purchase orders.'
                          : totalDiscrepancies > 0
                              ? 'Delivered quantities on the invoice differ from the original P.O. Order amount and invoice match, so no overpayment credit is recorded.'
                              : 'All ${comparisonDiscrepancies.length} products and quantities read on the invoice match the original P.O. exactly.',
                      style: TextStyle(
                        fontSize: 12,
                        color: calculatedOverpayment > 0
                            ? Colors.amber.shade900
                            : totalDiscrepancies > 0
                                ? Colors.orange.shade900
                                : Colors.green.shade900,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Summary Metrics Row
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Invoiced Units', style: TextStyle(fontSize: 10.5, color: Colors.grey, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('${invoiceLines.fold(0, (acc, l) => acc + l.quantity)} pcs', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: (shortages.length + missing.length) > 0 ? Colors.red.shade50 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Shortages', style: TextStyle(fontSize: 10.5, color: (shortages.length + missing.length) > 0 ? Colors.red.shade700 : Colors.grey, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('${shortages.length + missing.length}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: (shortages.length + missing.length) > 0 ? Colors.red.shade800 : Colors.black87)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: (excess.length + extra.length) > 0 ? Colors.blue.shade50 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Excess', style: TextStyle(fontSize: 10.5, color: (excess.length + extra.length) > 0 ? Colors.blue.shade700 : Colors.grey, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('${excess.length + extra.length}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: (excess.length + extra.length) > 0 ? Colors.blue.shade800 : Colors.black87)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: matched.isNotEmpty ? Colors.green.shade50 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Matched', style: TextStyle(fontSize: 10.5, color: matched.isNotEmpty ? Colors.green.shade700 : Colors.grey, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('${matched.length}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: matched.isNotEmpty ? Colors.green.shade800 : Colors.black87)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Segmented Tab Selector: Discrepancies vs Invoice Lines
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => onTabChanged(0),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: invoiceSelectedTab == 0 ? Colors.teal : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: invoiceSelectedTab == 0 ? Colors.teal : Colors.grey.shade300),
                        ),
                        child: Center(
                          child: Text(
                            'Discrepancies ($totalDiscrepancies)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: invoiceSelectedTab == 0 ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () => onTabChanged(1),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: invoiceSelectedTab == 1 ? Colors.teal : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: invoiceSelectedTab == 1 ? Colors.teal : Colors.grey.shade300),
                        ),
                        child: Center(
                          child: Text(
                            'Invoice Items (${invoiceLines.length})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: invoiceSelectedTab == 1 ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // TAB 0: Discrepancies Breakdown
              if (invoiceSelectedTab == 0) ...[
                if (totalDiscrepancies == 0)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No discrepancies! All invoiced items match P.O. quantities.',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.green),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: comparisonDiscrepancies.where((d) => d.type != PoDiscrepancyType.matched).length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (ctx, idx) {
                      final item = comparisonDiscrepancies.where((d) => d.type != PoDiscrepancyType.matched).toList()[idx];

                      Color badgeColor;
                      Color badgeTextColor;
                      String badgeText;

                      switch (item.type) {
                        case PoDiscrepancyType.shortage:
                          badgeColor = Colors.amber.shade100;
                          badgeTextColor = Colors.amber.shade900;
                          badgeText = 'SHORTAGE: -${item.differenceQuantity}';
                          break;
                        case PoDiscrepancyType.missing:
                          badgeColor = Colors.red.shade100;
                          badgeTextColor = Colors.red.shade900;
                          badgeText = 'NOT DELIVERED (-${item.orderedQuantity})';
                          break;
                        case PoDiscrepancyType.excess:
                          badgeColor = Colors.blue.shade100;
                          badgeTextColor = Colors.blue.shade900;
                          badgeText = 'EXCESS: +${item.differenceQuantity}';
                          break;
                        case PoDiscrepancyType.extra:
                          badgeColor = Colors.purple.shade100;
                          badgeTextColor = Colors.purple.shade900;
                          badgeText = 'EXTRA ITEM (+${item.invoicedQuantity})';
                          break;
                        case PoDiscrepancyType.matched:
                          badgeColor = Colors.green.shade100;
                          badgeTextColor = Colors.green.shade900;
                          badgeText = 'MATCHED';
                          break;
                      }

                      final invoiceIdx = invoiceLines.indexWhere((l) =>
                          l.productId == item.productId ||
                          (l.rawDocText.isNotEmpty && item.rawDocText.isNotEmpty && l.rawDocText == item.rawDocText));

                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                CachedProductImage(imageUrl: item.imageUrl, size: 40),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.productName,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(6)),
                                            child: Text(badgeText, style: TextStyle(color: badgeTextColor, fontWeight: FontWeight.bold, fontSize: 10.5)),
                                          ),
                                        ],
                                      ),
                                      if (item.rawDocText.isNotEmpty && item.rawDocText != item.productName) ...[
                                        const SizedBox(height: 5),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.amber.shade200),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(top: 2),
                                                child: Icon(Icons.receipt_long_outlined, size: 13, color: Colors.amber.shade900),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text.rich(
                                                  TextSpan(
                                                    children: [
                                                      TextSpan(
                                                        text: 'Actual Invoice: ',
                                                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                                      ),
                                                      TextSpan(
                                                        text: item.rawDocText,
                                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Ordered: ${item.orderedQuantity}  ➔  Invoiced: ${item.invoicedQuantity}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: item.invoicedQuantity < item.orderedQuantity ? Colors.red.shade700 : Colors.teal.shade800,
                                            ),
                                          ),
                                          Text(
                                            item.costDifference < 0
                                                ? '-${currencyFormat.format(item.costDifference.abs())}'
                                                : item.costDifference > 0
                                                    ? '+${currencyFormat.format(item.costDifference)}'
                                                    : currencyFormat.format(item.orderedTotal),
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.bold,
                                              color: item.costDifference < 0 ? Colors.red.shade700 : Colors.teal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (invoiceIdx != -1) ...[
                              const Divider(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  InkWell(
                                    onTap: () => onShowCorrectionDialog(invoiceIdx, allInventory, isInvoice: true),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.swap_horiz_rounded, size: 14, color: colorScheme.primary),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Assign Selecta Equivalent',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),

                // Collapsible Matched Items Section
                if (matched.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: onToggleMatchedItems,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${matched.length} Matched Items (Quantities Match P.O.)',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(showMatchedItems ? Icons.expand_less : Icons.expand_more, color: Colors.green, size: 18),
                        ],
                      ),
                    ),
                  ),
                  if (showMatchedItems) ...[
                    const SizedBox(height: 6),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: matched.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (ctx, idx) {
                        final m = matched[idx];
                        final mInvoiceIdx = invoiceLines.indexWhere((l) =>
                            l.productId == m.productId ||
                            (l.rawDocText.isNotEmpty && m.rawDocText.isNotEmpty && l.rawDocText == m.rawDocText));
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              CachedProductImage(imageUrl: m.imageUrl, size: 30),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.productName, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                    if (m.rawDocText.isNotEmpty && m.rawDocText != m.productName) ...[
                                      const SizedBox(height: 2),
                                      Text('Invoice: "${m.rawDocText}"', style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500)),
                                    ],
                                  ],
                                ),
                              ),
                              Text('${m.invoicedQuantity} pcs', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal)),
                              if (mInvoiceIdx != -1) ...[
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                                  tooltip: 'Change Selecta Equivalent',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                  onPressed: () => onShowCorrectionDialog(mInvoiceIdx, allInventory, isInvoice: true),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ],

              // TAB 1: Invoice Receipt Items (with accuracy check & dealer verification)
              if (invoiceSelectedTab == 1) ...[
                const SizedBox(height: 4),
                const Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.grey),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Check if AI read the invoice receipt correctly. Use steppers or edit to correct.',
                        style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: invoiceLines.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (ctx, index) {
                    final line = invoiceLines[index];
                    final String actualInvoiceName = line.rawDocText.isNotEmpty ? line.rawDocText : line.productName;

                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Prominent Actual Invoice Product Name
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(Icons.receipt_long_outlined, size: 14, color: Colors.amber.shade900),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'INVOICE: ',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.amber.shade900,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      TextSpan(
                                        text: actualInvoiceName,
                                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (line.isCorrected)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(4)),
                                  child: Text('✓ Reassigned', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                                ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // 2. Assigned Selecta Product Equivalent Row
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              CachedProductImage(imageUrl: line.imageUrl, size: 40),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: Colors.teal.shade50,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.teal.shade200),
                                          ),
                                          child: Text(
                                            'SELECTA EQUIVALENT',
                                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.teal.shade800),
                                          ),
                                        ),
                                        if (line.category.isNotEmpty) ...[
                                          const SizedBox(width: 4),
                                          Text('• ${line.category}', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      line.productName,
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${currencyFormat.format(line.buyingPrice)} × ${line.quantity} = ${currencyFormat.format(line.lineTotal)}',
                                      style: TextStyle(fontSize: 11.5, color: colorScheme.primary, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              // Stepper for quantity
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(6),
                                  color: Colors.white,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    InkWell(
                                      onTap: () => onQuantityDecrement(line),
                                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(5)),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(Icons.remove, size: 14),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Text('${line.quantity}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    ),
                                    InkWell(
                                      onTap: () => onQuantityIncrement(line),
                                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(5)),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(Icons.add, size: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 6),
                          const Divider(height: 8),

                          // 3. Button to Assign / Change Equivalent
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => onShowCorrectionDialog(index, allInventory, isInvoice: true),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)),
                                ),
                                icon: const Icon(Icons.swap_horiz_rounded, size: 15),
                                label: const Text('Assign / Change Selecta Equivalent', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => onAddMissingLine(allInventory, isInvoice: true),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Item Missed by AI to Invoice', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(double.infinity, 36),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
