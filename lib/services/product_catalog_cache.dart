import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/models/admin_selecta_product.dart';
import 'package:selecta_ops/models/other_product.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/services/other_product_service.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';

/// Centralized in-memory cache for product catalogs with a 5-minute TTL (Phase 2.2).
/// Eliminates repeated full-collection `.get()` reads across picklist, inventory,
/// PJP scheduling, product sorting, and export reports.
class ProductCatalogCache {
  static final ProductCatalogCache _instance = ProductCatalogCache._internal();
  factory ProductCatalogCache() => _instance;
  ProductCatalogCache._internal();

  FirebaseFirestore? _customFirestore;
  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;

  set firestore(FirebaseFirestore fs) => _customFirestore = fs;

  // TTL Duration
  static const Duration defaultTtl = Duration(minutes: 5);

  // Cached data
  List<SelectaProduct>? _cachedSelectaProducts;
  DateTime? _lastSelectaFetchTime;
  Future<List<SelectaProduct>>? _inFlightSelecta;

  List<OtherProduct>? _cachedOtherProducts;
  DateTime? _lastOtherFetchTime;
  Future<List<OtherProduct>>? _inFlightOther;

  List<AdminSelectaProduct>? _cachedAdminProducts;
  DateTime? _lastAdminFetchTime;
  Future<List<AdminSelectaProduct>>? _inFlightAdmin;

  /// Invalidate all cached product data
  void invalidate() {
    _cachedSelectaProducts = null;
    _lastSelectaFetchTime = null;
    _cachedOtherProducts = null;
    _lastOtherFetchTime = null;
    _cachedAdminProducts = null;
    _lastAdminFetchTime = null;
  }

  void invalidateAll() => invalidate();

  void invalidateSelecta() {
    _cachedSelectaProducts = null;
    _lastSelectaFetchTime = null;
  }

  void invalidateOther() {
    _cachedOtherProducts = null;
    _lastOtherFetchTime = null;
  }

  void invalidateAdmin() {
    _cachedAdminProducts = null;
    _lastAdminFetchTime = null;
  }

  /// Fetches Selecta products, reusing cached list if within TTL.
  Future<List<SelectaProduct>> getSelectaProducts({
    bool forceRefresh = false,
    Duration ttl = defaultTtl,
  }) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedSelectaProducts != null &&
        _lastSelectaFetchTime != null &&
        now.difference(_lastSelectaFetchTime!) < ttl) {
      return _cachedSelectaProducts!;
    }

    if (_inFlightSelecta != null) {
      return _inFlightSelecta!;
    }

    _inFlightSelecta = _fetchSelectaProducts();
    try {
      final result = await _inFlightSelecta!;
      _cachedSelectaProducts = result;
      _lastSelectaFetchTime = DateTime.now();
      return result;
    } finally {
      _inFlightSelecta = null;
    }
  }

  Future<List<SelectaProduct>> _fetchSelectaProducts() async {
    try {
      final snapshot = await _firestore.collection(SELECTA_PRODUCTS_COLLECTION_REF).get();
      return snapshot.docs.map((doc) => SelectaProduct.fromSnapshot(doc)).toList();
    } catch (_) {
      return _cachedSelectaProducts ?? [];
    }
  }

  /// Fetches Other products, reusing cached list if within TTL.
  Future<List<OtherProduct>> getOtherProducts({
    bool forceRefresh = false,
    Duration ttl = defaultTtl,
  }) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedOtherProducts != null &&
        _lastOtherFetchTime != null &&
        now.difference(_lastOtherFetchTime!) < ttl) {
      return _cachedOtherProducts!;
    }

    if (_inFlightOther != null) {
      return _inFlightOther!;
    }

    _inFlightOther = _fetchOtherProducts();
    try {
      final result = await _inFlightOther!;
      _cachedOtherProducts = result;
      _lastOtherFetchTime = DateTime.now();
      return result;
    } finally {
      _inFlightOther = null;
    }
  }

  Future<List<OtherProduct>> _fetchOtherProducts() async {
    try {
      final snapshot = await _firestore.collection(OTHER_PRODUCTS_COLLECTION_REF).get();
      return snapshot.docs.map((doc) => OtherProduct.fromSnapshot(doc)).toList();
    } catch (_) {
      return _cachedOtherProducts ?? [];
    }
  }

  /// Fetches Admin master products, reusing cached list if within TTL.
  Future<List<AdminSelectaProduct>> getAdminSelectaProducts({
    bool forceRefresh = false,
    Duration ttl = defaultTtl,
  }) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedAdminProducts != null &&
        _lastAdminFetchTime != null &&
        now.difference(_lastAdminFetchTime!) < ttl) {
      return _cachedAdminProducts!;
    }

    if (_inFlightAdmin != null) {
      return _inFlightAdmin!;
    }

    _inFlightAdmin = _fetchAdminSelectaProducts();
    try {
      final result = await _inFlightAdmin!;
      _cachedAdminProducts = result;
      _lastAdminFetchTime = DateTime.now();
      return result;
    } finally {
      _inFlightAdmin = null;
    }
  }

  Future<List<AdminSelectaProduct>> _fetchAdminSelectaProducts() async {
    try {
      final snapshot = await _firestore.collection(ADMIN_SELECTA_PRODUCTS_COLLECTION_REF).get();
      return snapshot.docs
          .map((doc) => AdminSelectaProduct.fromJson(doc.id, doc.data()))
          .toList();
    } catch (_) {
      return _cachedAdminProducts ?? [];
    }
  }
}
