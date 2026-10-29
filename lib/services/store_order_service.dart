// ignore_for_file: constant_identifier_names

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/store_order.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/inventory_service.dart';
import 'package:selecta_ops/services/push_notification_service.dart';

const String STORE_ORDERS_COLLECTION = 'store_orders';
const String STORE_ORDER_COUNTERS_COLLECTION = 'order_counters';

class StoreOrderService {
  final FirebaseFirestore? _customFirestore;
  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;
  final InventoryService? _customInventoryService;
  InventoryService get _inventoryService => _customInventoryService ?? InventoryService();
  final DeliveryService? _customDeliveryService;
  DeliveryService get _deliveryService => _customDeliveryService ?? DeliveryService();
  final PushNotificationService? _customPushNotificationService;
  PushNotificationService get _pushNotificationService => _customPushNotificationService ?? PushNotificationService();

  StoreOrderService({
    FirebaseFirestore? firestore,
    InventoryService? inventoryService,
    DeliveryService? deliveryService,
    PushNotificationService? pushNotificationService,
  })  : _customFirestore = firestore,
        _customInventoryService = inventoryService,
        _customDeliveryService = deliveryService,
        _customPushNotificationService = pushNotificationService;

  /// Generates a sequential running order number in format: SO-YYYYMMDD-XXXX
  Future<String> generateOrderNo() async {
    final now = DateTime.now();
    final dateKey = DateFormat('yyyyMMdd').format(now);
    final counterRef = _firestore.collection(STORE_ORDER_COUNTERS_COLLECTION).doc('store_orders_$dateKey');

    return await _firestore.runTransaction<String>((transaction) async {
      final snapshot = await transaction.get(counterRef);
      int nextSeq = 1;
      if (snapshot.exists) {
        final currentSeq = (snapshot.data()?['seq'] as num?)?.toInt() ?? 0;
        nextSeq = currentSeq + 1;
        transaction.update(counterRef, {'seq': nextSeq, 'updatedAt': FieldValue.serverTimestamp()});
      } else {
        transaction.set(counterRef, {'seq': nextSeq, 'date': dateKey, 'updatedAt': FieldValue.serverTimestamp()});
      }

      final paddedSeq = nextSeq.toString().padLeft(4, '0');
      return 'SO-$dateKey-$paddedSeq';
    });
  }

  /// Submits a new self-service store order
  Future<StoreOrder> createStoreOrder({
    required String storeId,
    required String storeName,
    required List<StoreOrderItem> items,
    required double totalAmount,
    required String createdByUid,
    required String createdByName,
    String? remarks,
  }) async {
    final orderNo = await generateOrderNo();
    final now = Timestamp.now();

    final initialHistory = StoreOrderStatusHistory(
      status: StoreOrderStatus.submitted,
      at: now,
      byUid: createdByUid,
      byName: createdByName,
    );

    final newOrder = StoreOrder(
      id: '',
      orderNo: orderNo,
      storeId: storeId,
      storeName: storeName,
      status: StoreOrderStatus.submitted,
      items: items,
      totalAmount: totalAmount,
      remarks: remarks,
      source: 'store',
      statusHistory: [initialHistory],
      createdBy: createdByUid,
      createdAt: now,
      updatedAt: now,
    );

    final docRef = await _firestore.collection(STORE_ORDERS_COLLECTION).add(newOrder.toJson());
    final createdOrder = newOrder.copyWith(id: docRef.id);

    // Notify dealer and salesmen about the incoming store order
    try {
      await _pushNotificationService.sendNotificationToRole(
        role: 'Staff',
        title: 'New Store Order Received',
        body: '$storeName submitted order $orderNo for ₱${totalAmount.toStringAsFixed(2)}',
        data: {
          'type': 'store_order',
          'orderId': docRef.id,
          'orderNo': orderNo,
          'storeId': storeId,
          'tag': 'order_${docRef.id}',
        },
        dedupeKey: 'so_${docRef.id}_submitted',
      );
    } catch (_) {}

    return createdOrder;
  }

