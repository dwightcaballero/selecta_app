import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/models/breakdown.dart';

// ignore: constant_identifier_names
const String BREAKDOWN_COLLECTION_REF = 'breakdown';

class BreakdownService {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference _breakdownRef;

  BreakdownService() {
    _breakdownRef = _firestore
        .collection(BREAKDOWN_COLLECTION_REF)
        .withConverter<Breakdown>(
          fromFirestore: (snapshots, _) =>
              Breakdown.fromJson(snapshots.data()!),
          toFirestore: (breakdown, _) => breakdown.toJson(),
        );
  }

  Future<Breakdown?> getDocumentsBySpecificDate(DateTime breakdownDate) async {
    DateTime startOfDay = DateTime(
      breakdownDate.year,
      breakdownDate.month,
      breakdownDate.day,
    );
    DateTime endOfDay = DateTime(
      breakdownDate.year,
      breakdownDate.month,
      breakdownDate.day,
      23,
      59,
      59,
    );

    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection(BREAKDOWN_COLLECTION_REF)
          .where(
            'breakdownDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where(
            'breakdownDate',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
          )
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) return null;

      return querySnapshot.docs.map((doc) {
        return Breakdown.fromJson(doc.data() as Map<String, dynamic>);
      }).first;
    } catch (e) {
      return null;
    }
  }

  Future<String> getIDofBreakdown(DateTime breakdownDate) async {
    DateTime startOfDay = DateTime(
      breakdownDate.year,
      breakdownDate.month,
      breakdownDate.day,
    );
    DateTime endOfDay = DateTime(
      breakdownDate.year,
      breakdownDate.month,
      breakdownDate.day,
      23,
      59,
      59,
    );

    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection(BREAKDOWN_COLLECTION_REF)
          .where(
            'breakdownDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where(
            'breakdownDate',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
          )
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) return '';

      return querySnapshot.docs[0].id;
    } catch (e) {
      return '';
    }
  }

  void addBreakdown(Breakdown breakdown) {
    _breakdownRef.add(breakdown);
  }

  void updateBreakdown(String breakdownID, Breakdown breakdown) {
    _breakdownRef.doc(breakdownID).update(breakdown.toJson());
  }

  void deleteBreakdown(String breakdownID) {
    _breakdownRef.doc(breakdownID).delete();
  }
}
