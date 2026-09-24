import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/models/scanning.dart';
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
    var scannings = await ScanningServices.getAllScannings();
    if (!mounted) return;
    setState(() {
      scanningList = scannings;
      _isLoading = false;
    });
  }

  List<Scanning> _filteredAndSorted(String status) {
    List<Scanning> filtered = scanningList.where((scanning) => scanning.status == status).toList();
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((scanning) {
        return scanning.storeName.toLowerCase().contains(_searchQuery) || scanning.barcode.toLowerCase().contains(_searchQuery);
      }).toList();
    }
    filtered.sort(_compareScannings);
    return filtered;
  }

  int _compareScannings(Scanning first, Scanning second) {
    final comparison = switch (_sort) {
      _ScanningSort.storeNameAscending ||
      _ScanningSort.storeNameDescending => first.storeName.toLowerCase().compareTo(second.storeName.toLowerCase()),
      _ScanningSort.barcodeAscending || _ScanningSort.barcodeDescending => first.barcode.compareTo(second.barcode),
      _ScanningSort.scannedDateAscending || _ScanningSort.scannedDateDescending =>
        first.scannedDate == null
            ? (second.scannedDate == null ? 0 : -1)
            : (second.scannedDate == null ? 1 : first.scannedDate!.compareTo(second.scannedDate!)),
    };

    return switch (_sort) {
      _ScanningSort.storeNameDescending || _ScanningSort.barcodeDescending || _ScanningSort.scannedDateDescending => -comparison,
      _ => comparison,
    };
  }

  void _openScanning(Scanning scanning) async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => ScanningPage(initialBarcode: scanning.barcode)));
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
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 140),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.qr_code_scanner_outlined, size: 48, color: colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(_searchQuery.isNotEmpty ? 'No matching records' : 'No $status records', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Scanning records will appear here when available.', style: TextStyle(color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      );
    }

    final statusColor = switch (status) {
      ScanningStatus.scanned => colorScheme.primary,
      ScanningStatus.pullout => colorScheme.error,
      _ => colorScheme.tertiary,
    };
    final statusIcon = switch (status) {
      ScanningStatus.scanned => Icons.check_circle_outline,
      ScanningStatus.pullout => Icons.outbox_outlined,
      _ => Icons.qr_code_2_outlined,
    };

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
      itemCount: scannings.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildSummaryBanner(count: scannings.length, status: status, statusColor: statusColor);
        }

        final scanning = scannings[index - 1];

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
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Icon(statusIcon, color: statusColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(scanning.storeName, style: KTextStyle.titleTextStyle, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        Text(scanning.barcode, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 3),
                        Text(
                          scanning.scannedDate == null ? 'Not scanned yet' : DateFormat('MMM d, yyyy hh:mm a').format(scanning.scannedDate!.toDate()),
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            status == ScanningStatus.scanned
                ? Icons.task_alt_rounded
                : status == ScanningStatus.pullout
                ? Icons.outbox_outlined
                : Icons.pending_actions_rounded,
            color: statusColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$status records',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 3),
                Text(
                  '$count ${count == 1 ? 'record' : 'records'}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: CustomAppbar(title: 'Scanning List', subtitle: 'Track barcode scanning progress', actions: [_buildSortMenu()]),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Column(
          children: [
            _buildSearchField(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _enterBarcodeManually,
                icon: const Icon(Icons.keyboard_outlined),
                label: const Text('Enter barcode manually'),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: RefreshIndicator(
                onRefresh: prefetchData,
                child: _scanningListView(const [ScanningStatus.notScanned, ScanningStatus.scanned, ScanningStatus.pullout][_currentIndex]),
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
        destinations: const [
          NavigationDestination(icon: Icon(Icons.radio_button_unchecked), selectedIcon: Icon(Icons.pending_outlined), label: 'Not Scanned'),
          NavigationDestination(icon: Icon(Icons.check_circle_outline), selectedIcon: Icon(Icons.check_circle), label: 'Scanned'),
          NavigationDestination(icon: Icon(Icons.outbox_outlined), selectedIcon: Icon(Icons.outbox), label: 'Pullout'),
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
