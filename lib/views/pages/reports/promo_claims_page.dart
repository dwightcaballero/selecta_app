import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/responsive.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/export_report_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';

/// Supplier Promo Claims Report page.
///
/// Collects and aggregates all completed deliveries where supplier-funded
/// promotional discounts or free reward items were availed, allowing dealers
/// to audit and export claims for supplier reimbursement.
class PromoClaimsPage extends StatefulWidget {
  const PromoClaimsPage({super.key});

  @override
  State<PromoClaimsPage> createState() => _PromoClaimsPageState();
}

class _PromoClaimsPageState extends State<PromoClaimsPage> {
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  final DateFormat _dateFormat = DateFormat('MMM dd, yyyy');

  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();
  final String _selectedSupplier = 'all';
  bool _isLoading = false;

  List<_ClaimRow> _claims = [];
  double _totalClaimAmount = 0.0;
  int _totalPromoSets = 0;
  int _totalFreeItems = 0;
  final Set<String> _distinctStores = {};

  @override
  void initState() {
    super.initState();
    _loadClaims();
  }

  Future<void> _loadClaims() async {
    setState(() => _isLoading = true);
    try {
      final startTimestamp = Timestamp.fromDate(DateTime(_startDate.year, _startDate.month, _startDate.day, 0, 0, 0));
      final endTimestamp = Timestamp.fromDate(DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59));

      // Query delivered orders within date range
      final snap = await FirebaseFirestore.instance
          .collection(DELIVERY_COLLECTION_REF)
          .where('transactionStatus', isEqualTo: DeliveryStatus.delivered)
          .where('deliveryDate', isGreaterThanOrEqualTo: startTimestamp)
          .where('deliveryDate', isLessThanOrEqualTo: endTimestamp)
          .get();

      final List<_ClaimRow> rows = [];
      double totalClaim = 0.0;
      int totalSets = 0;
      int totalFree = 0;
      final Set<String> stores = {};

      for (final doc in snap.docs) {
        final delivery = Delivery.fromSnapshot(doc);
        if (delivery.appliedPromos.isEmpty) continue;

        for (final promo in delivery.appliedPromos) {
          // Check if supplier-funded
          if (promo.fundedBy != 'supplier') continue;

          final suppName = promo.supplierName ?? 'Unilever';
          if (_selectedSupplier != 'all' && suppName.toLowerCase() != _selectedSupplier.toLowerCase()) {
            continue;
          }

          // Count free items
          int freeItemCount = 0;
          final List<String> freeItemNames = [];
          for (final item in delivery.items) {
            if (item.isFreeReward && item.promoId == promo.promoId) {
              final deliveredQty = item.deliveredQuantity > 0 ? item.deliveredQuantity : item.pickedQuantity;
              if (deliveredQty > 0) {
                freeItemCount += deliveredQty;
                freeItemNames.add('${deliveredQty}x ${item.productName}');
              }
            }
          }

          final claimAmount = promo.discountAmount;
          totalClaim += claimAmount;
          totalSets += promo.timesApplied;
          totalFree += freeItemCount;
          stores.add(delivery.storeName);

          final docRefId = doc.id;
          final shortRef = docRefId.length >= 8 ? docRefId.substring(0, 8).toUpperCase() : docRefId.toUpperCase();

          rows.add(_ClaimRow(
            deliveryId: docRefId,
            deliveryRef: shortRef,
            storeName: delivery.storeName,
            deliveryDate: delivery.deliveryDate?.toDate() ?? DateTime.now(),
            promoId: promo.promoId,
            promoName: promo.name,
            supplierName: suppName,
            timesApplied: promo.timesApplied,
            claimAmount: claimAmount,
            freeItemCount: freeItemCount,
            freeItemsDescription: freeItemNames.join(', '),
          ));
        }
      }

      // Sort rows by date descending
      rows.sort((a, b) => b.deliveryDate.compareTo(a.deliveryDate));

      if (mounted) {
        setState(() {
          _claims = rows;
          _totalClaimAmount = totalClaim;
          _totalPromoSets = totalSets;
          _totalFreeItems = totalFree;
          _distinctStores
            ..clear()
            ..addAll(stores);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ShowMessage.error(context, 'Failed to load promo claims: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isTablet = ScreenSize.isTabletLandscape(context);

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Supplier Promo Claims',
        subtitle: 'Audit & export supplier-funded promo discounts',
        actions: [
          AsyncIconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export CSV',
            onPressed: _claims.isEmpty ? null : _exportCsv,
          ),
          AsyncIconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadClaims,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.all(12),
            color: colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDateRange,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 16, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_dateFormat.format(_startDate)} – ${_dateFormat.format(_endDate)}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Summary Metrics Cards
          Container(
            padding: const EdgeInsets.all(12),
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
            child: Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    label: 'Claim Amount',
                    value: _currencyFormat.format(_totalClaimAmount),
                    color: const Color(0xFF16A34A),
                    icon: Icons.monetization_on_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricTile(
                    label: 'Promo Sets',
                    value: '$_totalPromoSets sets',
                    color: Colors.blue.shade700,
                    icon: Icons.layers_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricTile(
                    label: 'Free Items',
                    value: '$_totalFreeItems pcs',
                    color: Colors.purple.shade700,
                    icon: Icons.card_giftcard_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricTile(
                    label: 'Stores',
                    value: '${_distinctStores.length}',
                    color: Colors.amber.shade800,
                    icon: Icons.storefront_outlined,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content List / Table
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _claims.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 52, color: colorScheme.outline),
                              const SizedBox(height: 12),
                              const Text('No Supplier Claims Found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(
                                'No completed deliveries with supplier-funded promos match the selected date range.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, isTablet ? 24 : 80),
                        itemCount: _claims.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final claim = _claims[index];
                          return _buildClaimCard(claim, colorScheme);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildClaimCard(_ClaimRow claim, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                claim.storeName,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              Text(
                _currencyFormat.format(claim.claimAmount),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF16A34A)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  claim.promoName,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${claim.timesApplied}x set',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                _dateFormat.format(claim.deliveryDate),
                style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          if (claim.freeItemsDescription.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.card_giftcard, size: 14, color: Color(0xFF16A34A)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Free Items: ${claim.freeItemsDescription}',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF15803D)),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Ref: #${claim.deliveryRef} • Supplier: ${claim.supplierName}',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadClaims();
    }
  }

  Future<void> _exportCsv() async {
    try {
      final headers = [
        'Delivery Reference',
        'Store Name',
        'Delivery Date',
        'Supplier',
        'Promo Campaign',
        'Sets Applied',
        'Free Reward Items',
        'Claimable Amount (PHP)',
      ];

      final rows = <List<dynamic>>[];
      for (final c in _claims) {
        rows.add([
          c.deliveryRef,
          c.storeName,
          DateFormat('yyyy-MM-dd').format(c.deliveryDate),
          c.supplierName,
          c.promoName,
          c.timesApplied,
          c.freeItemsDescription,
          c.claimAmount.toStringAsFixed(2),
        ]);
      }

      // Add summary row
      rows.add([]);
      rows.add(['TOTAL', '', '', '', '', _totalPromoSets, '$_totalFreeItems pcs', _totalClaimAmount.toStringAsFixed(2)]);

      final csvContent = ExportReportService.buildCsv(headers, rows);
      final directory = await getApplicationDocumentsDirectory();
      final filename = 'Supplier_Promo_Claims_${DateFormat('yyyyMMdd').format(_startDate)}_${DateFormat('yyyyMMdd').format(_endDate)}.csv';
      final file = File('${directory.path}/$filename');
      await file.writeAsString(csvContent);

      await OpenFilex.open(file.path);
      if (mounted) ShowMessage.success(context, 'Exported $filename successfully');
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to export CSV: $e');
    }
  }
}

class _ClaimRow {
  final String deliveryId;
  final String deliveryRef;
  final String storeName;
  final DateTime deliveryDate;
  final String promoId;
  final String promoName;
  final String supplierName;
  final int timesApplied;
  final double claimAmount;
  final int freeItemCount;
  final String freeItemsDescription;

  _ClaimRow({
    required this.deliveryId,
    required this.deliveryRef,
    required this.storeName,
    required this.deliveryDate,
    required this.promoId,
    required this.promoName,
    required this.supplierName,
    required this.timesApplied,
    required this.claimAmount,
    required this.freeItemCount,
    required this.freeItemsDescription,
  });
}
