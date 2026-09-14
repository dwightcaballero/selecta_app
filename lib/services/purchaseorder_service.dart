import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/models/purchaseorder.dart';

// ignore: constant_identifier_names
const String PURCHASEORDER_COLLECTION_REF = 'purchaseorders';

class PurchaseOrderService {
  PurchaseOrderService() {
    _purchaseordersRef = _firestore
        .collection(PURCHASEORDER_COLLECTION_REF)
        .withConverter<Purchaseorder>(
          fromFirestore: (snapshots, _) => Purchaseorder.fromJson(snapshots.data()!),
          toFirestore: (purchaseorder, _) => purchaseorder.toJson(),
        );
  }

  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference _purchaseordersRef;

  void addPurchaseorder(Purchaseorder purchaseorder) {
    _purchaseordersRef.add(purchaseorder);
  }

  void updatePurchaseorder(String purchaseorderID, Purchaseorder purchaseorder) {
    _purchaseordersRef.doc(purchaseorderID).update(purchaseorder.toJson());
  }

  void deletePurchaseorder(String purchaseorderID) {
    _purchaseordersRef.doc(purchaseorderID).delete();
  }

  Stream<QuerySnapshot> getListPurchaseordersAsStream() {
    return _purchaseordersRef.orderBy('orderDate', descending: true).snapshots();
  }

  Stream<QuerySnapshot> getListPurchaseOrdersNotYetSettled() {
    return _purchaseordersRef.where('isSettled', isEqualTo: false).orderBy('orderDate', descending: true).snapshots();
  }

  static Future<int?> getCountDeliveriesNotYetSettled() async {
    var snapshot = await FirebaseFirestore.instance.collection(PURCHASEORDER_COLLECTION_REF).where('isSettled', isEqualTo: false).count().get();

    return snapshot.count;
  }

  static Future<double> getTotalInvoiceAmountForCurrentMonth() async {
    var now = DateTime.now();
    var firstDayOfMonth = DateTime(now.year, now.month, 1);
    var lastDayOfMonth = DateTime(now.year, now.month + 1, 0);

    var snapshot = await FirebaseFirestore.instance
        .collection(PURCHASEORDER_COLLECTION_REF)
        .where('invoiceDate', isGreaterThanOrEqualTo: firstDayOfMonth)
        .where('invoiceDate', isLessThanOrEqualTo: lastDayOfMonth)
        .get();

    double total = 0;
    for (var doc in snapshot.docs) {
      total += (doc.data()['invoiceAmount'] ?? 0).toDouble();
    }

    return total;
  }

  static Future<List<Purchaseorder>> getPurchaseOrdersForCurrentMonth() async {
    var now = DateTime.now();
    var firstDayOfMonth = DateTime(now.year, now.month, 1);
    var lastDayOfMonth = DateTime(now.year, now.month + 1, 0);

    var snapshot = await FirebaseFirestore.instance
        .collection(PURCHASEORDER_COLLECTION_REF)
        .where('invoiceDate', isGreaterThanOrEqualTo: firstDayOfMonth)
        .where('invoiceDate', isLessThanOrEqualTo: lastDayOfMonth)
        .get();

    List<Purchaseorder> purchaseorders = [];
    for (var doc in snapshot.docs) {
      purchaseorders.add(Purchaseorder.fromJson(doc.data()));
    }

    return purchaseorders;
  }
}
