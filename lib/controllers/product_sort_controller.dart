import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/models/product_sort_doc.dart';
import 'package:selecta_ops/models/sub_category.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/product_sort_service.dart';

/// Controller managing sub-categories and product ordering mutations,
/// reordering, assignments, and atomic saving.
class ProductSortController {
  final ProductSortService _sortService;
  ConfigurationService? _customConfigService;
  ConfigurationService get _configService =>
      _customConfigService ??= ConfigurationService();

  List<SubCategory> _subCategories = [];
  ProductSortDoc _sortDoc = ProductSortDoc.empty('default_dealer');
  bool _hasUnsavedChanges = false;

  ProductSortController({
    ProductSortService? sortService,
    ConfigurationService? configService,
  })  : _sortService = sortService ?? ProductSortService.instance,
        _customConfigService = configService;

  List<SubCategory> get subCategories => List.unmodifiable(_subCategories);
  ProductSortDoc get sortDoc => _sortDoc;
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  void markUnsaved() {
    _hasUnsavedChanges = true;
  }

  void clearUnsaved() {
    _hasUnsavedChanges = false;
  }

  /// Initializes state from loaded configuration and sort doc.
  void initialize({
    required List<SubCategory> subCategories,
    required ProductSortDoc sortDoc,
  }) {
    _subCategories = List.from(subCategories);
    _sortDoc = sortDoc;
    _hasUnsavedChanges = false;
  }

