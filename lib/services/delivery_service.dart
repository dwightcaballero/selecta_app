import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/delivery.dart';

// ignore: constant_identifier_names
const String DELIVERY_COLLECTION_REF = 'delivery';

class DeliveryService {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference<Delivery> _ordersRef;

  DeliveryService() {
    _ordersRef = _firestore
        .collection(DELIVERY_COLLECTION_REF)
        .withConverter<Delivery>(
          fromFirestore: (snapshots, _) => Delivery.fromJson(snapshots.data()!),
          toFirestore: (delivery, _) => delivery.toJson(),
        );
  }

  Future<String> addDelivery(Delivery delivery) async {
    final docRef = await _ordersRef.add(delivery);
    return docRef.id;
  }

  Future<void> updateDelivery(String deliveryID, Delivery delivery) async {
    await _ordersRef.doc(deliveryID).update(delivery.toJson());
  }

  void deleteDelivery(String deliveryID) {
    _ordersRef.doc(deliveryID).delete();
  }

  Future<Delivery?> getDeliveryById(String deliveryID) async {
    final doc = await _ordersRef.doc(deliveryID).get();
    return doc.data();
  }

  Stream<DocumentSnapshot<Delivery>> getDeliveryStreamById(String deliveryID) {
    return _ordersRef.doc(deliveryID).snapshots();
  }

  Stream<QuerySnapshot<Delivery>> getPendingPicklistsStream() {
    return _ordersRef.where(DeliveryModelString.transactionStatus, isEqualTo: DeliveryStatus.pendingPicklist).snapshots();
  }

  Stream<int> getPendingPicklistCountStream({DateTime? date}) {
    return _ordersRef.where(DeliveryModelString.transactionStatus, isEqualTo: DeliveryStatus.pendingPicklist).snapshots().map((snap) {
      final target = date ?? DateTime.now();
      return snap.docs.where((doc) {
        final delivery = doc.data();
        final dDate = delivery.deliveryDate?.toDate() ?? delivery.createdDate.toDate();
        return dDate.year == target.year && dDate.month == target.month && dDate.day == target.day;
      }).length;
    });
  }

  Stream<int> getPendingDeliveriesCountStream({DateTime? date}) {
    return _ordersRef.where(DeliveryModelString.transactionStatus, isEqualTo: DeliveryStatus.pending).snapshots().map((snap) {
      final target = date ?? DateTime.now();
      return snap.docs.where((doc) {
        final delivery = doc.data();
        final dDate = delivery.deliveryDate?.toDate() ?? delivery.createdDate.toDate();
        return dDate.year == target.year && dDate.month == target.month && dDate.day == target.day;
      }).length;
    });
  }

  /// Real-time stream of the count of returned deliveries requiring dealer action
  /// (not yet rescheduled and not yet finalized).
  Stream<int> getActiveReturnedDeliveriesCountStream() {
    return getListDeliveryWithReturnStatus().map((snap) {
      return snap.docs.where((doc) {
        final delivery = doc.data() as Delivery;
        return !delivery.isRescheduled && !delivery.isReturnFinalized;
      }).length;
    });
  }

  Stream<QuerySnapshot> getListDelivery() {
    return _ordersRef.orderBy(DeliveryModelString.createdDate).snapshots();
  }

