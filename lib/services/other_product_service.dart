import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/models/other_product.dart';
import 'package:selecta_ops/services/product_catalog_cache.dart';

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
    ProductCatalogCache().invalidateOther();
    final now = Timestamp.now();
    await _productsRef.add(product.copyWith(createdAt: now, updatedAt: now));
  }

  Future<void> updateProduct(String productId, OtherProduct product) async {
    ProductCatalogCache().invalidateOther();
    final now = Timestamp.now();
    await _firestore.collection(OTHER_PRODUCTS_COLLECTION_REF).doc(productId).update({
      'productName': product.productName,
      'imageUrl': product.imageUrl,
      'barcode': product.barcode,
      'buyingPrice': product.buyingPrice,
      'sellingPrice': product.sellingPrice,
      'isActive': product.isActive,
      'lowStockThreshold': product.lowStockThreshold,
      'updatedAt': now,
    });
  }

  Future<void> deleteProduct(String productId) async {
    ProductCatalogCache().invalidateOther();
    await _productsRef.doc(productId).delete();
  }

  Future<void> toggleProductActive(String productId, bool isActive) async {
    ProductCatalogCache().invalidateOther();
    await _firestore.collection(OTHER_PRODUCTS_COLLECTION_REF).doc(productId).update({
      'isActive': isActive,
      'updatedAt': Timestamp.now(),
    });
  }
}
