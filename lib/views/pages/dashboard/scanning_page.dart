import 'package:barcode_widget/barcode_widget.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/scanning.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/scanning_services.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/barcodescanner_widget.dart';
import 'package:flutter_app/views/widgets/hapistore_dropdown.dart';
import 'package:intl/intl.dart';

class ScanningPage extends StatefulWidget {
  const ScanningPage({super.key, required this.initialBarcode, this.initialStoreName});

  final String initialBarcode;
  final String? initialStoreName;

  @override
  State<ScanningPage> createState() => _ScanningPageState();
}

class _ScanningPageState extends State<ScanningPage> {
  final TextEditingController _dropdownHapiStore = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _hasCheckedDatabase = false;
  Scanning _scanning = Scanning.empty();
  final ScanningServices _scanningServices = ScanningServices();
  String _selectedStatus = ScanningStatus.notScanned;

  bool get _hasUnsavedChanges {
    if (!_hasCheckedDatabase) return false;
    final initialStore = _scanning.storeName.isNotEmpty ? _scanning.storeName : (widget.initialStoreName ?? '');
    final initialStatus = _scanning.status.isEmpty ? ScanningStatus.notScanned : _scanning.status;
    return _dropdownHapiStore.text.trim() != initialStore || _selectedStatus != initialStatus;
  }

