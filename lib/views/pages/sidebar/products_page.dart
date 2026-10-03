import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:selecta_ops/controllers/other_product_controller.dart';
import 'package:selecta_ops/controllers/selecta_product_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/admin_selecta_product.dart';
import 'package:selecta_ops/models/other_product.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/views/pages/sidebar/inventory_page.dart';
import 'package:selecta_ops/views/pages/sidebar/other_product_form_page.dart';
import 'package:selecta_ops/views/pages/sidebar/selecta_product_form_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/cached_product_image.dart';

/// Unified Products Page merging Selecta Products and Other Products into a single,
/// tabbed catalog experience.
///
/// - **Tab 1: Selecta Products** (Master Ice Cream Catalog)
///   - Dealer mode: view prices, toggle active status, sync with Admin catalog.
///   - Admin mode: full CRUD, CSV/JSON import & export.
///   - Salesman mode: read-only price and SKU lookup.
/// - **Tab 2: Other Products** (Dealer / Non-Selecta Goods)
///   - List, search, toggle active status.
///   - Floating Action Button ("Add Other Product") for Dealers and Admins.
class ProductsPage extends StatefulWidget {
  final String userRole;
  final int initialIndex;

  const ProductsPage({
    super.key,
    this.userRole = 'Dealer',
    this.initialIndex = 0,
  });

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final SelectaProductController _selectaController = SelectaProductController();
  final OtherProductController _otherController = OtherProductController();

  final TextEditingController _selectaSearchController = TextEditingController();
  final TextEditingController _otherSearchController = TextEditingController();

  final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  String _selectaSearchQuery = '';
  String _selectaFilterStatus = 'All'; // 'All', 'Active', 'Inactive'
  bool _isSelectaSyncing = false;
  bool _hasRemoteSelectaChanges = false;

  String _otherSearchQuery = '';
  String _otherFilterStatus = 'All'; // 'All', 'Active', 'Inactive'

  bool get _isAdmin {
    final role = widget.userRole.trim().toLowerCase();
    return role == 'admin' || role == 'super admin' || role == 'superadmin';
  }

  bool get _isSalesman {
    final role = widget.userRole.trim().toLowerCase();
    return role == 'salesman';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, 1),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    if (_isAdmin) {
      _selectaController.ensureAdminCatalogSeeded();
    } else {
      _checkForAdminCatalogUpdates();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _selectaSearchController.dispose();
    _otherSearchController.dispose();
    super.dispose();
  }

  Future<void> _checkForAdminCatalogUpdates() async {
    final check = await _selectaController.checkSyncNeeded();
    if (mounted) {
      setState(() {
        _hasRemoteSelectaChanges = check.needsSync;
      });
    }
  }

  Future<void> _handleDealerSync() async {
    if (_isSelectaSyncing) return;
    setState(() => _isSelectaSyncing = true);
    try {
      final result = await _selectaController.syncWithAdminCatalog();
      if (!mounted) return;
      setState(() {
        _hasRemoteSelectaChanges = false;
      });
      await _checkForAdminCatalogUpdates();
      if (!mounted) return;
      if (result.totalFetched == 0) {
        ShowMessage.alert(
          context,
          title: 'Sync Selecta Catalog',
          message: 'No products found in the master Admin catalog yet.',
        );
      } else if (result.addedCount == 0 && result.updatedCount == 0) {
        ShowMessage.success(context, 'Catalog is up to date (${result.totalFetched} products).');
      } else {
        ShowMessage.success(
          context,
          'Synced ${result.totalFetched} products (${result.addedCount} new, ${result.updatedCount} updated).',
        );
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to sync Selecta catalog: $e');
      }
    } finally {
      if (mounted) setState(() => _isSelectaSyncing = false);
    }
  }

