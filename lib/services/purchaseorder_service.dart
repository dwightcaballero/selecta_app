import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/models/purchaseorder.dart';

// ignore: constant_identifier_names
const String PURCHASEORDER_COLLECTION_REF = 'purchaseorders';

class PurchaseOrderService {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference _purchaseordersRef;

  PurchaseOrderService() {
    _purchaseordersRef = _firestore
        .collection(PURCHASEORDER_COLLECTION_REF)
        .withConverter<Purchaseorder>(
          fromFirestore: (snapshots, _) => Purchaseorder.fromJson(snapshots.data()!),
          toFirestore: (purchaseorder, _) => purchaseorder.toJson(),
        );
  }

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
}
