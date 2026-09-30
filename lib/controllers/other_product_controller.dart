import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/models/other_product.dart';
import 'package:flutter_app/services/other_product_service.dart';

/// Controller for "Other Products" catalog management.
/// Mediates between OtherProductService (Firestore) and the UI pages.
class OtherProductController {
  final OtherProductService _service = OtherProductService();

  Stream<QuerySnapshot<OtherProduct>> getProductsStream() =>
      _service.getProductsStream();

  Future<List<QueryDocumentSnapshot<OtherProduct>>> getAllProducts() =>
      _service.getAllProducts();

  Future<void> addProduct(OtherProduct product) => _service.addProduct(product);

  Future<void> updateProduct(String productId, OtherProduct product) =>
      _service.updateProduct(productId, product);

  Future<void> deleteProduct(String productId) =>
      _service.deleteProduct(productId);

  Future<void> toggleActive(String productId, bool isActive) =>
      _service.toggleProductActive(productId, isActive);

  /// Validates product fields. Returns list of error messages (empty = valid).
  List<String> validate(OtherProduct product) {
    final errors = <String>[];
    if (product.productName.trim().isEmpty) {
      errors.add('Product name is required.');
    }
    if (product.buyingPrice <= 0) {
      errors.add('Buying price must be greater than 0.');
    }
    if (product.sellingPrice <= 0) {
      errors.add('Selling price must be greater than 0.');
    }
    return errors;
  }
}
