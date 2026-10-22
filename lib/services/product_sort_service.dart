import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/product_sort_doc.dart';
import 'package:selecta_ops/models/sub_category.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: constant_identifier_names
const String PRODUCT_SORT_COLLECTION_REF = 'product_sort';
const String _kPrefProductSortDoc = 'cached_product_sort_doc';
const String _kPrefProductSortMode = 'cached_product_sort_mode';
const String _kPrefProductSubCategories = 'cached_product_sub_categories';

/// Rank metadata of a product in the custom sort hierarchy.
class ProductSortRank {
  final int subCategoryOrder;
  final int productIndex;

  const ProductSortRank({
    required this.subCategoryOrder,
    required this.productIndex,
  });

  @override
  String toString() => 'ProductSortRank(subCategoryOrder: $subCategoryOrder, productIndex: $productIndex)';
}

/// Service managing custom product sorting data, Firestore synchronization,
/// in-memory rank lookups, and offline SharedPreferences caching.
class ProductSortService {
  static final ProductSortService _instance = ProductSortService._internal();
  static ProductSortService get instance => _instance;

  final FirebaseFirestore? _customFirestore;
  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;
  SharedPreferences? _prefs;

  ProductSortDoc? _sortDoc;
  String _sortMode = 'srp';
  List<SubCategory> _subCategories = const [];

  // Fast lookup caches
  final Map<String, int> _subCategoryOrderMap = {};
  final Map<String, bool> _subCategoryActiveMap = {};
  final Map<String, int> _byPieceProductIndex = {};
  final Map<String, String> _byPieceProductSubCat = {};
  final Map<String, int> _byCaseProductIndex = {};
  final Map<String, String> _byCaseProductSubCat = {};

  final StreamController<ProductSortDoc?> _sortDocController =
      StreamController<ProductSortDoc?>.broadcast();

  ProductSortService({FirebaseFirestore? firestore, this._prefs})
      : _customFirestore = firestore;

  ProductSortService._internal() : _customFirestore = null;

  ProductSortDoc? get currentSortDoc => _sortDoc;
  String get sortMode => _sortMode;
  bool get isCustomMode => _sortMode == 'custom';
  List<SubCategory> get subCategories => List.unmodifiable(_subCategories);
  Stream<ProductSortDoc?> get sortDocStream => _sortDocController.stream;

  /// Updates the configuration mode and sub-categories in memory and refreshes lookups.
  void updateConfiguration({
    required String sortMode,
    required List<SubCategory> subCategories,
  }) {
    _sortMode = sortMode;
    _subCategories = List.from(subCategories);
    _rebuildLookupMaps();
    _saveConfigToPrefs();
  }

  /// Resolves effective dealerId based on provided ID, user profile, or fallback.
  Future<String> resolveDealerId([String? explicitDealerId]) async {
    if (explicitDealerId != null && explicitDealerId.trim().isNotEmpty) {
      return explicitDealerId.trim();
    }
    try {
      final user = await KVariables.getUser();
      if (user != null && user.dealerName.trim().isNotEmpty) {
        return user.dealerName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
      }
    } catch (_) {}
    return 'default_dealer';
  }

  /// Loads configuration and product sort data from remote or offline cache.
  Future<ProductSortDoc> load({String? dealerId, ConfigurationService? configService}) async {
    final effectiveDealerId = await resolveDealerId(dealerId);

    // 1. Try to sync configuration
    try {
      final cService = configService ?? ConfigurationService();
      final config = await cService.getConfiguration();
      _sortMode = config.productSortMode;
      _subCategories = List.from(config.subCategories);
    } catch (e) {
      debugPrint('[ProductSortService] Error loading configuration: $e');
      await _loadConfigFromPrefs();
    }

    // 2. Try to sync product_sort document
    try {
      final snap = await _firestore
          .collection(PRODUCT_SORT_COLLECTION_REF)
          .doc(effectiveDealerId)
          .get();

      if (snap.exists && snap.data() != null) {
        _sortDoc = ProductSortDoc.fromJson(effectiveDealerId, snap.data()!);
        await _saveDocToPrefs(_sortDoc!);
      } else {
        _sortDoc = ProductSortDoc.empty(effectiveDealerId);
      }
    } catch (e) {
      debugPrint('[ProductSortService] Error loading product_sort doc from Firestore: $e. Falling back to cache.');
      await _loadDocFromPrefs(effectiveDealerId);
    }

    _rebuildLookupMaps();
    _sortDocController.add(_sortDoc);
    return _sortDoc ?? ProductSortDoc.empty(effectiveDealerId);
  }

