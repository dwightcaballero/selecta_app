import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter_app/firebase_options.dart';
import 'package:flutter_app/models/admin_selecta_product.dart';
import 'package:flutter_app/models/selecta_product.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: constant_identifier_names
const String ADMIN_SELECTA_PRODUCTS_COLLECTION_REF = 'admin_selecta_products';
// ignore: constant_identifier_names
const String SELECTA_PRODUCTS_COLLECTION_REF = 'selecta_products';

/// Result of a dealer catalog sync operation.
class SelectaCatalogSyncResult {
  final int totalFetched;
  final int addedCount;
  final int updatedCount;
  final String versionSignature;

  const SelectaCatalogSyncResult({
    required this.totalFetched,
    required this.addedCount,
    required this.updatedCount,
    required this.versionSignature,
  });
}

/// Service for both:
/// 1. [AdminSelectaProduct] (Master Admin Catalog: `admin_selecta_products` & cross-DB REST/GitHub API)
/// 2. [SelectaProduct] (Dealer's Local Catalog: `selecta_products` where dealers toggle `isActive`)
class SelectaProductService {
  final _firestore = FirebaseFirestore.instance;

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
    ),
  );

  /// Central Master Firebase Project ID (`selectaapp`) for cross-database REST API syncing.
  static const String masterFirebaseProjectId = 'selectaapp';

  static const String _prefKeyLastSyncSignature = 'selecta_catalog_sync_signature_v1';
  static const String _prefKeyCustomApiUrl = 'selecta_catalog_custom_api_url_v1';

  // ═══════════════════════════════════════════════════════════════════════════
  // DEALER MODEL (`SelectaProduct` in `selecta_products` collection)
  // Dealers read from their own collection and only toggle `isActive`.
  // ═══════════════════════════════════════════════════════════════════════════

  /// Real-time stream of dealer's Selecta products stored in local Firestore.
  Stream<QuerySnapshot<Map<String, dynamic>>> getProductsStream() {
    return _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).orderBy('productName').snapshots();
  }

  /// One-time list of dealer's Selecta products.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getAllProducts() async {
    final snapshot = await _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).orderBy('productName').get();
    return snapshot.docs;
  }

  /// Toggles the [isActive] flag for a single dealer Selecta product.
  Future<void> toggleProductActive(String productId, bool isActive) async {
    await _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).doc(productId).update({
      'isActive': isActive,
      'updatedAt': Timestamp.now(),
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADMIN MODEL (`AdminSelectaProduct` in `admin_selecta_products` collection)
  // Admins have full Create, Read, Update, Delete, Import, and Export access.
  // ═══════════════════════════════════════════════════════════════════════════

  /// Real-time stream of Admin Selecta products.
  /// Falls back to reading `selecta_products` if `admin_selecta_products` is empty
  /// so existing products are seamlessly migrated.
  Stream<QuerySnapshot<Map<String, dynamic>>> getAdminProductsStream() {
    return _firestore.collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF).orderBy('productName').snapshots();
  }

  /// Ensures `admin_selecta_products` is populated from existing `selecta_products`
  /// on the master database if `admin_selecta_products` is currently empty.
  Future<void> ensureAdminCatalogSeededFromExisting() async {
    final adminSnap = await _firestore.collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF).limit(1).get();
    if (adminSnap.docs.isNotEmpty) return;

    final existingSnap = await _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).get();
    if (existingSnap.docs.isEmpty) return;

    final batch = _firestore.batch();
    final now = Timestamp.now();
    for (final doc in existingSnap.docs) {
      final adminProduct = AdminSelectaProduct.fromJson(doc.id, doc.data().cast<String, Object?>());
      if (adminProduct.productName.isEmpty) continue;
      final ref = _firestore.collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF).doc(doc.id);
      batch.set(ref, {
        ...adminProduct.toJson(),
        'createdAt': adminProduct.createdAt ?? now,
        'updatedAt': adminProduct.updatedAt ?? now,
      });
    }
    await batch.commit();
  }

  /// Returns all Admin Selecta products.
  Future<List<AdminSelectaProduct>> getAllAdminProducts() async {
    await ensureAdminCatalogSeededFromExisting();
    final snapshot = await _firestore.collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF).orderBy('productName').get();
    return snapshot.docs.map((doc) => AdminSelectaProduct.fromSnapshot(doc)).toList();
  }

  /// Adds a new [AdminSelectaProduct] (Admin only) and also updates the local dealer catalog.
  Future<String> addAdminProduct(AdminSelectaProduct product) async {
    final now = Timestamp.now();
    final data = {
      ...product.toJson(),
      'createdAt': now,
      'updatedAt': now,
    };

    final docRef = await _firestore.collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF).add(data);

    // Also keep local `selecta_products` in sync on this database
    final dealerRef = _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).doc(docRef.id);
    await dealerRef.set(
      {
        'productName': product.productName,
        'imageUrl': product.imageUrl,
        'buyingPrice': product.buyingPrice,
        'sellingPrice': product.sellingPrice,
        'price': product.sellingPrice,
        'itemCode': '',
        'category': '',
        'isActive': true,
        'importedAt': now,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    return docRef.id;
  }

  /// Updates an existing [AdminSelectaProduct] (Admin only) and updates local dealer catalog prices/name/image.
  Future<void> updateAdminProduct(String productId, AdminSelectaProduct product) async {
    final now = Timestamp.now();
    await _firestore.collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF).doc(productId).set(
      {
        'productName': product.productName,
        'imageUrl': product.imageUrl,
        'buyingPrice': product.buyingPrice,
        'sellingPrice': product.sellingPrice,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    // Also update product details in local dealer collection without overwriting dealer's `isActive`
    await _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).doc(productId).set(
      {
        'productName': product.productName,
        'imageUrl': product.imageUrl,
        'buyingPrice': product.buyingPrice,
        'sellingPrice': product.sellingPrice,
        'price': product.sellingPrice,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );
  }

  /// Deletes an [AdminSelectaProduct] (Admin only).
  Future<void> deleteAdminProduct(String productId) async {
    await _firestore.collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF).doc(productId).delete();
    await _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).doc(productId).delete();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADMIN IMPORT & EXPORT (JSON / GitHub / Master Firebase API)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Exports all [AdminSelectaProduct] records as a formatted JSON string
  /// (ready to be hosted on GitHub or imported into another environment).
  Future<String> exportAdminProductsToJsonString() async {
    final products = await getAllAdminProducts();
    final payload = {
      'version': DateTime.now().toUtc().toIso8601String(),
      'count': products.length,
      'products': products.map((p) => p.toExportJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Saves the exported Admin Catalog JSON to a local `.json` file and returns the [File].
  Future<File> exportAdminProductsToFile() async {
    final jsonString = await exportAdminProductsToJsonString();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/selecta_admin_catalog.json');
    await file.writeAsString(jsonString);
    return file;
  }

  /// Imports a list of [AdminSelectaProduct] from a raw JSON string or a remote URL
  /// (such as a GitHub Raw JSON URL) into `admin_selecta_products`.
  Future<int> importAdminProductsFromJsonString(String jsonSource) async {
    final products = _parseAdminProductsFromJson(jsonSource);
    if (products.isEmpty) {
      throw const FormatException('No valid Selecta products found in JSON.');
    }

    final now = Timestamp.now();
    const batchSize = 400;
    for (var i = 0; i < products.length; i += batchSize) {
      final chunk = products.skip(i).take(batchSize);
      final batch = _firestore.batch();
      for (final p in chunk) {
        final docRef = p.id.isNotEmpty
            ? _firestore.collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF).doc(p.id)
            : _firestore.collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF).doc();
        batch.set(
          docRef,
          {
            'productName': p.productName,
            'imageUrl': p.imageUrl,
            'buyingPrice': p.buyingPrice,
            'sellingPrice': p.sellingPrice,
            'createdAt': p.createdAt ?? now,
            'updatedAt': now,
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }

    // Also sync dealer collection on this database
    await syncDealerProductsWithAdminCatalog(remoteProducts: products);
    return products.length;
  }

  /// Imports Admin products from a remote JSON URL (e.g., GitHub raw JSON URL).
  Future<int> importAdminProductsFromUrl(String url) async {
    final response = await _dio.get<String>(
      url.trim(),
      options: Options(responseType: ResponseType.plain),
    );
    final body = response.data ?? '';
    return importAdminProductsFromJsonString(body);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CROSS-DATABASE API FETCH & DEALER SYNCING
  // Fetches from:
  // 1. Custom JSON API / GitHub Raw URL (if configured), OR
  // 2. Central Master Firebase Project (`selectaapp`) via Firestore REST API, OR
  // 3. Current Firestore's `admin_selecta_products`
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String?> getCustomCatalogApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_prefKeyCustomApiUrl)?.trim();
    return (url != null && url.isNotEmpty) ? url : null;
  }

  Future<void> setCustomCatalogApiUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.trim().isEmpty) {
      await prefs.remove(_prefKeyCustomApiUrl);
    } else {
      await prefs.setString(_prefKeyCustomApiUrl, url.trim());
    }
  }

  /// Fetches the authoritative list of [AdminSelectaProduct] from the central API source.
  /// Works even when the dealer is on a completely separate Firebase project/database.
  Future<List<AdminSelectaProduct>> fetchMasterAdminCatalogFromApi() async {
    // 1. Check if a custom GitHub / JSON API URL is configured
    final customUrl = await getCustomCatalogApiUrl();
    if (customUrl != null && customUrl.isNotEmpty) {
      try {
        final response = await _dio.get<String>(
          customUrl,
          options: Options(responseType: ResponseType.plain),
        );
        if (response.data != null && response.data!.isNotEmpty) {
          final parsed = _parseAdminProductsFromJson(response.data!);
          if (parsed.isNotEmpty) return parsed;
        }
      } catch (_) {
        // Fall through to Master Firebase REST API
      }
    }

    // 2. If connected to the master Firebase project directly, ensure `admin_selecta_products` is seeded
    final currentProjectId = DefaultFirebaseOptions.currentPlatform.projectId;
    if (currentProjectId == masterFirebaseProjectId) {
      await ensureAdminCatalogSeededFromExisting();
      final localAdmin = await getAllAdminProducts();
      if (localAdmin.isNotEmpty) return localAdmin;
    }

    // 3. Fetch from Master Firebase Project (`selectaapp`) via Firestore REST API
    // First try `admin_selecta_products`, then fallback to `selecta_products` on the master project.
    for (final collectionName in [
      ADMIN_SELECTA_PRODUCTS_COLLECTION_REF,
      SELECTA_PRODUCTS_COLLECTION_REF,
    ]) {
      try {
        final fetched = await _fetchFromFirestoreRestApi(
          projectId: masterFirebaseProjectId,
          collectionName: collectionName,
        );
        if (fetched.isNotEmpty) {
          return fetched;
        }
      } catch (_) {
        // Continue to fallback
      }
    }

    // 4. Final fallback: read from current Firestore instance
    await ensureAdminCatalogSeededFromExisting();
    return getAllAdminProducts();
  }

  Future<List<AdminSelectaProduct>> _fetchFromFirestoreRestApi({
    required String projectId,
    required String collectionName,
  }) async {
    final results = <AdminSelectaProduct>[];
    String? pageToken;

    do {
      final queryParams = <String, dynamic>{'pageSize': 300};
      if (pageToken != null && pageToken.isNotEmpty) {
        queryParams['pageToken'] = pageToken;
      }

      final url =
          'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$collectionName';
      final response = await _dio.get<Map<String, dynamic>>(
        url,
        queryParameters: queryParams,
      );

      final data = response.data;
      if (data == null) break;

      final docs = data['documents'] as List<dynamic>?;
      if (docs != null) {
        for (final rawDoc in docs) {
          if (rawDoc is Map<String, dynamic>) {
            final product = AdminSelectaProduct.fromFirestoreRestDoc(rawDoc);
            if (product.productName.isNotEmpty) {
              results.add(product);
            }
          }
        }
      }

      pageToken = data['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);

    results.sort((a, b) => a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));
    return results;
  }

  List<AdminSelectaProduct> _parseAdminProductsFromJson(String rawJson) {
    final decoded = jsonDecode(rawJson);
    List<dynamic> list = [];
    if (decoded is List) {
      list = decoded;
    } else if (decoded is Map<String, dynamic>) {
      if (decoded['products'] is List) {
        list = decoded['products'] as List<dynamic>;
      } else if (decoded['documents'] is List) {
        // Firestore REST format
        return (decoded['documents'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map(AdminSelectaProduct.fromFirestoreRestDoc)
            .where((p) => p.productName.isNotEmpty)
            .toList();
      }
    }

    final results = <AdminSelectaProduct>[];
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is Map) {
        final map = item.cast<String, Object?>();
        final id = (map['id'] as String? ?? map['itemCode'] as String? ?? '').trim();
        final product = AdminSelectaProduct.fromJson(id, map);
        if (product.productName.isNotEmpty) {
          results.add(product);
        }
      }
    }
    return results;
  }

  /// Computes a deterministic signature of the Admin catalog so we can detect
  /// whenever any product is added, deleted, renamed, or has its price/image changed.
  String computeCatalogSignature(List<AdminSelectaProduct> products) {
    final sorted = [...products]..sort((a, b) => a.id.compareTo(b.id));
    final buffer = StringBuffer();
    for (final p in sorted) {
      buffer
        ..write(p.id)
        ..write('|')
        ..write(p.productName)
        ..write('|')
        ..write(p.buyingPrice.toStringAsFixed(2))
        ..write('|')
        ..write(p.sellingPrice.toStringAsFixed(2))
        ..write('|')
        ..write(p.imageUrl)
        ..write(';');
    }
    var hash = 0xcbf29ce484222325;
    final str = buffer.toString();
    for (var i = 0; i < str.length; i++) {
      hash ^= str.codeUnitAt(i);
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return '${sorted.length}_${hash.toRadixString(16)}';
  }

  /// Checks whether the local dealer database needs to sync with the master Admin catalog
  /// (either first-time load with empty local catalog, or changes detected in the Admin API).
  Future<({bool needsSync, List<AdminSelectaProduct> remoteProducts, String reason})> checkSyncNeeded() async {
    try {
      final remoteProducts = await fetchMasterAdminCatalogFromApi();
      if (remoteProducts.isEmpty) {
        return (needsSync: false, remoteProducts: <AdminSelectaProduct>[], reason: '');
      }

      final localSnapshot = await _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).get();
      if (localSnapshot.docs.isEmpty) {
        return (
          needsSync: true,
          remoteProducts: remoteProducts,
          reason: 'Initializing Selecta product catalog for the first time...',
        );
      }

      final remoteSignature = computeCatalogSignature(remoteProducts);
      final prefs = await SharedPreferences.getInstance();
      final lastSyncSignature = prefs.getString(_prefKeyLastSyncSignature);

      // Also verify if local product count or fields differ from remote
      final localAsAdmin = localSnapshot.docs
          .map((d) => AdminSelectaProduct.fromJson(d.id, d.data().cast<String, Object?>()))
          .toList();
      final localSignature = computeCatalogSignature(localAsAdmin);

      if (lastSyncSignature != remoteSignature || localSignature != remoteSignature) {
        return (
          needsSync: true,
          remoteProducts: remoteProducts,
          reason: 'Updating Selecta products with the latest catalog changes...',
        );
      }

      return (needsSync: false, remoteProducts: remoteProducts, reason: '');
    } catch (_) {
      return (needsSync: false, remoteProducts: <AdminSelectaProduct>[], reason: '');
    }
  }

  /// Syncs the dealer's local `selecta_products` collection with the master [AdminSelectaProduct] list.
  /// Preserves each dealer's existing `isActive` status for existing products and defaults new products to `true`.
  Future<SelectaCatalogSyncResult> syncDealerProductsWithAdminCatalog({
    List<AdminSelectaProduct>? remoteProducts,
    void Function(int current, int total, String status)? onProgress,
  }) async {
    onProgress?.call(0, 1, 'Fetching master Selecta product catalog...');
    final masterList = remoteProducts ?? await fetchMasterAdminCatalogFromApi();
    final total = masterList.length;

    if (total == 0) {
      return const SelectaCatalogSyncResult(
        totalFetched: 0,
        addedCount: 0,
        updatedCount: 0,
        versionSignature: '0_0',
      );
    }

    onProgress?.call(0, total, 'Reading local dealer product status...');
    final existingSnap = await _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).get();
    final existingMap = <String, Map<String, dynamic>>{};
    final existingByName = <String, DocumentSnapshot<Map<String, dynamic>>>{};

    for (final doc in existingSnap.docs) {
      existingMap[doc.id] = doc.data();
      final nameKey = (doc.data()['productName'] as String? ?? '').trim().toLowerCase();
      if (nameKey.isNotEmpty) {
        existingByName[nameKey] = doc;
      }
    }

    int addedCount = 0;
    int updatedCount = 0;
    final now = Timestamp.now();
    final remoteIds = <String>{};

    const batchSize = 350;
    for (var i = 0; i < masterList.length; i += batchSize) {
      final chunk = masterList.skip(i).take(batchSize).toList();
      final batch = _firestore.batch();

      for (var j = 0; j < chunk.length; j++) {
        final adminProd = chunk[j];
        final nameKey = adminProd.productName.trim().toLowerCase();
        final matchedByName = existingByName[nameKey];

        final targetId = adminProd.id.isNotEmpty
            ? adminProd.id
            : (matchedByName?.id ?? _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).doc().id);
        remoteIds.add(targetId);

        final existingData = existingMap[targetId] ?? matchedByName?.data();
        final bool preservedIsActive = existingData != null
            ? (existingData['isActive'] as bool? ?? true)
            : true;
        final String preservedItemCode = existingData != null
            ? (existingData['itemCode'] as String? ?? '')
            : '';
        final String preservedCategory = existingData != null
            ? (existingData['category'] as String? ?? '')
            : '';
        final Timestamp importedAt = existingData != null && existingData['importedAt'] is Timestamp
            ? existingData['importedAt'] as Timestamp
            : now;

        if (existingData == null) {
          addedCount++;
        } else {
          final oldName = (existingData['productName'] as String? ?? '').trim();
          final oldImg = (existingData['imageUrl'] as String? ?? '').trim();
          final oldBuy = (existingData['buyingPrice'] as num?)?.toDouble() ?? 0.0;
          final oldSell = (existingData['sellingPrice'] as num?)?.toDouble() ?? 0.0;

          if (oldName != adminProd.productName ||
              oldImg != adminProd.imageUrl ||
              oldBuy != adminProd.buyingPrice ||
              oldSell != adminProd.sellingPrice) {
            updatedCount++;
          }
        }

        final dealerProduct = SelectaProduct.fromAdminProduct(
          id: targetId,
          productName: adminProd.productName,
          imageUrl: adminProd.imageUrl,
          buyingPrice: adminProd.buyingPrice,
          sellingPrice: adminProd.sellingPrice,
          isActive: preservedIsActive,
          itemCode: preservedItemCode,
          category: preservedCategory,
          importedAt: importedAt,
          updatedAt: now,
        );

        final docRef = _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).doc(targetId);
        batch.set(docRef, dealerProduct.toJson(), SetOptions(merge: true));

        final processed = i + j + 1;
        onProgress?.call(processed, total, 'Syncing ${adminProd.productName} ($processed/$total)...');
      }

      await batch.commit();
    }

    // Remove local products that were deleted from the master admin catalog
    final deletedDocs = existingSnap.docs.where((d) => !remoteIds.contains(d.id)).toList();
    if (deletedDocs.isNotEmpty) {
      final deleteBatch = _firestore.batch();
      for (final doc in deletedDocs) {
        deleteBatch.delete(doc.reference);
      }
      await deleteBatch.commit();
    }

    final signature = computeCatalogSignature(masterList);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyLastSyncSignature, signature);

    return SelectaCatalogSyncResult(
      totalFetched: total,
      addedCount: addedCount,
      updatedCount: updatedCount,
      versionSignature: signature,
    );
  }
}
