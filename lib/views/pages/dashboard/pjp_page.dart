import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:selecta_ops/controllers/pjp_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/services/auth_service.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/proof_of_visit.dart';
import 'package:selecta_ops/models/scanning.dart';
import 'package:selecta_ops/models/tasks.dart';
import 'package:selecta_ops/views/pages/dashboard/book_order_page.dart';
import 'package:selecta_ops/views/pages/dashboard/merchblitzlist_page.dart';
import 'package:selecta_ops/views/pages/dashboard/scanning_page.dart';
import 'package:selecta_ops/views/pages/sidebar/tasklist_page.dart';
import 'package:selecta_ops/views/widgets/imageviewer_page.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/barcodescanner_widget.dart';
import 'package:image_picker/image_picker.dart';

/// Presentation view for inspecting and completing individual PJP store visits.
///
/// Geolocation distance calculation, barcode check, book order verification,
/// proof of visit photograph, task queries, and Merch Blitz validation are managed by [PjpController].
class PjpPage extends StatefulWidget {
  const PjpPage({super.key, required this.hapiStoreID, required this.initialHapistore, required this.selectedDay});

  final String hapiStoreID;
  final Hapistore initialHapistore;
  final String selectedDay;

  @override
  State<PjpPage> createState() => _PjpPageState();
}

class _PjpPageState extends State<PjpPage> {
  final PjpController _controller = PjpController();

  late Hapistore _currentHapistore;

  // Step 1: Location state
  bool _isLoadingLocation = true;
  bool _isUpdatingLocation = false;
  bool _locationPassed = false;
  bool _isLocationOutOfRange = false;
  double? _locationDistanceMeters;
  double? _locationAccuracyMeters;
  String _locationStatus = '';
  String? _locationError;

  // Step 2: Scanning state
  bool _isLoadingScanning = true;
  bool _scanningPassed = false;
  String _scanningStatus = '';
  List<Scanning> _storeScannings = [];

  // Step 3: Book Order state
  bool _isLoadingBookOrder = true;
  bool _bookOrderPassed = false;
  bool _hasBookedOrder = false;
  String? _noOrderReason;
  String _bookOrderStatus = '';

  // Step 4: Proof of Visit state
  bool _isLoadingProofOfVisit = true;
  bool _isUploadingProofOfVisit = false;
  bool _proofOfVisitPassed = false;
  String _proofOfVisitStatus = '';
  ProofOfVisit? _proofOfVisit;

  // Step 5: Tasks state
  bool _isLoadingTasks = true;
  bool _tasksPassed = false;
  String _tasksStatus = '';
  List<Tasks> _pendingTasks = [];

  // Step 6: Merch Blitz state (Optional)
  bool _isLoadingMerchBlitz = true;
  bool _merchBlitzPassed = false;
  String _merchBlitzStatus = '';

  bool _isCompleting = false;

  bool get _isAlreadyCompletedToday {
    if (_currentHapistore.lastPjpVisit == null) return false;
    final visit = _currentHapistore.lastPjpVisit!.toDate();
    final now = DateTime.now();
    return visit.year == now.year && visit.month == now.month && visit.day == now.day;
  }

  bool get _isCompletedThisWeek {
    if (_currentHapistore.lastPjpVisit == null) return false;
    final visit = _currentHapistore.lastPjpVisit!.toDate();
    return Helperfunctions.isSameWeek(visit, DateTime.now());
  }

  /// All required criteria: 1 to 5.
  /// Step 6 (Merch Blitz) is optional.
  bool get _canCompleteVisit => _locationPassed && _scanningPassed && _bookOrderPassed && _proofOfVisitPassed && _tasksPassed;

