import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/controllers/selecta_product_controller.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/admin_selecta_product.dart';
import 'package:flutter_app/models/selecta_product.dart';
import 'package:flutter_app/services/selecta_product_service.dart';
import 'package:flutter_app/views/pages/sidebar/inventory_page.dart';
import 'package:flutter_app/views/pages/sidebar/selecta_product_form_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/cached_product_image.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

/// Selecta Products catalog page.
/// - **Dealer Mode**: Reads from dealer's local `selecta_products` ([SelectaProduct]).
///   Dealers can only switch active/inactive status and sync when there are changes in the Admin catalog.
/// - **Admin Mode**: Reads/writes the master `admin_selecta_products` ([AdminSelectaProduct]).
///   Admins can Create, Edit, Delete records, and Import/Export catalog data.
class SelectaProductsPage extends StatefulWidget {
  final String userRole;

  const SelectaProductsPage({
    super.key,
    this.userRole = 'Dealer',
  });

  @override
  State<SelectaProductsPage> createState() => _SelectaProductsPageState();
}

class _SelectaProductsPageState extends State<SelectaProductsPage> {
  final SelectaProductController _controller = SelectaProductController();
  final TextEditingController _searchController = TextEditingController();
  final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  String _searchQuery = '';
  String _filterStatus = 'All'; // 'All', 'Active', 'Inactive' (Dealer mode only)
  bool _isSyncing = false;
  bool _hasRemoteChanges = false;
  List<AdminSelectaProduct>? _pendingRemoteProducts;

  bool get _isAdmin {
    final role = widget.userRole.trim().toLowerCase();
    return role == 'admin' || role == 'super admin' || role == 'superadmin';
  }

