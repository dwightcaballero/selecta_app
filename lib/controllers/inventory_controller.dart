import 'package:selecta_ops/models/floating_stock.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/services/inventory_service.dart';

/// Aggregated metrics for the dealer's active inventory.
class InventorySummary {
  final int totalProducts;
  final int totalUnits;
  final int totalIncomingUnits;
  final int totalReservedUnits;
  final int totalAvailableUnits;
  final double totalCostValue;
  final double totalRetailValue;
  final int lowStockCount;
  final int outOfStockCount;

  const InventorySummary({
    required this.totalProducts,
    required this.totalUnits,
    this.totalIncomingUnits = 0,
    this.totalReservedUnits = 0,
    this.totalAvailableUnits = 0,
    required this.totalCostValue,
    required this.totalRetailValue,
    required this.lowStockCount,
    required this.outOfStockCount,
  });

  double get estimatedMarginValue => totalRetailValue - totalCostValue;
  int get needsRestockCount => lowStockCount + outOfStockCount;
}

/// Controller mediating between [InventoryService] and [InventoryPage].
class InventoryController {
  final InventoryService _service = InventoryService();

  /// Stream of all active products across Selecta and Other Products.
  Stream<List<InventoryItem>> getActiveInventoryStream() =>
      _service.getActiveInventoryStream();

  /// Computes summary KPIs for a list of [InventoryItem]s.
  InventorySummary computeSummary(List<InventoryItem> items) {
    int totalUnits = 0;
    int totalIncoming = 0;
    int totalReserved = 0;
    int totalAvailable = 0;
    double totalCost = 0.0;
    double totalRetail = 0.0;
    int lowStock = 0;
    int outOfStock = 0;

    final activeItems = items.where((item) => item.isActive).toList();

    for (final item in activeItems) {
      totalUnits += item.stockQuantity;
      totalIncoming += item.incomingQuantity;
      totalReserved += item.reservedQuantity;
      totalAvailable += item.availableQuantity;
      totalCost += item.stockCostValue;
      totalRetail += item.stockRetailValue;
      if (item.isOutOfStock) {
        outOfStock++;
      } else if (item.isLowStock) {
        lowStock++;
      }
    }

    return InventorySummary(
      totalProducts: activeItems.length,
      totalUnits: totalUnits,
      totalIncomingUnits: totalIncoming,
      totalReservedUnits: totalReserved,
      totalAvailableUnits: totalAvailable,
      totalCostValue: totalCost,
      totalRetailValue: totalRetail,
      lowStockCount: lowStock,
      outOfStockCount: outOfStock,
    );
  }

  /// Updates the stock quantity (and optional low stock threshold) of an [InventoryItem].
  Future<void> updateStock({
    required InventoryItem item,
    required int newStockQuantity,
    int? newLowStockThreshold,
    required String reason,
    String notes = '',
  }) =>
      _service.updateStock(
        item: item,
        newStockQuantity: newStockQuantity,
        newLowStockThreshold: newLowStockThreshold,
        reason: reason,
        notes: notes,
      );

  /// Quick increment/decrement helper (e.g., +1 or -1 from the card).
  Future<void> adjustStockByDelta({
    required InventoryItem item,
    required int delta,
    String reason = 'Quick Adjustment',
  }) {
    final nextStock = (item.stockQuantity + delta) < 0 ? 0 : (item.stockQuantity + delta);
    return _service.updateStock(
      item: item,
      newStockQuantity: nextStock,
      reason: reason,
    );
  }

  /// Streams recent stock movement logs across all products.
  Stream<List<InventoryMovement>> getRecentMovementsStream({int limit = 50}) =>
      _service.getRecentMovementsStream(limit: limit);

  /// Streams recent stock movement logs for a single product.
  Stream<List<InventoryMovement>> getProductMovementsStream(
    String productId, {
    int limit = 25,
  }) =>
      _service.getProductMovementsStream(productId, limit: limit);

  /// Streams real-time floating stock data (incoming POs, outgoing reserved deliveries, and product breakdown).
  Stream<FloatingStockData> getFloatingStockStream() =>
      _service.getFloatingStockStream();

  /// Manually settles or reconciles an individual delivery whose inventory was left floating / unsettled.
  Future<void> settleSingleDelivery(String deliveryId) =>
      _service.settleSingleDelivery(deliveryId);
}
