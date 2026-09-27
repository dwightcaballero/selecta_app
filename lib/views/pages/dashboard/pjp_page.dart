import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/controllers/pjp_controller.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:intl/intl.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/models/placement.dart';
import 'package:flutter_app/models/scanning.dart';
import 'package:flutter_app/models/tasks.dart';
import 'package:flutter_app/views/pages/dashboard/merchblitzlist_page.dart';
import 'package:flutter_app/views/pages/dashboard/placement_page.dart';
import 'package:flutter_app/views/pages/dashboard/scanning_page.dart';
import 'package:flutter_app/views/pages/sidebar/hapistore_page.dart';
import 'package:flutter_app/views/pages/sidebar/tasklist_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/barcodescanner_widget.dart';

/// Presentation view for inspecting and completing individual PJP store visits.
///
/// Geolocation distance calculation, barcode check, placement checklist status,
/// task queries, and Merch Blitz validation are managed by [PjpController].
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

  // Task 1: Location state
  bool _isLoadingLocation = true;
  bool _locationPassed = false;
  String _locationStatus = '';
  String? _locationError;

  // Task 2: Scanning state
  bool _isLoadingScanning = true;
  bool _scanningPassed = false;
  String _scanningStatus = '';
  List<Scanning> _storeScannings = [];

  // Task 3: Placement state
  bool _isLoadingPlacement = true;
  bool _placementPassed = false;
  bool _placementViewed = false;
  String _placementStatus = '';
  Placement? _storePlacement;

  // Task 4: Tasks state
  bool _isLoadingTasks = true;
  bool _tasksPassed = false;
  String _tasksStatus = '';
  List<Tasks> _pendingTasks = [];

  // Task 5: Merch Blitz state
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

  bool get _allPassed => _locationPassed && _scanningPassed && _placementPassed && _tasksPassed && _merchBlitzPassed;

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
    } catch (_) {}
  }

  Future<void> _runAllChecks() async {
    await Future.wait([_checkLocation(), _checkScanning(), _checkPlacement(), _checkTasks(), _checkMerchBlitz()]);
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
      _locationStatus = result.status;
      _locationError = result.error;
    });
  }

  Future<void> _checkScanning() async {
    if (!mounted) return;
    setState(() => _isLoadingScanning = true);

    final result = await _controller.checkScanning(_currentHapistore.storeName);
    if (!mounted) return;

    setState(() {
      _isLoadingScanning = false;
      _scanningPassed = result.passed;
      _scanningStatus = result.status;
      _storeScannings = result.storeScannings;
    });
  }

  Future<void> _checkPlacement() async {
    if (!mounted) return;
    setState(() => _isLoadingPlacement = true);

    final result = await _controller.checkPlacement(
      store: _currentHapistore,
      placementViewed: _placementViewed,
    );
    if (!mounted) return;

    setState(() {
      _isLoadingPlacement = false;
      _placementPassed = result.passed;
      _placementStatus = result.status;
      if (result.storePlacement != null) {
        _storePlacement = result.storePlacement;
      }
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

  Future<void> _onLocationAction() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HapiStorePage(hapiStoreID: widget.hapiStoreID, hapistore: _currentHapistore),
      ),
    );

    if (!mounted) return;
    await _refreshStoreDoc();
    await _checkLocation();
  }

  Future<void> _onScanningAction() async {
    if (_storeScannings.isNotEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ScanningPage(initialBarcode: _storeScannings.first.barcode, initialStoreName: _currentHapistore.storeName),
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

  Future<void> _onPlacementAction() async {
    final placementToView =
        _storePlacement ?? Placement.empty().copyWith(storeName: _currentHapistore.storeName);

    await Navigator.push(context, MaterialPageRoute(builder: (context) => PlacementPage(placement: placementToView)));

    if (!mounted) return;
    _placementViewed = true;
    await _checkPlacement();
  }

  Future<void> _onTasksAction() async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => TasklistPage(initialStoreName: _currentHapistore.storeName)));

    if (!mounted) return;
    await _checkTasks();
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

  Future<void> _onMerchBlitzAction() async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => MerchBlitzListPage(initialSearchQuery: _currentHapistore.storeName)));

    if (!mounted) return;
    await _refreshStoreDoc();
    await _checkMerchBlitz();
  }

  Future<void> _completeVisit() async {
    if (!_allPassed || _isCompleting) return;

    setState(() => _isCompleting = true);
    try {
      await _controller.completeVisit(
        hapiStoreID: widget.hapiStoreID,
        store: _currentHapistore,
        selectedDay: widget.selectedDay,
      );

      if (!mounted) return;
      ShowMessage.success(context, 'Successfully completed PJP visit for ${_currentHapistore.storeName}!');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ShowMessage.error(context, 'Failed to complete visit: $e');
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
  }

  Widget _buildVerificationProgress() {
    final passedCount = [_locationPassed, _scanningPassed, _placementPassed, _tasksPassed, _merchBlitzPassed].where((p) => p).length;
    final progress = passedCount / 5.0;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: passedCount == 5 ? Colors.green.withValues(alpha: isDark ? 0.2 : 0.08) : colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: passedCount == 5 ? Colors.green.withValues(alpha: 0.4) : colorScheme.outlineVariant.withValues(alpha: 0.6)),
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
                    passedCount == 5 ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                    size: 16,
                    color: passedCount == 5 ? (isDark ? Colors.greenAccent : Colors.green.shade700) : colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'PJP Checklist',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                  ),
                ],
              ),
              Text(
                '$passedCount of 5 Passed (${(progress * 100).toInt()}%)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: passedCount == 5 ? (isDark ? Colors.greenAccent : Colors.green.shade700) : colorScheme.primary,
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
              valueColor: AlwaysStoppedAnimation<Color>(passedCount == 5 ? Colors.green : colorScheme.primary),
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
    required VoidCallback onAction,
    VoidCallback? onRetry,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color statusColor;
    final String statusLabel;

    if (isLoading) {
      statusColor = Colors.grey;
      statusLabel = 'Checking...';
    } else if (isPassed) {
      statusColor = isDark ? Colors.greenAccent : Colors.green.shade700;
      statusLabel = 'Passed';
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
                  isLoading ? 'Verifying status...' : statusMessage,
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
                if (!isPassed && !isLoading) ...[
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
                            const Icon(Icons.arrow_forward_rounded, size: 14),
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
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh checks', onPressed: _runAllChecks)],
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
            isLoading: _isLoadingLocation,
            isPassed: _locationPassed,
            statusMessage: _locationStatus,
            errorMessage: _locationError,
            actionLabel: _currentHapistore.latitude == null ? 'Set Location' : 'Update Location',
            onAction: _onLocationAction,
            onRetry: _locationError != null ? _checkLocation : null,
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
          // Step 3: Placement
          _buildChecklistCard(
            stepNumber: 3,
            title: 'Product Placement',
            icon: Icons.inventory_2_outlined,
            isLoading: _isLoadingPlacement,
            isPassed: _placementPassed,
            statusMessage: _placementStatus,
            actionLabel: 'Review Placement',
            actionLabelWhenPassed: 'View Placement',
            showActionWhenPassed: true,
            onAction: _onPlacementAction,
          ),
          // Step 4: Tasks
          _buildChecklistCard(
            stepNumber: 4,
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
          // Step 5: Merch Blitz
          _buildChecklistCard(
            stepNumber: 5,
            title: 'Merch Blitz',
            icon: Icons.campaign_outlined,
            isLoading: _isLoadingMerchBlitz,
            isPassed: _merchBlitzPassed,
            statusMessage: _merchBlitzStatus,
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
            onPressed: _allPassed && !_isCompleting ? _completeVisit : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: _allPassed ? Colors.green.shade600 : null,
              disabledBackgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isCompleting
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _allPassed ? Icons.check_circle_outline_rounded : Icons.lock_outline_rounded,
                        size: 20,
                        color: _allPassed ? Colors.white : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _allPassed ? (_isCompletedThisWeek ? 'Re-complete Store Visit' : 'Complete Store Visit') : 'Complete Store Visit',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _allPassed ? Colors.white : colorScheme.onSurfaceVariant,
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
