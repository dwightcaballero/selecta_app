import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/store_order.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/store_order_service.dart';

class StoreOrderSubmissionResult {
  final StoreOrder order;
  final bool isAfterCutoff;
  final String? cutoffMessage;

  const StoreOrderSubmissionResult({
    required this.order,
    this.isAfterCutoff = false,
    this.cutoffMessage,
  });
}

class StoreOrderController {
  final StoreOrderService _service;
  final ConfigurationService _configService;

  StoreOrderController({
    StoreOrderService? service,
    ConfigurationService? configService,
  })  : _service = service ?? StoreOrderService(),
        _configService = configService ?? ConfigurationService();

  /// Validates cart contents and submits a new store order
  Future<StoreOrderSubmissionResult> submitOrder({
    required String storeId,
    required String storeName,
    required List<StoreOrderItem> items,
    String? remarks,
  }) async {
    if (items.isEmpty) {
      throw const FormatException('Your cart is empty. Please add items to place an order.');
    }

    for (final item in items) {
      if (item.qty <= 0) {
        throw FormatException('Quantity for ${item.name} must be greater than zero.');
      }
    }

    final totalAmount = items.fold<double>(0.0, (sum, item) => sum + item.lineTotal);

    // Optional configuration checks: Minimum Order Value & Cut-off Time
    final config = await _configService.getConfiguration();
    bool afterCutoff = false;
    String? cutoffMessage;

    // 1. Minimum order value validation
    if (config.hasStoreMinimumOrderValue && totalAmount < config.storeMinimumOrderValue!) {
      final minStr = NumberFormat.currency(symbol: '₱', decimalDigits: 2).format(config.storeMinimumOrderValue);
      final currentStr = NumberFormat.currency(symbol: '₱', decimalDigits: 2).format(totalAmount);
      throw FormatException(
        'Your order total is $currentStr, which is below the minimum order amount of $minStr.',
      );
    }

    // 2. Cut-off time check (orders accepted but flagged for next processing day)
    final now = DateTime.now();
    if (config.isAfterCutoff(now)) {
      afterCutoff = true;
      cutoffMessage = 'Order placed after the daily cut-off time (${config.storeCutoffTime}). It will be reviewed on the next business day.';
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    final createdByUid = currentUser?.uid ?? '';
    final createdByName = currentUser?.displayName ?? storeName;

    String finalRemarks = (remarks ?? '').trim();
    if (afterCutoff && cutoffMessage != null) {
      finalRemarks = finalRemarks.isEmpty
          ? '[After Cut-off]'
          : '$finalRemarks [After Cut-off]';
    }

    final createdOrder = await _service.createStoreOrder(
      storeId: storeId,
      storeName: storeName,
      items: items,
      totalAmount: totalAmount,
      createdByUid: createdByUid,
      createdByName: createdByName,
      remarks: finalRemarks.isEmpty ? null : finalRemarks,
    );

    return StoreOrderSubmissionResult(
      order: createdOrder,
      isAfterCutoff: afterCutoff,
      cutoffMessage: cutoffMessage,
    );
  }

  /// Cancels an order while it is still in Submitted status
  Future<void> cancelOrder({
    required String orderId,
    String? reason,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    await _service.cancelStoreOrder(
      orderId: orderId,
      byUid: user?.uid ?? '',
      byName: user?.displayName ?? 'Store Owner',
      reason: reason,
    );
  }

  /// Dealer approves store order with assigned delivery date and approved quantities
  Future<StoreOrder> approveOrder({
    required String orderId,
    required DateTime deliveryDate,
    required List<StoreOrderItem> approvedItems,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    return await _service.approveStoreOrder(
      orderId: orderId,
      deliveryDate: deliveryDate,
      approvedItems: approvedItems,
      reviewerUid: user?.uid ?? '',
      reviewerName: user?.displayName ?? 'Dealer',
    );
  }

  /// Dealer rejects store order with reason
  Future<void> rejectOrder({
    required String orderId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw const FormatException('Please provide a reason for declining this order.');
    }

    final user = FirebaseAuth.instance.currentUser;
    await _service.rejectStoreOrder(
      orderId: orderId,
      reason: reason.trim(),
      reviewerUid: user?.uid ?? '',
      reviewerName: user?.displayName ?? 'Dealer',
    );
  }

  /// Returns real-time stream of store orders for a specific store
  Stream<List<StoreOrder>> getStoreOrdersStream({
    required String storeId,
    String? status,
  }) {
    return _service.getStoreOrdersStream(storeId: storeId, status: status);
  }

  /// Returns real-time stream of all store orders for Dealer
  Stream<List<StoreOrder>> getAllStoreOrdersStream({
    String? status,
    String? searchQuery,
  }) {
    return _service.getAllStoreOrdersStream(status: status, searchQuery: searchQuery);
  }

  /// Real-time count of Submitted store orders awaiting dealer action
  Stream<int> getSubmittedCountStream() {
    return _service.getSubmittedStoreOrdersCountStream();
  }

  /// Fetches an order by its ID
  Future<StoreOrder?> getOrderById(String orderId) {
    return _service.getStoreOrderById(orderId);
  }
}
