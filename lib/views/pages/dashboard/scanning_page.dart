import 'dart:io';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/controllers/scanning_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/scanning.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/barcodescanner_widget.dart';
import 'package:selecta_ops/views/widgets/hapistore_dropdown.dart';
import 'package:selecta_ops/views/widgets/imageviewer_page.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

/// Presentation view for creating, editing, and deleting freezer barcode records.
///
/// Barcode persistence, status resolution, dealer authorization checks,
/// freezer photo validation, and audit transaction logging are managed by [ScanningController].
class ScanningPage extends StatefulWidget {
  const ScanningPage({
    super.key,
    required this.initialBarcode,
    this.initialStoreName,
    this.isEditing = false,
  });

  final String initialBarcode;
  final String? initialStoreName;
  final bool isEditing;

  @override
  State<ScanningPage> createState() => _ScanningPageState();
}

class _ScanningPageState extends State<ScanningPage> {
  final ScanningController _controller = ScanningController();
  final TextEditingController _dropdownHapiStore = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  bool _hasCheckedDatabase = false;
  bool _isDealer = false;
  bool _isSaving = false;
  bool _isDownloadingImage = false;
  File? _imageFile;
  Scanning _scanning = Scanning.empty();
  String _selectedStatus = ScanningStatus.notScanned;
  String _currentBarcode = '';
  List<Scanning> _storeScannings = [];

  String get _effectiveBarcode => _currentBarcode.isNotEmpty ? _currentBarcode : widget.initialBarcode;

  bool get _hasUnsavedChanges {
    if (!_hasCheckedDatabase) return false;
    if (_imageFile != null) return true;
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
    _currentBarcode = widget.initialBarcode.trim();
    prefetchData();
  }