  @override
  void dispose() {
    _dropdownHapiStore.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  void prefetchData() async {
    _scanning = await _scanningServices.getScanningByBarcode(widget.initialBarcode) ?? Scanning.empty();
    _selectedStatus = _scanning.status.isEmpty ? ScanningStatus.notScanned : _scanning.status;
    _dropdownHapiStore.text = _scanning.storeName.isNotEmpty ? _scanning.storeName : (widget.initialStoreName ?? '');
    _hasCheckedDatabase = true;

    if (mounted) setState(() {});
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Copied $label to clipboard'),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _rescanBarcode() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerWidget()),
    );
    if (scanned != null && scanned.isNotEmpty && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ScanningPage(
            initialBarcode: scanned,
            initialStoreName: _dropdownHapiStore.text,
          ),
        ),
      );
    }
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) {
      ShowMessage.error(context, 'Please fill up the required fields');
      return;
    }

    String scannedBy = '';
    String storeName = _dropdownHapiStore.text;
    Timestamp? scannedDate;

    switch (_selectedStatus) {
      case ScanningStatus.notScanned:
        scannedDate = null;
        scannedBy = '';
        break;
      case ScanningStatus.scanned:
        scannedDate = Timestamp.now();
        scannedBy = authService.value.currentUser?.displayName ?? '';
        break;
      case ScanningStatus.pullout:
        scannedDate = Timestamp.now();
        scannedBy = '';
        storeName = '';
        break;
      default:
        scannedDate = _scanning.scannedDate;
        scannedBy = _scanning.scannedBy;
    }

    final newRecord = Scanning(
      id: _scanning.id,
      barcode: widget.initialBarcode,
      storeName: storeName,
      scannedDate: scannedDate,
      scannedBy: scannedBy,
      status: _selectedStatus,
    );

    try {
      final bool isNewRecord = _scanning.id.isEmpty;
      await _scanningServices.saveScanning(newRecord);
      if (isNewRecord) {
        await Helperfunctions.logCreate(newRecord.storeName, newRecord.toJson());
      } else {
        await Helperfunctions.logUpdate(newRecord.storeName, _scanning.toJson(), newRecord.toJson());
      }
      if (!mounted) return;
      ShowMessage.success(context, 'Successfully saved the scanning record!\n[${newRecord.storeName.isNotEmpty ? newRecord.storeName : "Pullout"}]');
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ShowMessage.error(context, 'Unable to save the scanning record. Please try again.');
    }
  }

  Future<void> _onDelete() async {
    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Delete scanning record',
      message: 'Delete the record for barcode ${_scanning.barcode}? This cannot be undone.',
      confirmText: 'Delete',
      isDestructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed || !mounted) return;

    try {
      await _scanningServices.deleteScanning(_scanning.id);
      await Helperfunctions.logDelete(_scanning.storeName, _scanning.toJson());
      if (!mounted) return;
      ShowMessage.success(context, 'Scanning record deleted.');
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ShowMessage.error(context, 'Unable to delete the scanning record. Please try again.');
    }
  }

  Widget _buildSectionCard({required String title, required IconData icon, Widget? trailing, required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 18, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
                if (trailing != null) trailing,
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildBarcodeCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildSectionCard(
      title: 'Barcode',
      icon: Icons.qr_code_2_outlined,
      trailing: TextButton.icon(
        onPressed: _rescanBarcode,
        icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
        label: const Text('Re-scan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ),
      child: Column(
        children: [
          if (widget.initialBarcode.isNotEmpty)
            BarcodeWidget(barcode: Barcode.code128(), data: widget.initialBarcode, height: 75, drawText: false, color: colorScheme.onSurface)
          else
            Text('No barcode scanned yet.', style: TextStyle(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: widget.initialBarcode.isNotEmpty ? () => _copyToClipboard(widget.initialBarcode, 'barcode') : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.initialBarcode.isEmpty ? '—' : widget.initialBarcode,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
                  ),
                  if (widget.initialBarcode.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.copy_rounded, size: 14, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                  ],
                ],
              ),
            ),
          ),
          if (_hasCheckedDatabase && _scanning.id.isEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: colorScheme.tertiaryContainer.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: colorScheme.onTertiaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This is a new barcode and is not yet registered in the database.',
                      style: TextStyle(fontSize: 12, color: colorScheme.onTertiaryContainer, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStoreCard() {
    final isPullout = _selectedStatus == ScanningStatus.pullout;

    return _buildSectionCard(
      title: 'Target Store',
      icon: Icons.storefront_outlined,
      child: HapistorePickerField(
        controller: _dropdownHapiStore,
        enabled: !isPullout,
        label: isPullout ? 'Store unassigned (Pullout)' : 'Target Store',
        validator: (value) {
          if (!isPullout && (value == null || value.trim().isEmpty)) {
            return 'Target Store is required';
          }
          return null;
        },
        onChanged: () => setState(() {}),
      ),
    );
  }

  Widget _buildStatusCard() {
    final colorScheme = Theme.of(context).colorScheme;
    bool isScanned = _selectedStatus == ScanningStatus.scanned;
    bool isPullout = _selectedStatus == ScanningStatus.pullout;

    return _buildSectionCard(
      title: 'Scanning Status',
      icon: Icons.fact_check_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select current status for this barcode:', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              segments: [
                ButtonSegment<String>(
                  value: ScanningStatus.notScanned,
                  label: const Text(
                    'Pending',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  icon: Icon(Icons.radio_button_unchecked, size: 18, color: !isScanned && !isPullout ? colorScheme.tertiary : colorScheme.onSurfaceVariant),
                ),
                ButtonSegment<String>(
                  value: ScanningStatus.scanned,
                  label: const Text(
                    ScanningStatus.scanned,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  icon: Icon(Icons.check_circle_outline, size: 18, color: isScanned ? Colors.green : colorScheme.onSurfaceVariant),
                ),
                ButtonSegment<String>(
                  value: ScanningStatus.pullout,
                  label: const Text(
                    ScanningStatus.pullout,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  icon: Icon(
                    Icons.outbox_outlined,
                    size: 18,
                    color: isPullout ? colorScheme.error : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              selected: {_selectedStatus},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() => _selectedStatus = newSelection.first);
              },
            ),
          ),
          if (isPullout) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pullout marks this barcode as retrieved from the store and unassigned.',
                      style: TextStyle(fontSize: 12, color: colorScheme.onErrorContainer, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text('Last update', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                const Spacer(),
                Text(
                  _scanning.scannedDate == null ? 'Not scanned yet' : DateFormat('MMM d, yyyy  h:mm a').format(_scanning.scannedDate!.toDate()),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Icon(Icons.person_outline_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text('Last update by', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                const Spacer(),
                Flexible(
                  child: Text(
                    _scanning.scannedBy.isNotEmpty ? _scanning.scannedBy : 'Not scanned yet',
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
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
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await ShowMessage.confirm(
          context,
          title: 'Discard Changes',
          message: 'You have unsaved changes. Are you sure you want to discard them?',
          confirmText: 'Discard',
          isDestructive: true,
        );
        if (leave && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: CustomAppbar(
          title: _scanning.id.isEmpty ? 'New Scanning Record' : 'Edit Scanning Record',
          actions: [
            if (_scanning.id.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                tooltip: 'Delete scanning record',
                onPressed: _onDelete,
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _buildBarcodeCard(),
              const SizedBox(height: 12),
              _buildStoreCard(),
              const SizedBox(height: 12),
              _buildStatusCard(),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _onSave,
                icon: const Icon(Icons.check_circle_outline_rounded, size: 20, color: Colors.white),
                label: const Text('Save Record', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
