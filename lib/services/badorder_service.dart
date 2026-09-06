import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/models/badorder.dart';

// ignore: constant_identifier_names
const String BADORDER_COLLECTION_REF = 'badorder';

class BadOrderService {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference _badorderRef;

  BadOrderService() {
    _badorderRef = _firestore
        .collection(BADORDER_COLLECTION_REF)
        .withConverter<BadOrder>(
          fromFirestore: (snapshots, _) => BadOrder.fromJson(snapshots.data()!),
          toFirestore: (badorder, _) => badorder.toJson(),
        );
  }

  Stream<QuerySnapshot> getListBadOrder() {
    return _badorderRef.orderBy('badorderDate', descending: true).snapshots();
  }

  Future<double?> getTotalBadOrderForSpecificDay(DateTime badorderDate) async {
    final startOfDay = DateTime(
      badorderDate.year,
      badorderDate.month,
      badorderDate.day,
      0,
      0,
      0,
    );

    final endOfDay = DateTime(
      badorderDate.year,
      badorderDate.month,
      badorderDate.day,
      23,
      59,
      59,
    );

    try {
      // 1. Build the filtered query
      Query query = FirebaseFirestore.instance
          .collection(BADORDER_COLLECTION_REF)
          .where(
            'badorderDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where(
            'badorderDate',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
          );

      // 2. Attach the sum aggregate function
      AggregateQuerySnapshot snapshot = await query
          .aggregate(sum('badorderAmount'))
          .get();

      // 3. Extract and return the calculation result
      return snapshot.getSum('badorderAmount');
    } catch (e) {
      return null;
    }
  }

  void addBadOrder(BadOrder badorder) {
    _badorderRef.add(badorder);
  }

  void updateBadOrder(String badorderID, BadOrder badorder) {
    _badorderRef.doc(badorderID).update(badorder.toJson());
  }

  void deleteBadOrder(String badorderID) {
    _badorderRef.doc(badorderID).delete();
  }
}
