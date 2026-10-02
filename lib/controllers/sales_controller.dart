import 'package:selecta_ops/models/purchaseorder.dart';
import 'package:selecta_ops/services/purchaseorder_service.dart';

/// Data class holding aggregated sales summary for the current month.
class SalesSummary {
  final List<Purchaseorder> purchaseOrders;
  final double totalPurchaseOrder;
  final double totalInvoicedSales;
  final double totalOverpayment;
  final int totalInvoiceCount;
  final double averagePurchaseOrder;
  final double averageInvoicedAmount;
  final double averageOverpayment;

  const SalesSummary({
    required this.purchaseOrders,
    required this.totalPurchaseOrder,
    required this.totalInvoicedSales,
    required this.totalOverpayment,
    required this.totalInvoiceCount,
    required this.averagePurchaseOrder,
    required this.averageInvoicedAmount,
    required this.averageOverpayment,
  });

  factory SalesSummary.empty() => const SalesSummary(
        purchaseOrders: [],
        totalPurchaseOrder: 0,
        totalInvoicedSales: 0,
        totalOverpayment: 0,
        totalInvoiceCount: 0,
        averagePurchaseOrder: 0,
        averageInvoicedAmount: 0,
        averageOverpayment: 0,
      );
}

/// Controller handling sales business logic, monthly targets, fulfillment ratios, and search filtering.
class SalesController {
  static const double monthlyTarget = 1000000.0; // ₱1,000,000 target

  /// Fetches purchase orders for the current month and calculates key totals and averages.
  Future<SalesSummary> getSalesSummary() async {
    final orders = await PurchaseOrderService.getPurchaseOrdersForCurrentMonth();
    double purchaseOrderTotal = 0;
    double invoicedSalesTotal = 0;
    double overpaymentTotal = 0;

    for (final order in orders) {
      purchaseOrderTotal += order.orderAmount;
      invoicedSalesTotal += order.invoiceAmount;
      overpaymentTotal += order.overpayment;
    }

    // Sort newest invoice first
    orders.sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));

    final count = orders.length;
    return SalesSummary(
      purchaseOrders: orders,
      totalPurchaseOrder: purchaseOrderTotal,
      totalInvoicedSales: invoicedSalesTotal,
      totalOverpayment: overpaymentTotal,
      totalInvoiceCount: count,
      averagePurchaseOrder: count == 0 ? 0 : purchaseOrderTotal / count,
      averageInvoicedAmount: count == 0 ? 0 : invoicedSalesTotal / count,
      averageOverpayment: count == 0 ? 0 : overpaymentTotal / count,
    );
  }

  /// Filters purchase orders by invoice number based on user search query.
  List<Purchaseorder> filterOrders(List<Purchaseorder> orders, String query) {
    if (query.trim().isEmpty) return orders;
    final cleanQuery = query.trim().toLowerCase();
    return orders.where((order) {
      return order.invoiceNumber.toLowerCase().contains(cleanQuery);
    }).toList();
  }

  /// Calculates fulfillment ratio (invoiced / purchase order * 100).
  double calculateFulfillmentRatio(double totalInvoicedSales, double totalPurchaseOrder) {
    if (totalPurchaseOrder <= 0) return 0.0;
    return (totalInvoicedSales / totalPurchaseOrder) * 100;
  }

  /// Calculates progress towards monthly target clamped between 0.0 and 1.0.
  double calculateTargetProgress(double totalInvoicedSales, {double? target}) {
    final effectiveTarget = target ?? monthlyTarget;
    if (effectiveTarget <= 0) return 0.0;
    return (totalInvoicedSales / effectiveTarget).clamp(0.0, 1.0);
  }

  /// Calculates remaining amount needed to reach monthly target.
  double calculateRemainingAmount(double totalInvoicedSales, {double? target}) {
    final effectiveTarget = target ?? monthlyTarget;
    return (effectiveTarget - totalInvoicedSales).clamp(0.0, effectiveTarget);
  }
}
