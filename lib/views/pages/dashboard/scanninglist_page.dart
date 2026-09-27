import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/models/scanning.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/services/scanning_services.dart';
import 'package:flutter_app/views/widgets/barcodescanner_widget.dart';
import 'package:flutter_app/views/pages/dashboard/scanning_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

enum _ScanningSort { storeNameAscending, storeNameDescending, barcodeAscending, barcodeDescending, scannedDateAscending, scannedDateDescending }

class ScanninglistPage extends StatefulWidget {
  const ScanninglistPage({super.key});

  @override
  State<ScanninglistPage> createState() => _ScanninglistPageState();
}

class _ScanninglistPageState extends State<ScanninglistPage> {
  List<Scanning> scanningList = [];
  Map<String, Hapistore> _storesMap = {};

  int _currentIndex = 0;
  bool _isLoading = true;
  _ScanningSort _sort = _ScanningSort.storeNameAscending;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    prefetchData();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> prefetchData() async {
    if (mounted) setState(() => _isLoading = true);
    final results = await Future.wait([
      ScanningServices.getAllScannings(),
      HapiStoreService.getListHapiStores(forceRefresh: true),
    ]);
    final scannings = results[0] as List<Scanning>;
    final stores = results[1] as List<Hapistore>;

    if (!mounted) return;

    final storesMap = <String, Hapistore>{};
    final assignedStoreNames = <String>{};

    for (final store in stores) {
      if (store.storeName.trim().isNotEmpty) {
        storesMap[store.storeName.trim().toLowerCase()] = store;
      }
    }

    for (final s in scannings) {
      if (s.barcode.trim().isNotEmpty && s.status != ScanningStatus.pullout && s.storeName.trim().isNotEmpty) {
        assignedStoreNames.add(s.storeName.trim().toLowerCase());
      }
    }

    final combinedList = List<Scanning>.from(scannings);

    // Identify unassigned stores (stores with no barcode saved in the database)
    for (final store in stores) {
      final name = store.storeName.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      if (!assignedStoreNames.contains(key)) {
        final alreadyInList = combinedList.any(
          (s) => s.status == ScanningStatus.unassigned && s.storeName.trim().toLowerCase() == key,
        );
        if (!alreadyInList) {
          combinedList.add(
            Scanning(
              id: '',
              barcode: '',
              storeName: store.storeName,
              scannedDate: null,
              scannedBy: '',
              status: ScanningStatus.unassigned,
            ),
          );
        }
      }
    }

    setState(() {
      _storesMap = storesMap;
      scanningList = combinedList;
      _isLoading = false;
    });
  }