  Future<void> _handleAdminExport() async {
    try {
      String exportFormat = 'CSV';
      final csvStr = await _selectaController.exportAdminCatalogCsv();
      final jsonStr = await _selectaController.exportAdminCatalogJson();
      final csvFile = await _selectaController.exportAdminCatalogToCsvFile();
      final jsonFile = await _selectaController.exportAdminCatalogToFile();
      if (!mounted) return;

      final colorScheme = Theme.of(context).colorScheme;
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isCsv = exportFormat == 'CSV';
            final currentContent = isCsv ? csvStr : jsonStr;
            final currentFile = isCsv ? csvFile : jsonFile;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              title: const Row(
                children: [
                  Icon(Icons.file_upload_outlined, size: 22),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Export Master Catalog', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Format:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant)),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('CSV (Spreadsheet)'),
                          selected: isCsv,
                          onSelected: (_) => setDialogState(() => exportFormat = 'CSV'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('JSON (Raw)'),
                          selected: !isCsv,
                          onSelected: (_) => setDialogState(() => exportFormat = 'JSON'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(currentContent, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () => OpenFilex.open(currentFile.path),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text('Open ${isCsv ? 'CSV' : 'JSON'}'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: currentContent));
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ShowMessage.success(context, 'Admin catalog $exportFormat copied to clipboard!');
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: Text('Copy $exportFormat'),
                ),
              ],
            );
          },
        ),
      );
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Export failed: $e');
    }
  }

  Future<void> _handleAdminImport() async {
    final currentUrl = await _selectaController.getCustomCatalogApiUrl() ?? '';
    if (!mounted) return;

    final urlController = TextEditingController(text: currentUrl);
    final dataController = TextEditingController();
    String selectedFormat = 'Auto-Detect';
    bool isImporting = false;
    bool isFetchingUrl = false;

    const sampleCsv =
        'Product Name,Buying Price,Selling Price,Category,Image URL\n'
        'Cornetto Chocolate,25.00,30.00,By Piece,\n'
        'Magnum Classic,50.00,65.00,By Piece,\n'
        'Selecta Super Thick Vanilla 1.4L,180.00,210.00,By Case,';

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              title: const Row(
                children: [
                  Icon(Icons.file_download_outlined, size: 22),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Import Admin Catalog', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Import products from a CSV spreadsheet (Excel / Google Sheets), JSON catalog, or a remote URL.',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text('Format:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: ['Auto-Detect', 'CSV', 'JSON'].map((fmt) {
                                  final isSel = selectedFormat == fmt;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ChoiceChip(
                                      label: Text(fmt, style: const TextStyle(fontSize: 11.5)),
                                      selected: isSel,
                                      visualDensity: VisualDensity.compact,
                                      onSelected: (_) => setDialogState(() => selectedFormat = fmt),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: urlController,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'Remote Catalog URL (Optional)',
                          hintText: 'https://example.com/selecta_catalog.csv',
                          prefixIcon: const Icon(Icons.link, size: 18),
                          suffixIcon: isFetchingUrl
                              ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                              : IconButton(
                                  icon: const Icon(Icons.cloud_download_outlined, size: 20),
                                  tooltip: 'Fetch URL content',
                                  onPressed: () async {
                                    final fetchUrl = urlController.text.trim();
                                    if (fetchUrl.isEmpty) {
                                      ShowMessage.alert(ctx, title: 'URL Required', message: 'Please enter a valid remote URL first.');
                                      return;
                                    }
                                    setDialogState(() => isFetchingUrl = true);
                                    try {
                                      final raw = await _selectaController.fetchRawCatalogFromUrl(fetchUrl);
                                      if (raw.isNotEmpty) {
                                        dataController.text = raw;
                                        final isJson = raw.trim().startsWith('[') || raw.trim().startsWith('{');
                                        selectedFormat = isJson ? 'JSON' : 'CSV';
                                      }
                                    } catch (e) {
                                      if (ctx.mounted) ShowMessage.error(ctx, 'Failed to fetch URL: $e');
                                    } finally {
                                      setDialogState(() => isFetchingUrl = false);
                                    }
                                  },
                                ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Catalog Data:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant)),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  dataController.text = sampleCsv;
                                  setDialogState(() => selectedFormat = 'CSV');
                                },
                                icon: const Icon(Icons.description_outlined, size: 14),
                                label: const Text('Sample CSV', style: TextStyle(fontSize: 11)),
                                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), visualDensity: VisualDensity.compact),
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                                  if (data?.text != null && data!.text!.trim().isNotEmpty) {
                                    dataController.text = data.text!.trim();
                                    setDialogState(() {});
                                  }
                                },
                                icon: const Icon(Icons.paste_rounded, size: 14),
                                label: const Text('Paste', style: TextStyle(fontSize: 11)),
                                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), visualDensity: VisualDensity.compact),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: dataController,
                        maxLines: 6,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          hintText: selectedFormat == 'JSON'
                              ? '[{"productName": "...", "buyingPrice": 20, "sellingPrice": 25, "category": "By Piece", "imageUrl": "..."}]'
                              : 'Product Name,Buying Price,Selling Price,Category,Image URL\nCornetto Chocolate,25.00,30.00,By Piece,\nMagnum Classic,50.00,65.00,By Piece,',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isImporting ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: isImporting
                      ? null
                      : () async {
                          final text = dataController.text.trim();
                          final url = urlController.text.trim();
                          if (text.isEmpty && url.isEmpty) {
                            ShowMessage.alert(ctx, title: 'No Data Provided', message: 'Please paste catalog data or enter a catalog URL.');
                            return;
                          }
                          setDialogState(() => isImporting = true);
                          try {
                            if (url.isNotEmpty) {
                              await _selectaController.setCustomCatalogApiUrl(url);
                            }
                            final count = url.isNotEmpty && text.isEmpty
                                ? await _selectaController.importAdminCatalogFromUrl(url)
                                : await _selectaController.importAdminCatalog(text);
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              ShowMessage.success(
                                context,
                                'Imported $count products successfully.',
                              );
                            }
                          } catch (e) {
                            if (ctx.mounted) ShowMessage.error(ctx, 'Import failed: $e');
                          } finally {
                            setDialogState(() => isImporting = false);
                          }
                        },
                  icon: isImporting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.file_download_done_rounded, size: 16),
                  label: Text(isImporting ? 'Importing...' : 'Import Catalog'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── Selecta Navigation & Toggles ─────────────────────────────────────────
  Future<void> _navigateToSelectaForm({String? productId, AdminSelectaProduct? product}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SelectaProductFormPage(
          productId: productId,
          existingProduct: product,
          isReadOnly: false,
          userRole: widget.userRole,
        ),
      ),
    );
  }

  Future<void> _navigateToSelectaDealerDetails({required String productId, required SelectaProduct product}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SelectaProductFormPage(
          productId: productId,
          existingDealerProduct: product,
          isReadOnly: true,
          userRole: widget.userRole,
        ),
      ),
    );
  }

  Future<void> _toggleSelectaActive(String productId, String name, bool currentlyActive) async {
    try {
      await _selectaController.toggleActive(productId, !currentlyActive);
      if (mounted) {
        ShowMessage.success(context, '"$name" is now ${!currentlyActive ? 'Active' : 'Inactive'}.');
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to update status: $e');
    }
  }

  // ── Other Product Navigation & Toggles ───────────────────────────────────
  Future<void> _navigateToOtherForm({String? productId, OtherProduct? product}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OtherProductFormPage(
          productId: productId,
          existingProduct: product,
          isReadOnly: _isSalesman,
          userRole: widget.userRole,
        ),
      ),
    );
  }

  Future<void> _toggleOtherActive(String productId, String name, bool currentlyActive) async {
    try {
      await _otherController.toggleActive(productId, !currentlyActive);
      if (mounted) {
        ShowMessage.success(context, '"$name" is now ${!currentlyActive ? 'Active' : 'Inactive'}.');
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to update status: $e');
    }
  }

  // ── Filter helpers ────────────────────────────────────────────────────────
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applySelectaFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      final data = doc.data();
      final name = (data['productName'] as String? ?? '').toLowerCase();
      final code = (data['itemCode'] as String? ?? '').toLowerCase();
      final matchesSearch = _selectaSearchQuery.isEmpty ||
          name.contains(_selectaSearchQuery) ||
          code.contains(_selectaSearchQuery);

      final isActive = data['isActive'] as bool? ?? true;
      final matchesStatus = _selectaFilterStatus == 'All' ||
          (_selectaFilterStatus == 'Active' && isActive) ||
          (_selectaFilterStatus == 'Inactive' && !isActive);

      return matchesSearch && matchesStatus;
    }).toList();
  }

  List<QueryDocumentSnapshot<OtherProduct>> _applyOtherFilters(
    List<QueryDocumentSnapshot<OtherProduct>> docs,
  ) {
    final filtered = docs.where((doc) {
      final p = doc.data();
      final matchesSearch = _otherSearchQuery.isEmpty ||
          p.productName.toLowerCase().contains(_otherSearchQuery);
      final matchesStatus = _otherFilterStatus == 'All' ||
          (_otherFilterStatus == 'Active' && p.isActive) ||
          (_otherFilterStatus == 'Inactive' && !p.isActive);
      return matchesSearch && matchesStatus;
    }).toList();

    filtered.sort((a, b) {
      final pA = a.data();
      final pB = b.data();
      return Helperfunctions.compareBySrpAndName(
        nameA: pA.productName,
        priceA: pA.sellingPrice,
        nameB: pB.productName,
        priceB: pB.sellingPrice,
      );
    });

    return filtered;
  }

  // ── Build Method ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelectaTab = _tabController.index == 0;

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Products',
        subtitle: _isAdmin
            ? (isSelectaTab ? 'Admin Selecta Master Catalog' : 'Admin Other Products Catalog')
            : (_isSalesman ? 'Selecta & Other Products Reference' : 'Dealer Products Catalog'),
        actions: isSelectaTab && _isAdmin
            ? [
                IconButton(
                  icon: const Icon(Icons.file_download_outlined, color: Colors.white, size: 20),
                  tooltip: 'Import Catalog Data',
                  onPressed: _handleAdminImport,
                ),
                IconButton(
                  icon: const Icon(Icons.file_upload_outlined, color: Colors.white, size: 20),
                  tooltip: 'Export Catalog Data',
                  onPressed: _handleAdminExport,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.warehouse_outlined, color: Colors.white, size: 20),
                  tooltip: 'Manage Inventory',
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryPage()));
                  },
                ),
              ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.7),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13.5),
          tabs: const [
            Tab(
              icon: Icon(Icons.icecream_outlined, size: 20),
              text: 'Selecta Products',
            ),
            Tab(
              icon: Icon(Icons.inventory_2_outlined, size: 20),
              text: 'Other Products',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSelectaProductsTab(colorScheme),
          _buildOtherProductsTab(colorScheme),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(colorScheme),
    );
  }

  // ── Floating Action Button ────────────────────────────────────────────────
  Widget? _buildFloatingActionButton(ColorScheme colorScheme) {
    if (_tabController.index == 0) {
      // Selecta Products Tab: Only Admins can add directly to master catalog
      if (_isAdmin) {
        return FloatingActionButton.extended(
          heroTag: 'products_selecta_fab',
          onPressed: () => _navigateToSelectaForm(),
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Add Product', style: TextStyle(fontWeight: FontWeight.bold)),
        );
      }
      return null;
    } else {
      // Other Products Tab: FAB "Add Other Product" for Dealers and Admins
      if (!_isSalesman) {
        return FloatingActionButton.extended(
          heroTag: 'products_other_fab',
          onPressed: () => _navigateToOtherForm(),
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Add Other Product', style: TextStyle(fontWeight: FontWeight.bold)),
        );
      }
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TAB 1: SELECTA PRODUCTS
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildSelectaProductsTab(ColorScheme colorScheme) {
    return Column(
      children: [
        // Admin Mode Banner
        if (_isAdmin)
          Container(
            width: double.infinity,
            color: Colors.amber.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Row(
              children: [
                Icon(Icons.admin_panel_settings_rounded, size: 18, color: Colors.amber),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Admin Mode: Create, edit, delete, import, and export master Selecta products.',
                    style: TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

        // Dealer Out-of-Sync Banner
        if (!_isAdmin && !_isSalesman && _hasRemoteSelectaChanges)
          Container(
            width: double.infinity,
            color: colorScheme.primaryContainer.withValues(alpha: 0.55),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.cloud_sync_outlined, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'New updates available in the master Selecta catalog.',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                  ),
                ),
                TextButton.icon(
                  onPressed: _isSelectaSyncing ? null : _handleDealerSync,
                  icon: const Icon(Icons.sync_rounded, size: 15),
                  label: Text(_isSelectaSyncing ? 'Syncing...' : 'Sync Now', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ],
            ),
          ),

        // Search Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: TextField(
            controller: _selectaSearchController,
            onChanged: (val) => setState(() => _selectaSearchQuery = val.trim().toLowerCase()),
            style: const TextStyle(fontSize: 14.5),
            decoration: InputDecoration(
              hintText: 'Search Selecta products or item code...',
              hintStyle: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
              prefixIcon: Icon(Icons.search, size: 20, color: colorScheme.primary),
              suffixIcon: _selectaSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _selectaSearchController.clear();
                        setState(() => _selectaSearchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colorScheme.outlineVariant)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colorScheme.primary, width: 1.5)),
            ),
          ),
        ),

        // Status Filter Chips
        if (!_isAdmin)
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final status = const ['All', 'Active', 'Inactive'][index];
                final isSelected = _selectaFilterStatus == status;
                return FilterChip(
                  selected: isSelected,
                  label: Text(
                    status,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                    ),
                  ),
                  selectedColor: colorScheme.primary,
                  backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  checkmarkColor: colorScheme.onPrimary,
                  showCheckmark: false,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  onSelected: (_) => setState(() => _selectaFilterStatus = status),
                );
              },
            ),
          ),

        // Stream and List
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _isAdmin ? _selectaController.getAdminProductsStream() : _selectaController.getProductsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _buildErrorState(snapshot.error.toString());
              }

              final allDocs = snapshot.data?.docs ?? [];
              final filtered = _applySelectaFilters(allDocs);

              if (allDocs.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.icecream_outlined,
                  title: _isAdmin ? 'No Admin Selecta Products Found' : 'No Selecta Products Synced Yet',
                  subtitle: _isAdmin
                      ? 'Import or add Selecta products to build the master catalog.'
                      : 'Sync with the master Admin catalog to populate Selecta products.',
                );
              }

              final selectaCaseItems = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              final selectaPieceItems = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

              for (final doc in filtered) {
                final data = doc.data();
                final cat = (data['category'] as String? ?? '').trim().toLowerCase();
                if (cat == 'by case' || cat.contains('case')) {
                  selectaCaseItems.add(doc);
                } else {
                  selectaPieceItems.add(doc);
                }
              }

              int compareProducts(
                QueryDocumentSnapshot<Map<String, dynamic>> a,
                QueryDocumentSnapshot<Map<String, dynamic>> b,
              ) {
                final dataA = a.data();
                final dataB = b.data();
                final nameA = dataA['productName'] as String? ?? '';
                final nameB = dataB['productName'] as String? ?? '';
                final priceA = (dataA['sellingPrice'] as num?)?.toDouble() ?? 0.0;
                final priceB = (dataB['sellingPrice'] as num?)?.toDouble() ?? 0.0;
                return Helperfunctions.compareBySrpAndName(nameA: nameA, priceA: priceA, nameB: nameB, priceB: priceB);
              }

              selectaCaseItems.sort(compareProducts);
              selectaPieceItems.sort(compareProducts);

              final isFiltered = _selectaSearchQuery.isNotEmpty || (!_isAdmin && _selectaFilterStatus != 'All');

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isFiltered
                              ? 'Showing ${filtered.length} of ${allDocs.length} products'
                              : '${allDocs.length} product${allDocs.length == 1 ? '' : 's'} in catalog',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                        ),
                        if (isFiltered)
                          InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () {
                              _selectaSearchController.clear();
                              setState(() {
                                _selectaSearchQuery = '';
                                _selectaFilterStatus = 'All';
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.filter_alt_off_outlined, size: 15, color: colorScheme.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Reset',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? _buildNoResultsState(onReset: () {
                            _selectaSearchController.clear();
                            setState(() {
                              _selectaSearchQuery = '';
                              _selectaFilterStatus = 'All';
                            });
                          })
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                            children: [
                              if (selectaCaseItems.isNotEmpty) ...[
                                _buildGroupHeader(
                                  title: 'Selecta Products (By Case)',
                                  icon: Icons.all_inbox_rounded,
                                  color: Colors.deepOrange.shade700,
                                  count: selectaCaseItems.length,
                                ),
                                ...selectaCaseItems.map(
                                  (doc) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _isAdmin ? _buildAdminSelectaCard(doc) : _buildDealerSelectaCard(doc),
                                  ),
                                ),
                              ],
                              if (selectaPieceItems.isNotEmpty) ...[
                                _buildGroupHeader(
                                  title: 'Selecta Products (By Piece)',
                                  icon: Icons.icecream_outlined,
                                  color: Colors.blue.shade700,
                                  count: selectaPieceItems.length,
                                ),
                                ...selectaPieceItems.map(
                                  (doc) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _isAdmin ? _buildAdminSelectaCard(doc) : _buildDealerSelectaCard(doc),
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAdminSelectaCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final product = AdminSelectaProduct.fromJson(doc.id, data.cast<String, Object?>());
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _navigateToSelectaForm(productId: doc.id, product: product),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CachedProductImage(imageUrl: product.imageUrl, isActive: true, size: 48, borderRadius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.productName,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, height: 1.25, color: colorScheme.onSurface),
                    ),
                    if (product.category.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        product.category,
                        style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('Buy: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant)),
                        Text(currencyFormat.format(product.buyingPrice), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant)),
                        const SizedBox(width: 16),
                        Text('Sell: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant)),
                        Text(currencyFormat.format(product.sellingPrice), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: colorScheme.onSurface)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 22, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDealerSelectaCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final product = SelectaProduct.fromJson(doc.id, data.cast<String, Object?>());
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = product.isActive;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _navigateToSelectaDealerDetails(productId: doc.id, product: product),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CachedProductImage(imageUrl: product.imageUrl, isActive: isActive, size: 48, borderRadius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.productName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        height: 1.25,
                        color: isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (product.itemCode.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Item Code: ${product.itemCode}',
                        style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'Buy: ',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isActive ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          currencyFormat.format(product.buyingPrice),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: isActive ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Sell: ',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isActive ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          currencyFormat.format(product.sellingPrice),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!_isSalesman)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleSelectaActive(doc.id, product.productName, product.isActive),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 40,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isActive ? colorScheme.primary : colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Align(
                      alignment: isActive ? Alignment.centerRight : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(2.5),
                        child: Container(
                          width: 19,
                          height: 19,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 22, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TAB 2: OTHER PRODUCTS
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildOtherProductsTab(ColorScheme colorScheme) {
    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: TextField(
            controller: _otherSearchController,
            onChanged: (val) => setState(() => _otherSearchQuery = val.trim().toLowerCase()),
            style: const TextStyle(fontSize: 14.5),
            decoration: InputDecoration(
              hintText: 'Search other products...',
              hintStyle: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
              prefixIcon: Icon(Icons.search, size: 20, color: colorScheme.primary),
              suffixIcon: _otherSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _otherSearchController.clear();
                        setState(() => _otherSearchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colorScheme.outlineVariant)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colorScheme.primary, width: 1.5)),
            ),
          ),
        ),

        // Status Filter Chips
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 3,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final status = const ['All', 'Active', 'Inactive'][index];
              final isSelected = _otherFilterStatus == status;
              return FilterChip(
                selected: isSelected,
                label: Text(
                  status,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                  ),
                ),
                selectedColor: colorScheme.primary,
                backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                checkmarkColor: colorScheme.onPrimary,
                showCheckmark: false,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                onSelected: (_) => setState(() => _otherFilterStatus = status),
              );
            },
          ),
        ),

        // Stream and List
        Expanded(
          child: StreamBuilder<QuerySnapshot<OtherProduct>>(
            stream: _otherController.getProductsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _buildErrorState(snapshot.error.toString());
              }

              final allDocs = snapshot.data?.docs ?? [];
              final filtered = _applyOtherFilters(allDocs);

              if (allDocs.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No Other Products Yet',
                  subtitle: _isSalesman
                      ? 'No non-Selecta products are registered in the catalog yet.'
                      : 'Tap "Add Other Product" to create your first non-Selecta product.',
                );
              }

              final isFiltered = _otherSearchQuery.isNotEmpty || _otherFilterStatus != 'All';

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isFiltered
                              ? 'Showing ${filtered.length} of ${allDocs.length} products'
                              : '${allDocs.length} product${allDocs.length == 1 ? '' : 's'} in catalog',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                        ),
                        if (isFiltered)
                          InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () {
                              _otherSearchController.clear();
                              setState(() {
                                _otherSearchQuery = '';
                                _otherFilterStatus = 'All';
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.filter_alt_off_outlined, size: 15, color: colorScheme.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Reset',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? _buildNoResultsState(onReset: () {
                            _otherSearchController.clear();
                            setState(() {
                              _otherSearchQuery = '';
                              _otherFilterStatus = 'All';
                            });
                          })
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                            children: [
                              _buildGroupHeader(
                                title: 'Other Products',
                                icon: Icons.inventory_2_outlined,
                                color: colorScheme.onSurfaceVariant,
                                count: filtered.length,
                              ),
                              ...filtered.map(
                                (doc) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _buildOtherProductCard(doc),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOtherProductCard(QueryDocumentSnapshot<OtherProduct> doc) {
    final product = doc.data();
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = product.isActive;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _navigateToOtherForm(productId: doc.id, product: product),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CachedProductImage(imageUrl: product.imageUrl, isActive: isActive, size: 48, borderRadius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.productName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        height: 1.25,
                        color: isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'Buy: ',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isActive ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          currencyFormat.format(product.buyingPrice),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: isActive ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Sell: ',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isActive ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          currencyFormat.format(product.sellingPrice),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!_isSalesman)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleOtherActive(doc.id, product.productName, product.isActive),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 40,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isActive ? colorScheme.primary : colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Align(
                      alignment: isActive ? Alignment.centerRight : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(2.5),
                        child: Container(
                          width: 19,
                          height: 19,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 22, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  // ── Common Shared Widgets ─────────────────────────────────────────────────
  Widget _buildGroupHeader({
    required String title,
    required IconData icon,
    required Color color,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: color),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(
                  '$count ${count == 1 ? "product" : "products"}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, thickness: 1),
        ],
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(icon, size: 40, color: colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState({required VoidCallback onReset}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text('No Results Found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search query or status filter.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
              label: const Text('Reset Filters'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Something went wrong', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