  @override
  void initState() {
    super.initState();
    _currentHapistore = widget.initialHapistore;
    _runAllChecks();
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

  Future<void> _refreshStoreDoc() async {
    try {
      final updated = await _controller.refreshStore(widget.hapiStoreID);
      if (updated != null && mounted) {
        setState(() {
          _currentHapistore = updated;
        });
      }
    } catch (e, s) {
      ErrorLogService.logError(
        page: 'PjpPage',
        action: 'Refresh Store Document',
        error: e,
        stackTrace: s,
        extraData: {'hapiStoreID': widget.hapiStoreID},
      );
    }
  }

  Future<void> _runAllChecks() async {
    await Future.wait([_checkLocation(), _checkScanning(), _checkBookOrder(), _checkProofOfVisit(), _checkTasks(), _checkMerchBlitz()]);
  }

  Future<void> _checkLocation() async {
    if (!mounted) return;
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    final result = await _controller.checkLocation(_currentHapistore);
    if (!mounted) return;

    setState(() {
      _isLoadingLocation = false;
      _locationPassed = result.passed;
      _isLocationOutOfRange = result.isOutOfRange;
      _locationDistanceMeters = result.distanceMeters;
      _locationAccuracyMeters = result.accuracyMeters;
      _locationStatus = result.status;
      _locationError = result.error;
    });
  }

  Future<void> _checkScanning() async {
    if (!mounted) return;
    setState(() => _isLoadingScanning = true);

    final result = await _controller.checkScanning(_currentHapistore.storeName);
    if (!mounted) return;

    final hasPendingOrScanned = result.storeScannings.any((s) => s.status == ScanningStatus.pending || s.status == ScanningStatus.scanned);

    setState(() {
      _isLoadingScanning = false;
      _scanningPassed = result.passed || hasPendingOrScanned;
      _scanningStatus = result.status;
      _storeScannings = result.storeScannings;
    });
  }

  Future<void> _checkBookOrder() async {
    if (!mounted) return;
    setState(() => _isLoadingBookOrder = true);

    final result = await _controller.checkBookOrder(_currentHapistore.storeName);
    if (!mounted) return;

    setState(() {
      _isLoadingBookOrder = false;
      _bookOrderPassed = result.passed;
      _bookOrderStatus = result.status;
      _hasBookedOrder = result.hasBookedOrder;
      _noOrderReason = result.noOrderReason;
    });
  }

  Future<void> _checkProofOfVisit() async {
    if (!mounted) return;
    setState(() => _isLoadingProofOfVisit = true);

    final result = await _controller.checkProofOfVisit(_currentHapistore.storeName);
    if (!mounted) return;

    setState(() {
      _isLoadingProofOfVisit = false;
      _proofOfVisitPassed = result.passed;
      _proofOfVisitStatus = result.status;
      _proofOfVisit = result.proofOfVisit;
    });
  }

  Future<void> _checkTasks() async {
    if (!mounted) return;
    setState(() => _isLoadingTasks = true);

    final result = await _controller.checkTasks(_currentHapistore.storeName);
    if (!mounted) return;

    setState(() {
      _isLoadingTasks = false;
      _tasksPassed = result.passed;
      _tasksStatus = result.status;
      _pendingTasks = result.pendingTasks;
    });
  }

  Future<void> _checkMerchBlitz() async {
    if (!mounted) return;
    setState(() => _isLoadingMerchBlitz = true);

    final result = await _controller.checkMerchBlitz(_currentHapistore);
    if (!mounted) return;

    setState(() {
      _isLoadingMerchBlitz = false;
      _merchBlitzPassed = result.passed;
      _merchBlitzStatus = result.status;
    });
  }

  String _formatDistance(double? meters) {
    if (meters == null) return '';
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.round()} m';
  }

