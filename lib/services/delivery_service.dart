import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/delivery.dart';

// ignore: constant_identifier_names
const String DELIVERY_COLLECTION_REF = 'delivery';

class DeliveryService {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference _ordersRef;

  DeliveryService() {
    _ordersRef = _firestore
        .collection(DELIVERY_COLLECTION_REF)
        .withConverter<Delivery>(
          fromFirestore: (snapshots, _) => Delivery.fromJson(snapshots.data()!),
          toFirestore: (delivery, _) => delivery.toJson(),
        );
  }

  void addDelivery(Delivery delivery) {
    _ordersRef.add(delivery);
  }

  void updateDelivery(String deliveryID, Delivery delivery) {
    _ordersRef.doc(deliveryID).update(delivery.toJson());
  }

  void deleteDelivery(String deliveryID) {
    _ordersRef.doc(deliveryID).delete();
  }

  Stream<QuerySnapshot> getListDelivery() {
    return _ordersRef.orderBy(DeliveryModelString.createdDate).snapshots();
  }

  Stream<QuerySnapshot> getListDeliveryByDate(DateTime deliveryDate) {
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
    DateTime startOfDay = now;

    switch (monthsBefore) {
      case MonthsAgo.months1:
        startOfDay = KVariables.firstDayOfTheMonth();
        break;
      case MonthsAgo.months3:
        startOfDay = DateTime(now.year, now.month - 3, 0);
        break;
      case MonthsAgo.months6:
        startOfDay = DateTime(now.year, now.month - 6, 0);
        break;
      default:
    }

    return _ordersRef
        .where(DeliveryModelString.storeName, isEqualTo: storeName)
        .where(DeliveryModelString.transactionStatus, isEqualTo: DeliveryStatus.delivered)
        .where(DeliveryModelString.deliveryDate, isGreaterThanOrEqualTo: startOfDay)
        .where(DeliveryModelString.deliveryDate, isLessThan: endofday)
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
        .where(DeliveryModelString.transactionStatus, isEqualTo: DeliveryStatus.returned)
        .orderBy(DeliveryModelString.deliveryDate, descending: true)
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

  static Future<int?> getCountReturnedDeliveriesOnOtherDays() async {
    var currentDate = DateTime.now();
    final startOfDay = DateTime(currentDate.year, currentDate.month, currentDate.day, 0, 0, 0);

    var snapshot = await FirebaseFirestore.instance
        .collection(DELIVERY_COLLECTION_REF)
        .where(DeliveryModelString.transactionStatus, isEqualTo: DeliveryStatus.returned)
        .where(DeliveryModelString.lastupdatedDate, isLessThan: startOfDay)
        .count()
        .get();

    return snapshot.count;
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
}
