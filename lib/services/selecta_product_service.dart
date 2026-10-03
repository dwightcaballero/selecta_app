import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/admin_selecta_product.dart';
import 'package:selecta_ops/models/selecta_product.dart';
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
  /// and vice-versa so no products are dropped.
  Future<void> ensureAdminCatalogSeededFromExisting() async {
    final adminSnap = await _firestore.collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF).get();
    final existingSnap = await _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).get();

    if (existingSnap.docs.isEmpty && adminSnap.docs.isEmpty) return;

    final existingAdminNames = <String>{};
    for (final doc in adminSnap.docs) {
      final name = (doc.data()['productName'] as String? ?? '').trim().toLowerCase();
      if (name.isNotEmpty) existingAdminNames.add(name);
    }

    final batch = _firestore.batch();
    final now = Timestamp.now();
    bool hasBatched = false;

    for (final doc in existingSnap.docs) {
      final name = (doc.data()['productName'] as String? ?? '').trim().toLowerCase();
      if (name.isNotEmpty && !existingAdminNames.contains(name)) {
        final adminProduct = AdminSelectaProduct.fromJson(doc.id, doc.data().cast<String, Object?>());
        if (adminProduct.productName.isEmpty) continue;
        final ref = _firestore.collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF).doc(doc.id);
        batch.set(ref, {
          ...adminProduct.toJson(),
          'createdAt': adminProduct.createdAt ?? now,
          'updatedAt': adminProduct.updatedAt ?? now,
        });
        existingAdminNames.add(name);
        hasBatched = true;
      }
    }

    if (hasBatched) {
      await batch.commit();
    }
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
        'category': product.category,
        'tag': product.tag,
        'isActive': true,
        'importedAt': now,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    return docRef.id;
  }

  /// Updates an existing [AdminSelectaProduct] (Admin only) and updates local dealer catalog prices/name/image/category.
  Future<void> updateAdminProduct(String productId, AdminSelectaProduct product) async {
    final now = Timestamp.now();
    await _firestore.collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF).doc(productId).set(
      {
        'productName': product.productName,
        'imageUrl': product.imageUrl,
        'buyingPrice': product.buyingPrice,
        'sellingPrice': product.sellingPrice,
        'category': product.category,
        'tag': product.tag,
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
        'category': product.category,
        'tag': product.tag,
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

  /// Exports all [AdminSelectaProduct] records as CSV text.
  Future<String> exportAdminProductsToCsvString() async {
    final products = await getAllAdminProducts();
    final buffer = StringBuffer();
    buffer.writeln('Product Name,Buying Price,Selling Price,Category,Tag,Image URL,ID');
    for (final p in products) {
      buffer.writeln(
        '${_escapeCsv(p.productName)},'
        '${p.buyingPrice.toStringAsFixed(2)},'
        '${p.sellingPrice.toStringAsFixed(2)},'
        '${_escapeCsv(p.category)},'
        '${_escapeCsv(p.tag)},'
        '${_escapeCsv(p.imageUrl)},'
        '${_escapeCsv(p.id)}',
      );
    }
    return buffer.toString();
  }

  /// Saves the exported Admin Catalog to a local `.csv` file and returns the [File].
  Future<File> exportAdminProductsToCsvFile() async {
    final csvString = await exportAdminProductsToCsvString();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/selecta_admin_catalog.csv');
    await file.writeAsString(csvString);
    return file;
  }

  static String _escapeCsv(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n') || field.contains('\r')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  /// Saves a list of [AdminSelectaProduct] into Firestore, matching existing records by ID
  /// or lowercase name to prevent duplicates, then syncs with dealer products.
  Future<int> _saveAdminProductsToFirestore(List<AdminSelectaProduct> products) async {
    if (products.isEmpty) return 0;

    // Fetch existing admin products to reuse existing doc IDs and prevent duplicates
    final existingSnap = await _firestore.collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF).get();
    final existingByName = <String, String>{};
    for (final doc in existingSnap.docs) {
      final name = (doc.data()['productName'] as String? ?? '').trim().toLowerCase();
      if (name.isNotEmpty) {
        existingByName[name] = doc.id;
      }
    }

    final now = Timestamp.now();
    final savedProducts = <AdminSelectaProduct>[];
    const batchSize = 400;
    for (var i = 0; i < products.length; i += batchSize) {
      final chunk = products.skip(i).take(batchSize);
      final batch = _firestore.batch();
      for (final p in chunk) {
        final existingId = p.id.isNotEmpty
            ? p.id
            : existingByName[p.productName.trim().toLowerCase()];
        final docRef = (existingId != null && existingId.isNotEmpty)
            ? _firestore.collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF).doc(existingId)
            : _firestore.collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF).doc();
        final finalId = docRef.id;
        savedProducts.add(p.copyWith(id: finalId));
        batch.set(
          docRef,
          {
            'productName': p.productName,
            'imageUrl': p.imageUrl,
            'buyingPrice': p.buyingPrice,
            'sellingPrice': p.sellingPrice,
            'category': p.category,
            'tag': p.tag,
            'createdAt': p.createdAt ?? now,
            'updatedAt': now,
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }

    // Also sync dealer collection on this database
    await syncDealerProductsWithAdminCatalog(remoteProducts: savedProducts);
    return products.length;
  }

  /// Imports a list of [AdminSelectaProduct] from a raw JSON string into `admin_selecta_products`.
  Future<int> importAdminProductsFromJsonString(String jsonSource) async {
    final products = parseAdminProductsFromJson(jsonSource);
    if (products.isEmpty) {
      throw const FormatException('No valid Selecta products found in JSON.');
    }
    return _saveAdminProductsToFirestore(products);
  }

  /// Imports a list of [AdminSelectaProduct] from a CSV string into `admin_selecta_products`.
  Future<int> importAdminProductsFromCsvString(String csvSource) async {
    final products = parseAdminProductsFromCsv(csvSource);
    if (products.isEmpty) {
      throw const FormatException('No valid Selecta products found in CSV.');
    }
    return _saveAdminProductsToFirestore(products);
  }

  /// Imports products from raw data string, auto-detecting whether it is JSON or CSV.
  Future<int> importAdminProductsFromData(String data) async {
    final products = parseAdminProductsFromData(data);
    if (products.isEmpty) {
      throw const FormatException('No valid Selecta products found in data.');
    }
    return _saveAdminProductsToFirestore(products);
  }

  /// Fetches raw text content from a remote URL.
  Future<String> fetchRawCatalogFromUrl(String url) async {
    final response = await _dio.get<String>(
      url.trim(),
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  /// Imports Admin products from a remote URL (supporting either JSON or CSV, e.g. GitHub raw, Google Sheets CSV).
  Future<int> importAdminProductsFromUrl(String url) async {
    final body = await fetchRawCatalogFromUrl(url);
    return importAdminProductsFromData(body);
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
    if (url != null && (url.contains('dwightcaballero.github.io') || url.contains('importselecta.csv'))) {
      await prefs.remove(_prefKeyCustomApiUrl);
      return null;
    }
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
    // 1. Primary Source: Live master Firestore admin catalog
    try {
      await ensureAdminCatalogSeededFromExisting();
      final localAdmin = await getAllAdminProducts();
      if (localAdmin.isNotEmpty) return localAdmin;
    } catch (_) {
      // Continue to REST API / fallback
    }

    // 2. Fetch from Master Firebase Project (`selectaapp`) via Firestore REST API (cross-DB)
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

    // 3. Fallback: Custom GitHub / JSON API URL (only if Firestore is unavailable or empty)
    final customUrl = await getCustomCatalogApiUrl();
    if (customUrl != null && customUrl.isNotEmpty) {
      try {
        final response = await _dio.get<String>(
          customUrl,
          options: Options(responseType: ResponseType.plain),
        );
        if (response.data != null && response.data!.isNotEmpty) {
          final parsed = parseAdminProductsFromData(response.data!);
          if (parsed.isNotEmpty) return parsed;
        }
      } catch (_) {
        // Fallback exhausted
      }
    }

    // 4. Final safety fallback: ensure seeded and read local collection
    try {
      await ensureAdminCatalogSeededFromExisting();
      return await getAllAdminProducts();
    } catch (_) {
      return [];
    }
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

  /// Parses JSON string into a list of [AdminSelectaProduct].
  static List<AdminSelectaProduct> parseAdminProductsFromJson(String rawJson) {
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


  /// Parses CSV or TSV string into rows and cells, properly handling quotes, escaped quotes, and newlines.
  static List<List<String>> parseCsvRows(String input) {
    final rows = <List<String>>[];
    var trimmed = input.trim();
    if (trimmed.startsWith('\uFEFF')) {
      trimmed = trimmed.substring(1).trim();
    }
    if (trimmed.isEmpty) return rows;

    // Detect delimiter from the first non-empty line
    final firstLine = trimmed.split(RegExp(r'\r\n|\n|\r')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    String delimiter = ',';
    if (!firstLine.contains(',') && firstLine.contains('\t')) {
      delimiter = '\t';
    } else if (!firstLine.contains(',') && firstLine.contains(';')) {
      delimiter = ';';
    }

    var currentRow = <String>[];
    var currentField = StringBuffer();
    var insideQuotes = false;
    var i = 0;

    while (i < trimmed.length) {
      final char = trimmed[i];

      if (char == '"') {
        if (insideQuotes && i + 1 < trimmed.length && trimmed[i + 1] == '"') {
          currentField.write('"');
          i += 2;
          continue;
        } else {
          insideQuotes = !insideQuotes;
          i++;
          continue;
        }
      }

      if (!insideQuotes) {
        if (char == delimiter) {
          currentRow.add(currentField.toString().trim());
          currentField.clear();
          i++;
          continue;
        } else if (char == '\r' || char == '\n') {
          if (char == '\r' && i + 1 < trimmed.length && trimmed[i + 1] == '\n') {
            i++;
          }
          currentRow.add(currentField.toString().trim());
          currentField.clear();
          if (currentRow.any((c) => c.isNotEmpty)) {
            rows.add(currentRow);
          }
          currentRow = <String>[];
          i++;
          continue;
        }
      }

      currentField.write(char);
      i++;
    }

    currentRow.add(currentField.toString().trim());
    if (currentRow.any((c) => c.isNotEmpty)) {
      rows.add(currentRow);
    }

    return rows;
  }

  /// Parses CSV text into a list of [AdminSelectaProduct].
  /// Matches standard column headers (Product Name, Buying Price, Selling Price, Category, Image URL, ID)
  /// or falls back to standard column positions. Cleans prices with currency symbols (e.g. ₱, $).
  static List<AdminSelectaProduct> parseAdminProductsFromCsv(String csvSource) {
    final rows = parseCsvRows(csvSource);
    if (rows.isEmpty) {
      throw const FormatException('CSV data is empty.');
    }

    final firstRow = rows.first;
    int nameCol = -1;
    int buyingPriceCol = -1;
    int sellingPriceCol = -1;
    int priceCol = -1;
    int categoryCol = -1;
    int tagCol = -1;
    int imageCol = -1;
    int idCol = -1;

    String normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    for (var i = 0; i < firstRow.length; i++) {
      final header = normalize(firstRow[i]);
      if (header.contains('productname') ||
          header == 'product' ||
          header == 'itemname' ||
          header == 'item' ||
          header == 'name' ||
          header == 'description' ||
          header == 'title') {
        nameCol = i;
      } else if (header.contains('buyingprice') ||
          header.contains('cost') ||
          header.contains('buyprice') ||
          header == 'buying' ||
          header.contains('dealerprice') ||
          header.contains('purchaseprice')) {
        buyingPriceCol = i;
      } else if (header.contains('sellingprice') ||
          header.contains('retailprice') ||
          header == 'srp' ||
          header == 'selling' ||
          header.contains('sellprice') ||
          header.contains('retail')) {
        sellingPriceCol = i;
      } else if (header == 'price') {
        priceCol = i;
      } else if (header.contains('category') ||
          header == 'cat' ||
          header == 'type' ||
          header.contains('classification')) {
        categoryCol = i;
      } else if (header.contains('tag') ||
          header == 'label' ||
          header == 'badge') {
        tagCol = i;
      } else if (header.contains('image') ||
          header.contains('photo') ||
          header.contains('picture') ||
          header == 'img' ||
          header == 'pic' ||
          header == 'url') {
        imageCol = i;
      } else if (header == 'id' ||
          header.contains('itemcode') ||
          header.contains('code') ||
          header.contains('productid')) {
        idCol = i;
      }
    }

    final hasHeader = nameCol != -1 || buyingPriceCol != -1 || sellingPriceCol != -1 || priceCol != -1;
    final startIndex = hasHeader ? 1 : 0;

    if (!hasHeader) {
      nameCol = 0;
      if (firstRow.length > 1) buyingPriceCol = 1;
      if (firstRow.length > 2) sellingPriceCol = 2;
      if (firstRow.length > 3) categoryCol = 3;
      if (firstRow.length > 4) imageCol = 4;
      if (firstRow.length > 5) idCol = 5;
    } else {
      if (sellingPriceCol == -1 && priceCol != -1) {
        sellingPriceCol = priceCol;
      }
      if (buyingPriceCol == -1 && priceCol != -1) {
        buyingPriceCol = priceCol;
      }
    }

    final products = <AdminSelectaProduct>[];
    for (var r = startIndex; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty || (row.length == 1 && row[0].trim().isEmpty)) continue;

      String getCol(int idx) => (idx >= 0 && idx < row.length) ? row[idx].trim() : '';

      final name = nameCol >= 0 ? getCol(nameCol) : (row.isNotEmpty ? row[0].trim() : '');
      if (name.isEmpty) continue;

      double parseNum(int idx) {
        if (idx < 0 || idx >= row.length) return 0.0;
        final raw = row[idx].replaceAll(RegExp(r'[^0-9.]'), '');
        return double.tryParse(raw) ?? 0.0;
      }

      var buyingPrice = parseNum(buyingPriceCol);
      var sellingPrice = parseNum(sellingPriceCol);
      if (buyingPrice == 0.0 && priceCol >= 0) buyingPrice = parseNum(priceCol);
      if (sellingPrice == 0.0 && priceCol >= 0) sellingPrice = parseNum(priceCol);
      if (buyingPrice == 0.0 && sellingPrice > 0.0) buyingPrice = sellingPrice;
      if (sellingPrice == 0.0 && buyingPrice > 0.0) sellingPrice = buyingPrice;

      final catRaw = categoryCol >= 0 ? getCol(categoryCol) : '';
      final isCase = catRaw.toLowerCase().contains('case');
      final category = isCase ? 'By Case' : 'By Piece';

      final imageUrl = imageCol >= 0 ? getCol(imageCol) : '';
      final tag = tagCol >= 0 ? getCol(tagCol) : '';
      final id = idCol >= 0 ? getCol(idCol) : '';

      products.add(
        AdminSelectaProduct(
          id: id,
          productName: name,
          imageUrl: imageUrl,
          buyingPrice: buyingPrice,
          sellingPrice: sellingPrice,
          category: category,
          tag: tag,
        ),
      );
    }

    if (products.isEmpty) {
      throw const FormatException('No valid Selecta products found in CSV data.');
    }
    return products;
  }

  /// Parses either JSON or CSV depending on data format.
  static List<AdminSelectaProduct> parseAdminProductsFromData(String data) {
    final trimmed = data.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Catalog data is empty.');
    }
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List ||
            (decoded is Map && (decoded.containsKey('products') || decoded.containsKey('documents')))) {
          return parseAdminProductsFromJson(trimmed);
        }
      } catch (_) {
        // Not valid JSON, fallback to CSV parsing
      }
    }
    return parseAdminProductsFromCsv(trimmed);
  }

  /// Computes a deterministic signature of the Admin catalog so we can detect
  /// whenever any product is added, deleted, renamed, or has its price/image changed.
  static String computeCatalogSignature(List<AdminSelectaProduct> products) {
    final sorted = List<AdminSelectaProduct>.from(products)..sort((a, b) {
      final nameComp = a.productName.trim().toLowerCase().compareTo(b.productName.trim().toLowerCase());
      if (nameComp != 0) return nameComp;
      return a.id.compareTo(b.id);
    });
    final buffer = StringBuffer();
    for (final p in sorted) {
      final isCase = p.category.trim().toLowerCase().contains('case');
      buffer
        ..write(p.productName.trim().toLowerCase())
        ..write('|')
        ..write(p.buyingPrice.toStringAsFixed(2))
        ..write('|')
        ..write(p.sellingPrice.toStringAsFixed(2))
        ..write('|')
        ..write(isCase ? 'case' : 'piece')
        ..write('|')
        ..write(p.imageUrl.trim())
        ..write('|')
        ..write(p.tag.trim())
        ..write(';');
    }
    var hash = 0x811c9dc5;
    final str = buffer.toString();
    for (var i = 0; i < str.length; i++) {
      hash ^= str.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xffffffff;
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

      // Fast check: if the recorded sync signature matches the remote signature
      // and local product count matches the remote product count, we are fully up-to-date!
      if (lastSyncSignature == remoteSignature && localSnapshot.docs.length == remoteProducts.length) {
        return (needsSync: false, remoteProducts: remoteProducts, reason: '');
      }

      // Check whether the local catalog content matches the remote catalog signature
      final localAsAdmin = localSnapshot.docs
          .map((d) => AdminSelectaProduct.fromJson(d.id, d.data().cast<String, Object?>()))
          .toList();
      final localSignature = computeCatalogSignature(localAsAdmin);

      if (localSignature == remoteSignature) {
        // Local database already matches remote catalog; update the stored pref so future checks are instant
        if (lastSyncSignature != remoteSignature) {
          await prefs.setString(_prefKeyLastSyncSignature, remoteSignature);
        }
        return (needsSync: false, remoteProducts: remoteProducts, reason: '');
      }

      return (
        needsSync: true,
        remoteProducts: remoteProducts,
        reason: 'Updating Selecta products with the latest catalog changes...',
      );
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
        final int preservedStockQuantity = existingData != null
            ? ((existingData['stockQuantity'] as num?)?.toInt() ?? 0)
            : 0;
        final int preservedLowStockThreshold = existingData != null
            ? ((existingData['lowStockThreshold'] as num?)?.toInt() ?? 10)
            : 10;
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

          final oldCat = (existingData['category'] as String? ?? '').trim();
          final oldTag = (existingData['tag'] as String? ?? '').trim();

          if (oldName != adminProd.productName ||
              oldImg != adminProd.imageUrl ||
              oldBuy != adminProd.buyingPrice ||
              oldSell != adminProd.sellingPrice ||
              oldCat != adminProd.category ||
              oldTag != adminProd.tag) {
            updatedCount++;
          }
        }

        final targetCategory = adminProd.category.isNotEmpty
            ? adminProd.category
            : (preservedCategory.isNotEmpty ? preservedCategory : 'By Piece');

        final dealerProduct = SelectaProduct.fromAdminProduct(
          id: targetId,
          productName: adminProd.productName,
          imageUrl: adminProd.imageUrl,
          buyingPrice: adminProd.buyingPrice,
          sellingPrice: adminProd.sellingPrice,
          isActive: preservedIsActive,
          stockQuantity: preservedStockQuantity,
          lowStockThreshold: preservedLowStockThreshold,
          itemCode: preservedItemCode,
          category: targetCategory,
          tag: adminProd.tag,
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

  /// Fetches all active products tagged as "Best Seller" from the local dealer catalog.
  /// If none found in `selecta_products`, also checks `admin_selecta_products`.
  Future<List<SelectaProduct>> getBestSellerProducts() async {
    final snapshot = await _firestore
        .collection(SELECTA_PRODUCTS_COLLECTION_REF)
        .where('tag', isEqualTo: ProductTag.bestSeller)
        .get();

    var products = snapshot.docs
        .map((doc) => SelectaProduct.fromJson(doc.id, doc.data()))
        .where((p) => p.isActive)
        .toList();

    if (products.isEmpty) {
      // Fallback: Check admin collection directly
      final adminSnap = await _firestore
          .collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF)
          .where('tag', isEqualTo: ProductTag.bestSeller)
          .get();
      products = adminSnap.docs.map((doc) {
        final adminProd = AdminSelectaProduct.fromSnapshot(doc);
        return SelectaProduct.fromAdminProduct(
          id: adminProd.id,
          productName: adminProd.productName,
          imageUrl: adminProd.imageUrl,
          buyingPrice: adminProd.buyingPrice,
          sellingPrice: adminProd.sellingPrice,
          category: adminProd.category,
          tag: adminProd.tag,
        );
      }).toList();
    }

    return products;
  }
}
