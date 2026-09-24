import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/models/placement.dart';
import 'package:flutter_app/models/scanning.dart';
import 'package:flutter_app/models/tasks.dart';
import 'package:flutter_app/services/placement_service.dart';
import 'package:flutter_app/views/pages/dashboard/placement_page.dart';
import 'package:flutter_app/views/pages/dashboard/scanning_page.dart';
import 'package:flutter_app/views/pages/sidebar/hapistore_page.dart';
import 'package:flutter_app/views/pages/sidebar/tasklist_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/barcodescanner_widget.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

class PjpVisitPage extends StatefulWidget {
  const PjpVisitPage({
    super.key,
    required this.hapiStoreID,
    required this.initialHapistore,
    required this.selectedDay,
  });

  final String hapiStoreID;
  final Hapistore initialHapistore;
  final String selectedDay;

  @override
  State<PjpVisitPage> createState() => _PjpVisitPageState();
}

class _PjpVisitPageState extends State<PjpVisitPage> {
  static const double _maxAllowedDistanceMeters = 200.0;

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

  bool get _allPassed => _locationPassed && _scanningPassed && _placementPassed && _tasksPassed;

  @override
  void initState() {
    super.initState();
    _currentHapistore = widget.initialHapistore;
    _runAllChecks();
  }