  @override
  void initState() {
    super.initState();
    if (_isAdmin) {
      _controller.ensureAdminCatalogSeeded();
    } else {
      _checkForAdminCatalogUpdates();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkForAdminCatalogUpdates() async {
    final check = await _controller.checkSyncNeeded();
    if (mounted) {
      setState(() {
        _hasRemoteChanges = check.needsSync;
        _pendingRemoteProducts = check.remoteProducts.isNotEmpty ? check.remoteProducts : null;
      });
    }
  }

  Future<void> _handleDealerSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      final result = await _controller.syncWithAdminCatalog(
        remoteProducts: _pendingRemoteProducts,
      );
      if (!mounted) return;
      setState(() {
        _hasRemoteChanges = false;
        _pendingRemoteProducts = null;
      });
      if (result.totalFetched == 0) {
        ShowMessage.alert(
          context,
          title: 'Sync Selecta Catalog',
          message: 'No products found in the master Admin catalog yet.',
        );
      } else if (result.addedCount == 0 && result.updatedCount == 0) {
        ShowMessage.success(
          context,
          'Catalog is up to date (${result.totalFetched} products).',
        );
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
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _handleAdminExport() async {
    try {
      String exportFormat = 'CSV'; // 'CSV' or 'JSON'
      final csvStr = await _controller.exportAdminCatalogCsv();
      final jsonStr = await _controller.exportAdminCatalogJson();
      final csvFile = await _controller.exportAdminCatalogToCsvFile();
      final jsonFile = await _controller.exportAdminCatalogToFile();
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
                    child: Text(
                      'Export Admin Catalog',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'CSV',
                            label: Text('CSV (Excel)'),
                            icon: Icon(Icons.table_chart_outlined, size: 16),
                          ),
                          ButtonSegment<String>(
                            value: 'JSON',
                            label: Text('JSON'),
                            icon: Icon(Icons.code_rounded, size: 16),
                          ),
                        ],
                        selected: {exportFormat},
                        onSelectionChanged: (val) {
                          setDialogState(() => exportFormat = val.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Saved to:\n${currentFile.path}',
                      style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
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
                        child: SelectableText(
                          currentContent,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                        ),
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
    final currentUrl = await _controller.getCustomCatalogApiUrl() ?? '';
    if (!mounted) return;

    final urlController = TextEditingController(text: currentUrl);
    final dataController = TextEditingController();
    String selectedFormat = 'Auto-Detect'; // 'Auto-Detect', 'CSV', 'JSON'
    bool isImporting = false;
    bool isFetchingUrl = false;

    const sampleCsv = 'Product Name,Buying Price,Selling Price,Category,Image URL\n'
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
                    child: Text(
                      'Import Admin Catalog',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
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

                      // Format toggle
                      Row(
                        children: [
                          Text(
                            'Format:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  ChoiceChip(
                                    label: const Text('Auto-Detect', style: TextStyle(fontSize: 11)),
                                    selected: selectedFormat == 'Auto-Detect',
                                    onSelected: (s) {
                                      if (s) setDialogState(() => selectedFormat = 'Auto-Detect');
                                    },
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const SizedBox(width: 6),
                                  ChoiceChip(
                                    label: const Text('CSV', style: TextStyle(fontSize: 11)),
                                    selected: selectedFormat == 'CSV',
                                    onSelected: (s) {
                                      if (s) setDialogState(() => selectedFormat = 'CSV');
                                    },
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const SizedBox(width: 6),
                                  ChoiceChip(
                                    label: const Text('JSON', style: TextStyle(fontSize: 11)),
                                    selected: selectedFormat == 'JSON',
                                    onSelected: (s) {
                                      if (s) setDialogState(() => selectedFormat = 'JSON');
                                    },
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Remote URL input with fetch action
                      TextField(
                        controller: urlController,
                        decoration: InputDecoration(
                          labelText: 'Remote URL (CSV or JSON)',
                          hintText: 'https://raw.githubusercontent.com/.../catalog.csv',
                          prefixIcon: const Icon(Icons.link_rounded, size: 18),
                          suffixIcon: isFetchingUrl
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.cloud_download_outlined, size: 20),
                                  tooltip: 'Fetch & load URL content into editor',
                                  onPressed: () async {
                                    final fetchUrl = urlController.text.trim();
                                    if (fetchUrl.isEmpty) {
                                      ShowMessage.alert(ctx, title: 'URL Required', message: 'Please enter a valid remote URL first.');
                                      return;
                                    }
                                    setDialogState(() => isFetchingUrl = true);
                                    try {
                                      final raw = await _controller.fetchRawCatalogFromUrl(fetchUrl);
                                      if (raw.isNotEmpty) {
                                        dataController.text = raw;
                                        final isJson = raw.trim().startsWith('[') || raw.trim().startsWith('{');
                                        selectedFormat = isJson ? 'JSON' : 'CSV';
                                      }
                                    } catch (e) {
                                      if (ctx.mounted) {
                                        ShowMessage.error(ctx, 'Failed to fetch URL: $e');
                                      }
                                    } finally {
                                      setDialogState(() => isFetchingUrl = false);
                                    }
                                  },
                                ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                          helperText: 'Supports GitHub raw files, Google Sheets CSV links, or REST APIs. Tap download icon to preview.',
                          helperMaxLines: 2,
                          helperStyle: const TextStyle(fontSize: 10.5),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Paste Data Header with Quick Action Buttons
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Paste Catalog Data:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  dataController.text = sampleCsv;
                                  setDialogState(() => selectedFormat = 'CSV');
                                },
                                icon: const Icon(Icons.description_outlined, size: 14),
                                label: const Text('Sample CSV', style: TextStyle(fontSize: 11)),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  visualDensity: VisualDensity.compact,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
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
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  visualDensity: VisualDensity.compact,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
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
                      const SizedBox(height: 4),

                      // Live preview of parsed products
                      Builder(
                        builder: (_) {
                          final currentText = dataController.text.trim();
                          if (currentText.isEmpty) {
                            return Text(
                              'Columns supported: Product Name, Buying Price, Selling Price, Category (By Piece / By Case), Image URL',
                              style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
                            );
                          }
                          if (currentText.startsWith('http://') || currentText.startsWith('https://')) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.link_rounded, size: 15, color: colorScheme.primary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Remote link detected: Click Import to fetch and import products.',
                                      style: TextStyle(fontSize: 11, color: colorScheme.primary, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          try {
                            final parsed = SelectaProductService.parseAdminProductsFromData(currentText);
                            final isJson = currentText.startsWith('[') || currentText.startsWith('{');
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle_outline_rounded, size: 15, color: Color(0xFF15803D)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '✓ ${parsed.length} valid products detected (${isJson ? 'JSON' : 'CSV'})',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF15803D), fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          } catch (e) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, size: 15, color: colorScheme.error),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Format note: $e',
                                      style: TextStyle(fontSize: 10.5, color: colorScheme.error),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
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
                          final rawData = dataController.text.trim();
                          var url = urlController.text.trim();

                          if (rawData.isEmpty && url.isEmpty) {
                            ShowMessage.error(ctx, 'Please provide a URL or paste CSV / JSON data.');
                            return;
                          }

                          // If the user pasted a URL into the large text area, treat it as remote URL
                          final isRawDataUrl = rawData.startsWith('http://') || rawData.startsWith('https://');
                          if (isRawDataUrl && url.isEmpty) {
                            url = rawData;
                          }

                          setDialogState(() => isImporting = true);
                          try {
                            int count = 0;
                            if (url.isNotEmpty) {
                              await _controller.setCustomCatalogApiUrl(url);
                            }

                            if (rawData.isNotEmpty && !isRawDataUrl) {
                              if (selectedFormat == 'CSV') {
                                count = await _controller.importAdminCatalogFromCsv(rawData);
                              } else if (selectedFormat == 'JSON') {
                                count = await _controller.importAdminCatalogFromJson(rawData);
                              } else {
                                count = await _controller.importAdminCatalog(rawData);
                              }
                            } else if (url.isNotEmpty) {
                              count = await _controller.importAdminCatalogFromUrl(url);
                            }

                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              ShowMessage.success(context, 'Imported $count products into Admin catalog!');
                            }
                          } catch (e) {
                            setDialogState(() => isImporting = false);
                            if (ctx.mounted) {
                              ShowMessage.error(ctx, 'Import failed: $e');
                            }
                          }
                        },
                  icon: isImporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download_done_rounded, size: 18),
                  label: Text(isImporting ? 'Importing...' : 'Import'),
                ),
              ],
            );

          },
        );
      },
    );
  }

  void _onSearchChanged(String text) {
    setState(() => _searchQuery = text.trim().toLowerCase());
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _filterStatus = 'All';
    });
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final filtered = docs.where((doc) {
      final data = doc.data();
      final name = (data['productName'] as String? ?? '').toLowerCase();
      final matchesSearch = _searchQuery.isEmpty || name.contains(_searchQuery);
      if (_isAdmin) {
        return matchesSearch;
      }
      final isActive = data['isActive'] as bool? ?? true;
      final matchesStatus = _filterStatus == 'All' ||
          (_filterStatus == 'Active' && isActive) ||
          (_filterStatus == 'Inactive' && !isActive);
      return matchesSearch && matchesStatus;
    }).toList();

    filtered.sort((a, b) {
      final dataA = a.data();
      final dataB = b.data();
      final catA = (dataA['category'] as String? ?? '').trim();
      final catB = (dataB['category'] as String? ?? '').trim();
      final catComp = Helperfunctions.compareCategoryHierarchy(catA, catB);
      if (catComp != 0) return catComp;

      final nameA = dataA['productName'] as String? ?? '';
      final nameB = dataB['productName'] as String? ?? '';
      final priceA = (dataA['sellingPrice'] as num?)?.toDouble() ?? 0.0;
      final priceB = (dataB['sellingPrice'] as num?)?.toDouble() ?? 0.0;

      return Helperfunctions.compareBySrpAndName(
        nameA: nameA,
        priceA: priceA,
        nameB: nameB,
        priceB: priceB,
      );
    });

    return filtered;
  }

