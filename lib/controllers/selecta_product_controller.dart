import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/models/admin_selecta_product.dart';
import 'package:flutter_app/services/selecta_product_service.dart';

/// Controller for both:
/// - Dealer Selecta Products (`SelectaProduct`): read, sync from Admin catalog, and toggle `isActive` status.
/// - Admin Selecta Products (`AdminSelectaProduct`): full CRUD + Import/Export.
class SelectaProductController {
  final SelectaProductService _service = SelectaProductService();

  // ═══════════════════════════════════════════════════════════════════════════
  // DEALER ACTIONS (`SelectaProduct`)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Real-time stream of dealer's local Selecta products from Firestore.
  Stream<QuerySnapshot<Map<String, dynamic>>> getProductsStream() => _service.getProductsStream();

  /// One-time fetch of dealer's local Selecta products.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getAllProducts() => _service.getAllProducts();

  /// Toggles the active/inactive status of a single dealer product.
  Future<void> toggleActive(String productId, bool isActive) =>
      _service.toggleProductActive(productId, isActive);

  /// Checks if the dealer's local catalog is empty or out-of-sync with the Admin API.
  Future<({bool needsSync, List<AdminSelectaProduct> remoteProducts, String reason})> checkSyncNeeded() =>
      _service.checkSyncNeeded();

  /// Syncs the dealer's `selecta_products` with the master [AdminSelectaProduct] catalog,
  /// preserving the dealer's local `isActive` status for existing items.
  Future<SelectaCatalogSyncResult> syncWithAdminCatalog({
    List<AdminSelectaProduct>? remoteProducts,
    void Function(int current, int total, String status)? onProgress,
  }) =>
      _service.syncDealerProductsWithAdminCatalog(
        remoteProducts: remoteProducts,
        onProgress: onProgress,
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // ADMIN ACTIONS (`AdminSelectaProduct` — imageUrl, productName, buyingPrice, sellingPrice)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Ensures `admin_selecta_products` is seeded from any existing `selecta_products` records.
  Future<void> ensureAdminCatalogSeeded() => _service.ensureAdminCatalogSeededFromExisting();

  /// Real-time stream of Admin Selecta products (`admin_selecta_products`).
  Stream<QuerySnapshot<Map<String, dynamic>>> getAdminProductsStream() =>
      _service.getAdminProductsStream();

  /// Adds a new [AdminSelectaProduct] (Admin only).
  Future<String> addAdminProduct(AdminSelectaProduct product) =>
      _service.addAdminProduct(product);

  /// Updates an existing [AdminSelectaProduct] (Admin only).
  Future<void> updateAdminProduct(String productId, AdminSelectaProduct product) =>
      _service.updateAdminProduct(productId, product);

  /// Deletes an [AdminSelectaProduct] (Admin only).
  Future<void> deleteAdminProduct(String productId) =>
      _service.deleteAdminProduct(productId);

  /// Exports all [AdminSelectaProduct] records as a formatted JSON string.
  Future<String> exportAdminCatalogJson() => _service.exportAdminProductsToJsonString();

  /// Exports all [AdminSelectaProduct] records to a local `.json` file.
  Future<File> exportAdminCatalogToFile() => _service.exportAdminProductsToFile();

  /// Imports [AdminSelectaProduct] records from a JSON string.
  Future<int> importAdminCatalogFromJson(String jsonSource) =>
      _service.importAdminProductsFromJsonString(jsonSource);

  /// Imports [AdminSelectaProduct] records from a remote URL (e.g., GitHub raw JSON).
  Future<int> importAdminCatalogFromUrl(String url) =>
      _service.importAdminProductsFromUrl(url);

  Future<String?> getCustomCatalogApiUrl() => _service.getCustomCatalogApiUrl();

  Future<void> setCustomCatalogApiUrl(String? url) => _service.setCustomCatalogApiUrl(url);

  /// Validates [AdminSelectaProduct] fields. Returns list of error messages (empty = valid).
  List<String> validateAdminProduct(AdminSelectaProduct product) {
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
