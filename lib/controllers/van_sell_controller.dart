import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/van_load.dart';
import 'package:selecta_ops/services/auth_service.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/services/van_load_service.dart';

class VanSellController {
  final VanLoadService _vanLoadService;
  final DeliveryService _deliveryService;
  final HapiStoreService _hapiStoreService;
  final FirebaseFirestore _firestore;

  VanSellController({
    VanLoadService? vanLoadService,
    DeliveryService? deliveryService,
    HapiStoreService? hapiStoreService,
    FirebaseFirestore? firestore,
  })  : _vanLoadService = vanLoadService ?? VanLoadService(),
        _deliveryService = deliveryService ?? DeliveryService(),
        _hapiStoreService = hapiStoreService ?? HapiStoreService(),
        _firestore = firestore ?? FirebaseFirestore.instance;

  /// Gets current user display name.
  String getCurrentUserDisplayName() {
    return authService.value.currentUser?.displayName ?? 'Salesman';
  }

  /// Checks if current user is Dealer.
  Future<bool> checkIsDealer() => KVariables.getIsDealer();

  /// Stream active van load for salesman.
  Stream<VanLoad?> streamActiveVanLoad() =>
      _vanLoadService.streamActiveVanLoad();

  /// Fetch active van load once.
  Future<VanLoad?> getActiveVanLoad() =>
      _vanLoadService.getActiveVanLoad();

  /// Stream of registered HapiStores.
  Stream<QuerySnapshot> getHapiStoresStream() =>
      _hapiStoreService.getListHapiStoresAsStream();

  /// Returns a set of lowercase store names that have placed orders / had deliveries in the current calendar month.
  Future<Set<String>> getBuyingStoreNamesCurrentMonth() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startTimestamp = Timestamp.fromDate(startOfMonth);

    try {
      final snap = await _firestore
          .collection(DELIVERY_COLLECTION_REF)
          .where('deliveryDate', isGreaterThanOrEqualTo: startTimestamp)
          .get();

      final buyingStores = <String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final status = data['transactionStatus'] as String? ?? '';
        if (status == DeliveryStatus.voided) continue;
        final storeName = (data['storeName'] as String? ?? '').trim().toLowerCase();
        if (storeName.isNotEmpty) {
          buyingStores.add(storeName);
        }
      }
      return buyingStores;
    } catch (e) {
      // In case composite index or offline, return empty set gracefully
      return <String>{};
    }
  }

  /// Validates line items against currently available van stock.
  String? validateVanStock(VanLoad vanLoad, List<OrderItem> items) {
    if (items.isEmpty) {
      return 'Please add at least one product to the sale.';
    }

    final Map<String, int> availableMap = {
      for (final vi in vanLoad.items) vi.productId: vi.availableQuantity
    };

    for (final item in items) {
      final available = availableMap[item.productId] ?? 0;
      if (item.pickedQuantity > available) {
        return 'Not enough stock on van for ${item.productName}. Available: $available, requested: ${item.pickedQuantity}';
      }
    }
    return null;
  }

  /// Executes a quick van sale:
  /// 1. Validates available van inventory.
  /// 2. Creates a [Delivery] record tagged with `orderType = 'van-sell'`, `transactionStatus = 'Delivered'`.
  /// 3. Atomically increments `soldQuantity` in the corresponding [VanLoad].
  /// 4. Returns the created [Delivery] object (with `rescheduledToDeliveryId` storing its new Firestore doc ID).
  Future<({String deliveryId, Delivery delivery})> completeVanSale({
    required VanLoad vanLoad,
    required Hapistore store,
    required List<OrderItem> items,
    required String paymentMethod, // 'Cash' | 'Online' | 'Credit'
    required double cashAmount,
    required double onlineAmount,
    required double creditAmount,
    String remarks = '',
    required String imagePath,
  }) async {
    if (vanLoad.id == null || vanLoad.id!.isEmpty) {
      throw ArgumentError('Active VanLoad must have a valid ID.');
    }

    if (imagePath.trim().isEmpty) {
      throw ArgumentError('Proof of van selling photo is required.');
    }

    final stockError = validateVanStock(vanLoad, items);
    if (stockError != null) {
      throw StateError(stockError);
    }

    final now = Timestamp.now();
    final user = getCurrentUserDisplayName();
    final totalAmount = items.fold<double>(0.0, (acc, item) => acc + item.lineTotal);

    final creditStatus = (paymentMethod == 'Credit' || creditAmount > 0)
        ? CreditStatus.unpaid
        : CreditStatus.paid;

    // Convert items into picked OrderItem lines (fixed catalog SRP pricing)
    final deliveryItems = items.map((item) {
      return item.copyWith(
        orderedQuantity: item.pickedQuantity,
        pickedQuantity: item.pickedQuantity,
        returnedQuantity: 0,
        isPicked: true,
      );
    }).toList();

    final delivery = Delivery(
      storeName: store.storeName,
      remarks: remarks.isEmpty ? 'Van Sell' : 'Van Sell - $remarks',
      transactionStatus: DeliveryStatus.delivered,
      imagePath: imagePath,
      orderAmount: totalAmount,
      originalOrderAmount: totalAmount,
      returnAmount: 0.0,
      creditAmount: creditAmount,
      cashAmount: cashAmount,
      onlineAmount: onlineAmount,
      deliveryDate: now,
      creditStatus: creditStatus,
      orderType: OrderType.vanSell,
      vanLoadId: vanLoad.id,
      items: deliveryItems,
      isInventoryReserved: false,
      isInventoryDeducted: true, // Already physically loaded on van
      isInventorySettled: true,
      createdBy: user,
      lastUpdatedBy: user,
      createdDate: now,
      lastupdatedDate: now,
      createdPage: AppPages.vanSell,
      lastUpdatedPage: AppPages.vanSell,
    );

    // 1. Create delivery document
    final deliveryId = await _deliveryService.addDelivery(delivery);

    // 2. Record sale on van load
    await _vanLoadService.recordVanSale(
      vanLoadId: vanLoad.id!,
      soldItems: deliveryItems,
    );

    return (deliveryId: deliveryId, delivery: delivery);
  }
}
