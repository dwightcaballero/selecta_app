import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/views/pages/dashboard/pjp_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:url_launcher/url_launcher.dart';

class MappedStoreItem {
  final String docId;
  final Hapistore store;

  MappedStoreItem({required this.docId, required this.store});
}

/// Interactive PJP Route & Store Map Page displaying sequential store visit route,
/// road-snapped driving directions, turn-by-turn navigation handoff to Google Maps,
/// real-time rep GPS location, store sequence pins, and visit details.
class PjpMapPage extends StatefulWidget {
  final String? initialDay;

  const PjpMapPage({super.key, this.initialDay});

  @override
  State<PjpMapPage> createState() => _PjpMapPageState();
}

class _PjpMapPageState extends State<PjpMapPage> {
  final MapController _mapController = MapController();
  late String _selectedDay;

  List<MappedStoreItem> _allStores = [];
  List<MappedStoreItem> _mappedStores = [];
  List<LatLng> _roadPolylinePoints = [];
  double _totalRouteDistanceKm = 0.0;
  int _estimatedDrivingMinutes = 0;
  bool _isLoadingRouteGeometry = false;

  MappedStoreItem? _selectedStore;
  Position? _currentPosition;
  bool _isLoading = true;
  bool _isLocating = false;

  // Default coordinate (Metro Manila / Central Philippines fallback)
  final LatLng _defaultCenter = const LatLng(14.5995, 120.9842);

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.initialDay ?? DateFormat('EEEE').format(DateTime.now());
    _loadStoresForDay();
    _determinePosition();
  }

  Future<void> _loadStoresForDay() async {
    setState(() => _isLoading = true);

    try {
      final snapshot = await HapiStoreService.getHapiStoresSnapshotByPjpSchedule(_selectedDay);

      final items = snapshot.docs.map((doc) {
        return MappedStoreItem(
          docId: doc.id,
          store: Hapistore.fromJson(doc.data()),
        );
      }).toList();

      // Sort by sequence
      items.sort((a, b) => (a.store.pjpSequence ?? 999).compareTo(b.store.pjpSequence ?? 999));

      // Filter stores with valid GPS coordinates
      final mapped = items.where((item) => item.store.latitude != null && item.store.longitude != null).toList();

      if (mounted) {
        setState(() {
          _allStores = items;
          _mappedStores = mapped;
          _selectedStore = mapped.isNotEmpty ? mapped.first : null;
          _isLoading = false;
        });

        // Fit map bounds to stores if any exist
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _fitAllStoreMarkers();
        });

        // Fetch road-snapped driving geometry
        _fetchDrivingRoadRoute(mapped);
      }
    } catch (e, s) {
      ErrorLogService.logError(
        page: 'PjpMapPage',
        action: 'Load Stores For Day',
        error: e,
        stackTrace: s,
      );
      if (mounted) {
        setState(() => _isLoading = false);
        ShowMessage.error(context, 'Failed to load route stores: $e');
      }
    }
  }

  /// Queries the Open Source Routing Machine (OSRM) driving API to snap route lines
  /// to actual roads, streets, and highways, and calculate driving distance and duration.
  Future<void> _fetchDrivingRoadRoute(List<MappedStoreItem> stores) async {
    if (stores.length < 2) {
      if (mounted) {
        setState(() {
          _roadPolylinePoints = stores.map((s) => LatLng(s.store.latitude!, s.store.longitude!)).toList();
          _totalRouteDistanceKm = 0;
          _estimatedDrivingMinutes = 0;
        });
      }
      return;
    }

    setState(() => _isLoadingRouteGeometry = true);

    try {
      // OSRM accepts up to 25 waypoints per request: {lon},{lat};{lon},{lat}...
      final waypoints = stores.take(25).map((s) => '${s.store.longitude},${s.store.latitude}').join(';');
      final url = Uri.parse('https://router.project-osrm.org/route/v1/driving/$waypoints?overview=full&geometries=geojson');

      final response = await http.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final firstRoute = routes[0];
          final geometry = firstRoute['geometry'] as Map<String, dynamic>?;
          final coordinates = geometry?['coordinates'] as List?;

          final distanceMeters = (firstRoute['distance'] as num?)?.toDouble() ?? 0.0;
          final durationSeconds = (firstRoute['duration'] as num?)?.toDouble() ?? 0.0;

          if (coordinates != null && coordinates.isNotEmpty) {
            final points = coordinates
                .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
                .toList();

            if (mounted) {
              setState(() {
                _roadPolylinePoints = points;
                _totalRouteDistanceKm = distanceMeters / 1000.0;
                _estimatedDrivingMinutes = (durationSeconds / 60.0).round();
                _isLoadingRouteGeometry = false;
              });
              return;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('OSRM routing fetch failed or timed out: $e');
    }

    // Fallback: direct waypoint line if routing service is unreachable
    if (mounted) {
      setState(() {
        _roadPolylinePoints = stores.map((s) => LatLng(s.store.latitude!, s.store.longitude!)).toList();
        _isLoadingRouteGeometry = false;
      });
    }
  }

  Future<void> _determinePosition() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _isLocating = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _isLocating = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isLocating = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _isLocating = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _fitAllStoreMarkers() {
    if (_mappedStores.isEmpty) {
      if (_currentPosition != null) {
        _mapController.move(LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 14);
      }
      return;
    }

    if (_mappedStores.length == 1) {
      final s = _mappedStores.first.store;
      _mapController.move(LatLng(s.latitude!, s.longitude!), 15);
      return;
    }

    double minLat = _mappedStores.first.store.latitude!;
    double maxLat = _mappedStores.first.store.latitude!;
    double minLng = _mappedStores.first.store.longitude!;
    double maxLng = _mappedStores.first.store.longitude!;

    for (final item in _mappedStores) {
      final s = item.store;
      if (s.latitude! < minLat) minLat = s.latitude!;
      if (s.latitude! > maxLat) maxLat = s.latitude!;
      if (s.longitude! < minLng) minLng = s.longitude!;
      if (s.longitude! > maxLng) maxLng = s.longitude!;
    }

    final bounds = LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.only(top: 80, bottom: 220, left: 40, right: 40),
      ),
    );
  }

  bool _isVisitedToday(Hapistore store) {
    if (store.lastPjpVisit == null) return false;
    final now = DateTime.now();
    final visit = store.lastPjpVisit!.toDate();
    return visit.year == now.year && visit.month == now.month && visit.day == now.day;
  }

  String _formatDistanceToStore(Hapistore store) {
    if (_currentPosition == null || store.latitude == null || store.longitude == null) {
      return '';
    }
    final distanceInMeters = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      store.latitude!,
      store.longitude!,
    );
    if (distanceInMeters >= 1000) {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)} km away';
    }
    return '${distanceInMeters.round()} m away';
  }

  /// Launches Google Maps or Waze with real-time turn-by-turn driving navigation to the store.
  Future<void> _launchTurnByTurnNavigation(Hapistore store) async {
    if (store.latitude == null || store.longitude == null) {
      ShowMessage.alert(
        context,
        title: 'Coordinates Missing',
        message: 'This store does not have GPS coordinates registered yet.',
        icon: Icons.location_off_outlined,
      );
      return;
    }

    final lat = store.latitude!;
    final lng = store.longitude!;
    final nameEncoded = Uri.encodeComponent(store.storeName);

    // Google Navigation intent for Android, falls back to web/iOS universal maps URL
    final googleNavUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final universalMapsUri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&destination_place_id=$nameEncoded&travelmode=driving');
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng($nameEncoded)');

    try {
      if (await canLaunchUrl(googleNavUri)) {
        await launchUrl(googleNavUri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(universalMapsUri)) {
        await launchUrl(universalMapsUri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ShowMessage.error(context, 'Could not open map navigation application.');
        }
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to launch navigation: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: CustomAppbar(
        title: 'PJP Route Map',
        subtitle: '$_selectedDay • ${_allStores.length} stores scheduled',
      ),
      body: Stack(
        children: [
          // ── FlutterMap ──────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _mappedStores.isNotEmpty
                  ? LatLng(_mappedStores.first.store.latitude!, _mappedStores.first.store.longitude!)
                  : (_currentPosition != null
                      ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                      : _defaultCenter),
              initialZoom: 13,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'selecta_ops',
              ),

              // Road-Snapped Driving Polyline
              if (_roadPolylinePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    // Outer subtle glow
                    Polyline(
                      points: _roadPolylinePoints,
                      strokeWidth: 6.0,
                      color: colorScheme.primary.withValues(alpha: 0.3),
                    ),
                    // Core driving path
                    Polyline(
                      points: _roadPolylinePoints,
                      strokeWidth: 3.5,
                      color: colorScheme.primary,
                    ),
                  ],
                ),

              // Store Markers
              MarkerLayer(
                markers: [
                  // User GPS Position
                  if (_currentPosition != null)
                    Marker(
                      point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                      width: 44,
                      height: 44,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Store Pins
                  ..._mappedStores.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    final store = item.store;
                    final isVisited = _isVisitedToday(store);
                    final isSelected = _selectedStore?.docId == item.docId;
                    final sequenceNumber = store.pjpSequence ?? (index + 1);

                    final pinColor = isVisited
                        ? const Color(0xFF15803D)
                        : (isSelected ? colorScheme.primary : Colors.orange.shade700);

                    return Marker(
                      point: LatLng(store.latitude!, store.longitude!),
                      width: isSelected ? 52 : 44,
                      height: isSelected ? 52 : 44,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedStore = item);
                          _mapController.move(LatLng(store.latitude!, store.longitude!), 15);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: pinColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: isSelected ? 3 : 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: pinColor.withValues(alpha: 0.4),
                                blurRadius: isSelected ? 8 : 4,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Center(
                            child: isVisited
                                ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                                : Text(
                                    '$sequenceNumber',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: isSelected ? 15 : 13,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),

          // ── Day Selector Chips at Top ──────────────────────────────────
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: PjpScheduleDays.all.map((day) {
                  final isSelected = _selectedDay == day;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      selected: isSelected,
                      label: Text(day.substring(0, 3)),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                      ),
                      selectedColor: colorScheme.primary,
                      backgroundColor: colorScheme.surface.withValues(alpha: 0.95),
                      elevation: 2,
                      checkmarkColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      onSelected: (_) {
                        setState(() {
                          _selectedDay = day;
                          _loadStoresForDay();
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── Driving Distance & Duration Pill (Top-Center) ───────────────
          if (_totalRouteDistanceKm > 0)
            Positioned(
              top: 56,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.directions_car_outlined, size: 14, color: colorScheme.primary),
                    const SizedBox(width: 5),
                    Text(
                      '${_totalRouteDistanceKm.toStringAsFixed(1)} km',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                    if (_estimatedDrivingMinutes > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '• ~$_estimatedDrivingMinutes min driving',
                        style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // ── Map Floating Control Buttons (Right side) ──────────────────
          Positioned(
            right: 16,
            bottom: _selectedStore != null ? 225 : 30,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'fab_fit_bounds',
                  onPressed: _fitAllStoreMarkers,
                  backgroundColor: colorScheme.surface,
                  foregroundColor: colorScheme.onSurface,
                  tooltip: 'Fit All Stores',
                  child: const Icon(Icons.crop_free_rounded),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'fab_my_location',
                  onPressed: () async {
                    await _determinePosition();
                    if (_currentPosition != null) {
                      _mapController.move(
                        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                        15,
                      );
                    }
                  },
                  backgroundColor: colorScheme.surface,
                  foregroundColor: colorScheme.primary,
                  tooltip: 'My Location',
                  child: _isLocating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location_rounded),
                ),
              ],
            ),
          ),

          // ── Bottom Store Preview Sheet with Navigation Button ──────────
          if (_selectedStore != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _buildStorePreviewCard(_selectedStore!, colorScheme),
            ),

          // ── Loading Overlay ────────────────────────────────────────────
          if (_isLoading || _isLoadingRouteGeometry)
            Positioned(
              top: 56,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 6),
                    Text(
                      _isLoading ? 'Loading stores...' : 'Snapping route to roads...',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStorePreviewCard(MappedStoreItem item, ColorScheme colorScheme) {
    final store = item.store;
    final isVisited = _isVisitedToday(store);
    final distanceText = _formatDistanceToStore(store);

    return Card(
      elevation: 6,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stop Sequence & Status Pill
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Stop #${store.pjpSequence ?? 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (isVisited)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 13, color: Colors.green),
                        SizedBox(width: 4),
                        Text(
                          'Visited Today',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Pending Visit',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                  ),
                const Spacer(),
                if (distanceText.isNotEmpty)
                  Text(
                    distanceText,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: colorScheme.primary),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // Store Name
            Text(
              store.storeName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            if (store.storeAddress.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      store.storeAddress,
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),

            // Action Buttons: Navigate in Google Maps | Open Details | Call
            Row(
              children: [
                // Turn-by-Turn Google Maps Navigation button
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _launchTurnByTurnNavigation(store),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF15803D), // Forest green navigation color
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.navigation_rounded, size: 18),
                    label: const Text('Navigate', maxLines: 1, softWrap: false),
                  ),
                ),
                const SizedBox(width: 8),

                // Open Store Details button (PjpPage)
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PjpPage(
                            hapiStoreID: item.docId,
                            initialHapistore: store,
                            selectedDay: _selectedDay,
                          ),
                        ),
                      ).then((_) => _loadStoresForDay());
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.storefront_rounded, size: 18),
                    label: const Text('Details', maxLines: 1, softWrap: false),
                  ),
                ),

                // Call Phone button
                if (store.storeContact.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () async {
                      final telUri = Uri.parse('tel:${store.storeContact.replaceAll(' ', '')}');
                      if (await canLaunchUrl(telUri)) {
                        await launchUrl(telUri);
                      } else {
                        Clipboard.setData(ClipboardData(text: store.storeContact));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Contact ${store.storeContact} copied to clipboard'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.phone_outlined, size: 18),
                    tooltip: 'Call Store',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