  void prefetchData([String? targetBarcode]) async {
    final barcodeToLoad = (targetBarcode ?? _currentBarcode).trim();
    final isDealer = await _controller.checkIsDealer();
    final found = await _controller.getScanningByBarcode(barcodeToLoad);

    final Scanning scanning;
    final String selectedStatus;

    if (found != null) {
      scanning = found;
      // Preserve actual status from database so users see the accurate current status
      selectedStatus = scanning.status.isNotEmpty ? scanning.status : ScanningStatus.notScanned;
    } else {
      scanning = Scanning.empty();
      selectedStatus = ScanningStatus.notScanned;
    }

    final storeName = scanning.storeName.isNotEmpty ? scanning.storeName : (widget.initialStoreName ?? '');
    _dropdownHapiStore.text = storeName;

    List<Scanning> storeScannings = [];
    if (storeName.isNotEmpty) {
      storeScannings = await _controller.getScanningsByStoreName(storeName);
    }

    if (mounted) {
      setState(() {
        _currentBarcode = barcodeToLoad;
        _isDealer = isDealer;
        _scanning = scanning;
        _storeScannings = storeScannings;
        _selectedStatus = selectedStatus;
        _imageFile = null;
        _hasCheckedDatabase = true;
      });
    }
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
    final scanned = await Navigator.push<String>(context, MaterialPageRoute(builder: (context) => const BarcodeScannerWidget()));
    if (scanned != null && scanned.trim().isNotEmpty && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ScanningPage(
            initialBarcode: scanned.trim(),
            initialStoreName: _dropdownHapiStore.text,
            isEditing: false,
          ),
        ),
      );
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (pickedFile != null && mounted) {
        setState(() {
          _imageFile = File(pickedFile.path);
          if (_selectedStatus == ScanningStatus.notScanned || _selectedStatus.isEmpty) {
            _selectedStatus = _isDealer ? ScanningStatus.scanned : ScanningStatus.pending;
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      ShowMessage.error(context, 'Failed to capture or select photo: $e');
    }
  }

  void _viewFullscreenPhoto() {
    if (_imageFile == null && _scanning.imageUrl.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImageViewerPage(
          image: _imageFile,
          networkImagePath: _scanning.imageUrl,
        ),
      ),
    );
  }

  Future<void> _downloadFreezerPhoto() async {
    if (_isDownloadingImage) return;

    final hasPhoto = _imageFile != null || _scanning.imageUrl.isNotEmpty;
    if (!hasPhoto) {
      ShowMessage.error(context, 'No freezer photo available to download.');
      return;
    }

    setState(() => _isDownloadingImage = true);

    try {
      final Uint8List bytes;
      if (_imageFile != null) {
        bytes = await _imageFile!.readAsBytes();
      } else {
        final response = await http.get(Uri.parse(_scanning.imageUrl));
        if (response.statusCode != 200) {
          throw Exception('Unable to download photo from server.');
        }
        bytes = response.bodyBytes;
      }

      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final accessGranted = await Gal.requestAccess();
        if (!accessGranted) {
          throw Exception('Gallery permission was denied.');
        }
      }

      final storeTag = _dropdownHapiStore.text.replaceAll(RegExp(r'\s+'), '_');
      await Gal.putImageBytes(
        bytes,
        name: 'freezer_${storeTag}_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (!mounted) return;
      ShowMessage.success(context, 'Freezer photo saved to your gallery!');
    } catch (error) {
      if (!mounted) return;
      ShowMessage.error(context, 'Failed to download photo: $error');
    } finally {
      if (mounted) setState(() => _isDownloadingImage = false);
    }
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) {
      ShowMessage.error(context, 'Please fill up the required fields');
      return;
    }

    // Role verification: only dealers can mark status as scanned
    if (_selectedStatus == ScanningStatus.scanned && !_isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to mark a barcode as Scanned.');
      return;
    }

    // Photo requirement: when scanning to Pending or Scanned, freezer photo is required
    final hasExistingPhoto = _scanning.imageUrl.trim().isNotEmpty;
    final hasNewPhoto = _imageFile != null;
    if ((_selectedStatus == ScanningStatus.pending || _selectedStatus == ScanningStatus.scanned) && !hasExistingPhoto && !hasNewPhoto) {
      ShowMessage.error(context, 'A picture of the freezer for this month is required upon scanning.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final trimmedBarcode = _effectiveBarcode.trim();
      final duplicateCheck = await _controller.getScanningByBarcode(trimmedBarcode);

      // If a record exists in DB under a different document ID
      if (duplicateCheck != null && _scanning.id.isNotEmpty && duplicateCheck.id != _scanning.id) {
        if (!mounted) return;
        ShowMessage.error(context, 'This barcode is already assigned to another record in the database.');
        return;
      }

      // If existing was empty but it actually exists in DB, attach the ID so we update instead of duplicate
      final existingToSave = (_scanning.id.isEmpty && duplicateCheck != null)
          ? duplicateCheck
          : _scanning;

      // Upload new image if user took/selected one
      String finalImageUrl = existingToSave.imageUrl;
      if (_imageFile != null) {
        if (!mounted) return;
        final uploaded = await Helperfunctions.saveImage(context, _imageFile!);
        if (uploaded.isEmpty) {
          if (!mounted) return;
          ShowMessage.error(context, 'Unable to upload freezer photo. Please check your internet connection.');
          return;
        }
        finalImageUrl = uploaded;
      }

      final newRecord = await _controller.saveScanningRecord(
        existing: existingToSave,
        barcode: trimmedBarcode,
        storeName: _dropdownHapiStore.text,
        status: _selectedStatus,
        imageUrl: finalImageUrl,
        isDealer: _isDealer,
      );

      if (!mounted) return;
      final statusNotice = newRecord.status == ScanningStatus.pending ? ' (Pending Dealer Review)' : '';
      ShowMessage.success(
        context,
        'Successfully saved scanning record$statusNotice!\n[${newRecord.storeName.isNotEmpty ? newRecord.storeName : "Pullout"}]',
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      final errorMessage = error.toString().replaceFirst('Exception: ', '');
      ShowMessage.error(context, errorMessage.isNotEmpty ? errorMessage : 'Unable to save the scanning record. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _onDelete() async {
    if (!_isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to delete scanning records.');
      return;
    }

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
      await _controller.deleteScanningRecord(_scanning);
      if (!mounted) return;
      ShowMessage.success(context, 'Scanning record deleted.');
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ShowMessage.error(context, 'Unable to delete the scanning record. Please try again.');
    }
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    Widget? trailing,
    required Widget child,
  }) {
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
                Expanded(
                  child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
                ?trailing,
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildWorkflowBanner() {
    final colorScheme = Theme.of(context).colorScheme;

    // Show banner when a dealer opens a pending record and it was marked as scanned
    if (_hasCheckedDatabase && _scanning.status == ScanningStatus.pending && _isDealer) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.verified_outlined, color: Colors.green, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pending Scan Ready to Verify',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'This barcode was scanned and pending dealer approval. Review the freezer photo below and tap Save to mark as Scanned.',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Show banner when a salesman opens a pending record
    if (_hasCheckedDatabase && _scanning.status == ScanningStatus.pending && !_isDealer) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.hourglass_top_rounded, color: Colors.amber.shade800, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pending Dealer Verification',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'This scan is submitted as Pending. Dealers are the only ones authorized to scan/mark this record as Scanned.',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildStoreFreezersBanner() {
    if (_storeScannings.length <= 1) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.kitchen_outlined, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'Store Freezers (${_storeScannings.length})',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _storeScannings.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final item = entry.value;
              final isCurrent = item.barcode.trim().toLowerCase() == _effectiveBarcode.trim().toLowerCase();
              final isDone = item.status == ScanningStatus.scanned || item.status == ScanningStatus.pending;

              return InkWell(
                onTap: isCurrent
                    ? null
                    : () {
                        prefetchData(item.barcode);
                      },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : (isDone ? Colors.green.withValues(alpha: 0.08) : colorScheme.surface),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCurrent
                          ? colorScheme.primary
                          : (isDone ? Colors.green.shade400 : colorScheme.outlineVariant),
                      width: isCurrent ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isCurrent
                            ? Icons.check_circle
                            : (item.status == ScanningStatus.scanned
                                ? Icons.check_circle_outline
                                : (item.status == ScanningStatus.pending
                                    ? Icons.hourglass_top_rounded
                                    : Icons.radio_button_unchecked)),
                        size: 13,
                        color: isCurrent
                            ? colorScheme.primary
                            : (item.status == ScanningStatus.scanned
                                ? Colors.green.shade700
                                : (item.status == ScanningStatus.pending
                                    ? Colors.amber.shade900
                                    : colorScheme.onSurfaceVariant)),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '#$idx ${item.barcode}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                          color: isCurrent ? colorScheme.primary : colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
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
          if (_effectiveBarcode.isNotEmpty)
            BarcodeWidget(barcode: Barcode.code128(), data: _effectiveBarcode, height: 75, drawText: false, color: colorScheme.onSurface)
          else
            Text('No barcode scanned yet.', style: TextStyle(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: _effectiveBarcode.isNotEmpty ? () => _copyToClipboard(_effectiveBarcode, 'barcode') : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _effectiveBarcode.isEmpty ? '—' : _effectiveBarcode,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
                  ),
                  if (_effectiveBarcode.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.copy_rounded, size: 14, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                  ],
                ],
              ),
            ),
          ),
          if (_hasCheckedDatabase && _scanning.id.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 20, color: colorScheme.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Existing Barcode Record',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSecondaryContainer),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _scanning.storeName.isNotEmpty
                              ? 'This barcode is registered to "${_scanning.storeName}". Current status: ${_scanning.status.isNotEmpty ? _scanning.status : "Not Scanned"}.'
                              : 'This barcode exists in the database.',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSecondaryContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_hasCheckedDatabase && _scanning.id.isEmpty) ...[
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

  Widget _buildFreezerPhotoCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final currentMonthLabel = DateFormat('MMMM yyyy').format(DateTime.now());
    final hasLocalImage = _imageFile != null;
    final hasRemoteImage = _scanning.imageUrl.isNotEmpty;
    final hasAnyImage = hasLocalImage || hasRemoteImage;
    final isPhotoRequired = _selectedStatus == ScanningStatus.pending || _selectedStatus == ScanningStatus.scanned;

    return _buildSectionCard(
      title: 'Freezer Photo',
      icon: Icons.kitchen_outlined,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: hasAnyImage
              ? Colors.green.withValues(alpha: 0.12)
              : (isPhotoRequired ? Colors.amber.withValues(alpha: 0.15) : colorScheme.surfaceContainerHighest),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          hasLocalImage
              ? 'New Photo'
              : (hasRemoteImage ? 'Photo Attached' : (isPhotoRequired ? 'Required for $currentMonthLabel' : 'Optional')),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: hasAnyImage
                ? Colors.green.shade800
                : (isPhotoRequired ? Colors.amber.shade900 : colorScheme.onSurfaceVariant),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Monthly freezer proof for $currentMonthLabel. Required upon scanning for dealer review and record.',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),

          // Photo Display / Placeholder
          if (hasAnyImage)
            GestureDetector(
              onTap: _viewFullscreenPhoto,
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.black.withValues(alpha: 0.05),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: hasLocalImage
                        ? Image.file(_imageFile!, fit: BoxFit.cover)
                        : Image.network(
                            _scanning.imageUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const Center(child: CircularProgressIndicator());
                            },
                            errorBuilder: (_, _, _) => Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.broken_image_outlined, size: 36, color: colorScheme.error),
                                  const SizedBox(height: 4),
                                  const Text('Unable to load photo', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fullscreen_rounded, size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text('Tap to expand & zoom', style: TextStyle(color: Colors.white, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: isPhotoRequired ? Colors.amber.withValues(alpha: 0.05) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isPhotoRequired ? Colors.amber.shade700.withValues(alpha: 0.4) : colorScheme.outlineVariant,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.add_a_photo_outlined,
                    size: 38,
                    color: isPhotoRequired ? Colors.amber.shade800 : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No freezer photo uploaded yet',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isPhotoRequired ? Colors.amber.shade900 : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A photo of the freezer is required for $currentMonthLabel upon scanning.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // Photo Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: Text(hasAnyImage ? 'Retake' : 'Camera'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Gallery'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),

          if (hasAnyImage) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _viewFullscreenPhoto,
                    icon: const Icon(Icons.fullscreen_rounded, size: 18),
                    label: const Text('View Fullscreen'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _isDownloadingImage ? null : _downloadFreezerPhoto,
                    icon: _isDownloadingImage
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(_isDownloadingImage ? 'Downloading...' : 'Download'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusOptionButton({
    required String value,
    required String label,
    required IconData icon,
    required Color activeColor,
    bool enabled = true,
  }) {
    final isSelected = _selectedStatus == value;
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: InkWell(
        onTap: enabled
            ? () => setState(() => _selectedStatus = value)
            : () {
                ShowMessage.error(context, 'Only dealers are authorized to mark a barcode as Scanned.');
              },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.12)
                : (enabled ? colorScheme.surface : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : (enabled ? colorScheme.outlineVariant : colorScheme.outlineVariant.withValues(alpha: 0.4)),
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? activeColor
                    : (enabled ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected
                        ? activeColor
                        : (enabled ? colorScheme.onSurface : colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final isPullout = _selectedStatus == ScanningStatus.pullout;

    return _buildSectionCard(
      title: 'Scanning Status',
      icon: Icons.fact_check_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Current Status: $_selectedStatus',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _isDealer ? Colors.blue.withValues(alpha: 0.12) : Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _isDealer ? 'Dealer Mode' : 'Salesman Mode',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _isDealer ? Colors.blue.shade800 : Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 2 Rows for Status selection to ensure readable labels
          Column(
            children: [
              Row(
                children: [
                  _buildStatusOptionButton(
                    value: ScanningStatus.pending,
                    label: 'Pending',
                    icon: Icons.hourglass_top_rounded,
                    activeColor: Colors.amber.shade800,
                  ),
                  const SizedBox(width: 8),
                  _buildStatusOptionButton(
                    value: ScanningStatus.scanned,
                    label: _isDealer ? 'Scanned' : 'Scanned (Dealer)',
                    icon: _isDealer ? Icons.check_circle_outline : Icons.lock_outline_rounded,
                    activeColor: Colors.green,
                    enabled: _isDealer,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildStatusOptionButton(
                    value: ScanningStatus.notScanned,
                    label: 'Not Scanned',
                    icon: Icons.radio_button_unchecked,
                    activeColor: colorScheme.tertiary,
                  ),
                  const SizedBox(width: 8),
                  _buildStatusOptionButton(
                    value: ScanningStatus.pullout,
                    label: 'Pullout',
                    icon: Icons.outbox_outlined,
                    activeColor: colorScheme.error,
                  ),
                ],
              ),
            ],
          ),
          if (!_isDealer) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Salesman scans are saved as Pending. Only dealers can mark a barcode as Scanned.',
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ],
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
            if (_scanning.id.isNotEmpty && _isDealer)
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
              _buildWorkflowBanner(),
              _buildStoreFreezersBanner(),
              _buildBarcodeCard(),
              const SizedBox(height: 12),
              _buildStoreCard(),
              const SizedBox(height: 12),
              _buildFreezerPhotoCard(),
              const SizedBox(height: 12),
              _buildStatusCard(),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: (_isSaving || !_hasCheckedDatabase) ? null : _onSave,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle_outline_rounded, size: 20, color: Colors.white),
                label: Text(
                  _isSaving
                      ? 'Saving Record...'
                      : (_selectedStatus == ScanningStatus.scanned
                          ? 'Confirm & Mark Scanned'
                          : (_selectedStatus == ScanningStatus.pending ? 'Save as Pending' : 'Save Record')),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: _selectedStatus == ScanningStatus.scanned
                      ? Colors.green.shade700
                      : (_selectedStatus == ScanningStatus.pending
                          ? Colors.amber.shade800
                          : Theme.of(context).colorScheme.primary),
                  disabledBackgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
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