  /// Saves the product sort document atomically to Firestore and local offline cache.
  Future<void> save(ProductSortDoc doc) async {
    _sortDoc = doc;
    _rebuildLookupMaps();
    _sortDocController.add(_sortDoc);

    // Save to SharedPreferences cache immediately
    await _saveDocToPrefs(doc);

    // Save to Firestore
    try {
      await _firestore
          .collection(PRODUCT_SORT_COLLECTION_REF)
          .doc(doc.dealerId)
          .set(doc.toJson(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('[ProductSortService] Error saving product_sort doc to Firestore: $e');
      rethrow;
    }
  }

  /// Returns a stream of real-time updates for the dealer's sort doc.
  Stream<ProductSortDoc?> getProductSortStream(String dealerId) {
    return _firestore
        .collection(PRODUCT_SORT_COLLECTION_REF)
        .doc(dealerId)
        .snapshots()
        .map((snap) {
      if (snap.exists && snap.data() != null) {
        final doc = ProductSortDoc.fromJson(dealerId, snap.data()!);
        _sortDoc = doc;
        _rebuildLookupMaps();
        return doc;
      }
      return ProductSortDoc.empty(dealerId);
    });
  }

  /// Fast lookup for the product's rank (subCategoryOrder, productIndex) in custom mode.
  /// Returns `null` if the product is unassigned, if the subcategory is inactive,
  /// or if custom mode is disabled.
  ProductSortRank? getProductRank({
    required String? productId,
    required String category,
  }) {
    if (_sortMode != 'custom' || productId == null || productId.trim().isEmpty) {
      return null;
    }

    final isCase = category.toLowerCase().contains('case');
    final productSubCat = isCase ? _byCaseProductSubCat : _byPieceProductSubCat;
    final productIndexMap = isCase ? _byCaseProductIndex : _byPieceProductIndex;

    final subCatId = productSubCat[productId];
    if (subCatId == null) return null;

    final isActive = _subCategoryActiveMap[subCatId] ?? false;
    if (!isActive) return null;

    final subCatOrder = _subCategoryOrderMap[subCatId];
    final index = productIndexMap[productId];

    if (subCatOrder == null || index == null) return null;

    return ProductSortRank(
      subCategoryOrder: subCatOrder,
      productIndex: index,
    );
  }

  /// Rebuilds in-memory index maps for O(1) sort comparisons.
  void _rebuildLookupMaps() {
    _subCategoryOrderMap.clear();
    _subCategoryActiveMap.clear();
    _byPieceProductIndex.clear();
    _byPieceProductSubCat.clear();
    _byCaseProductIndex.clear();
    _byCaseProductSubCat.clear();

    for (final subCat in _subCategories) {
      _subCategoryOrderMap[subCat.id] = subCat.order;
      _subCategoryActiveMap[subCat.id] = subCat.isActive;
    }

    if (_sortDoc != null) {
      _sortDoc!.byPiece.forEach((subCatId, productIds) {
        for (int i = 0; i < productIds.length; i++) {
          final pid = productIds[i];
          _byPieceProductIndex[pid] = i;
          _byPieceProductSubCat[pid] = subCatId;
        }
      });

      _sortDoc!.byCase.forEach((subCatId, productIds) {
        for (int i = 0; i < productIds.length; i++) {
          final pid = productIds[i];
          _byCaseProductIndex[pid] = i;
          _byCaseProductSubCat[pid] = subCatId;
        }
      });
    }
  }

  // --- Offline Persistence Helpers ---

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> _saveDocToPrefs(ProductSortDoc doc) async {
    try {
      final prefs = await _getPrefs();
      final map = doc.toJson();
      // Replace Timestamp with iso string for prefs
      if (map['updatedAt'] is Timestamp) {
        map['updatedAt'] = (map['updatedAt'] as Timestamp).toDate().toIso8601String();
      }
      await prefs.setString('${_kPrefProductSortDoc}_${doc.dealerId}', jsonEncode(map));
    } catch (e) {
      debugPrint('[ProductSortService] Error caching sort doc to prefs: $e');
    }
  }

  Future<void> _loadDocFromPrefs(String dealerId) async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString('${_kPrefProductSortDoc}_$dealerId');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _sortDoc = ProductSortDoc.fromJson(dealerId, decoded);
      } else {
        _sortDoc = ProductSortDoc.empty(dealerId);
      }
    } catch (e) {
      _sortDoc = ProductSortDoc.empty(dealerId);
    }
  }

  Future<void> _saveConfigToPrefs() async {
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_kPrefProductSortMode, _sortMode);
      final subCatsJson = _subCategories.map((s) => s.toJson()).toList();
      await prefs.setString(_kPrefProductSubCategories, jsonEncode(subCatsJson));
    } catch (e) {
      debugPrint('[ProductSortService] Error caching sort config to prefs: $e');
    }
  }

  Future<void> _loadConfigFromPrefs() async {
    try {
      final prefs = await _getPrefs();
      _sortMode = prefs.getString(_kPrefProductSortMode) ?? 'srp';
      final rawSubCats = prefs.getString(_kPrefProductSubCategories);
      if (rawSubCats != null && rawSubCats.isNotEmpty) {
        final list = jsonDecode(rawSubCats) as List;
        _subCategories = list
            .whereType<Map>()
            .map((m) => SubCategory.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
    } catch (_) {}
  }

  /// Direct configuration helper for tests and mock environments.
  @visibleForTesting
  void configureForTesting({
    required String sortMode,
    required List<SubCategory> subCategories,
    required ProductSortDoc? sortDoc,
  }) {
    _sortMode = sortMode;
    _subCategories = List.from(subCategories);
    _sortDoc = sortDoc;
    _rebuildLookupMaps();
  }

  /// Clears in-memory test states.
  @visibleForTesting
  void resetForTesting() {
    _sortDoc = null;
    _sortMode = 'srp';
    _subCategories = const [];
    _subCategoryOrderMap.clear();
    _subCategoryActiveMap.clear();
    _byPieceProductIndex.clear();
    _byPieceProductSubCat.clear();
    _byCaseProductIndex.clear();
    _byCaseProductSubCat.clear();
  }
}