  /// Returns sub-categories filtered for category ('By Piece' or 'By Case'),
  /// sorted by their `order`.
  List<SubCategory> getSubCategoriesForCategory(String category) {
    final isCase = category.toLowerCase().contains('case');
    final list = _subCategories
        .where((s) => s.category.toLowerCase().contains(isCase ? 'case' : 'piece'))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  /// Creates a new sub-category for the given category with the next available order index.
  SubCategory createSubCategory({
    required String name,
    required String category,
  }) {
    final cleanName = name.trim();
    final isCase = category.toLowerCase().contains('case');
    final catName = isCase ? 'By Case' : 'By Piece';

    final existingForCat = getSubCategoriesForCategory(catName);
    final maxOrder = existingForCat.isEmpty
        ? -1
        : existingForCat.map((s) => s.order).reduce((a, b) => a > b ? a : b);

    final id = 'sub_${DateTime.now().millisecondsSinceEpoch}_${existingForCat.length}';
    final newSubCat = SubCategory(
      id: id,
      name: cleanName,
      category: catName,
      order: maxOrder + 1,
      isActive: true,
    );

    _subCategories.add(newSubCat);
    _hasUnsavedChanges = true;
    return newSubCat;
  }

  /// Renames an existing sub-category.
  void renameSubCategory(String subCategoryId, String newName) {
    final idx = _subCategories.indexWhere((s) => s.id == subCategoryId);
    if (idx != -1) {
      _subCategories[idx] = _subCategories[idx].copyWith(name: newName.trim());
      _hasUnsavedChanges = true;
    }
  }

  /// Toggles active state of a sub-category.
  void toggleSubCategoryActive(String subCategoryId, bool isActive) {
    final idx = _subCategories.indexWhere((s) => s.id == subCategoryId);
    if (idx != -1) {
      _subCategories[idx] = _subCategories[idx].copyWith(isActive: isActive);
      _hasUnsavedChanges = true;
    }
  }

  /// Deletes a sub-category and moves all its assigned products to Unassigned.
  void deleteSubCategory(String subCategoryId, String category) {
    _subCategories.removeWhere((s) => s.id == subCategoryId);

    final isCase = category.toLowerCase().contains('case');
    if (isCase) {
      final updatedCase = Map<String, List<String>>.from(_sortDoc.byCase);
      updatedCase.remove(subCategoryId);
      _sortDoc = _sortDoc.copyWith(byCase: updatedCase);
    } else {
      final updatedPiece = Map<String, List<String>>.from(_sortDoc.byPiece);
      updatedPiece.remove(subCategoryId);
      _sortDoc = _sortDoc.copyWith(byPiece: updatedPiece);
    }

    // Normalize order indices
    _normalizeSubCategoryOrders(category);
    _hasUnsavedChanges = true;
  }

  /// Reorders sub-categories within a category and updates their `order` indices (Level 1).
  void reorderSubCategories(String category, int oldIndex, int newIndex) {
    final isCase = category.toLowerCase().contains('case');
    final catName = isCase ? 'By Case' : 'By Piece';

    final forCat = getSubCategoriesForCategory(catName);
    if (oldIndex < 0 || oldIndex >= forCat.length) return;
    if (newIndex < 0 || newIndex >= forCat.length) return;

    final item = forCat.removeAt(oldIndex);
    forCat.insert(newIndex, item);

    // Re-assign order numbers 0, 1, 2, ...
    for (int i = 0; i < forCat.length; i++) {
      final updated = forCat[i].copyWith(order: i);
      final masterIdx = _subCategories.indexWhere((s) => s.id == updated.id);
      if (masterIdx != -1) {
        _subCategories[masterIdx] = updated;
      }
    }
    _hasUnsavedChanges = true;
  }

  /// Adds a product to a sub-category, ensuring it is removed from any previous sub-category (Level 2).
  void addProductToSubCategory({
    required String category,
    required String subCategoryId,
    required String productId,
    int? index,
  }) {
    final isCase = category.toLowerCase().contains('case');
    final targetMap = isCase
        ? Map<String, List<String>>.from(_sortDoc.byCase)
        : Map<String, List<String>>.from(_sortDoc.byPiece);

    // Remove product from all sub-categories in this category first
    targetMap.forEach((subId, list) {
      list.remove(productId);
    });

    // Add to target sub-category
    final targetList = List<String>.from(targetMap[subCategoryId] ?? []);
    if (index != null && index >= 0 && index <= targetList.length) {
      targetList.insert(index, productId);
    } else {
      targetList.add(productId);
    }
    targetMap[subCategoryId] = targetList;

    _sortDoc = isCase
        ? _sortDoc.copyWith(byCase: targetMap)
        : _sortDoc.copyWith(byPiece: targetMap);

    _hasUnsavedChanges = true;
  }

  /// Removes a product from a sub-category (making it Unassigned).
  void removeProductFromSubCategory({
    required String category,
    required String subCategoryId,
    required String productId,
  }) {
    final isCase = category.toLowerCase().contains('case');
    final targetMap = isCase
        ? Map<String, List<String>>.from(_sortDoc.byCase)
        : Map<String, List<String>>.from(_sortDoc.byPiece);

    final list = List<String>.from(targetMap[subCategoryId] ?? []);
    list.remove(productId);
    targetMap[subCategoryId] = list;

    _sortDoc = isCase
        ? _sortDoc.copyWith(byCase: targetMap)
        : _sortDoc.copyWith(byPiece: targetMap);

    _hasUnsavedChanges = true;
  }

  /// Reorders products inside a sub-category (Level 2).
  void reorderProductsInSubCategory({
    required String category,
    required String subCategoryId,
    required int oldIndex,
    required int newIndex,
  }) {
    final isCase = category.toLowerCase().contains('case');
    final targetMap = isCase
        ? Map<String, List<String>>.from(_sortDoc.byCase)
        : Map<String, List<String>>.from(_sortDoc.byPiece);

    final list = List<String>.from(targetMap[subCategoryId] ?? []);
    if (oldIndex < 0 || oldIndex >= list.length) return;
    if (newIndex < 0 || newIndex >= list.length) return;

    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    targetMap[subCategoryId] = list;

    _sortDoc = isCase
        ? _sortDoc.copyWith(byCase: targetMap)
        : _sortDoc.copyWith(byPiece: targetMap);

    _hasUnsavedChanges = true;
  }

  /// Moves a product directly from one sub-category to another.
  void moveProduct({
    required String category,
    required String fromSubCategoryId,
    required String toSubCategoryId,
    required String productId,
    int? targetIndex,
  }) {
    removeProductFromSubCategory(
      category: category,
      subCategoryId: fromSubCategoryId,
      productId: productId,
    );
    addProductToSubCategory(
      category: category,
      subCategoryId: toSubCategoryId,
      productId: productId,
      index: targetIndex,
    );
  }

  /// Normalizes sub-category orders consecutively.
  void _normalizeSubCategoryOrders(String category) {
    final forCat = getSubCategoriesForCategory(category);
    for (int i = 0; i < forCat.length; i++) {
      final updated = forCat[i].copyWith(order: i);
      final idx = _subCategories.indexWhere((s) => s.id == updated.id);
      if (idx != -1) {
        _subCategories[idx] = updated;
      }
    }
  }

  /// Saves the updated sort document and sub-categories to Firestore and caches.
  Future<void> saveChanges({
    required String dealerId,
    required String updatedBy,
    Configuration? currentConfig,
  }) async {
    final updatedDoc = _sortDoc.copyWith(
      dealerId: dealerId,
      updatedAt: Timestamp.now(),
      updatedBy: updatedBy,
    );

    // Save product_sort doc
    await _sortService.save(updatedDoc);
    _sortDoc = updatedDoc;

    // Save subCategories to app configuration doc if config is supplied
    if (currentConfig != null) {
      final updatedConfig = currentConfig.copyWith(
        subCategories: _subCategories,
      );
      await _configService.saveConfiguration(updatedConfig);
      _sortService.updateConfiguration(
        sortMode: updatedConfig.productSortMode,
        subCategories: _subCategories,
      );
    } else {
      _sortService.updateConfiguration(
        sortMode: _sortService.sortMode,
        subCategories: _subCategories,
      );
    }

    _hasUnsavedChanges = false;
  }
}