  List<Scanning> _filteredAndSorted(String status) {
    List<Scanning> filtered = scanningList.where((scanning) => scanning.status == status).toList();
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((scanning) {
        final store = _storesMap[scanning.storeName.trim().toLowerCase()];
        final address = store?.storeAddress.toLowerCase() ?? '';
        final contact = store?.storeContact.toLowerCase() ?? '';
        return scanning.storeName.toLowerCase().contains(_searchQuery) ||
            scanning.barcode.toLowerCase().contains(_searchQuery) ||
            address.contains(_searchQuery) ||
            contact.contains(_searchQuery);
      }).toList();
    }
    filtered.sort(_compareScannings);
    return filtered;
  }

  int _compareScannings(Scanning first, Scanning second) {
    final comparison = switch (_sort) {
      _ScanningSort.storeNameAscending ||
      _ScanningSort.storeNameDescending => first.storeName.toLowerCase().compareTo(second.storeName.toLowerCase()),
      _ScanningSort.barcodeAscending || _ScanningSort.barcodeDescending =>
        first.barcode.compareTo(second.barcode) != 0
            ? first.barcode.compareTo(second.barcode)
            : first.storeName.toLowerCase().compareTo(second.storeName.toLowerCase()),
      _ScanningSort.scannedDateAscending || _ScanningSort.scannedDateDescending =>
        first.scannedDate == null
            ? (second.scannedDate == null ? first.storeName.toLowerCase().compareTo(second.storeName.toLowerCase()) : -1)
            : (second.scannedDate == null ? 1 : first.scannedDate!.compareTo(second.scannedDate!)),
    };

    return switch (_sort) {
      _ScanningSort.storeNameDescending || _ScanningSort.barcodeDescending || _ScanningSort.scannedDateDescending => -comparison,
      _ => comparison,
    };
  }

  void _openScanning(Scanning scanning) async {
    if (scanning.status == ScanningStatus.unassigned || scanning.barcode.isEmpty) {
      await _assignBarcodeToStore(scanning.storeName);
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (context) => ScanningPage(initialBarcode: scanning.barcode)));
    prefetchData();
  }

  Future<void> _assignBarcodeToStore(String storeName) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.link_rounded, color: Colors.orange.shade800, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Assign Barcode', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(storeName, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Choose how you want to provide the barcode for this store:',
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.qr_code_scanner_rounded, color: colorScheme.primary),
                  ),
                  title: const Text('Scan with Camera', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Scan the physical barcode on the freezer'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'scan'),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: colorScheme.secondary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.keyboard_outlined, color: colorScheme.secondary),
                  ),
                  title: const Text('Enter Manually', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Type the barcode digits manually'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'manual'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == null || !mounted) return;

    String? barcode;
    if (action == 'scan') {
      barcode = await Navigator.push<String>(context, MaterialPageRoute(builder: (context) => const BarcodeScannerWidget()));
    } else if (action == 'manual') {
      barcode = await showDialog<String>(context: context, builder: (context) => const _ManualBarcodeDialog());
    }

    if (barcode == null || barcode.isEmpty || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScanningPage(initialBarcode: barcode!, initialStoreName: storeName),
      ),
    );
    prefetchData();
  }

  void _scanBarcode() async {
    final barcode = await Navigator.push<String>(context, MaterialPageRoute(builder: (context) => const BarcodeScannerWidget()));
    if (barcode == null || barcode.isEmpty || !mounted) return;

    await Navigator.push(context, MaterialPageRoute(builder: (context) => ScanningPage(initialBarcode: barcode)));
    prefetchData();
  }

  Future<void> _enterBarcodeManually() async {
    final barcode = await showDialog<String>(context: context, builder: (context) => const _ManualBarcodeDialog());

    if (barcode == null || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (context) => ScanningPage(initialBarcode: barcode)));
    prefetchData();
  }

  Widget _buildSortMenu() {
    return PopupMenuButton<_ScanningSort>(
      icon: const Icon(Icons.sort_rounded, color: Colors.white),
      tooltip: 'Sort scannings',
      onSelected: (sort) => setState(() => _sort = sort),
      itemBuilder: (context) => [
        _buildSortOption(_ScanningSort.storeNameAscending, 'Store Name', true),
        _buildSortOption(_ScanningSort.storeNameDescending, 'Store Name', false),
        _buildSortOption(_ScanningSort.barcodeAscending, 'Barcode', true),
        _buildSortOption(_ScanningSort.barcodeDescending, 'Barcode', false),
        _buildSortOption(_ScanningSort.scannedDateAscending, 'Scanned Date', true),
        _buildSortOption(_ScanningSort.scannedDateDescending, 'Scanned Date', false),
      ],
    );
  }

  PopupMenuItem<_ScanningSort> _buildSortOption(_ScanningSort sort, String label, bool ascending) {
    return PopupMenuItem(
      value: sort,
      child: Row(
        children: [
          Icon(ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text('$label (${ascending ? 'Ascending' : 'Descending'})')),
          if (_sort == sort) const Icon(Icons.check_rounded, size: 18),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      decoration: InputDecoration(
        hintText: 'Search by store name or barcode',
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchQuery.isEmpty ? null : IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () => _searchController.clear()),
        filled: true,
        fillColor: colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _scanningListView(String status) {
    List<Scanning> scannings = _filteredAndSorted(status);
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 180),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (scannings.isEmpty) {
      final isUnassigned = status == ScanningStatus.unassigned;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 140),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUnassigned ? Icons.check_circle_outline : Icons.qr_code_scanner_outlined,
                  size: 48,
                  color: isUnassigned ? Colors.green : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  _searchQuery.isNotEmpty
                      ? 'No matching records'
                      : (isUnassigned ? 'All stores have barcodes' : 'No $status records'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  isUnassigned
                      ? 'Every registered store has a barcode saved in the database.'
                      : 'Scanning records will appear here when available.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final statusColor = switch (status) {
      ScanningStatus.scanned => Colors.green,
      ScanningStatus.pullout => colorScheme.error,
      ScanningStatus.unassigned => Colors.orange.shade800,
      _ => colorScheme.tertiary,
    };
    final statusIcon = switch (status) {
      ScanningStatus.scanned => Icons.check_circle_outline,
      ScanningStatus.pullout => Icons.outbox_outlined,
      ScanningStatus.unassigned => Icons.link_off_rounded,
      _ => Icons.qr_code_2_outlined,
    };

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      itemCount: scannings.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildSummaryBanner(count: scannings.length, status: status, statusColor: statusColor);
        }

        final scanning = scannings[index - 1];
        final isUnassigned = scanning.status == ScanningStatus.unassigned;
        final store = _storesMap[scanning.storeName.trim().toLowerCase()];

        return Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
          ),
          child: InkWell(
            onTap: () => _openScanning(scanning),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                    child: Icon(statusIcon, color: statusColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          scanning.storeName.isNotEmpty ? scanning.storeName : 'Unassigned Store',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if (isUnassigned) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.link_off_rounded, size: 14, color: Colors.orange.shade800),
                              const SizedBox(width: 4),
                              Text(
                                'No barcode in database',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade800),
                              ),
                            ],
                          ),
                          if (store != null && store.storeAddress.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              store.storeAddress,
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ] else ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.qr_code_2_rounded, size: 13, color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(
                                scanning.barcode,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.primary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            scanning.scannedDate == null ? 'Not scanned yet' : DateFormat('MMM d, yyyy hh:mm a').format(scanning.scannedDate!.toDate()),
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isUnassigned)
                    FilledButton.tonal(
                      onPressed: () => _assignBarcodeToStore(scanning.storeName),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Assign', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                  else
                    Icon(Icons.chevron_right, size: 20, color: colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryBanner({required int count, required String status, required Color statusColor}) {
    final colorScheme = Theme.of(context).colorScheme;
    final notScannedCount = scanningList.where((s) => s.status == ScanningStatus.notScanned).length;
    final scannedCount = scanningList.where((s) => s.status == ScanningStatus.scanned).length;
    final totalActive = notScannedCount + scannedCount;
    final overallProgress = totalActive > 0 ? scannedCount / totalActive : 0.0;
    final isUnassigned = status == ScanningStatus.unassigned;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                status == ScanningStatus.scanned
                    ? Icons.task_alt_rounded
                    : status == ScanningStatus.pullout
                    ? Icons.outbox_outlined
                    : status == ScanningStatus.unassigned
                    ? Icons.link_off_rounded
                    : Icons.pending_actions_rounded,
                color: statusColor,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isUnassigned ? 'Unassigned stores' : '$status records',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                    ),
                    Text(
                      isUnassigned
                          ? '$count ${count == 1 ? 'store without barcode' : 'stores without barcode'}'
                          : '$count ${count == 1 ? 'record' : 'records'}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              if (!isUnassigned && status != ScanningStatus.pullout && totalActive > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    '${(overallProgress * 100).toInt()}% Done',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                  ),
                ),
            ],
          ),
          if (!isUnassigned && status != ScanningStatus.pullout && totalActive > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: overallProgress,
                minHeight: 5,
                backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final notScannedCount = scanningList.where((s) => s.status == ScanningStatus.notScanned).length;
    final scannedCount = scanningList.where((s) => s.status == ScanningStatus.scanned).length;
    final pulloutCount = scanningList.where((s) => s.status == ScanningStatus.pullout).length;
    final unassignedCount = scanningList.where((s) => s.status == ScanningStatus.unassigned).length;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: CustomAppbar(
        title: 'Scanning List',
        subtitle: 'Track barcode scanning progress',
        actions: [_buildSortMenu()],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          children: [
            _buildSearchField(),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _enterBarcodeManually,
                icon: const Icon(Icons.keyboard_outlined, size: 18),
                label: const Text('Enter barcode manually', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: RefreshIndicator(
                onRefresh: prefetchData,
                child: _scanningListView(const [
                  ScanningStatus.notScanned,
                  ScanningStatus.scanned,
                  ScanningStatus.pullout,
                  ScanningStatus.unassigned,
                ][_currentIndex]),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanBarcode,
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Scan barcode'),
      ),
      bottomNavigationBar: NavigationBar(
        elevation: 0,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.14),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          setState(() => _currentIndex = index);
        },
        destinations: [
          NavigationDestination(
            icon: Badge.count(
              count: notScannedCount,
              isLabelVisible: notScannedCount > 0,
              backgroundColor: colorScheme.tertiary,
              child: const Icon(Icons.radio_button_unchecked),
            ),
            selectedIcon: Badge.count(
              count: notScannedCount,
              isLabelVisible: notScannedCount > 0,
              backgroundColor: colorScheme.tertiary,
              child: const Icon(Icons.pending_outlined),
            ),
            label: 'Not Scanned',
          ),
          NavigationDestination(
            icon: Badge.count(
              count: scannedCount,
              isLabelVisible: scannedCount > 0,
              backgroundColor: Colors.green,
              child: const Icon(Icons.check_circle_outline),
            ),
            selectedIcon: Badge.count(
              count: scannedCount,
              isLabelVisible: scannedCount > 0,
              backgroundColor: Colors.green,
              child: const Icon(Icons.check_circle),
            ),
            label: 'Scanned',
          ),
          NavigationDestination(
            icon: Badge.count(
              count: pulloutCount,
              isLabelVisible: pulloutCount > 0,
              backgroundColor: colorScheme.error,
              child: const Icon(Icons.outbox_outlined),
            ),
            selectedIcon: Badge.count(
              count: pulloutCount,
              isLabelVisible: pulloutCount > 0,
              backgroundColor: colorScheme.error,
              child: const Icon(Icons.outbox),
            ),
            label: 'Pullout',
          ),
          NavigationDestination(
            icon: Badge.count(
              count: unassignedCount,
              isLabelVisible: unassignedCount > 0,
              backgroundColor: Colors.orange.shade800,
              child: const Icon(Icons.link_off_outlined),
            ),
            selectedIcon: Badge.count(
              count: unassignedCount,
              isLabelVisible: unassignedCount > 0,
              backgroundColor: Colors.orange.shade800,
              child: const Icon(Icons.link_off_rounded),
            ),
            label: 'Unassigned',
          ),
        ],
      ),
    );
  }
}

class _ManualBarcodeDialog extends StatefulWidget {
  const _ManualBarcodeDialog();

  @override
  State<_ManualBarcodeDialog> createState() => _ManualBarcodeDialogState();
}

class _ManualBarcodeDialogState extends State<_ManualBarcodeDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter barcode'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Barcode', hintText: 'Type the barcode number', prefixIcon: Icon(Icons.keyboard_outlined)),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}
