import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/models/other_product.dart';

// ignore: constant_identifier_names
const String OTHER_PRODUCTS_COLLECTION_REF = 'other_products';

class OtherProductService {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference _productsRef;

  OtherProductService() {
    _productsRef = _firestore
        .collection(OTHER_PRODUCTS_COLLECTION_REF)
        .withConverter<OtherProduct>(
          fromFirestore: (snapshots, _) => OtherProduct.fromJson(snapshots.data()!),
          toFirestore: (product, _) => product.toJson(),
        );
  }

  Stream<QuerySnapshot<OtherProduct>> getProductsStream() {
    return (_productsRef as Query<OtherProduct>)
        .orderBy('productName')
        .snapshots();
  }

  Future<List<QueryDocumentSnapshot<OtherProduct>>> getAllProducts() async {
    final snapshot = await (_productsRef as Query<OtherProduct>)
        .orderBy('productName')
        .get();
    return snapshot.docs;
  }

  Future<void> addProduct(OtherProduct product) async {
    final now = Timestamp.now();
    await _productsRef.add(product.copyWith(createdAt: now, updatedAt: now));
  }

  Future<void> updateProduct(String productId, OtherProduct product) async {
    await _productsRef
        .doc(productId)
        .update(product.copyWith(updatedAt: Timestamp.now()).toJson());
  }

  Future<void> deleteProduct(String productId) async {
    await _productsRef.doc(productId).delete();
  }

  Future<void> toggleProductActive(String productId, bool isActive) async {
    await _firestore.collection(OTHER_PRODUCTS_COLLECTION_REF).doc(productId).update({
      'isActive': isActive,
      'updatedAt': Timestamp.now(),
    });
  }
}
