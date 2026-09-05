import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/data/constants.dart';
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

  Stream<QuerySnapshot> getListDelivery() {
    return _ordersRef.orderBy(DeliveryModelString.createdDate).snapshots();
  }

  Stream<QuerySnapshot> getListDeliveryFilter(DateTime deliveryDate) {
    final startOfDay = DateTime(
      deliveryDate.year,
      deliveryDate.month,
      deliveryDate.day,
      0,
      0,
      0,
    );

    final endOfDay = DateTime(
      deliveryDate.year,
      deliveryDate.month,
      deliveryDate.day,
      23,
      59,
      59,
    );

    return _ordersRef
        .orderBy(DeliveryModelString.createdDate)
        .where(
          DeliveryModelString.deliveryDate,
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where(
          DeliveryModelString.deliveryDate,
          isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
        )
        .snapshots();
  }

  Stream<QuerySnapshot> getListDeliveryWithCredit() {
    return _ordersRef
        .where(DeliveryModelString.creditStatus, isEqualTo: CreditStatus.unpaid)
        .where(DeliveryModelString.creditAmount, isGreaterThan: 0)
        .orderBy(DeliveryModelString.deliveryDate, descending: true)
        .snapshots();
  }

  Future<int?> getCountDeliveryWithCreditNotYetPaid() async {
    try {
      var snapshot = await FirebaseFirestore.instance
          .collection(DELIVERY_COLLECTION_REF)
          .where(
            DeliveryModelString.creditStatus,
            isEqualTo: CreditStatus.unpaid,
          )
          .where(DeliveryModelString.creditAmount, isGreaterThan: 0)
          .orderBy(DeliveryModelString.deliveryDate, descending: true)
          .count()
          .get();

      return snapshot.count;
    } catch (e) {
      return 0;
    }
  }

  Future<int?> getCountDeliveriesByStatus(String status) async {
    var snapshot = await FirebaseFirestore.instance
        .collection(DELIVERY_COLLECTION_REF)
        .where(DeliveryModelString.transactionStatus, isEqualTo: status)
        .count()
        .get();

    return snapshot.count;
  }

  Future<int?> getCountReturnedDeliveriesOnOtherDays() async {
    var currentDate = DateTime.now();
    final startOfDay = DateTime(
      currentDate.year,
      currentDate.month,
      currentDate.day,
      0,
      0,
      0,
    );

    var snapshot = await FirebaseFirestore.instance
        .collection(DELIVERY_COLLECTION_REF)
        .where(
          DeliveryModelString.transactionStatus,
          isEqualTo: DeliveryStatus.returned,
        )
        .where(DeliveryModelString.lastupdatedDate, isLessThan: startOfDay)
        .count()
        .get();

    return snapshot.count;
  }

  Stream<QuerySnapshot> getListDeliveryWithReturnStatus() {
    return _ordersRef
        .where(
          DeliveryModelString.transactionStatus,
          isEqualTo: DeliveryStatus.returned,
        )
        .orderBy(DeliveryModelString.deliveryDate, descending: true)
        .snapshots();
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
}
