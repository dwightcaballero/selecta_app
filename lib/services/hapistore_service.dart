import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/models/hapistore.dart';

// ignore: constant_identifier_names
const String HAPISTORE_COLLECTION_REF = 'hapistores';

class HapiStoreService {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference _hapistoresRef;

  HapiStoreService() {
    _hapistoresRef = _firestore
        .collection(HAPISTORE_COLLECTION_REF)
        .withConverter<Hapistore>(
          fromFirestore: (snapshots, _) => Hapistore.fromJson(snapshots.data()!),
          toFirestore: (hapistore, _) => hapistore.toJson(),
        );
  }

  void addHapiStore(Hapistore hapistore) {
    _hapistoresRef.add(hapistore);
  }

  void updateHapiStore(String hapiStoreID, Hapistore hapistore) {
    _hapistoresRef.doc(hapiStoreID).update(hapistore.toJson());
  }

  void deleteHapiStore(String hapiStoreID) {
    _hapistoresRef.doc(hapiStoreID).delete();
  }

  Stream<QuerySnapshot> getListHapiStoresAsStream() {
    return _hapistoresRef.orderBy('storeName').snapshots();
  }

  Stream<QuerySnapshot> getListHapiStoreSearch(String searchKeyword) {
    return _hapistoresRef
        .orderBy('storeName')
        .where('storeName', isGreaterThanOrEqualTo: searchKeyword)
        .where('storeName', isLessThanOrEqualTo: '$searchKeyword\uf8ff')
        .snapshots();
  }

  static Future<String> getContactByStoreName(String storeName) async {
    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection(HAPISTORE_COLLECTION_REF)
          .where('storeName', isEqualTo: storeName)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        var result = querySnapshot.docs.map((doc) {
          return Hapistore.fromJson(doc.data() as Map<String, dynamic>);
        }).first;
        return result.storeContact;
      }

      return '';
    } catch (e) {
      return '';
    }
  }

  // Get list hapi stores as a Future (not stream)
  static Future<List<Hapistore>> getListHapiStores() async {
    var snapshot = await FirebaseFirestore.instance.collection(HAPISTORE_COLLECTION_REF).orderBy('storeName').get();
    return snapshot.docs.map((doc) => Hapistore.fromJson(doc.data())).toList();
  }
}