  Stream<QuerySnapshot<Delivery>> getListDeliveryByDate(DateTime deliveryDate) {
    final startOfDay = DateTime(deliveryDate.year, deliveryDate.month, deliveryDate.day, 0, 0, 0);
    final endOfDay = DateTime(deliveryDate.year, deliveryDate.month, deliveryDate.day, 23, 59, 59);

    return _ordersRef
        .orderBy(DeliveryModelString.createdDate)
        .where(DeliveryModelString.deliveryDate, isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where(DeliveryModelString.deliveryDate, isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .snapshots();
  }

  Stream<QuerySnapshot> getListDeliveryByStoreNameAndDateRange(String storeName, String monthsBefore) {
    DateTime now = DateTime.now();
    DateTime endofday = KVariables.lastDayOfTheMonth();
    DateTime startOfDay;

    switch (monthsBefore) {
      case MonthsAgo.months1:
        // Current month (e.g. September 1 to September 30)
        startOfDay = DateTime(now.year, now.month, 1);
        break;
      case MonthsAgo.months3:
        // 3 months including current month (e.g. July 1 to September 30)
        startOfDay = DateTime(now.year, now.month - 2, 1);
        break;
      case MonthsAgo.months6:
        // 6 months including current month (e.g. April 1 to September 30)
        startOfDay = DateTime(now.year, now.month - 5, 1);
        break;
      default:
        startOfDay = DateTime(now.year, now.month, 1);
    }

    return _ordersRef
        .where(DeliveryModelString.storeName, isEqualTo: storeName)
        .where(DeliveryModelString.transactionStatus, isEqualTo: DeliveryStatus.delivered)
        .where(DeliveryModelString.deliveryDate, isGreaterThanOrEqualTo: startOfDay)
        .where(DeliveryModelString.deliveryDate, isLessThanOrEqualTo: endofday)
        .orderBy(DeliveryModelString.deliveryDate, descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> getListDeliveryWithCredit() {
    return _ordersRef
        .where(DeliveryModelString.creditStatus, isEqualTo: CreditStatus.unpaid)
        .where(DeliveryModelString.creditAmount, isGreaterThan: 0)
        .orderBy(DeliveryModelString.deliveryDate, descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> getListDeliveryWithReturnStatus() {
    return _ordersRef
        .where(
          Filter.or(
            Filter(DeliveryModelString.transactionStatus, isEqualTo: DeliveryStatus.returned),
            Filter(DeliveryModelString.isReturnIncoming, isEqualTo: true),
            Filter(DeliveryModelString.isReturnApprovedByDealer, isEqualTo: true),
          ),
        )
        .snapshots();
  }

  static Future<int?> getCountDeliveryWithCreditNotYetPaid() async {
    try {
      var snapshot = await FirebaseFirestore.instance
          .collection(DELIVERY_COLLECTION_REF)
          .where(DeliveryModelString.creditStatus, isEqualTo: CreditStatus.unpaid)
          .where(DeliveryModelString.creditAmount, isGreaterThan: 0)
          .orderBy(DeliveryModelString.deliveryDate, descending: true)
          .count()
          .get();

      return snapshot.count;
    } catch (e) {
      return 0;
    }
  }

  static Future<int?> getCountDeliveriesByStatus(String status) async {
    var snapshot = await FirebaseFirestore.instance
        .collection(DELIVERY_COLLECTION_REF)
        .where(DeliveryModelString.transactionStatus, isEqualTo: status)
        .count()
        .get();

    return snapshot.count;
  }

  /// Counts returned deliveries requiring dealer action (not yet rescheduled and not yet finalized).
  static Future<int> getCountActiveReturnedDeliveries() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(DELIVERY_COLLECTION_REF)
          .where(
            Filter.or(
              Filter(DeliveryModelString.transactionStatus, isEqualTo: DeliveryStatus.returned),
              Filter(DeliveryModelString.isReturnIncoming, isEqualTo: true),
              Filter(DeliveryModelString.isReturnApprovedByDealer, isEqualTo: true),
            ),
          )
          .get();

      return snapshot.docs.where((doc) {
        final data = doc.data();
        return data[DeliveryModelString.isRescheduled] != true &&
            data[DeliveryModelString.isReturnFinalized] != true;
      }).length;
    } catch (e) {
      return 0;
    }
  }

  /// Counts pending picklists specifically scheduled/created for [date].
  static Future<int> getCountPendingPicklistsForDate(DateTime date) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(DELIVERY_COLLECTION_REF)
          .where(DeliveryModelString.transactionStatus, isEqualTo: DeliveryStatus.pendingPicklist)
          .get();

      return snapshot.docs.where((doc) {
        final data = doc.data();
        final deliveryDate = data[DeliveryModelString.deliveryDate] as Timestamp?;
        final createdDate = data[DeliveryModelString.createdDate] as Timestamp?;
        final dDate = deliveryDate?.toDate() ?? createdDate?.toDate();
        if (dDate == null) return false;
        return dDate.year == date.year && dDate.month == date.month && dDate.day == date.day;
      }).length;
    } catch (e) {
      return 0;
    }
  }

  static Future<int?> getCountReturnedDeliveriesOnOtherDays() async {
    var currentDate = DateTime.now();
    final startOfDay = DateTime(currentDate.year, currentDate.month, currentDate.day, 0, 0, 0);

    var snapshot = await FirebaseFirestore.instance
        .collection(DELIVERY_COLLECTION_REF)
        .where(DeliveryModelString.transactionStatus, isEqualTo: DeliveryStatus.returned)
        .where(DeliveryModelString.lastupdatedDate, isLessThan: startOfDay)
        .get();

    return snapshot.docs.where((doc) {
      final data = doc.data();
      return data[DeliveryModelString.isRescheduled] != true &&
          data[DeliveryModelString.isReturnFinalized] != true;
    }).length;
  }

  // Get list delivery within the month of the current year
  static Future<List<Delivery>> getListDeliveryWithinCurrentMonth() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    var snapshot = await FirebaseFirestore.instance
        .collection(DELIVERY_COLLECTION_REF)
        .where(DeliveryModelString.deliveryDate, isGreaterThanOrEqualTo: startOfMonth)
        .where(DeliveryModelString.deliveryDate, isLessThan: endOfMonth)
        .where(DeliveryModelString.transactionStatus, isEqualTo: DeliveryStatus.delivered)
        .get();

    return snapshot.docs.map((doc) => Delivery.fromJson(doc.data())).toList();
  }

  /// Updates picklistSequence order on the given delivery documents in a batch.
  Future<void> updatePicklistSequenceOrder(List<String> deliveryIDs) async {
    final batch = _firestore.batch();
    for (int i = 0; i < deliveryIDs.length; i++) {
      batch.update(_ordersRef.doc(deliveryIDs[i]), {DeliveryModelString.picklistSequence: i, DeliveryModelString.lastupdatedDate: Timestamp.now()});
    }
    await batch.commit();
  }

  /// Clears picklistSequence on the given delivery documents to revert back to default PJP order.
  Future<void> clearPicklistSequenceOrder(List<String> deliveryIDs) async {
    final batch = _firestore.batch();
    for (final id in deliveryIDs) {
      batch.update(_ordersRef.doc(id), {DeliveryModelString.picklistSequence: null, DeliveryModelString.lastupdatedDate: Timestamp.now()});
    }
    await batch.commit();
  }

  /// Updates deliverySequence order on the given delivery documents in a batch.
  Future<void> updateDeliverySequenceOrder(List<String> deliveryIDs) async {
    final batch = _firestore.batch();
    for (int i = 0; i < deliveryIDs.length; i++) {
      batch.update(_ordersRef.doc(deliveryIDs[i]), {DeliveryModelString.deliverySequence: i, DeliveryModelString.lastupdatedDate: Timestamp.now()});
    }
    await batch.commit();
  }

  /// Clears deliverySequence on the given delivery documents to revert back to default order.
  Future<void> clearDeliverySequenceOrder(List<String> deliveryIDs) async {
    final batch = _firestore.batch();
    for (final id in deliveryIDs) {
      batch.update(_ordersRef.doc(id), {DeliveryModelString.deliverySequence: null, DeliveryModelString.lastupdatedDate: Timestamp.now()});
    }
    await batch.commit();
  }
}