  Future<void> _refreshStoreDoc() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('hapistores').doc(widget.hapiStoreID).get();
      if (doc.exists && doc.data() != null) {
        if (mounted) {
          setState(() {
            _currentHapistore = Hapistore.fromJson(doc.data()!);
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _runAllChecks() async {
    await Future.wait([
      _checkLocation(),
      _checkScanning(),
      _checkPlacement(),
      _checkTasks(),
    ]);
  }

  Future<void> _checkLocation() async {
    if (!mounted) return;
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    if (_currentHapistore.latitude == null || _currentHapistore.longitude == null) {
      if (mounted) {
        setState(() {
          _locationPassed = false;
          _isLoadingLocation = false;
          _locationStatus = 'No store location saved in database.';
        });
      }
      return;
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _locationPassed = false;
            _isLoadingLocation = false;
            _locationError = 'GPS is turned off. Please enable device location services.';
            _locationStatus = 'GPS services disabled';
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _locationPassed = false;
              _isLoadingLocation = false;
              _locationError = 'Location permission denied.';
              _locationStatus = 'Location permission denied';
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _locationPassed = false;
            _isLoadingLocation = false;
            _locationError = 'Location permission permanently denied. Enable in device settings.';
            _locationStatus = 'Permission permanently denied';
          });
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
      );

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        _currentHapistore.latitude!,
        _currentHapistore.longitude!,
      );

      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          if (distance <= _maxAllowedDistanceMeters) {
            _locationPassed = true;
            _locationStatus = 'Within range (${distance.toStringAsFixed(0)}m away, max ${_maxAllowedDistanceMeters.toStringAsFixed(0)}m)';
          } else {
            _locationPassed = false;
            final distLabel = distance >= 1000 ? '${(distance / 1000).toStringAsFixed(1)}km' : '${distance.toStringAsFixed(0)}m';
            _locationStatus = 'Out of range ($distLabel away, max ${_maxAllowedDistanceMeters.toStringAsFixed(0)}m)';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationPassed = false;
          _isLoadingLocation = false;
          _locationError = 'Failed to get GPS location: $e';
          _locationStatus = 'Unable to acquire location';
        });
      }
    }
  }

  Future<void> _checkScanning() async {
    if (!mounted) return;
    setState(() => _isLoadingScanning = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('scanning')
          .where('storeName', isEqualTo: _currentHapistore.storeName)
          .get();

      final scannings = snapshot.docs.map((doc) {
        var s = Scanning.fromJson(doc.data());
        return s.copyWith(id: doc.id);
      }).toList();

      if (!mounted) return;

      _storeScannings = scannings;

      if (scannings.isEmpty) {
        setState(() {
          _scanningPassed = false;
          _isLoadingScanning = false;
          _scanningStatus = 'No barcode assigned to this store.';
        });
        return;
      }

      final now = DateTime.now();
      Scanning? scannedThisMonth;

      for (final s in scannings) {
        if (s.status == ScanningStatus.scanned) {
          if (s.scannedDate != null) {
            final date = s.scannedDate!.toDate();
            if (date.year == now.year && date.month == now.month) {
              scannedThisMonth = s;
              break;
            }
          } else {
            scannedThisMonth = s;
            break;
          }
        }
      }

      setState(() {
        _isLoadingScanning = false;
        if (scannedThisMonth != null) {
          _scanningPassed = true;
          _scanningStatus = 'Barcode (${scannedThisMonth.barcode}) scanned for ${DateFormat('MMMM yyyy').format(now)}.';
        } else {
          _scanningPassed = false;
          final barcodeList = scannings.map((s) => s.barcode).join(', ');
          _scanningStatus = 'Barcode(s) [$barcodeList] not yet scanned this month.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanningPassed = false;
          _isLoadingScanning = false;
          _scanningStatus = 'Failed to load scanning records';
        });
      }
    }
  }

  Future<void> _checkPlacement() async {
    if (!mounted) return;
    setState(() => _isLoadingPlacement = true);

    try {
      final placements = await PlacementService.getListOfPlacementsWithinCurrentMonth();
      final matching = placements.where((p) => p.storeName == _currentHapistore.storeName).firstOrNull;

      if (!mounted) return;

      _storePlacement = matching;

      final now = DateTime.now();
      final lastVisit = _currentHapistore.lastPjpVisit?.toDate();
      final bool lastVisitWithinWeek = lastVisit != null && Helperfunctions.isSameWeek(lastVisit, now);

      final bool isPassed = _placementViewed ||
          lastVisitWithinWeek ||
          (matching != null && matching.isFinished);

      String statusMsg;
      if (_placementViewed) {
        statusMsg = 'Placement record viewed and verified.';
      } else if (lastVisitWithinWeek) {
        final dateLabel = DateFormat('EEE, MMM d').format(lastVisit);
        statusMsg = 'Placement verified (PJP visit completed on $dateLabel).';
      } else if (matching != null && matching.isFinished) {
        statusMsg = 'Placement checklist completed (${matching.progressCount}/12 placed).';
      } else if (matching != null) {
        statusMsg = 'Placement in progress (${matching.progressCount}/12 placed) — review needed.';
      } else {
        statusMsg = 'Placement checklist not yet reviewed for this store.';
      }

      setState(() {
        _isLoadingPlacement = false;
        _placementPassed = isPassed;
        _placementStatus = statusMsg;
      });
    } catch (e) {
      if (mounted) {
        final now = DateTime.now();
        final lastVisit = _currentHapistore.lastPjpVisit?.toDate();
        final bool lastVisitWithinWeek = lastVisit != null && Helperfunctions.isSameWeek(lastVisit, now);

        setState(() {
          _isLoadingPlacement = false;
          if (_placementViewed || lastVisitWithinWeek) {
            _placementPassed = true;
            _placementStatus = 'Placement verified for this week.';
          } else {
            _placementPassed = false;
            _placementStatus = 'Failed to load placement records';
          }
        });
      }
    }
  }

  Future<void> _checkTasks() async {
    if (!mounted) return;
    setState(() => _isLoadingTasks = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('tasks')
          .where('storeName', isEqualTo: _currentHapistore.storeName)
          .get();

      final tasks = snapshot.docs.map((doc) {
        var t = Tasks.fromJson(doc.data());
        if (t.taskID.isEmpty) t.taskID = doc.id;
        return t;
      }).toList();

      if (!mounted) return;

      _pendingTasks = tasks.where((t) => !t.isTaskDone).toList();

      setState(() {
        _isLoadingTasks = false;
        if (_pendingTasks.isEmpty) {
          _tasksPassed = true;
          if (tasks.isEmpty) {
            _tasksStatus = 'No pending tasks for this store.';
          } else {
            _tasksStatus = 'All ${tasks.length} task(s) completed.';
          }
        } else {
          _tasksPassed = false;
          _tasksStatus = '${_pendingTasks.length} pending / overdue task(s) remaining.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _tasksPassed = false;
          _isLoadingTasks = false;
          _tasksStatus = 'Failed to load store tasks';
        });
      }
    }
  }

  Future<void> _onLocationAction() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HapiStorePage(
          hapiStoreID: widget.hapiStoreID,
          hapistore: _currentHapistore,
        ),
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
          builder: (context) => ScanningPage(
            initialBarcode: _storeScannings.first.barcode,
            initialStoreName: _currentHapistore.storeName,
          ),
        ),
      );
    } else {
      final scannedBarcode = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => const BarcodeScannerWidget()),
      );

      if (scannedBarcode != null && scannedBarcode.isNotEmpty && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ScanningPage(
              initialBarcode: scannedBarcode,
              initialStoreName: _currentHapistore.storeName,
            ),
          ),
        );
      }
    }

    if (!mounted) return;
    await _checkScanning();
  }

  Future<void> _onPlacementAction() async {
    final placementToView = _storePlacement ??
        Placement(
          id: '',
          storeName: _currentHapistore.storeName,
          deliveryDate: Timestamp.now(),
          cotc1: false,
          cotc2: false,
          cotc3: false,
          cotc4: false,
          cotc5: false,
          cotc6: false,
          cotc7: false,
          cotc8: false,
          cotc9: false,
          cotc10: false,
          cotc11: false,
          cotc12: false,
          isFinished: false,
          progressCount: 0,
        );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlacementPage(placement: placementToView),
      ),
    );

    if (!mounted) return;
    _placementViewed = true;
    await _checkPlacement();
  }

  Future<void> _onTasksAction() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TasklistPage(initialStoreName: _currentHapistore.storeName),
      ),
    );

    if (!mounted) return;
    await _checkTasks();
  }

  Future<void> _completeVisit() async {
    if (!_allPassed || _isCompleting) return;

    setState(() => _isCompleting = true);
    try {
      await FirebaseFirestore.instance.collection('hapistores').doc(widget.hapiStoreID).update({
        'lastPjpVisit': Timestamp.now(),
      });

      await Helperfunctions.logTransaction(
        'PJP Visit Completed - ${_currentHapistore.storeName}',
        'Completed all 4 PJP criteria for ${widget.selectedDay}',
        LogAction.update,
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

  Widget _buildChecklistCard({
    required int stepNumber,
    required String title,
    required IconData icon,
    required bool isLoading,
    required bool isPassed,
    required String statusMessage,
    String? errorMessage,
    required String actionLabel,
    String? actionLabelWhenPassed,
    bool showActionWhenPassed = false,
    required VoidCallback onAction,
    VoidCallback? onRetry,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color statusColor;
    final String statusLabel;

    if (isLoading) {
      statusColor = Colors.grey;
      statusLabel = 'Checking...';
    } else if (isPassed) {
      statusColor = Colors.green;
      statusLabel = 'Passed';
    } else {
      statusColor = Colors.orange.shade800;
      statusLabel = 'Action Needed';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isPassed ? Colors.green.withValues(alpha: 0.04) : colorScheme.surface,
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
                child: Icon(
                  isPassed ? Icons.check_circle_rounded : icon,
                  size: 18,
                  color: isPassed ? Colors.green : colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$stepNumber. $title',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLoading) ...[
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(strokeWidth: 2, color: statusColor),
                      ),
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
                    color: isPassed ? Colors.green.shade800 : colorScheme.onSurfaceVariant,
                    fontWeight: isPassed ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    errorMessage,
                    style: TextStyle(fontSize: 12, color: colorScheme.error),
                  ),
                ],
                if (isPassed && showActionWhenPassed && !isLoading) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.visibility_outlined, size: 14),
                    label: Text(
                      actionLabelWhenPassed ?? actionLabel,
                      style: const TextStyle(fontSize: 12),
                    ),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh checks',
            onPressed: _runAllChecks,
          ),
        ],
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
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.store_rounded, color: colorScheme.primary, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _currentHapistore.storeName,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            if (_currentHapistore.storeAddress.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                _currentHapistore.storeAddress,
                                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                            if (_currentHapistore.storeContact.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Contact: ${_currentHapistore.storeContact}',
                                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
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
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Visit Verification',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              Text(
                '${[_locationPassed, _scanningPassed, _placementPassed, _tasksPassed].where((p) => p).length} of 4 Passed',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _allPassed ? Colors.green.shade700 : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
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
            actionLabel: 'View Store Tasks',
            actionLabelWhenPassed: 'View Store Tasks',
            showActionWhenPassed: true,
            onAction: _onTasksAction,
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
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
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
                          _allPassed
                              ? (_isCompletedThisWeek ? 'Re-complete Store Visit' : 'Complete Store Visit')
                              : 'Complete Store Visit',
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