  /// Real-time stream of orders for a specific store
  Stream<List<StoreOrder>> getStoreOrdersStream({
    required String storeId,
    String? status,
  }) {
    if (Firebase.apps.isEmpty && _customFirestore == null) {
      return const Stream<List<StoreOrder>>.empty();
    }

    Query query = _firestore
        .collection(STORE_ORDERS_COLLECTION)
        .where('storeId', isEqualTo: storeId);

    if (status != null && status.isNotEmpty && status != 'All') {
      query = query.where('status', isEqualTo: status);
    }

    query = query.orderBy('createdAt', descending: true);

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => StoreOrder.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>))
          .toList();
    });
  }

  /// Real-time stream of all store orders for Dealer/Admin inbox
  Stream<List<StoreOrder>> getAllStoreOrdersStream({
    String? status,
    String? searchQuery,
  }) {
    if (Firebase.apps.isEmpty && _customFirestore == null) {
      return const Stream<List<StoreOrder>>.empty();
    }

    Query query = _firestore.collection(STORE_ORDERS_COLLECTION);

    if (status != null && status.isNotEmpty && status != 'All') {
      query = query.where('status', isEqualTo: status);
    }

    query = query.orderBy('createdAt', descending: true);

    return query.snapshots().map((snapshot) {
      final orders = snapshot.docs
          .map((doc) => StoreOrder.fromSnapshot(doc as DocumentSnapshot<Map<String, dynamic>>))
          .toList();

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final queryClean = searchQuery.trim().toLowerCase();
        return orders.where((o) {
          return o.orderNo.toLowerCase().contains(queryClean) ||
              o.storeName.toLowerCase().contains(queryClean) ||
              o.status.toLowerCase().contains(queryClean);
        }).toList();
      }

      return orders;
    });
  }

  /// Live count badge stream for Submitted store orders awaiting dealer review
  Stream<int> getSubmittedStoreOrdersCountStream() {
    if (Firebase.apps.isEmpty && _customFirestore == null) {
      return const Stream<int>.empty();
    }

    return _firestore
        .collection(STORE_ORDERS_COLLECTION)
        .where('status', isEqualTo: StoreOrderStatus.submitted)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// Fetches a single store order by document ID
  Future<StoreOrder?> getStoreOrderById(String orderId) async {
    final doc = await _firestore.collection(STORE_ORDERS_COLLECTION).doc(orderId).get();
    if (!doc.exists || doc.data() == null) return null;
    return StoreOrder.fromSnapshot(doc);
  }

  /// Store cancels their own order while it is still in Submitted status
  Future<void> cancelStoreOrder({
    required String orderId,
    required String byUid,
    required String byName,
    String? reason,
  }) async {
    final docRef = _firestore.collection(STORE_ORDERS_COLLECTION).doc(orderId);
    final snapshot = await docRef.get();

    if (!snapshot.exists) {
      throw Exception('Order does not exist.');
    }

    final currentStatus = snapshot.data()?['status'] as String?;
    if (currentStatus != StoreOrderStatus.submitted) {
      throw Exception('Only submitted orders can be cancelled.');
    }

    final now = Timestamp.now();
    final newHistoryItem = StoreOrderStatusHistory(
      status: StoreOrderStatus.cancelled,
      at: now,
      byUid: byUid,
      byName: byName,
    ).toJson();

    await docRef.update({
      'status': StoreOrderStatus.cancelled,
      if (reason != null && reason.isNotEmpty) 'rejectReason': reason,
      'statusHistory': FieldValue.arrayUnion([newHistoryItem]),
      'updatedAt': now,
    });
  }

  /// Dealer approves store order:
  /// 1. Re-reads current product prices from selecta_products
  /// 2. Calculates approved amount and line totals
  /// 3. Creates unified Delivery pre-sell document
  /// 4. Executes stock reservations via InventoryService
  /// 5. Updates store_orders record with Approved status & deliveryId
  /// 6. Sends notification to store
  Future<StoreOrder> approveStoreOrder({
    required String orderId,
    required DateTime deliveryDate,
    required List<StoreOrderItem> approvedItems,
    required String reviewerUid,
    required String reviewerName,
  }) async {
    final orderRef = _firestore.collection(STORE_ORDERS_COLLECTION).doc(orderId);
    final orderDoc = await orderRef.get();

    if (!orderDoc.exists) {
      throw Exception('Store order not found.');
    }

    final currentOrder = StoreOrder.fromSnapshot(orderDoc);
    if (currentOrder.status != StoreOrderStatus.submitted) {
      throw Exception('Order is already ${currentOrder.status}. Only submitted orders can be approved.');
    }

    // 1. Re-read current selling prices from selecta_products catalog to compute exact current totals
    final updatedItems = <StoreOrderItem>[];
    double recomputedApprovedAmount = 0.0;

    for (final item in approvedItems) {
      double currentPrice = item.unitPrice;
      try {
        final prodDoc = await _firestore.collection('selecta_products').doc(item.productId).get();
        if (prodDoc.exists && prodDoc.data() != null) {
          final p = prodDoc.data()!;
          final catalogPrice = (p['sellingPrice'] as num?)?.toDouble();
          if (catalogPrice != null && catalogPrice > 0) {
            currentPrice = catalogPrice;
          }
        }
      } catch (_) {}

      final effectiveQty = item.qtyApproved;
      final lineTotal = effectiveQty * currentPrice;
      if (effectiveQty > 0) {
        recomputedApprovedAmount += lineTotal;
      }

      updatedItems.add(item.copyWith(
        unitPrice: currentPrice,
        lineTotal: lineTotal,
      ));
    }

    // Filter items with approved quantity > 0 for delivery creation
    final positiveItems = updatedItems.where((i) => i.qtyApproved > 0).toList();
    if (positiveItems.isEmpty) {
      throw Exception('Cannot approve order with 0 approved items. Please reject the order instead.');
    }

    // 2. Map items to OrderItem lines for pre-sell Delivery
    final deliveryOrderItems = positiveItems.map((item) {
      return OrderItem(
        productId: item.productId,
        productName: item.name,
        category: item.category,
        imageUrl: item.imageUrl,
        productSource: 'selecta',
        sellingPrice: item.unitPrice,
        orderedQuantity: item.qtyApproved,
        pickedQuantity: item.qtyApproved,
        isPicked: false,
      );
    }).toList();

    // 3. Create pre-sell Delivery document
    final newDelivery = Delivery(
      storeName: currentOrder.storeName,
      remarks: 'Self-Ordered #${currentOrder.orderNo}${currentOrder.remarks != null ? " - ${currentOrder.remarks}" : ""}',
      transactionStatus: DeliveryStatus.pendingPicklist,
      imagePath: '',
      orderAmount: recomputedApprovedAmount,
      grossAmount: recomputedApprovedAmount,
      discountAmount: 0.0,
      returnAmount: 0.0,
      creditAmount: 0.0,
      cashAmount: 0.0,
      onlineAmount: 0.0,
      deliveryDate: Timestamp.fromDate(deliveryDate),
      creditStatus: CreditStatus.unpaid,
      orderType: OrderType.preSell,
      createdBy: reviewerName,
      lastUpdatedBy: reviewerName,
      createdDate: Timestamp.now(),
      lastupdatedDate: Timestamp.now(),
      createdPage: AppPages.storeOrders,
      lastUpdatedPage: AppPages.storeOrders,
      items: deliveryOrderItems,
      isInventoryReserved: true,
      isInventoryDeducted: false,
      source: 'store_order',
      storeOrderId: orderId,
    );

    // Reserve stock via InventoryService
    await _inventoryService.reserveStockForOrder(
      storeName: currentOrder.storeName,
      items: deliveryOrderItems,
    );

    // Save Delivery document
    final deliveryId = await _deliveryService.addDelivery(newDelivery);

    // 4. Update store_order record
    final now = Timestamp.now();
    final newHistoryItem = StoreOrderStatusHistory(
      status: StoreOrderStatus.approved,
      at: now,
      byUid: reviewerUid,
      byName: reviewerName,
    );

    final updatedHistory = List<StoreOrderStatusHistory>.from(currentOrder.statusHistory)..add(newHistoryItem);

    await orderRef.update({
      'status': StoreOrderStatus.approved,
      'approvedAmount': recomputedApprovedAmount,
      'deliveryDate': Timestamp.fromDate(deliveryDate),
      'deliveryId': deliveryId,
      'items': updatedItems.map((i) => i.toJson()).toList(),
      'statusHistory': updatedHistory.map((h) => h.toJson()).toList(),
      'updatedAt': now,
    });

    final approvedOrder = currentOrder.copyWith(
      status: StoreOrderStatus.approved,
      approvedAmount: recomputedApprovedAmount,
      deliveryDate: Timestamp.fromDate(deliveryDate),
      deliveryId: deliveryId,
      items: updatedItems,
      statusHistory: updatedHistory,
      updatedAt: now,
    );

    // Notify store user
    try {
      await _pushNotificationService.sendNotificationToRole(
        role: 'store_${currentOrder.storeId}',
        title: 'Order Approved!',
        body: 'Your order #${currentOrder.orderNo} was approved for delivery on ${DateFormat("MMM dd, yyyy").format(deliveryDate)}.',
        data: {
          'type': 'store_order_status',
          'orderId': orderId,
          'status': StoreOrderStatus.approved,
          'tag': 'order_$orderId',
        },
        dedupeKey: 'so_${orderId}_approved',
      );
    } catch (_) {}

    return approvedOrder;
  }

  /// Dealer rejects store order with mandatory reason
  Future<void> rejectStoreOrder({
    required String orderId,
    required String reason,
    required String reviewerUid,
    required String reviewerName,
  }) async {
    final orderRef = _firestore.collection(STORE_ORDERS_COLLECTION).doc(orderId);
    final orderDoc = await orderRef.get();

    if (!orderDoc.exists) {
      throw Exception('Store order not found.');
    }

    final currentOrder = StoreOrder.fromSnapshot(orderDoc);
    if (currentOrder.status != StoreOrderStatus.submitted) {
      throw Exception('Order is already ${currentOrder.status}.');
    }

    final now = Timestamp.now();
    final newHistoryItem = StoreOrderStatusHistory(
      status: StoreOrderStatus.rejected,
      at: now,
      byUid: reviewerUid,
      byName: reviewerName,
    );

    final updatedHistory = List<StoreOrderStatusHistory>.from(currentOrder.statusHistory)..add(newHistoryItem);

    await orderRef.update({
      'status': StoreOrderStatus.rejected,
      'rejectReason': reason.trim(),
      'statusHistory': updatedHistory.map((h) => h.toJson()).toList(),
      'updatedAt': now,
    });

    // Notify store user
    try {
      await _pushNotificationService.sendNotificationToRole(
        role: 'store_${currentOrder.storeId}',
        title: 'Order Status Update',
        body: 'Your order #${currentOrder.orderNo} was declined: $reason',
        data: {
          'type': 'store_order_status',
          'orderId': orderId,
          'status': StoreOrderStatus.rejected,
          'tag': 'order_$orderId',
        },
        dedupeKey: 'so_${orderId}_rejected',
      );
    } catch (_) {}
  }

  /// Synchronizes Delivery milestone transitions back to the corresponding Store Order
  Future<void> syncDeliveryStatusToStoreOrder({
    required String deliveryId,
    required String newDeliveryStatus,
    required String byUid,
    required String byName,
  }) async {
    try {
      final query = await _firestore
          .collection(STORE_ORDERS_COLLECTION)
          .where('deliveryId', isEqualTo: deliveryId)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return;

      final doc = query.docs.first;
      final currentOrder = StoreOrder.fromSnapshot(doc);
      String? targetStatus;

      if (newDeliveryStatus == DeliveryStatus.delivered) {
        targetStatus = StoreOrderStatus.delivered;
      } else if (newDeliveryStatus == DeliveryStatus.pending) {
        targetStatus = StoreOrderStatus.outForDelivery;
      } else if (newDeliveryStatus == DeliveryStatus.returned || newDeliveryStatus == DeliveryStatus.voided) {
        targetStatus = StoreOrderStatus.cancelled;
      }

      if (targetStatus != null && currentOrder.status != targetStatus) {
        final now = Timestamp.now();
        final newHistory = StoreOrderStatusHistory(
          status: targetStatus,
          at: now,
          byUid: byUid,
          byName: byName,
        );

        final updatedHistory = List<StoreOrderStatusHistory>.from(currentOrder.statusHistory)..add(newHistory);

        await doc.reference.update({
          'status': targetStatus,
          'statusHistory': updatedHistory.map((h) => h.toJson()).toList(),
          'updatedAt': now,
        });

        // Notify store
        try {
          await _pushNotificationService.sendNotificationToRole(
            role: 'store_${currentOrder.storeId}',
            title: 'Order $targetStatus',
            body: 'Order #${currentOrder.orderNo} is now $targetStatus.',
            data: {
              'type': 'store_order_status',
              'orderId': doc.id,
              'status': targetStatus,
              'tag': 'order_${doc.id}',
            },
            dedupeKey: 'so_${doc.id}_$targetStatus',
          );
        } catch (_) {}
      }
    } catch (_) {}
  }
}
