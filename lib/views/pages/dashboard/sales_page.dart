import 'package:flutter/material.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/purchaseorder.dart';
import 'package:flutter_app/services/purchaseorder_service.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});
  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  List<Purchaseorder> purchaseOrders = [];
  double totalPurchaseOrder = 0;
  double totalInvoicedSales = 0;
  double totalOverpayment = 0;
  int totalInvoiceCount = 0;
  double averagePurchaseOrder = 0;
  double averageInvoicedAmount = 0;
  double averageOverpayment = 0;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPurchaseOrders();
  }

  Future<void> _loadPurchaseOrders() async {
    final orders = await PurchaseOrderService.getPurchaseOrdersForCurrentMonth();
    double purchaseOrderTotal = 0;
    double invoicedSalesTotal = 0;
    double overpaymentTotal = 0;

    for (final order in orders) {
      purchaseOrderTotal += order.orderAmount;
      invoicedSalesTotal += order.invoiceAmount;
      overpaymentTotal += order.overpayment;
    }

    if (!mounted) return;

    setState(() {
      purchaseOrders = orders;
      totalPurchaseOrder = purchaseOrderTotal;
      totalInvoicedSales = invoicedSalesTotal;
      totalOverpayment = overpaymentTotal;
      totalInvoiceCount = orders.length;
      averagePurchaseOrder = totalInvoiceCount == 0 ? 0 : totalPurchaseOrder / totalInvoiceCount;
      averageInvoicedAmount = totalInvoiceCount == 0 ? 0 : totalInvoicedSales / totalInvoiceCount;
      averageOverpayment = totalInvoiceCount == 0 ? 0 : totalOverpayment / totalInvoiceCount;
      isLoading = false;
    });
  }

  Widget _buildSummary(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(Icons.point_of_sale_outlined, color: colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This month', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                const SizedBox(height: 3),
                Text(
                  Helperfunctions.formatDoubleAmountForDisplay(totalInvoicedSales),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text('Total invoiced sales', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Text(
            '$totalInvoiceCount',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, {required String title, required IconData icon, required List<Widget> children}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppbar(title: 'Sales', subtitle: 'Monthly sales performance'),
      body: RefreshIndicator(
        onRefresh: _loadPurchaseOrders,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _buildSummary(context),
                  const SizedBox(height: 20),
                  _buildSection(
                    context,
                    title: 'Sales Overview',
                    icon: Icons.receipt_long_outlined,
                    children: [
                      _buildMetricRow(
                        context,
                        label: 'Purchase orders',
                        value: Helperfunctions.formatDoubleAmountForDisplay(totalPurchaseOrder),
                        icon: Icons.shopping_bag_outlined,
                      ),
                      _buildMetricRow(
                        context,
                        label: 'Invoiced sales',
                        value: Helperfunctions.formatDoubleAmountForDisplay(totalInvoicedSales),
                        icon: Icons.payments_outlined,
                        valueColor: Theme.of(context).colorScheme.primary,
                      ),
                      _buildMetricRow(context, label: 'Invoice count', value: '$totalInvoiceCount', icon: Icons.receipt_outlined),
                      _buildMetricRow(
                        context,
                        label: 'Overpayment',
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
                        label: 'Purchase order',
                        value: Helperfunctions.formatDoubleAmountForDisplay(averagePurchaseOrder),
                        icon: Icons.shopping_bag_outlined,
                      ),
                      _buildMetricRow(
                        context,
                        label: 'Invoiced amount',
                        value: Helperfunctions.formatDoubleAmountForDisplay(averageInvoicedAmount),
                        icon: Icons.trending_up_outlined,
                      ),
                      _buildMetricRow(
                        context,
                        label: 'Overpayment',
                        value: Helperfunctions.formatDoubleAmountForDisplay(averageOverpayment),
                        icon: Icons.price_check_outlined,
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
