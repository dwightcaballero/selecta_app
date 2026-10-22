import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/configuration_controller.dart';
import 'package:selecta_ops/controllers/product_sort_controller.dart';
import 'package:selecta_ops/controllers/selecta_product_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/models/sub_category.dart';
import 'package:selecta_ops/services/product_sort_service.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Dedicated page for Dealers and Admins to configure 2-level product sorting:
/// - Level 1: Sub-Category sequencing (drag and drop)
/// - Level 2: Product sequencing inside each sub-category (drag and drop)
///
/// Also provides:
/// - Quick product assignment from Unassigned pool
/// - Unassigned products section at the bottom (sorted by SRP then name)
/// - Sub-category creation, renaming, active toggling, and deletion
/// - Unsaved changes guard
class ProductSortingPage extends StatefulWidget {
  final int initialTabIndex;

  const ProductSortingPage({super.key, this.initialTabIndex = 0});

  @override
  State<ProductSortingPage> createState() => _ProductSortingPageState();
}

class _ProductSortingPageState extends State<ProductSortingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final SelectaProductController _productController = SelectaProductController();
  final ConfigurationController _configController = ConfigurationController();
  final ProductSortController _sortController = ProductSortController();

  final NumberFormat _currencyFormat =
      NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isAuthorized = true;

  String _dealerId = 'default_dealer';
  String _userEmail = '';
  Configuration? _currentConfig;
  List<SelectaProduct> _allProducts = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _currentCategoryName =>
      _tabController.index == 0 ? 'By Piece' : 'By Case';

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = await KVariables.getUser();
      if (user != null && !user.isDealerOrAdmin) {
        if (mounted) {
          setState(() {
            _isAuthorized = false;
            _isLoading = false;
          });
        }
        return;
      }

      _userEmail = user?.email ?? '';
      _dealerId = await ProductSortService.instance.resolveDealerId();

      // 1. Load config
      final configResult = await _configController.loadConfiguration();
      _currentConfig = configResult.config;

      // 2. Load sort doc
      final sortDoc =
          await ProductSortService.instance.load(dealerId: _dealerId);

      // 3. Load all products
      final productDocs = await _productController.getAllProducts();
      final products = productDocs.map((doc) {
        final data = doc.data();
        return SelectaProduct.fromJson(doc.id, data);
      }).toList();

      // 4. Initialize sort controller
      _sortController.initialize(
        subCategories: _currentConfig?.subCategories ?? [],
        sortDoc: sortDoc,
      );

      if (mounted) {
        setState(() {
          _allProducts = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ShowMessage.error(context, 'Failed to load product sort data: $e');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SAVE & REVERT ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _saveChanges() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      // 1. Save sort doc and update subCategories in config
      await _sortController.saveChanges(
        dealerId: _dealerId,
        updatedBy: _userEmail,
        currentConfig: _currentConfig,
      );

      // 2. Batch update subCategoryId in selecta_products collection
      try {
        final firestore = FirebaseFirestore.instance;
        final batch = firestore.batch();
        final doc = _sortController.sortDoc;

        // Map product id -> subCategoryId
        final Map<String, String?> assignmentMap = {};
        for (final p in _allProducts) {
          assignmentMap[p.id] = null;
        }

        doc.byPiece.forEach((subId, pIds) {
          for (final pid in pIds) {
            assignmentMap[pid] = subId;
          }
        });

        doc.byCase.forEach((subId, pIds) {
          for (final pid in pIds) {
            assignmentMap[pid] = subId;
          }
        });

        int operations = 0;
        for (final entry in assignmentMap.entries) {
          final ref = firestore
              .collection(SELECTA_PRODUCTS_COLLECTION_REF)
              .doc(entry.key);
          batch.update(ref, {'subCategoryId': entry.value});
          operations++;
          if (operations >= 450) {
            // Commit chunk if reaching batch limit
            await batch.commit();
            operations = 0;
          }
        }
        if (operations > 0) {
          await batch.commit();
        }
      } catch (e) {
        debugPrint('[ProductSortingPage] Batch update subCategoryId warning: $e');
      }

      if (mounted) {
        ShowMessage.success(context, 'Product sorting saved successfully!');
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to save product sorting: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<bool> _handlePopScope() async {
    if (!_sortController.hasUnsavedChanges) {
      return true;
    }

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text(
          'You have unsaved changes to your product sequence. If you leave now, these changes will be discarded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard & Leave'),
          ),
        ],
      ),
    );

    return shouldLeave ?? false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUB-CATEGORY ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showCreateSubCategoryDialog() {
    final textCtrl = TextEditingController();
    final catName = _currentCategoryName;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New $catName Sub-Category'),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Sub-Category Name',
            hintText: 'e.g., Cones, Pints, Bulk, Sticks...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = textCtrl.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  _sortController.createSubCategory(
                    name: name,
                    category: catName,
                  );
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showRenameSubCategoryDialog(SubCategory sub) {
    final textCtrl = TextEditingController(text: sub.name);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Sub-Category'),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = textCtrl.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  _sortController.renameSubCategory(sub.id, name);
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSubCategory(SubCategory sub) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Sub-Category?'),
        content: Text(
          'Are you sure you want to delete "${sub.name}"?\n\n'
          'All products currently assigned to this sub-category will become Unassigned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                _sortController.deleteSubCategory(sub.id, sub.category);
              });
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRODUCT ASSIGNMENT DIALOG
  // ═══════════════════════════════════════════════════════════════════════════

  void _showAddProductsDialog(SubCategory subCategory) {
    final isCase = subCategory.category.toLowerCase().contains('case');
    final catName = isCase ? 'By Case' : 'By Piece';

    // Products in this category
    final categoryProducts = _allProducts.where((p) {
      final pIsCase = p.category.toLowerCase().contains('case');
      return isCase ? pIsCase : !pIsCase;
    }).toList();

    // Map existing assignments for category
    final currentMap = isCase
        ? _sortController.sortDoc.byCase
        : _sortController.sortDoc.byPiece;

    final assignedToThisSub = Set<String>.from(currentMap[subCategory.id] ?? []);

    // Other subcategories in same category
    final allSubCats = _sortController.getSubCategoriesForCategory(catName);
    final Map<String, String> subCatNameById = {
      for (final s in allSubCats) s.id: s.name,
    };

    final Map<String, String> productCurrentSubName = {};
    currentMap.forEach((subId, pids) {
      for (final pid in pids) {
        if (subId != subCategory.id) {
          productCurrentSubName[pid] = subCatNameById[subId] ?? 'Another Sub-Category';
        }
      }
    });

    final selectedProductIds = Set<String>.from(assignedToThisSub);
    String searchQuery = '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filtered = categoryProducts.where((p) {
              if (searchQuery.isEmpty) return true;
              final q = searchQuery.toLowerCase();
              return p.productName.toLowerCase().contains(q) ||
                  p.itemCode.toLowerCase().contains(q);
            }).toList();

            // Sort unassigned first, then by name
            filtered.sort((a, b) {
              final aAssigned = productCurrentSubName.containsKey(a.id);
              final bAssigned = productCurrentSubName.containsKey(b.id);
              if (aAssigned != bAssigned) {
                return aAssigned ? 1 : -1;
              }
              return a.productName.compareTo(b.productName);
            });

            return AlertDialog(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Assign Products to "${subCategory.name}"'),
                  const SizedBox(height: 4),
                  Text(
                    'Select products to place in this sub-category ($catName).',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              content: SizedBox(
                width: 480,
                height: 520,
                child: Column(
                  children: [
                    TextField(
                      autofocus: false,
                      decoration: InputDecoration(
                        hintText: 'Search products by name or code...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onChanged: (val) {
                        setDialogState(() => searchQuery = val.trim());
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${selectedProductIds.length} selected',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () {
                                setDialogState(() {
                                  for (final p in filtered) {
                                    selectedProductIds.add(p.id);
                                  }
                                });
                              },
                              child: const Text('Select All Visible',
                                  style: TextStyle(fontSize: 11)),
                            ),
                            TextButton(
                              onPressed: () {
                                setDialogState(() {
                                  selectedProductIds.clear();
                                });
                              },
                              child: const Text('Clear All',
                                  style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No products found'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (ctx, idx) {
                                final prod = filtered[idx];
                                final isSelected =
                                    selectedProductIds.contains(prod.id);
                                final currentSub = productCurrentSubName[prod.id];

                                return CheckboxListTile(
                                  value: isSelected,
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  activeColor: Theme.of(ctx).colorScheme.primary,
                                  onChanged: (val) {
                                    setDialogState(() {
                                      if (val == true) {
                                        selectedProductIds.add(prod.id);
                                      } else {
                                        selectedProductIds.remove(prod.id);
                                      }
                                    });
                                  },
                                  secondary: CachedProductImage(
                                    imageUrl: prod.imageUrl,
                                    size: 32,
                                  ),
                                  title: Text(
                                    prod.productName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      height: 1.25,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    currentSub != null
                                        ? 'Currently in: $currentSub'
                                        : 'Unassigned • ${_currencyFormat.format(prod.sellingPrice)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: currentSub != null
                                          ? Colors.orange.shade800
                                          : Theme.of(ctx)
                                              .colorScheme
                                              .onSurfaceVariant,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      // Apply additions and removals to subcategory
                      for (final pid in selectedProductIds) {
                        _sortController.addProductToSubCategory(
                          category: catName,
                          subCategoryId: subCategory.id,
                          productId: pid,
                        );
                      }
                      for (final pid in assignedToThisSub) {
                        if (!selectedProductIds.contains(pid)) {
                          _sortController.removeProductFromSubCategory(
                            category: catName,
                            subCategoryId: subCategory.id,
                            productId: pid,
                          );
                        }
                      }
                    });
                    Navigator.pop(ctx);
                  },
                  child: Text('Apply (${selectedProductIds.length})'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UI BUILDERS
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!_isAuthorized) {
      return Scaffold(
        appBar: const CustomAppbar(title: 'Product Sorting'),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              const Text(
                'Access Restricted',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Only Dealers and Admins can configure product sorting.',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final canLeave = await _handlePopScope();
        if (canLeave && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: CustomAppbar(
          title: 'Product Sorting',
          centerTitle: false,
          actions: [
            FilledButton.icon(
              onPressed: _isSaving ? null : _saveChanges,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                visualDensity: VisualDensity.compact,
                backgroundColor: _sortController.hasUnsavedChanges
                    ? const Color(0xFFD97706) // Rich amber to highlight pending changes
                    : null,
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Badge(
                      isLabelVisible: _sortController.hasUnsavedChanges,
                      smallSize: 8,
                      backgroundColor: Colors.white,
                      child: const Icon(Icons.save_rounded, size: 16),
                    ),
              label: Text(
                _sortController.hasUnsavedChanges ? 'Save *' : 'Save',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Category Tabs (By Piece / By Case)
                  Container(
                    color: colorScheme.surface,
                    child: TabBar(
                      controller: _tabController,
                      indicatorColor: colorScheme.primary,
                      indicatorWeight: 3,
                      labelColor: colorScheme.primary,
                      unselectedLabelColor: colorScheme.onSurfaceVariant,
                      tabs: const [
                        Tab(
                          icon: Icon(Icons.icecream_outlined, size: 20),
                          text: 'By Piece',
                        ),
                        Tab(
                          icon: Icon(Icons.inventory_2_outlined, size: 20),
                          text: 'By Case',
                        ),
                      ],
                    ),
                  ),

                  // Info & Action Banner
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      border: Border(
                        bottom: BorderSide(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.swap_vert_rounded,
                            size: 18, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Drag cards to set group order; drag items inside to sequence products.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colorScheme.onSurfaceVariant,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.tonalIcon(
                          onPressed: _showCreateSubCategoryDialog,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.add, size: 15),
                          label: const Text('Add Group',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),

                  // Tab View Content
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildCategorySortList('By Piece'),
                        _buildCategorySortList('By Case'),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildCategorySortList(String category) {
    final subCategories = _sortController.getSubCategoriesForCategory(category);
    final isCase = category.toLowerCase().contains('case');
    final sortMap = isCase
        ? _sortController.sortDoc.byCase
        : _sortController.sortDoc.byPiece;

    // Collect all assigned product ids in this category
    final Set<String> assignedIds = {};
    sortMap.forEach((_, pids) => assignedIds.addAll(pids));

    // Filter products belonging to this category
    final categoryProducts = _allProducts.where((p) {
      final pIsCase = p.category.toLowerCase().contains('case');
      return isCase ? pIsCase : !pIsCase;
    }).toList();

    // Map id -> product
    final Map<String, SelectaProduct> productMap = {
      for (final p in categoryProducts) p.id: p,
    };

    // Unassigned products sorted by SRP then name
    final unassignedProducts = categoryProducts
        .where((p) => !assignedIds.contains(p.id))
        .toList()
      ..sort((a, b) => Helperfunctions.compareBySrpAndName(
            nameA: a.productName,
            nameB: b.productName,
            priceA: a.sellingPrice,
            priceB: b.sellingPrice,
          ));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (subCategories.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Column(
                children: [
                  Icon(
                    Icons.category_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No sub-categories in $category yet',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Create sub-categories to group and sequence products.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _showCreateSubCategoryDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Sub-Category'),
                  ),
                ],
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SUB-CATEGORIES & PRODUCTS (${subCategories.length})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  'Drag headers to reorder',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // Level 1: Sub-Categories Reorderable List
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: subCategories.length,
            onReorderItem: (oldIndex, newIndex) {
              setState(() {
                _sortController.reorderSubCategories(
                  category,
                  oldIndex,
                  newIndex,
                );
              });
            },
            itemBuilder: (context, index) {
              final sub = subCategories[index];
              final productIds = sortMap[sub.id] ?? [];
              final productsInSub = productIds
                  .map((id) => productMap[id])
                  .whereType<SelectaProduct>()
                  .toList();

              return _buildSubCategoryCard(
                key: ValueKey('sub_${sub.id}'),
                category: category,
                subCategory: sub,
                index: index,
                products: productsInSub,
              );
            },
          ),
        ],

        const SizedBox(height: 24),

        // Unassigned Products Section
        _buildUnassignedProductsSection(
          category: category,
          unassignedProducts: unassignedProducts,
          subCategories: subCategories,
        ),
      ],
    );
  }

  Widget _buildSubCategoryCard({
    required Key key,
    required String category,
    required SubCategory subCategory,
    required int index,
    required List<SelectaProduct> products,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: subCategory.isActive
              ? colorScheme.outlineVariant.withValues(alpha: 0.8)
              : colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sub-Category Header (Level 1 Drag Handle)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: subCategory.isActive
                  ? colorScheme.primaryContainer.withValues(alpha: 0.25)
                  : Colors.grey.withValues(alpha: 0.1),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                // Level 1 Drag Handle
                ReorderableDragStartListener(
                  index: index,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Order badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#${subCategory.order + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Sub-category Name
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              subCategory.name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: subCategory.isActive
                                    ? colorScheme.onSurface
                                    : colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!subCategory.isActive) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Inactive',
                                style:
                                    TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${products.length} products',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),

                // "+ Add" button
                FilledButton.tonalIcon(
                  onPressed: () => _showAddProductsDialog(subCategory),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  icon: const Icon(Icons.add, size: 15),
                  label: const Text('Add', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                ),

                // Overflow Menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  padding: EdgeInsets.zero,
                  onSelected: (val) {
                    if (val == 'rename') {
                      _showRenameSubCategoryDialog(subCategory);
                    } else if (val == 'toggle') {
                      setState(() {
                        _sortController.toggleSubCategoryActive(
                          subCategory.id,
                          !subCategory.isActive,
                        );
                      });
                    } else if (val == 'delete') {
                      _confirmDeleteSubCategory(subCategory);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Rename'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Row(
                        children: [
                          Icon(
                            subCategory.isActive
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(subCategory.isActive
                              ? 'Deactivate'
                              : 'Activate'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline,
                              size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Level 2: Products List (Reorderable)
          if (products.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Center(
                child: Text(
                  'No products assigned. Tap "Add Products" above to sequence items here.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: products.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  _sortController.reorderProductsInSubCategory(
                    category: category,
                    subCategoryId: subCategory.id,
                    oldIndex: oldIndex,
                    newIndex: newIndex,
                  );
                });
              },
              itemBuilder: (context, prodIdx) {
                final product = products[prodIdx];

                return Container(
                  key: ValueKey('prod_${subCategory.id}_${product.id}'),
                  decoration: BoxDecoration(
                    color: prodIdx.isEven
                        ? colorScheme.surface
                        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                    border: Border(
                      bottom: BorderSide(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Level 2 Drag Handle
                        ReorderableDragStartListener(
                          index: prodIdx,
                          child: Icon(
                            Icons.drag_handle_rounded,
                            size: 20,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 10),
                        CachedProductImage(
                          imageUrl: product.imageUrl,
                          size: 34,
                        ),
                      ],
                    ),
                    title: Text(
                      product.productName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${_currencyFormat.format(product.sellingPrice)} • Code: ${product.itemCode}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: 'Remove from sub-category (Unassign)',
                      color: Colors.red.shade400,
                      onPressed: () {
                        setState(() {
                          _sortController.removeProductFromSubCategory(
                            category: category,
                            subCategoryId: subCategory.id,
                            productId: product.id,
                          );
                        });
                      },
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildUnassignedProductsSection({
    required String category,
    required List<SelectaProduct> unassignedProducts,
    required List<SubCategory> subCategories,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.08),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 20, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Unassigned Products (${unassignedProducts.length})',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Placed at the bottom of lists and ordered by SRP then name.',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (unassignedProducts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Center(
                child: Text(
                  'All products in $category have been assigned to a sub-category!',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: unassignedProducts.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),
              itemBuilder: (context, idx) {
                final prod = unassignedProducts[idx];

                return ListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  leading: CachedProductImage(
                    imageUrl: prod.imageUrl,
                    size: 34,
                  ),
                  title: Text(
                    prod.productName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_currencyFormat.format(prod.sellingPrice)} • Code: ${prod.itemCode}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: subCategories.isEmpty
                      ? null
                      : PopupMenuButton<String>(
                          icon: const Icon(Icons.add_circle_outline_rounded,
                              size: 20),
                          tooltip: 'Assign to sub-category',
                          onSelected: (subId) {
                            setState(() {
                              _sortController.addProductToSubCategory(
                                category: category,
                                subCategoryId: subId,
                                productId: prod.id,
                              );
                            });
                          },
                          itemBuilder: (ctx) => subCategories.map((s) {
                            return PopupMenuItem<String>(
                              value: s.id,
                              child: Text('Assign to "${s.name}"'),
                            );
                          }).toList(),
                        ),
                );
              },
            ),
        ],
      ),
    );
  }
}