  Future<void> _navigateToForm({String? productId, AdminSelectaProduct? product}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SelectaProductFormPage(productId: productId, existingProduct: product),
      ),
    );
  }

  Future<void> _toggleActive(String productId, String name, bool currentlyActive) async {
    try {
      await _controller.toggleActive(productId, !currentlyActive);
      if (mounted) {
        ShowMessage.success(context, '"$name" is now ${!currentlyActive ? 'Active' : 'Inactive'}.');
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to update status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Selecta Products',
        subtitle: _isAdmin ? 'Admin Master Catalog' : 'Dealer Product Catalog',
        actions: _isAdmin
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
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const InventoryPage()),
                    );
                  },
                ),
              ],
      ),
      body: Column(
        children: [
          // ── Admin Banner ──────────────────────────────────────
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

          // ── Dealer Out-of-Sync Banner ─────────────────────────
          if (!_isAdmin && _hasRemoteChanges)
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
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isSyncing ? null : _handleDealerSync,
                    icon: const Icon(Icons.sync_rounded, size: 15),
                    label: Text(_isSyncing ? 'Syncing...' : 'Sync Now', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
            ),

          // ── Search Bar ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search Selecta products...',
                hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                prefixIcon: Icon(Icons.search, size: 20, color: colorScheme.primary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                ),
              ),
            ),
          ),

          // ── Status Filter Chips (Dealer mode only) ──────────────────────
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
                  final isSelected = _filterStatus == status;
                  return FilterChip(
                    selected: isSelected,
                    label: Text(
                      status,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                      ),
                    ),
                    selectedColor: colorScheme.primary,
                    backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    checkmarkColor: colorScheme.onPrimary,
                    showCheckmark: false,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    onSelected: (_) => setState(() => _filterStatus = status),
                  );
                },
              ),
            ),

          // ── Products List ────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _isAdmin ? _controller.getAdminProductsStream() : _controller.getProductsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _buildErrorState(snapshot.error.toString());
                }

                final allDocs = snapshot.data?.docs ?? [];
                final filtered = _applyFilters(allDocs);

                if (allDocs.isEmpty) {
                  return _buildEmptyState();
                }

                final isFiltered = _searchQuery.isNotEmpty || (!_isAdmin && _filterStatus != 'All');

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
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (isFiltered)
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: _resetFilters,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.filter_alt_off_outlined, size: 14, color: colorScheme.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Reset',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
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
                          ? _buildNoResultsState()
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 88),
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final doc = filtered[index];
                                return _isAdmin ? _buildAdminProductCard(doc) : _buildDealerProductCard(doc);
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _navigateToForm(),
              backgroundColor: colorScheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add Product', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  /// Renders a card for the Admin Master Model ([AdminSelectaProduct]):
  /// Only image, product name, buying price, selling price, and margin.
  Widget _buildAdminProductCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final product = AdminSelectaProduct.fromJson(doc.id, data.cast<String, Object?>());
    final colorScheme = Theme.of(context).colorScheme;
    final isPositiveMargin = product.margin >= 0;
    final marginColor = isPositiveMargin ? const Color(0xFF15803D) : colorScheme.error;

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
        onTap: () => _navigateToForm(productId: doc.id, product: product),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _buildProductImage(product.imageUrl, true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.productName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: product.category == 'By Case'
                                ? Colors.deepOrange.withValues(alpha: 0.12)
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: product.category == 'By Case'
                                  ? Colors.deepOrange.withValues(alpha: 0.4)
                                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            product.category,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: product.category == 'By Case'
                                  ? Colors.deepOrange.shade800
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            currencyFormat.format(product.buyingPrice),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            currencyFormat.format(product.sellingPrice),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: product.sellingPrice > 0 && product.buyingPrice > 0
                              ? Text(
                                  '${currencyFormat.format(product.margin)} (${isPositiveMargin ? '+' : ''}${product.marginPercent.round()}%)',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: marginColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 20, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// Renders a card for the Dealer Model ([SelectaProduct]):
  /// Dealer can only switch the active/inactive status.
  Widget _buildDealerProductCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final product = SelectaProduct.fromJson(doc.id, data.cast<String, Object?>());
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = product.isActive;
    final isPositiveMargin = product.margin >= 0;
    final marginColor = isPositiveMargin ? const Color(0xFF15803D) : colorScheme.error;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _buildProductImage(product.imageUrl, isActive),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.productName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 6),
                        _buildStockBadge(product, colorScheme),
                      ],
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: product.category == 'By Case'
                              ? Colors.deepOrange.withValues(alpha: 0.12)
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: product.category == 'By Case'
                                ? Colors.deepOrange.withValues(alpha: 0.4)
                                : colorScheme.outlineVariant.withValues(alpha: 0.5),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          product.category,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: product.category == 'By Case'
                                ? Colors.deepOrange.shade800
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          currencyFormat.format(product.buyingPrice),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isActive
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          currencyFormat.format(product.sellingPrice),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: product.sellingPrice > 0 && product.buyingPrice > 0
                            ? Text(
                                '${currencyFormat.format(product.margin)} (${isPositiveMargin ? '+' : ''}${product.marginPercent.round()}%)',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: isActive ? marginColor : colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _toggleActive(doc.id, product.productName, product.isActive),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 38,
                height: 22,
                decoration: BoxDecoration(
                  color: isActive ? colorScheme.primary : colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Align(
                  alignment: isActive ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(2.5),
                    child: Container(
                      width: 17,
                      height: 17,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockBadge(SelectaProduct product, ColorScheme colorScheme) {
    final Color badgeColor = product.isOutOfStock
        ? colorScheme.error
        : product.isLowStock
            ? const Color(0xFFD97706)
            : const Color(0xFF15803D);
    final String label = product.isOutOfStock
        ? 'Out: 0'
        : 'Stock: ${product.stockQuantity}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: badgeColor,
        ),
      ),
    );
  }

  Widget _buildProductImage(String imageUrl, bool isActive) {
    return CachedProductImage(imageUrl: imageUrl, isActive: isActive);
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.inventory_2_outlined, size: 40, color: colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              _isAdmin ? 'No Admin Selecta Products Found' : 'No Selecta Products Synced Yet',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _isAdmin
                  ? 'Tap Add Product or Import to populate the master Selecta catalog.'
                  : 'Tap Sync below to fetch the official product list from the Admin catalog.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            if (_isAdmin)
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => _navigateToForm(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Product', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _handleAdminImport,
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: const Text('Import Data', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              )
            else
              FilledButton.icon(
                onPressed: _isSyncing ? null : _handleDealerSync,
                icon: _isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.sync_rounded, size: 18),
                label: Text(
                  _isSyncing ? 'Syncing Catalog...' : 'Sync from Master Catalog',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.search_off_rounded, size: 40, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 20),
            const Text('No Results Found', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search or filter to find products.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
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
            Text(error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
