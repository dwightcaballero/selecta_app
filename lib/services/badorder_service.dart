import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/models/badorder.dart';

// ignore: constant_identifier_names
const String BADORDER_COLLECTION_REF = 'badorder';

class BadOrderService {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference<BadOrder> _badorderRef;

  BadOrderService() {
    _badorderRef = _firestore
        .collection(BADORDER_COLLECTION_REF)
        .withConverter<BadOrder>(
          fromFirestore: (snapshots, _) =>
              BadOrder.fromJson(snapshots.data()!, snapshots.id),
          toFirestore: (badorder, _) => badorder.toJson(),
        );
  }

  Stream<QuerySnapshot<BadOrder>> getListBadOrder() {
    return _badorderRef.orderBy('badorderDate', descending: true).snapshots();
  }

  Future<String> addBadOrder(BadOrder badorder) async {
    final docRef = await _badorderRef.add(badorder);
    return docRef.id;
  }

  Future<void> updateBadOrder(String badorderID, BadOrder badorder) async {
    await _badorderRef.doc(badorderID).update(badorder.toJson());
  }

  Future<void> updateBadOrderStatus(
    String badorderID,
    String status, {
    required String updatedBy,
    String page = '',
  }) async {
    await _badorderRef.doc(badorderID).update({
      'status': status,
      'lastUpdatedBy': updatedBy,
      'lastupdatedDate': Timestamp.now(),
      'lastUpdatedPage': page,
    });
  }

  Future<void> deleteBadOrder(String badorderID) async {
    await _badorderRef.doc(badorderID).delete();
  }
}
