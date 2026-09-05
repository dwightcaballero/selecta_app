import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/models/dealer.dart';

// ignore: constant_identifier_names
const String DEALER_COLLECTION_REF = 'dealers';

class DealerService {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference _dealerRef;

  DealerService() {
    _dealerRef = _firestore
        .collection(DEALER_COLLECTION_REF)
        .withConverter<Dealer>(
          fromFirestore: (snapshots, _) => Dealer.fromJson(snapshots.data()!),
          toFirestore: (dealer, _) => dealer.toJson(),
        );
  }

  Future<Dealer?> getDealerByName(String dealerName) async {
    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection(DEALER_COLLECTION_REF)
          .where('dealerName', isEqualTo: dealerName)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        var result = querySnapshot.docs.map((doc) {
          return Dealer.fromJson(doc.data() as Map<String, dynamic>);
        }).first;
        return result;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  void addDealer(Dealer dealer) {
    _dealerRef.add(dealer);
  }

  void updateDealer(String dealerID, Dealer dealer) {
    _dealerRef.doc(dealerID).update(dealer.toJson());
  }

  void deleteDealer(String dealerID) {
    _dealerRef.doc(dealerID).delete();
  }
}
