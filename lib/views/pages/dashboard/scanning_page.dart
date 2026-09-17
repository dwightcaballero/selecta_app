import 'package:barcode_widget/barcode_widget.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:intl/intl.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/scanning.dart';
import 'package:flutter_app/services/scanning_services.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/hapistore_dropdown.dart';

class ScanningPage extends StatefulWidget {
  final String initialBarcode;
  const ScanningPage({super.key, required this.initialBarcode});

  @override
  State<ScanningPage> createState() => _ScanningPageState();
}

class _ScanningPageState extends State<ScanningPage> {
  final _formKey = GlobalKey<FormState>();
  final ScanningServices _scanningServices = ScanningServices();
  final TextEditingController _dropdownHapiStore = TextEditingController();
  String _selectedStatus = ScanningStatus.notScanned;
  Scanning _scanning = Scanning.empty();
  bool _hasCheckedDatabase = false;

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  void prefetchData() async {
    _scanning = await _scanningServices.getScanningByBarcode(widget.initialBarcode) ?? Scanning.empty();
    _selectedStatus = _scanning.status.isEmpty ? ScanningStatus.notScanned : _scanning.status;
    _dropdownHapiStore.text = _scanning.storeName;
    _hasCheckedDatabase = true;

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _dropdownHapiStore.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) {
      ShowMessage.error(context, 'Please fill up the required fields');
      return;
    }

    String scannedBy = '';
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
        break;
      default:
        scannedDate = _scanning.scannedDate;
        scannedBy = _scanning.scannedBy;
    }

    final newRecord = Scanning(
      id: _scanning.id,
      barcode: widget.initialBarcode,
      storeName: _dropdownHapiStore.text,
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
      ShowMessage.success(context, 'Successfully saved the scanning record!\n[${newRecord.storeName}]');
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ShowMessage.error(context, 'Unable to save the scanning record. Please try again.');
    }
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
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
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
      child: Column(
        children: [
          if (widget.initialBarcode.isNotEmpty)
            BarcodeWidget(barcode: Barcode.code128(), data: widget.initialBarcode, height: 80, drawText: false, color: colorScheme.onSurface)
          else
            Text('No barcode scanned yet.', style: TextStyle(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(widget.initialBarcode.isEmpty ? '—' : widget.initialBarcode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          if (_hasCheckedDatabase && _scanning.id.isEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: colorScheme.tertiaryContainer, borderRadius: BorderRadius.circular(10)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: colorScheme.onTertiaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This is a new barcode and is not yet saved in the database.',
                      style: TextStyle(fontSize: 13, color: colorScheme.onTertiaryContainer),
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
    return _buildSectionCard(
      title: 'Hapi Store',
      icon: Icons.storefront_outlined,
      child: hapistoreDropdown(_dropdownHapiStore, onChanged: () => setState(() {})),
    );
  }

  Widget _buildStatusCard() {
    final colorScheme = Theme.of(context).colorScheme;
    bool isScanned = _selectedStatus == ScanningStatus.scanned;

    return _buildSectionCard(
      title: 'Scanning Status',
      icon: Icons.fact_check_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tag whether this record has been scanned:', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
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
                  icon: Icon(Icons.radio_button_unchecked, size: 18, color: isScanned ? colorScheme.onSurfaceVariant : colorScheme.tertiary),
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
                  icon: Icon(Icons.check_circle_outline, size: 18, color: isScanned ? colorScheme.primary : colorScheme.onSurfaceVariant),
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
                    color: _selectedStatus == ScanningStatus.pullout ? colorScheme.error : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              selected: {_selectedStatus},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() => _selectedStatus = newSelection.first);
              },
            ),
          ),
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
                    _scanning.scannedBy.isNotEmpty == true ? _scanning.scannedBy : 'Not scanned yet',
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
    return Scaffold(
      appBar: CustomAppbar(title: _scanning.id.isEmpty ? 'New Scanning Record' : 'Edit Scanning Record'),
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
            FilledButton(onPressed: _onSave, style: KButtonStyle.save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
