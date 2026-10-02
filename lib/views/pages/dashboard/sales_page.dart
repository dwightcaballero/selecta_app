import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/sales_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/purchaseorder.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class SalesPage extends StatefulWidget {
  final double? monthlyTarget;
  const SalesPage({super.key, this.monthlyTarget});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  // Controller managing sales aggregation, targets, and filtering
  final SalesController _controller = SalesController();

  double get effectiveTarget => widget.monthlyTarget ?? SalesController.monthlyTarget;

  SalesSummary _summary = SalesSummary.empty();
  bool isLoading = true;
  String? errorMessage;
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Getters delegating directly to controller-managed summary
  List<Purchaseorder> get purchaseOrders => _summary.purchaseOrders;
  double get totalPurchaseOrder => _summary.totalPurchaseOrder;
  double get totalInvoicedSales => _summary.totalInvoicedSales;
  double get totalOverpayment => _summary.totalOverpayment;
  int get totalInvoiceCount => _summary.totalInvoiceCount;
  double get averagePurchaseOrder => _summary.averagePurchaseOrder;
  double get averageInvoicedAmount => _summary.averageInvoicedAmount;
  double get averageOverpayment => _summary.averageOverpayment;

  @override
  void initState() {
    super.initState();
    _loadPurchaseOrders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Load sales data via SalesController
  Future<void> _loadPurchaseOrders() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final summary = await _controller.getSalesSummary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Failed to load sales data: $e';
        isLoading = false;
      });
    }
  }

  // Filter purchase orders using SalesController
  List<Purchaseorder> get _filteredOrders => _controller.filterOrders(_summary.purchaseOrders, searchQuery);

  Widget _buildSummaryCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentMonthLabel = DateFormat('MMMM yyyy').format(DateTime.now());
    final progress = _controller.calculateTargetProgress(totalInvoicedSales, target: effectiveTarget);
    final remainingAmount = _controller.calculateRemainingAmount(totalInvoicedSales, target: effectiveTarget);
    final fulfillmentRatio = _controller.calculateFulfillmentRatio(totalInvoicedSales, totalPurchaseOrder);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(Icons.point_of_sale_outlined, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentMonthLabel,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.primary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Helperfunctions.formatDoubleAmountForDisplay(totalInvoicedSales),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text('Total invoiced sales', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_outlined, size: 14, color: colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '$totalInvoiceCount',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: colorScheme.primary,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Target: ${Helperfunctions.formatDoubleAmountForDisplay(effectiveTarget)} (${(progress * 100).toStringAsFixed(1)}%)',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
              Text(
                remainingAmount == 0 ? 'Goal achieved! 🎉' : 'Rem: ${Helperfunctions.formatDoubleAmountForDisplay(remainingAmount)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: remainingAmount == 0 ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (totalPurchaseOrder > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Order Fulfillment: ${fulfillmentRatio.toStringAsFixed(1)}% of PO amount',
              style: TextStyle(fontSize: 11, color: colorScheme.outline),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, {required String title, required IconData icon, required List<Widget> children}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, size: 19, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildMetricRow(BuildContext context, {required String label, required String value, required IconData icon, Color? valueColor}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor ?? colorScheme.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoicesSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final orders = _filteredOrders;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 19, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('Invoices (${orders.length})', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search invoice number...',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => searchQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
              ),
              onChanged: (val) => setState(() => searchQuery = val),
            ),
          ),
          const Divider(height: 12),
          if (orders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  searchQuery.isNotEmpty ? 'No invoices match your search' : 'No invoices for this month yet',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: orders.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) {
                final order = orders[index];
                final dateStr = DateFormat('MMM d, yyyy').format(order.invoiceDate.toDate());

                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                    child: Icon(Icons.receipt_long, size: 16, color: colorScheme.primary),
                  ),
                  title: Text(
                    order.invoiceNumber.isEmpty ? 'No Invoice #' : order.invoiceNumber,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  subtitle: Text(dateStr, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Helperfunctions.formatDoubleAmountForDisplay(order.invoiceAmount),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      if (order.overpayment > 0)
                        Text(
                          '+${Helperfunctions.formatDoubleAmountForDisplay(order.overpayment)} over',
                          style: TextStyle(fontSize: 11, color: colorScheme.error, fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppbar(title: 'Sales', subtitle: 'Monthly sales performance'),
      body: RefreshIndicator(
        onRefresh: _loadPurchaseOrders,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
                      const SizedBox(height: 12),
                      Text(errorMessage!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(onPressed: _loadPurchaseOrders, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _buildSummaryCard(context),
                  const SizedBox(height: 20),
                  _buildSection(
                    context,
                    title: 'Sales Overview',
                    icon: Icons.receipt_long_outlined,
                    children: [
                      _buildMetricRow(
                        context,
                        label: 'Purchase orders total',
                        value: Helperfunctions.formatDoubleAmountForDisplay(totalPurchaseOrder),
                        icon: Icons.shopping_bag_outlined,
                      ),
                      _buildMetricRow(
                        context,
                        label: 'Invoiced sales total',
                        value: Helperfunctions.formatDoubleAmountForDisplay(totalInvoicedSales),
                        icon: Icons.payments_outlined,
                        valueColor: Theme.of(context).colorScheme.primary,
                      ),
                      _buildMetricRow(context, label: 'Invoice count', value: '$totalInvoiceCount', icon: Icons.receipt_outlined),
                      _buildMetricRow(
                        context,
                        label: 'Total overpayment',
                        value: Helperfunctions.formatDoubleAmountForDisplay(totalOverpayment),
                        icon: Icons.money_off_csred_outlined,
                        valueColor: totalOverpayment > 0 ? Theme.of(context).colorScheme.error : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    context,
                    title: 'Average Per Invoice',
                    icon: Icons.analytics_outlined,
                    children: [
                      _buildMetricRow(
                        context,
                        label: 'Purchase order average',
                        value: Helperfunctions.formatDoubleAmountForDisplay(averagePurchaseOrder),
                        icon: Icons.shopping_bag_outlined,
                      ),
                      _buildMetricRow(
                        context,
                        label: 'Invoiced amount average',
                        value: Helperfunctions.formatDoubleAmountForDisplay(averageInvoicedAmount),
                        icon: Icons.trending_up_outlined,
                      ),
                      _buildMetricRow(
                        context,
                        label: 'Overpayment average',
                        value: Helperfunctions.formatDoubleAmountForDisplay(averageOverpayment),
                        icon: Icons.price_check_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInvoicesSection(context),
                ],
              ),
      ),
    );
  }
}