  Future<void> _openDirections() async {
    final hasGps = _currentHapistore.latitude != null && _currentHapistore.longitude != null;
    final hasAddress = _currentHapistore.storeAddress.trim().isNotEmpty;

    if (!hasGps && !hasAddress) {
      ShowMessage.alert(
        context,
        title: 'Location Unavailable',
        message: 'This store has no registered GPS coordinates or street address to navigate to.',
        icon: Icons.location_off_outlined,
      );
      return;
    }

    try {
      if (hasGps) {
        final lat = _currentHapistore.latitude!;
        final lng = _currentHapistore.longitude!;
        final nameEncoded = Uri.encodeComponent(_currentHapistore.storeName);

        final googleNavUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
        final universalMapsUri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&destination_place_id=$nameEncoded&travelmode=driving',
        );
        final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng($nameEncoded)');

        if (await canLaunchUrl(googleNavUri)) {
          await launchUrl(googleNavUri, mode: LaunchMode.externalApplication);
        } else if (await canLaunchUrl(geoUri)) {
          await launchUrl(geoUri, mode: LaunchMode.externalApplication);
        } else if (await canLaunchUrl(universalMapsUri)) {
          await launchUrl(universalMapsUri, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) ShowMessage.error(context, 'Could not open map navigation application.');
        }
      } else {
        final query = Uri.encodeComponent('${_currentHapistore.storeName}, ${_currentHapistore.storeAddress}');
        final searchUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
        if (await canLaunchUrl(searchUri)) {
          await launchUrl(searchUri, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) ShowMessage.error(context, 'Could not open Google Maps.');
        }
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to launch navigation: $e');
      }
    }
  }

  Future<void> _makePhoneCall() async {
    final contact = _currentHapistore.storeContact.trim();
    if (contact.isEmpty) {
      ShowMessage.alert(
        context,
        title: 'No Contact Number',
        message: 'This store does not have a contact number registered.',
        icon: Icons.phone_disabled_outlined,
      );
      return;
    }

    final cleaned = contact.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleaned');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) ShowMessage.error(context, 'Could not place phone call to $contact.');
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to launch phone dialer: $e');
    }
  }

  Future<void> _sendSms() async {
    final contact = _currentHapistore.storeContact.trim();
    if (contact.isEmpty) {
      ShowMessage.alert(
        context,
        title: 'No Contact Number',
        message: 'This store does not have a contact number registered.',
        icon: Icons.sms_failed_outlined,
      );
      return;
    }

    final cleaned = contact.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('sms:$cleaned');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) ShowMessage.error(context, 'Could not open messaging for $contact.');
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to open SMS: $e');
    }
  }

  Future<void> _onLocationAction() async {
    if (_isUpdatingLocation) return;

    if (_currentHapistore.latitude != null && _currentHapistore.longitude != null) {
      final shouldUpdate = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.edit_location_alt_rounded, color: Theme.of(ctx).colorScheme.primary),
              const SizedBox(width: 8),
              const Text('Update Store GPS?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you physically at ${_currentHapistore.storeName} right now?', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                'This will update the store\'s registered GPS location to your current position${_isLocationOutOfRange && _locationDistanceMeters != null ? ' (currently ${_formatDistance(_locationDistanceMeters)} away)' : ''}.',
                style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Update to Current GPS'),
            ),
          ],
        ),
      );

      if (shouldUpdate != true) return;
    }

    setState(() {
      _isUpdatingLocation = true;
      _locationError = null;
    });

    try {
      final position = await _controller.getCurrentLocation();
      final updatedStore = await _controller.updateStoreLocation(
        hapiStoreID: widget.hapiStoreID,
        currentStore: _currentHapistore,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (!mounted) return;
      setState(() {
        _currentHapistore = updatedStore;
      });
      ShowMessage.success(context, 'Store location updated successfully!');
      await _checkLocation();
    } catch (e, s) {
      ErrorLogService.logError(
        page: 'PjpPage',
        action: 'Update Store Location',
        error: e,
        stackTrace: s,
        extraData: {'hapiStoreID': widget.hapiStoreID, 'storeName': _currentHapistore.storeName},
      );
      if (!mounted) return;
      ShowMessage.error(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingLocation = false;
        });
      }
    }
  }

  Future<void> _onScanningAction() async {
    if (_storeScannings.isNotEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ScanningPage(initialBarcode: _storeScannings.first.barcode, initialStoreName: _currentHapistore.storeName, isEditing: true),
        ),
      );
    } else {
      final scannedBarcode = await Navigator.push<String>(context, MaterialPageRoute(builder: (context) => const BarcodeScannerWidget()));

      if (scannedBarcode != null && scannedBarcode.isNotEmpty && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ScanningPage(initialBarcode: scannedBarcode, initialStoreName: _currentHapistore.storeName),
          ),
        );
      }
    }

    if (!mounted) return;
    await _checkScanning();
  }

  // --- Step 3: Book Order Handlers ---

  Future<void> _onBookOrderDecisionPrompt() async {
    // Show a modal to select whether to book an order or not
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  'Book Order for ${_currentHapistore.storeName}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add_shopping_cart_rounded, color: Colors.green),
                title: const Text('Yes, Book an Order', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Create a new order for this store'),
                onTap: () => Navigator.pop(ctx, 'yes'),
              ),
              ListTile(
                leading: const Icon(Icons.do_not_disturb_on_outlined, color: Colors.orange),
                title: const Text('Will Not Book an Order', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Provide a required reason why no order is placed'),
                onTap: () => Navigator.pop(ctx, 'no'),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == 'yes') {
      await _onBookOrderYes();
    } else if (choice == 'no') {
      await _onBookOrderNo();
    }
  }

  Future<void> _onBookOrderYes() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => BookOrderPage(initialStoreName: _currentHapistore.storeName)),
    );

    if (!mounted) return;
    await _checkBookOrder();

    if (result != null && mounted) {
      ShowMessage.success(context, 'Order saved! Step marked as passed.');
    }
  }

  Future<void> _onBookOrderNo() async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.edit_note_rounded, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Reason Required', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Why will you not book an order for ${_currentHapistore.storeName} today?', style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: ['Sufficient Stock', 'Store Closed', 'Owner Not Around', 'No Budget'].map((preset) {
                          return ActionChip(
                            label: Text(preset, style: const TextStyle(fontSize: 11)),
                            onPressed: () {
                              setDialogState(() {
                                reasonController.text = preset;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: reasonController,
                        autofocus: true,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Reason (Required) *',
                          hintText: 'Enter reason why no order was booked...',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Reason is required';
                          }
                          if (value.trim().length < 3) {
                            return 'Please provide a more descriptive reason';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.pop(ctx, reasonController.text.trim());
                    }
                  },
                  child: const Text('Save Reason'),
                ),
              ],
            );
          },
        );
      },
    );

    if (reason != null && reason.isNotEmpty && mounted) {
      try {
        final currentUserName = authService.value.currentUser?.displayName ?? 'Salesman';
        await _controller.recordNoOrderReason(storeName: _currentHapistore.storeName, reason: reason, createdBy: currentUserName);
        if (!mounted) return;
        ShowMessage.success(context, 'Reason recorded successfully! Step marked as passed.');
        await _checkBookOrder();
      } catch (e) {
        if (mounted) {
          ShowMessage.error(context, 'Failed to record reason: $e');
        }
      }
    }
  }

  // --- Step 4: Proof of Visit Handlers ---

  Future<void> _onProofOfVisitAction() async {
    if (_isUploadingProofOfVisit) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('Proof of Visit Photo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take Picture with Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 80);

    if (picked == null || !mounted) return;

    setState(() => _isUploadingProofOfVisit = true);

    try {
      final imageFile = File(picked.path);
      final downloadUrl = await Helperfunctions.saveImage(context, imageFile);
      if (!mounted) return;

      final currentUserName = authService.value.currentUser?.displayName ?? 'Salesman';
      await _controller.saveProofOfVisit(storeName: _currentHapistore.storeName, imageUrl: downloadUrl, takenBy: currentUserName);

      if (!mounted) return;
      ShowMessage.success(context, 'Proof of visit photo captured and saved!');
      await _checkProofOfVisit();
    } catch (e, s) {
      ErrorLogService.logError(
        page: 'PjpPage',
        action: 'Proof of Visit Photo Upload',
        error: e,
        stackTrace: s,
        extraData: {'storeName': _currentHapistore.storeName},
      );
      if (mounted) {
        ShowMessage.error(context, 'Failed to save proof of visit photo: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingProofOfVisit = false);
      }
    }
  }

  // --- Step 5: Store Tasks Handlers ---

  Future<void> _onTasksAction() async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => TasklistPage(initialStoreName: _currentHapistore.storeName)));

    if (!mounted) return;
    await _checkTasks();
  }

  // --- Step 6: Merch Blitz Handlers ---

  Future<void> _onMerchBlitzAction() async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => MerchBlitzListPage(initialSearchQuery: _currentHapistore.storeName)));

    if (!mounted) return;
    await _refreshStoreDoc();
    await _checkMerchBlitz();
  }

  Future<void> _completeVisit() async {
    if (!_canCompleteVisit || _isCompleting) return;

    setState(() => _isCompleting = true);
    try {
      await _controller.completeVisit(hapiStoreID: widget.hapiStoreID, store: _currentHapistore, selectedDay: widget.selectedDay);

      if (!mounted) return;
      ShowMessage.success(context, 'Successfully completed PJP visit for ${_currentHapistore.storeName}!');
      Navigator.pop(context, true);
    } catch (e, s) {
      ErrorLogService.logError(
        page: 'PjpPage',
        action: 'Complete PJP Visit',
        error: e,
        stackTrace: s,
        extraData: {'hapiStoreID': widget.hapiStoreID, 'storeName': _currentHapistore.storeName, 'selectedDay': widget.selectedDay},
      );
      if (!mounted) return;
      ShowMessage.error(context, 'Failed to complete visit: $e');
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
  }

  Widget _buildVerificationProgress() {
    final requiredCount = [_locationPassed, _scanningPassed, _bookOrderPassed, _proofOfVisitPassed, _tasksPassed].where((p) => p).length;
    final progress = requiredCount / 5.0;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allRequired = requiredCount == 5;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: allRequired ? Colors.green.withValues(alpha: isDark ? 0.2 : 0.08) : colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: allRequired ? Colors.green.withValues(alpha: 0.4) : colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    allRequired ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                    size: 16,
                    color: allRequired ? (isDark ? Colors.greenAccent : Colors.green.shade700) : colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'PJP Checklist',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                  ),
                ],
              ),
              Text(
                allRequired && _merchBlitzPassed
                    ? 'All 5 Required + Merch Blitz (100%)'
                    : '$requiredCount of 5 Required (${(progress * 100).toInt()}%)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: allRequired ? (isDark ? Colors.greenAccent : Colors.green.shade700) : colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              valueColor: AlwaysStoppedAnimation<Color>(allRequired ? Colors.green : colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistCard({
    required int stepNumber,
    required String title,
    required IconData icon,
    required bool isLoading,
    required bool isPassed,
    required String statusMessage,
    String? errorMessage,
    Widget? extraContent,
    required String actionLabel,
    String? actionLabelWhenPassed,
    bool showActionWhenPassed = false,
    bool showActionWhenNotPassed = true,
    bool isOptional = false,
    IconData? actionIcon,
    String? loadingLabel,
    required VoidCallback onAction,
    VoidCallback? onRetry,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color statusColor;
    final String statusLabel;

    if (isLoading) {
      statusColor = Colors.grey;
      statusLabel = loadingLabel ?? 'Checking...';
    } else if (isPassed) {
      statusColor = isDark ? Colors.greenAccent : Colors.green.shade700;
      statusLabel = 'Passed';
    } else if (isOptional) {
      statusColor = isDark ? Colors.blueAccent : Colors.indigo.shade600;
      statusLabel = 'Optional';
    } else {
      statusColor = isDark ? Colors.amberAccent : Colors.orange.shade800;
      statusLabel = 'Action Needed';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isPassed ? Colors.green.withValues(alpha: isDark ? 0.08 : 0.04) : colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPassed ? Colors.green.withValues(alpha: 0.4) : colorScheme.outlineVariant.withValues(alpha: 0.7),
          width: isPassed ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isPassed ? Colors.green.withValues(alpha: 0.15) : colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(isPassed ? Icons.check_circle_rounded : icon, size: 18, color: isPassed ? Colors.green : colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('$stepNumber. $title', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLoading) ...[
                      SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, color: statusColor)),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      statusLabel,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoading ? (statusMessage.isNotEmpty ? statusMessage : 'Verifying status...') : statusMessage,
                  style: TextStyle(
                    fontSize: 13,
                    color: isPassed ? (isDark ? Colors.greenAccent : Colors.green.shade800) : colorScheme.onSurfaceVariant,
                    fontWeight: isPassed ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(errorMessage, style: TextStyle(fontSize: 12, color: colorScheme.error)),
                ],
                ?extraContent,
                if (isPassed && showActionWhenPassed && !isLoading) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.visibility_outlined, size: 14),
                    label: Text(actionLabelWhenPassed ?? actionLabel, style: const TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
                if (!isPassed && !isLoading && showActionWhenNotPassed) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      FilledButton.tonal(
                        onPressed: onAction,
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(actionLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            Icon(actionIcon ?? Icons.arrow_forward_rounded, size: 14),
                          ],
                        ),
                      ),
                      if (onRetry != null)
                        OutlinedButton(
                          onPressed: onRetry,
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh, size: 14),
                              SizedBox(width: 4),
                              Text('Retry GPS', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
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
      appBar: CustomAppbar(
        title: _currentHapistore.storeName,
        subtitle: 'PJP • ${widget.selectedDay}',
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), color: Colors.white, tooltip: 'Refresh checks', onPressed: _runAllChecks)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // Store Info Card
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.store_rounded, color: colorScheme.primary, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_currentHapistore.storeName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                            if (_currentHapistore.storeAddress.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Icon(Icons.location_on_outlined, size: 12, color: colorScheme.onSurfaceVariant),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _currentHapistore.storeAddress,
                                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (_currentHapistore.storeContact.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              InkWell(
                                borderRadius: BorderRadius.circular(4),
                                onTap: () => _copyToClipboard(_currentHapistore.storeContact, 'contact number'),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.phone_outlined, size: 12, color: colorScheme.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      _currentHapistore.storeContact,
                                      style: TextStyle(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.copy_rounded, size: 11, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_isCompletedThisWeek && _currentHapistore.lastPjpVisit != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_rounded, color: Colors.green, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isAlreadyCompletedToday
                                  ? 'Visit completed today at ${DateFormat('h:mm a').format(_currentHapistore.lastPjpVisit!.toDate())}'
                                  : 'Visit completed on ${DateFormat('EEEE, MMM d • h:mm a').format(_currentHapistore.lastPjpVisit!.toDate())}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Driver Assistance Actions: Directions, Call, Message
                  Row(
                    children: [
                      // Directions / Navigation Button
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openDirections,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                            foregroundColor: const Color(0xFF15803D), // Forest green
                            side: const BorderSide(color: Color(0xFF15803D), width: 1.2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.navigation_rounded, size: 16),
                          label: const Text(
                            'Directions',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Call Button
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _currentHapistore.storeContact.trim().isNotEmpty ? _makePhoneCall : null,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                            foregroundColor: colorScheme.primary,
                            side: BorderSide(
                              color: _currentHapistore.storeContact.trim().isNotEmpty ? colorScheme.primary : colorScheme.outlineVariant,
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.call_rounded, size: 16),
                          label: const Text(
                            'Call',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Message Button
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _currentHapistore.storeContact.trim().isNotEmpty ? _sendSms : null,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                            foregroundColor: Colors.indigo.shade700,
                            side: BorderSide(
                              color: _currentHapistore.storeContact.trim().isNotEmpty ? Colors.indigo.shade600 : colorScheme.outlineVariant,
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.sms_rounded, size: 16),
                          label: const Text(
                            'Message',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Verification Progress Indicator
          _buildVerificationProgress(),

          const SizedBox(height: 10),
          // Step 1: Location
          _buildChecklistCard(
            stepNumber: 1,
            title: 'Store Location',
            icon: Icons.location_on_outlined,
            isLoading: _isLoadingLocation || _isUpdatingLocation,
            isPassed: _locationPassed,
            statusMessage: _isUpdatingLocation
                ? 'Acquiring GPS and updating store location...'
                : (_isLocationOutOfRange
                      ? 'Out of range: ~${_formatDistance(_locationDistanceMeters)} from registered pin (200m geofence).'
                      : (_locationPassed && _locationDistanceMeters != null
                            ? 'In range: ~${_formatDistance(_locationDistanceMeters)} from store${_locationAccuracyMeters != null && _locationAccuracyMeters! > 0 ? " (±${_locationAccuracyMeters!.round()}m accuracy)" : ""}.'
                            : _locationStatus)),
            actionLabel: _isUpdatingLocation ? 'Updating...' : (_currentHapistore.latitude == null ? 'Get Location' : 'Update Location'),
            actionIcon: Icons.my_location_rounded,
            loadingLabel: _isUpdatingLocation ? 'Updating...' : null,
            showActionWhenPassed: true,
            actionLabelWhenPassed: 'Update Location',
            onAction: _onLocationAction,
            onRetry: _locationError != null || _isLocationOutOfRange || !_locationPassed ? _checkLocation : null,
          ),

          // Step 2: Scanning
          _buildChecklistCard(
            stepNumber: 2,
            title: 'Barcode Scanning',
            icon: Icons.qr_code_scanner_rounded,
            isLoading: _isLoadingScanning,
            isPassed: _scanningPassed,
            statusMessage: _scanningStatus,
            actionLabel: _storeScannings.isEmpty ? 'Assign & Scan Barcode' : 'Scan Barcode',
            actionLabelWhenPassed: 'View Barcode',
            showActionWhenPassed: true,
            onAction: _onScanningAction,
          ),

          // Step 3: Book Order (Replaces Product Placement)
          _buildChecklistCard(
            stepNumber: 3,
            title: 'Book Order',
            icon: Icons.shopping_bag_outlined,
            isLoading: _isLoadingBookOrder,
            isPassed: _bookOrderPassed,
            statusMessage: _bookOrderStatus,
            actionLabel: 'Order Options',
            actionIcon: Icons.touch_app_outlined,
            showActionWhenNotPassed: false,
            actionLabelWhenPassed: _hasBookedOrder ? 'Add / View Order' : 'Change Decision',
            showActionWhenPassed: true,
            onAction: _hasBookedOrder ? _onBookOrderYes : _onBookOrderDecisionPrompt,
            extraContent: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _bookOrderPassed ? Colors.green.withValues(alpha: 0.08) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _bookOrderPassed ? Colors.green.withValues(alpha: 0.3) : colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _bookOrderPassed
                          ? (_hasBookedOrder ? 'An order has been booked for this store.' : 'Decision: No order booked (Reason: $_noOrderReason)')
                          : 'Will you book an order for this store today?',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _bookOrderPassed ? Colors.green.shade800 : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isLoadingBookOrder ? null : _onBookOrderYes,
                            icon: const Icon(Icons.add_shopping_cart_rounded, size: 15),
                            label: Text(_hasBookedOrder ? 'View / New Order' : 'Book Order (Yes)', style: const TextStyle(fontSize: 12)),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isLoadingBookOrder ? null : _onBookOrderNo,
                            icon: Icon(_noOrderReason != null ? Icons.edit_note_rounded : Icons.do_not_disturb_on_outlined, size: 15),
                            label: Text(_noOrderReason != null ? 'Edit Reason' : 'Will Not Book', style: const TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Step 4: Proof of Visit
          _buildChecklistCard(
            stepNumber: 4,
            title: 'Proof of Visit',
            icon: Icons.camera_alt_outlined,
            isLoading: _isLoadingProofOfVisit || _isUploadingProofOfVisit,
            isPassed: _proofOfVisitPassed,
            statusMessage: _isUploadingProofOfVisit ? 'Uploading proof of visit photo...' : _proofOfVisitStatus,
            actionLabel: _isUploadingProofOfVisit ? 'Uploading...' : 'Take Picture',
            actionLabelWhenPassed: 'Retake Photo',
            showActionWhenPassed: true,
            actionIcon: Icons.photo_camera_rounded,
            loadingLabel: _isUploadingProofOfVisit ? 'Uploading...' : null,
            onAction: _onProofOfVisitAction,
            extraContent: (_proofOfVisit != null && _proofOfVisit!.imageUrl.isNotEmpty)
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => ImageViewerPage(image: null, networkImagePath: _proofOfVisit!.imageUrl)),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  Image.network(
                                    _proofOfVisit!.imageUrl,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      width: 60,
                                      height: 60,
                                      color: Colors.grey.shade300,
                                      child: const Icon(Icons.broken_image, size: 24),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.only(topLeft: Radius.circular(4)),
                                    ),
                                    child: const Icon(Icons.fullscreen, color: Colors.white, size: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentHapistore.storeName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Date: ${DateFormat('EEE, MMM d, yyyy • h:mm a').format(_proofOfVisit!.visitDate.toDate())}',
                                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 3),
                                const Text(
                                  'Tap photo thumbnail to view full image',
                                  style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.teal),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          ),

          // Step 5: Store Tasks (formerly Step 4)
          _buildChecklistCard(
            stepNumber: 5,
            title: 'Store Tasks',
            icon: Icons.task_alt_outlined,
            isLoading: _isLoadingTasks,
            isPassed: _tasksPassed,
            statusMessage: _tasksStatus,
            extraContent: (!_isLoadingTasks && !_tasksPassed && _pendingTasks.isNotEmpty)
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange.shade800),
                              const SizedBox(width: 4),
                              Text(
                                'Pending Task(s):',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ..._pendingTasks
                              .take(3)
                              .map(
                                (task) => Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '• ',
                                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                                      ),
                                      Expanded(
                                        child: Text(
                                          task.taskTitle,
                                          style: TextStyle(fontSize: 12, color: colorScheme.onSurface, fontWeight: FontWeight.w500),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          if (_pendingTasks.length > 3)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '+${_pendingTasks.length - 3} more task(s)',
                                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant),
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                : null,
            actionLabel: 'View Store Tasks',
            actionLabelWhenPassed: 'View Store Tasks',
            showActionWhenPassed: true,
            onAction: _onTasksAction,
          ),

          // Step 6: Merch Blitz (formerly Step 5, now Optional)
          _buildChecklistCard(
            stepNumber: 6,
            title: 'Merch Blitz (Optional)',
            icon: Icons.campaign_outlined,
            isLoading: _isLoadingMerchBlitz,
            isPassed: _merchBlitzPassed,
            isOptional: true,
            statusMessage: _merchBlitzStatus.isNotEmpty ? _merchBlitzStatus : 'Optional: Store has not yet been surveyed for Merch Blitz.',
            actionLabel: 'Go to Merch Blitz',
            actionLabelWhenPassed: 'View Merch Blitz',
            showActionWhenPassed: true,
            onAction: _onMerchBlitzAction,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
          ),
          child: FilledButton(
            onPressed: _canCompleteVisit && !_isCompleting ? _completeVisit : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: _canCompleteVisit ? Colors.green.shade600 : null,
              disabledBackgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isCompleting
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _canCompleteVisit ? Icons.check_circle_outline_rounded : Icons.lock_outline_rounded,
                        size: 20,
                        color: _canCompleteVisit ? Colors.white : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _canCompleteVisit ? (_isCompletedThisWeek ? 'Re-complete Store Visit' : 'Complete Store Visit') : 'Complete Store Visit',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _canCompleteVisit ? Colors.white : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
