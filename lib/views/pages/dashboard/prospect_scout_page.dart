import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:selecta_ops/controllers/prospect_scout_controller.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/map_tile_style.dart';
import 'package:selecta_ops/models/prospect_scout.dart';
import 'package:selecta_ops/models/scout_route_track.dart';
import 'package:selecta_ops/services/scout_tracking_service.dart';
import 'package:selecta_ops/views/pages/dashboard/prospect_scout_form_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/map_style_switcher_button.dart';
import 'package:selecta_ops/views/widgets/scout_route_history_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

class ProspectScoutPage extends StatefulWidget {
  final int initialTabIndex;

  const ProspectScoutPage({super.key, this.initialTabIndex = 0});

  @override
  State<ProspectScoutPage> createState() => _ProspectScoutPageState();
}

class _ProspectScoutPageState extends State<ProspectScoutPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MapController _mapController = MapController();
  final ProspectScoutController _controller = ProspectScoutController();

  StreamSubscription<List<ProspectScout>>? _prospectsSubscription;
  List<ProspectScout> _allProspects = [];
  List<Hapistore> _allHapiStores = [];

  Position? _currentPosition;
  bool _isLoading = true;
  bool _isLocating = false;

  // Layer Toggles
  bool _showProspects = true;
  bool _showHapiStores = true;
  bool _showCompetitorsOnly = false;
  bool _showScoutedRoutes = true;
  String _selectedRouteTimeFilter = 'All Recent'; // 'All Recent', 'Today', 'This Month', 'Past 30 Days', 'Due Re-Scout (>3m)', 'Custom'
  DateTimeRange? _customRouteDateRange;
  String _selectedCompetitorColor = 'All';
  String _selectedStatusFilter = 'All';
  String _selectedSortBy = 'Nearest'; // 'Nearest', 'Newest', 'Potential', 'Name'
  bool _isMapReady = false;
  MapTileStyle _mapStyle = MapTileStyle.standard;

  // Route Tracking
  final ScoutTrackingService _trackingService = ScoutTrackingService();
  StreamSubscription<List<ScoutRouteSession>>? _routesSubscription;
  List<ScoutRouteSession> _scoutedRoutes = [];
  String _currentUsername = 'Salesman';

  // Selected item on map
  ProspectScout? _selectedProspect;
  Hapistore? _selectedHapiStore;

  // Search in list view
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final LatLng _defaultCenter = const LatLng(14.5995, 120.9842); // Metro Manila fallback

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTabIndex);

    _listenToProspects();
    _listenToRoutes();
    _loadCurrentUser();
    _loadHapiStores();
    _determinePosition();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _prospectsSubscription?.cancel();
    _routesSubscription?.cancel();
    _mapController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _listenToRoutes() {
    DateTime? start;
    DateTime? end;
    bool onlyDue = false;

    final now = DateTime.now();
    if (_selectedRouteTimeFilter == 'Today') {
      start = DateTime(now.year, now.month, now.day);
      end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else if (_selectedRouteTimeFilter == 'This Month') {
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    } else if (_selectedRouteTimeFilter == 'Past 30 Days') {
      start = now.subtract(const Duration(days: 30));
      end = now;
    } else if (_selectedRouteTimeFilter == 'Due Re-Scout (>3m)') {
      onlyDue = true;
    } else if (_selectedRouteTimeFilter == 'Custom' && _customRouteDateRange != null) {
      start = _customRouteDateRange!.start;
      end = _customRouteDateRange!.end;
    }

    _routesSubscription?.cancel();
    _routesSubscription = _trackingService.getRoutesStreamByRange(startDate: start, endDate: end, onlyDueForRescout: onlyDue).listen((routes) {
      if (mounted) {
        setState(() {
          _scoutedRoutes = routes;
        });
      }
    });
  }

  void _showRouteDateFilterDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final presets = [
          {'label': 'All Recent', 'icon': Icons.all_inclusive_rounded},
          {'label': 'Today', 'icon': Icons.today_rounded},
          {'label': 'This Month', 'icon': Icons.calendar_month_rounded},
          {'label': 'Past 30 Days', 'icon': Icons.history_rounded},
          {'label': 'Due Re-Scout (>3m)', 'icon': Icons.warning_amber_rounded},
          {'label': 'Custom Range...', 'icon': Icons.date_range_rounded},
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Filter Traveled Routes by Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                ...presets.map((item) {
                  final label = item['label'] as String;
                  final icon = item['icon'] as IconData;
                  final isSelected = _selectedRouteTimeFilter == label;
                  return ListTile(
                    leading: Icon(icon, color: isSelected ? Theme.of(context).colorScheme.primary : null),
                    title: Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                    trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (label == 'Custom Range...') {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2025),
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                        );
                        if (picked != null) {
                          setState(() {
                            _selectedRouteTimeFilter = 'Custom';
                            _customRouteDateRange = picked;
                          });
                          _listenToRoutes();
                        }
                      } else {
                        setState(() {
                          _selectedRouteTimeFilter = label;
                        });
                        _listenToRoutes();
                      }
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMapStyleDialog() {
    MapStyleSwitcherButton.showStyleDialog(
      context: context,
      currentStyle: _mapStyle,
      onStyleChanged: (newStyle) => setState(() => _mapStyle = newStyle),
    );
  }

  void _showRouteHistorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ScoutRouteHistorySheet(
        routes: _scoutedRoutes,
        onFocusRoute: (route) {
          if (route.polylinePoints.isNotEmpty && _isMapReady) {
            try {
              double minLat = route.polylinePoints.first.latitude;
              double maxLat = route.polylinePoints.first.latitude;
              double minLng = route.polylinePoints.first.longitude;
              double maxLng = route.polylinePoints.first.longitude;

              for (final pt in route.polylinePoints) {
                if (pt.latitude < minLat) minLat = pt.latitude;
                if (pt.latitude > maxLat) maxLat = pt.latitude;
                if (pt.longitude < minLng) minLng = pt.longitude;
                if (pt.longitude > maxLng) maxLng = pt.longitude;
              }

              _mapController.fitCamera(
                CameraFit.bounds(bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)), padding: const EdgeInsets.all(50)),
              );
            } catch (_) {}
          }
        },
      ),
    );
  }

  Future<void> _loadCurrentUser() async {
    final user = await _controller.getCurrentUser();
    if (mounted && user != null && user.username.isNotEmpty) {
      setState(() {
        _currentUsername = user.username;
      });
    }
  }

  Future<void> _toggleRouteTracking() async {
    if (_trackingService.isTracking) {
      await _trackingService.stopTracking();
      if (mounted) {
        ShowMessage.success(context, 'Scouting route stopped. Road track saved!');
      }
    } else {
      final started = await _trackingService.startTracking(salesmanName: _currentUsername);
      if (mounted) {
        if (started) {
          ShowMessage.success(context, 'Route tracking active! Recording roads visited.');
        } else {
          ShowMessage.error(context, 'Location permission is required to track routes.');
        }
      }
    }
  }

  void _listenToProspects() {
    _prospectsSubscription = _controller.getProspectsStream().listen(
      (prospects) {
        if (mounted) {
          setState(() {
            _allProspects = prospects;
            _isLoading = false;
          });
        }
      },
      onError: (err) {
        if (mounted) {
          setState(() => _isLoading = false);
          ShowMessage.error(context, 'Error loading prospects: $err');
        }
      },
    );
  }

  Future<void> _loadHapiStores() async {
    try {
      final stores = await _controller.getHapiStores();
      final validStores = stores.where((s) => s.latitude != null && s.longitude != null).toList();
      if (mounted) {
        setState(() {
          _allHapiStores = validStores;
        });
      }
    } catch (_) {
      // Ignored for secondary layer
    }
  }

  Future<void> _determinePosition() async {
    setState(() => _isLocating = true);
    try {
      final pos = await _controller.getCurrentLocation();
      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _isLocating = false;
        });
        if (_isMapReady) {
          try {
            _mapController.move(LatLng(pos.latitude, pos.longitude), 14.5);
          } catch (_) {}
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  List<ProspectScout> get _filteredProspects {
    return _controller.filterProspects(
      prospects: _allProspects,
      query: _searchQuery,
      statusFilter: _selectedStatusFilter,
      competitorFilter: _showCompetitorsOnly ? 'With Competitors' : (_selectedCompetitorColor != 'All' ? _selectedCompetitorColor : 'All'),
      sortBy: _selectedSortBy,
      currentPosition: _currentPosition,
    );
  }

  String? _getDistanceText(double lat, double lng) {
    if (_currentPosition == null || (lat == 0.0 && lng == 0.0)) return null;
    final meters = ProspectScoutController.calculateDistanceInMeters(_currentPosition!.latitude, _currentPosition!.longitude, lat, lng);
    return ProspectScoutController.formatDistance(meters);
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) ShowMessage.error(context, 'Could not initiate call to $phoneNumber');
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Error launching call: $e');
    }
  }

  bool get _hasActiveFilters {
    return _showCompetitorsOnly ||
        _selectedCompetitorColor != 'All' ||
        _selectedStatusFilter != 'All' ||
        _searchQuery.isNotEmpty ||
        _selectedRouteTimeFilter != 'All Recent';
  }

  void _resetAllFilters() {
    setState(() {
      _showProspects = true;
      _showHapiStores = true;
      _showCompetitorsOnly = false;
      _selectedCompetitorColor = 'All';
      _selectedStatusFilter = 'All';
      _selectedRouteTimeFilter = 'All Recent';
      _customRouteDateRange = null;
      _searchQuery = '';
      _searchController.clear();
    });
    _listenToRoutes();
  }

  void _showConvertToHapiStoreDialog(ProspectScout prospect) {
    final addressController = TextEditingController(text: prospect.notes ?? '');
    final pjpController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.celebration_rounded, color: Color(0xFF10B981)),
            SizedBox(width: 10),
            Expanded(child: Text('Convert to Hapi Store', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Convert "${prospect.storeName.isNotEmpty ? prospect.storeName : "Unnamed Prospect"}" into an active Selecta Hapi Store in your operational territory.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: addressController,
                decoration: InputDecoration(
                  labelText: 'Store Address',
                  hintText: 'Enter street, barangay, city...',
                  prefixIcon: const Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pjpController,
                decoration: InputDecoration(
                  labelText: 'PJP Delivery Schedule (Optional)',
                  hintText: 'e.g. Mon / Thu Week 1-3',
                  prefixIcon: const Icon(Icons.calendar_month_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await _controller.convertToHapiStore(
                  prospect: prospect,
                  storeAddress: addressController.text.trim(),
                  pjpSchedule: pjpController.text.trim().isNotEmpty ? pjpController.text.trim() : null,
                );
                await _loadHapiStores();
                if (mounted) {
                  ShowMessage.success(context, '${prospect.storeName} successfully converted to Selecta Hapi Store!');
                }
              } catch (e) {
                if (mounted) {
                  ShowMessage.error(context, 'Failed to convert prospect: $e');
                }
              }
            },
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Confirm Conversion'),
          ),
        ],
      ),
    );
  }

  void _fitAllMarkers() {
    if (!_isMapReady) return;

    try {
      final List<LatLng> points = [];

      if (_showProspects) {
        for (final p in _filteredProspects) {
          if (p.latitude != 0.0 && p.longitude != 0.0) {
            points.add(LatLng(p.latitude, p.longitude));
          }
        }
      }

      if (_showHapiStores && !_showCompetitorsOnly) {
        for (final h in _allHapiStores) {
          if (h.latitude != null && h.longitude != null) {
            points.add(LatLng(h.latitude!, h.longitude!));
          }
        }
      }

      if (points.isEmpty) {
        if (_currentPosition != null) {
          _mapController.move(LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 14.0);
        }
        return;
      }

      if (points.length == 1) {
        _mapController.move(points.first, 15.0);
        return;
      }

      double minLat = points.first.latitude;
      double maxLat = points.first.latitude;
      double minLng = points.first.longitude;
      double maxLng = points.first.longitude;

      for (final pt in points) {
        if (pt.latitude < minLat) minLat = pt.latitude;
        if (pt.latitude > maxLat) maxLat = pt.latitude;
        if (pt.longitude < minLng) minLng = pt.longitude;
        if (pt.longitude > maxLng) maxLng = pt.longitude;
      }

      _mapController.fitCamera(
        CameraFit.bounds(bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)), padding: const EdgeInsets.all(50)),
      );
    } catch (_) {}
  }

  Future<void> _launchNavigation(double lat, double lng, String label) async {
    final nameEncoded = Uri.encodeComponent(label);
    final googleNavUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final universalMapsUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&destination_place_id=$nameEncoded&travelmode=driving',
    );
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

  void _showProspectDetailsSheet(ProspectScout prospect) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;

        return StatefulBuilder(
          builder: (dialogCtx, setSheetState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Store Photo Banner (if available)
                  if (prospect.imageUrl != null && prospect.imageUrl!.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 180,
                        child: Image.network(
                          prospect.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (c, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Header with Store Name & Quality Badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: prospect.qualityColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: Icon(Icons.storefront_rounded, color: prospect.qualityColor, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              prospect.storeName.isNotEmpty ? prospect.storeName : 'Unnamed Prospect',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: prospect.qualityColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: prospect.qualityColor.withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    prospect.qualityLabel,
                                    style: TextStyle(color: prospect.qualityColor, fontWeight: FontWeight.bold, fontSize: 11.5),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: ProspectStatus.statusColor(prospect.status).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    prospect.status,
                                    style: TextStyle(color: ProspectStatus.statusColor(prospect.status), fontWeight: FontWeight.bold, fontSize: 11.5),
                                  ),
                                ),
                                if (_getDistanceText(prospect.latitude, prospect.longitude) != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.near_me_rounded, size: 12, color: Color(0xFF0284C7)),
                                        const SizedBox(width: 4),
                                        Text(
                                          _getDistanceText(prospect.latitude, prospect.longitude)!,
                                          style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 11.5),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Contact Owner Info & Quick Call
                  if ((prospect.contactPerson != null && prospect.contactPerson!.isNotEmpty) ||
                      (prospect.contactPhone != null && prospect.contactPhone!.isNotEmpty)) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.person_rounded, size: 20, color: colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (prospect.contactPerson != null && prospect.contactPerson!.isNotEmpty)
                                  Text(
                                    prospect.contactPerson!,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                  ),
                                if (prospect.contactPhone != null && prospect.contactPhone!.isNotEmpty)
                                  Text(
                                    prospect.contactPhone!,
                                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                  ),
                              ],
                            ),
                          ),
                          if (prospect.contactPhone != null && prospect.contactPhone!.isNotEmpty)
                            FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => _makePhoneCall(prospect.contactPhone!),
                              icon: const Icon(Icons.phone_rounded, size: 15),
                              label: const Text('Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 3 Assessment Breakdown Badges
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Q1 Visibility
                      _buildDetailChip(
                        icon: prospect.isAccessible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        label: prospect.isAccessible ? 'Accessible Storefront' : 'Obstructed / Grills',
                        color: prospect.isAccessible ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                      // Q2 Size
                      _buildDetailChip(
                        icon: Icons.store_mall_directory_outlined,
                        label: prospect.isStoreBig ? 'Big Store (Capital Ready)' : 'Small Store',
                        color: prospect.isStoreBig ? const Color(0xFF0284C7) : const Color(0xFFF59E0B),
                      ),
                      // Q3 Competitor
                      _buildDetailChip(
                        icon: Icons.kitchen_rounded,
                        label: prospect.hasCompetitorFreezer ? 'Has Other Brand Freezers' : 'No Competitor Freezer (?)',
                        color: prospect.hasCompetitorFreezer ? const Color(0xFF8B5CF6) : Colors.grey,
                      ),
                    ],
                  ),

                  // Competitor Colors
                  if (prospect.hasCompetitorFreezer && prospect.competitorColors.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Competitor Brands:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Wrap(
                          spacing: 6,
                          children: prospect.competitorColors.map((colorName) {
                            final c = CompetitorBrandColor.toColor(colorName);
                            final tc = CompetitorBrandColor.toTextColor(colorName);
                            final isWhite = colorName == CompetitorBrandColor.white;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: c,
                                borderRadius: BorderRadius.circular(12),
                                border: isWhite ? Border.all(color: Colors.grey.shade400) : null,
                              ),
                              child: Text(
                                colorName,
                                style: TextStyle(color: tc, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ],

                  if (prospect.notes != null && prospect.notes!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('Notes: ${prospect.notes}', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    ),
                  ],

                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Scouted by: ${prospect.scoutedBy ?? "Salesman"}', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
                      if (prospect.createdAt != null)
                        Text(
                          DateFormat('MMM d, yyyy').format(prospect.createdAt!.toDate()),
                          style: TextStyle(fontSize: 11, color: colorScheme.outline),
                        ),
                    ],
                  ),

                  if (prospect.status != ProspectStatus.converted) ...[
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        foregroundColor: const Color(0xFF10B981),
                        side: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showConvertToHapiStoreDialog(prospect);
                      },
                      icon: const Icon(Icons.celebration_rounded, size: 18),
                      label: const Text('Convert to Active Hapi Store', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Actions
                  Row(
                    children: [
                      // Turn-by-Turn Navigation
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _launchNavigation(
                              prospect.latitude,
                              prospect.longitude,
                              prospect.storeName.isNotEmpty ? prospect.storeName : 'Prospect Store',
                            );
                          },
                          icon: const Icon(Icons.navigation_rounded, size: 18),
                          label: const Text('Navigate'),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Status Pipeline Menu
                      PopupMenuButton<String>(
                        tooltip: 'Update Status',
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onSelected: (newStatus) async {
                          if (newStatus == ProspectStatus.converted) {
                            if (ctx.mounted) Navigator.pop(ctx);
                            _showConvertToHapiStoreDialog(prospect);
                          } else if (prospect.id != null) {
                            await _controller.updateStatus(prospect.id!, newStatus);
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) ShowMessage.success(context, 'Status updated to $newStatus');
                          }
                        },
                        itemBuilder: (pCtx) => ProspectStatus.all.map((s) {
                          return PopupMenuItem(
                            value: s,
                            child: Row(
                              children: [
                                Icon(ProspectStatus.statusIcon(s), color: ProspectStatus.statusColor(s), size: 18),
                                const SizedBox(width: 8),
                                Text(s, style: const TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            ),
                          );
                        }).toList(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.swap_vert_circle_outlined, color: colorScheme.primary),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Edit Record Button
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final updated = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProspectScoutFormPage(prospect: prospect, prospectId: prospect.id),
                            ),
                          );
                          if (updated == true) {
                            setState(() {});
                          }
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showHapiStoreDetailsSheet(Hapistore store) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.icecream_rounded, color: Color(0xFFEF4444), size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(store.storeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(6)),
                              child: const Text(
                                'Active Selecta Hapi Store',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (store.latitude != null && store.longitude != null && _getDistanceText(store.latitude!, store.longitude!) != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.near_me_rounded, size: 12, color: Color(0xFF0284C7)),
                                    const SizedBox(width: 4),
                                    Text(
                                      _getDistanceText(store.latitude!, store.longitude!)!,
                                      style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (store.storeContact.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.phone_outlined, size: 16, color: colorScheme.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(store.storeContact, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                      ),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _makePhoneCall(store.storeContact),
                        icon: const Icon(Icons.phone_rounded, size: 14),
                        label: const Text('Call', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              if (store.storeAddress.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.place_outlined, size: 16, color: colorScheme.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(store.storeAddress, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ),
              if (store.pjpSchedule != null && store.pjpSchedule!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 16, color: colorScheme.outline),
                      const SizedBox(width: 8),
                      Text('PJP Schedule: ${store.pjpSchedule}', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  if (store.latitude != null && store.longitude != null) {
                    _launchNavigation(store.latitude!, store.longitude!, store.storeName);
                  }
                },
                icon: const Icon(Icons.navigation_rounded),
                label: const Text('Navigate to Hapi Store'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailChip({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  void _showLegendDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.palette_outlined, size: 22),
              SizedBox(width: 8),
              Text('Map Legend & Guide', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Stores & Territory:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                _buildLegendItem(
                  color: const Color(0xFFEF4444),
                  title: 'Selecta Hapi Store',
                  subtitle: 'Current active Selecta client',
                  icon: Icons.icecream_rounded,
                ),
                const Divider(height: 24),
                const Text('Competitor Brand Colors (5 Options):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                _buildLegendItem(
                  color: const Color(0xFF2563EB),
                  title: 'Blue Competitor',
                  subtitle: 'Single brand freezer',
                  icon: Icons.icecream_rounded,
                ),
                _buildLegendItem(
                  color: const Color(0xFFEC4899),
                  title: 'Pink Competitor',
                  subtitle: 'Single brand freezer',
                  icon: Icons.icecream_rounded,
                ),
                _buildLegendItem(
                  color: const Color(0xFF10B981),
                  title: 'Green Competitor',
                  subtitle: 'Single brand freezer',
                  icon: Icons.icecream_rounded,
                ),
                _buildLegendItem(
                  color: const Color(0xFFF59E0B),
                  title: 'Yellow Competitor',
                  subtitle: 'Single brand freezer',
                  icon: Icons.icecream_rounded,
                ),
                _buildLegendItem(
                  color: Colors.white,
                  title: 'White Competitor',
                  subtitle: 'Single brand freezer',
                  icon: Icons.icecream_rounded,
                  hasBorder: true,
                ),
                _buildLegendItem(
                  gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFFEC4899), Color(0xFF10B981)]),
                  title: 'Multi-Brand Competitor',
                  subtitle: 'Rainbow / Gradient pin with ice cream logo',
                  icon: Icons.icecream_rounded,
                ),
                _buildLegendItem(
                  color: const Color(0xFF0F172A),
                  title: 'No Competitor Brand (?)',
                  subtitle: 'Store has no existing ice cream freezer',
                  icon: Icons.storefront_rounded,
                ),
                const Divider(height: 24),
                const Text('Salesman Routes & Recency:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                _buildLegendItem(
                  color: const Color(0xFF10B981),
                  title: 'Live Scouting Session',
                  subtitle: 'Active GPS route currently being recorded',
                  icon: Icons.play_arrow_rounded,
                ),
                _buildLegendItem(
                  color: const Color(0xFF0284C7),
                  title: 'Fresh Route (< 30 days)',
                  subtitle: 'Recently surveyed; territory is up-to-date',
                  icon: Icons.alt_route_rounded,
                ),
                _buildLegendItem(
                  color: const Color(0xFFF59E0B),
                  title: 'Aging Route (1 - 3 months)',
                  subtitle: 'Getting older; check for new competitor shifts',
                  icon: Icons.alt_route_rounded,
                ),
                _buildLegendItem(
                  color: const Color(0xFFEF4444),
                  title: 'Overdue for Re-Scout (> 3 months)',
                  subtitle: 'Old route needing re-survey / dealer follow-up',
                  icon: Icons.warning_amber_rounded,
                ),
              ],
            ),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Got it'))],
        );
      },
    );
  }

  Widget _buildLegendItem({
    Color? color,
    Gradient? gradient,
    required String title,
    required String subtitle,
    IconData? icon,
    bool hasBorder = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              gradient: gradient,
              shape: BoxShape.circle,
              border: hasBorder ? Border.all(color: Colors.grey.shade400, width: 1.5) : null,
            ),
            child: icon != null ? Icon(icon, size: 14, color: color == Colors.white ? Colors.black87 : Colors.white) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Prospect Scouting',
        subtitle: 'Map & scout new store opportunities',
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: [
            Tab(icon: const Icon(Icons.map_rounded, size: 20), text: 'Territory Map (${_filteredProspects.length})'),
            Tab(icon: const Icon(Icons.list_alt_rounded, size: 20), text: 'Prospect Directory (${_allProspects.length})'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            tooltip: 'Map & Route Options',
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (value) {
              switch (value) {
                case 'map_style':
                  _showMapStyleDialog();
                  break;
                case 'route_history':
                  _showRouteHistorySheet();
                  break;
                case 'map_legend':
                  _showLegendDialog();
                  break;
                case 'fit_all':
                  _fitAllMarkers();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem<String>(
                value: 'map_style',
                child: Row(
                  children: [
                    Icon(Icons.layers_rounded, size: 20, color: Color(0xFF0284C7)),
                    SizedBox(width: 12),
                    Text('Choose Map Style', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'route_history',
                child: Row(
                  children: [
                    Icon(Icons.alt_route_rounded, size: 20, color: Color(0xFF10B981)),
                    SizedBox(width: 12),
                    Text('Route History & Recency', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'map_legend',
                child: Row(
                  children: [
                    Icon(Icons.palette_outlined, size: 20, color: Color(0xFFF59E0B)),
                    SizedBox(width: 12),
                    Text('Map Legend & Guide', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'fit_all',
                child: Row(
                  children: [
                    Icon(Icons.filter_center_focus_rounded, size: 20, color: Color(0xFF64748B)),
                    SizedBox(width: 12),
                    Text('Fit All Stores', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Tab 1: Territory Map ──────────────────────────────────────────
          _buildMapTab(colorScheme),

          // ── Tab 2: Prospect Directory List ────────────────────────────────
          _buildListTab(colorScheme),
        ],
      ),
      floatingActionButton: (_selectedProspect != null || _selectedHapiStore != null)
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final added = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProspectScoutFormPage(
                      initialLocation: _currentPosition != null ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude) : null,
                    ),
                  ),
                );
                if (added == true) {
                  setState(() {});
                }
              },
              backgroundColor: const Color(0xFFEF4444), // Selecta red
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text('Scout New Store', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
    );
  }

  Widget _buildMapTab(ColorScheme colorScheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final prospectMarkers = _filteredProspects.map((p) {
      final isSelected = _selectedProspect?.id == p.id;
      final hasCompetitor = p.hasCompetitorFreezer && p.competitorColors.isNotEmpty;
      final isMultiBrand = hasCompetitor && p.competitorColors.length > 1;

      // Pin appearance
      Color? pinColor;
      Gradient? pinGradient;
      IconData pinIcon = Icons.icecream_rounded;
      Color iconColor = Colors.white;
      bool isWhite = false;

      if (!p.hasCompetitorFreezer) {
        // Fresh prospect with NO competitor freezer: Obsidian black with storefront icon
        pinColor = const Color(0xFF0F172A);
        pinIcon = Icons.storefront_rounded;
      } else if (!isMultiBrand) {
        // Single competitor brand (e.g. Pink or Blue): Solid brand color with ice cream icon
        final colorName = p.competitorColors.isNotEmpty ? p.competitorColors.first : 'Blue';
        pinColor = CompetitorBrandColor.toColor(colorName);
        isWhite = colorName.toLowerCase() == 'white';
        iconColor = isWhite ? const Color(0xFF1E293B) : Colors.white;
      } else {
        // Multi-brand competitor store: Rainbow/Gradient pin with single ice cream icon (just like Selecta!)
        final colors = p.competitorColors.map((c) => CompetitorBrandColor.toColor(c)).toList();
        if (colors.length == 1) colors.add(colors.first);
        pinGradient = LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight);
        pinIcon = Icons.icecream_rounded;
        iconColor = Colors.white;
      }

      return Marker(
        point: LatLng(p.latitude, p.longitude),
        width: isSelected ? 48 : 40,
        height: isSelected ? 48 : 40,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _selectedProspect = p;
              _selectedHapiStore = null;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: pinColor,
              gradient: pinGradient,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.yellowAccent : (isWhite ? Colors.grey.shade400 : Colors.white),
                width: isSelected ? 3.5 : 2.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected ? Colors.yellowAccent.withValues(alpha: 0.5) : (pinColor ?? Colors.black38).withValues(alpha: 0.35),
                  blurRadius: isSelected ? 10 : 4,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                pinIcon,
                color: iconColor,
                size: isSelected ? 24 : 20,
                shadows: pinGradient != null ? const [Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1))] : null,
              ),
            ),
          ),
        ),
      );
    }).toList();

    final hapiStoreMarkers = (_showHapiStores && !_showCompetitorsOnly)
        ? _allHapiStores.map((store) {
            return Marker(
              point: LatLng(store.latitude!, store.longitude!),
              width: 38,
              height: 38,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedHapiStore = store;
                    _selectedProspect = null;
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444), // Selecta Red
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _selectedHapiStore == store ? Colors.yellowAccent : Colors.white,
                      width: _selectedHapiStore == store ? 3.5 : 2.0,
                    ),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                  ),
                  child: const Center(child: Icon(Icons.icecream_rounded, color: Colors.white, size: 18)),
                ),
              ),
            );
          }).toList()
        : <Marker>[];

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _allProspects.isNotEmpty
                ? LatLng(_allProspects.first.latitude, _allProspects.first.longitude)
                : (_currentPosition != null ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude) : _defaultCenter),
            initialZoom: 13.5,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
            onTap: (_, _) {
              if (_selectedProspect != null || _selectedHapiStore != null) {
                setState(() {
                  _selectedProspect = null;
                  _selectedHapiStore = null;
                });
              }
            },
            onMapReady: () {
              if (mounted) {
                setState(() => _isMapReady = true);
              }
            },
          ),
          children: [
            TileLayer(urlTemplate: _mapStyle.url, userAgentPackageName: 'selecta_ops'),

            // Road Route Polylines (Color-coded by Recency Freshness)
            if (_showScoutedRoutes && _scoutedRoutes.isNotEmpty)
              PolylineLayer(
                polylines: [
                  for (final route in _scoutedRoutes)
                    if (route.polylinePoints.length >= 2) ...[
                      // Outer glow
                      Polyline(
                        points: route.polylinePoints,
                        strokeWidth: route.needsRescout ? 8.0 : 6.0,
                        color: (route.needsRescout ? const Color(0xFFEF4444) : route.recencyTier.color).withValues(alpha: 0.35),
                      ),
                      // Core route path
                      Polyline(
                        points: route.polylinePoints,
                        strokeWidth: 3.5,
                        color: route.needsRescout ? const Color(0xFFEF4444) : route.recencyTier.color,
                      ),
                    ],
                ],
              ),

            MarkerLayer(
              markers: [
                // Rep Current GPS location
                if (_currentPosition != null)
                  Marker(
                    point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                    width: 36,
                    height: 36,
                    child: Container(
                      decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.25), shape: BoxShape.circle),
                      child: Center(
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Hapi Store Pins
                ...hapiStoreMarkers,

                // Prospect Pins
                if (_showProspects) ...prospectMarkers,
              ],
            ),
          ],
        ),

        // Floating Filter Chips Header
        Positioned(
          top: 10,
          left: 10,
          right: 10,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Prospects Toggle
                FilterChip(
                  avatar: Icon(Icons.explore_rounded, size: 16, color: _showProspects ? Colors.white : colorScheme.onSurface),
                  label: Text('Prospects (${_allProspects.length})'),
                  selected: _showProspects,
                  selectedColor: colorScheme.primary,
                  labelStyle: TextStyle(color: _showProspects ? Colors.white : null, fontWeight: FontWeight.bold, fontSize: 12),
                  onSelected: (val) => setState(() => _showProspects = val),
                ),
                const SizedBox(width: 8),

                // Scouted Routes Toggle & Date Range Filter
                FilterChip(
                  avatar: Icon(Icons.alt_route_rounded, size: 16, color: _showScoutedRoutes ? Colors.white : colorScheme.onSurface),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Routes: $_selectedRouteTimeFilter (${_scoutedRoutes.length})'),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: _showRouteDateFilterDialog,
                        child: Icon(Icons.calendar_month_rounded, size: 14, color: _showScoutedRoutes ? Colors.white : colorScheme.primary),
                      ),
                    ],
                  ),
                  selected: _showScoutedRoutes,
                  selectedColor: const Color(0xFF0284C7),
                  labelStyle: TextStyle(color: _showScoutedRoutes ? Colors.white : null, fontWeight: FontWeight.bold, fontSize: 12),
                  onSelected: (val) {
                    if (_showScoutedRoutes && val) {
                      _showRouteDateFilterDialog();
                    } else {
                      setState(() => _showScoutedRoutes = val);
                    }
                  },
                ),
                const SizedBox(width: 8),

                // Current Hapi Stores Toggle
                FilterChip(
                  avatar: const Icon(Icons.icecream_rounded, size: 16, color: Colors.white),
                  label: Text('Selecta Stores (${_allHapiStores.length})'),
                  selected: _showHapiStores && !_showCompetitorsOnly,
                  selectedColor: const Color(0xFFEF4444),
                  labelStyle: TextStyle(
                    color: (_showHapiStores && !_showCompetitorsOnly) ? Colors.white : null,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  onSelected: (val) {
                    setState(() {
                      _showHapiStores = val;
                      if (val) _showCompetitorsOnly = false;
                    });
                  },
                ),
                const SizedBox(width: 8),

                // Competitor Stores Filter
                FilterChip(
                  avatar: Icon(Icons.kitchen_rounded, size: 16, color: _showCompetitorsOnly ? Colors.white : colorScheme.onSurface),
                  label: const Text('Competitor Only'),
                  selected: _showCompetitorsOnly,
                  selectedColor: const Color(0xFF8B5CF6),
                  labelStyle: TextStyle(color: _showCompetitorsOnly ? Colors.white : null, fontWeight: FontWeight.bold, fontSize: 12),
                  onSelected: (val) {
                    setState(() {
                      _showCompetitorsOnly = val;
                      if (val) _showProspects = true;
                    });
                  },
                ),
                const SizedBox(width: 8),

                // Specific Competitor Color filter dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCompetitorColor,
                      isDense: true,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      items: ['All', ...CompetitorBrandColor.all].map((c) {
                        return DropdownMenuItem(
                          value: c,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (c != 'All') ...[
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: CompetitorBrandColor.toColor(c),
                                    shape: BoxShape.circle,
                                    border: c == CompetitorBrandColor.white ? Border.all(color: Colors.grey.shade400) : null,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(c == 'All' ? 'Colors: All' : c),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedCompetitorColor = val);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Route Tracking Active Banner / Start Button
        Positioned(
          top: 56,
          left: 12,
          right: 12,
          child: ValueListenableBuilder<bool>(
            valueListenable: _trackingService.isTrackingNotifier,
            builder: (ctx, isTracking, _) {
              if (!isTracking) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(20),
                    color: colorScheme.surface,
                    child: InkWell(
                      onTap: _toggleRouteTracking,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.6)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_circle_fill_rounded, color: Color(0xFF10B981), size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Start Scouting Route',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF047857)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }

              return ValueListenableBuilder<int>(
                valueListenable: _trackingService.recordedPointsNotifier,
                builder: (ctx, pointsCount, _) {
                  return ValueListenableBuilder<double>(
                    valueListenable: _trackingService.distanceTraveledNotifier,
                    builder: (ctx, distance, _) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
                          border: Border.all(color: const Color(0xFF10B981), width: 1.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Scouting Route Active',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                                    ),
                                    Text(
                                      '$pointsCount pts (${(distance / 1000).toStringAsFixed(2)} km covered)',
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFEF4444),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: _toggleRouteTracking,
                              icon: const Icon(Icons.stop_circle_rounded, size: 16),
                              label: const Text('End Scouting', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),

        // Floating GPS Recenter button
        Positioned(
          right: 16,
          bottom: (_selectedProspect != null || _selectedHapiStore != null) ? 140 : 96,
          child: FloatingActionButton.small(
            heroTag: 'gps_recenter',
            backgroundColor: colorScheme.surface,
            foregroundColor: colorScheme.primary,
            tooltip: 'My Location',
            onPressed: _determinePosition,
            child: _isLocating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location_rounded),
          ),
        ),

        // Floating Mini-Preview Card for Selected Prospect
        if (_selectedProspect != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _buildProspectMiniPreviewCard(_selectedProspect!, colorScheme),
          ),

        // Floating Mini-Preview Card for Selected HapiStore
        if (_selectedHapiStore != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _buildHapiStoreMiniPreviewCard(_selectedHapiStore!, colorScheme),
          ),
      ],
    );
  }

  Widget _buildProspectMiniPreviewCard(ProspectScout p, ColorScheme colorScheme) {
    final dist = _getDistanceText(p.latitude, p.longitude);

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      color: colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.qualityColor.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (p.imageUrl != null && p.imageUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      p.imageUrl!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: p.qualityColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: Icon(Icons.storefront_rounded, color: p.qualityColor, size: 22),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: p.qualityColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Icon(Icons.storefront_rounded, color: p.qualityColor, size: 22),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p.storeName.isNotEmpty ? p.storeName : 'Unnamed Prospect',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: p.qualityColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                            child: Text(p.qualityLabel, style: TextStyle(color: p.qualityColor, fontWeight: FontWeight.bold, fontSize: 10.5)),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: ProspectStatus.statusColor(p.status).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              p.status,
                              style: TextStyle(color: ProspectStatus.statusColor(p.status), fontWeight: FontWeight.bold, fontSize: 10.5),
                            ),
                          ),
                          if (dist != null) ...[
                            const SizedBox(width: 6),
                            Text('• $dist', style: TextStyle(fontSize: 11, color: colorScheme.outline, fontWeight: FontWeight.w600)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'Close Preview',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _selectedProspect = null),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _launchNavigation(p.latitude, p.longitude, p.storeName),
                    icon: const Icon(Icons.navigation_rounded, size: 15),
                    label: const Text('Directions', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                if (p.contactPhone != null && p.contactPhone!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _makePhoneCall(p.contactPhone!),
                    icon: const Icon(Icons.phone_rounded, size: 15),
                    label: const Text('Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _showProspectDetailsSheet(p),
                  icon: const Icon(Icons.info_outline_rounded, size: 15),
                  label: const Text('Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHapiStoreMiniPreviewCard(Hapistore store, ColorScheme colorScheme) {
    final dist = (store.latitude != null && store.longitude != null)
        ? _getDistanceText(store.latitude!, store.longitude!)
        : null;

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      color: colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.icecream_rounded, color: Color(0xFFEF4444), size: 24),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        store.storeName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(6)),
                            child: const Text('Active Hapi Store', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5)),
                          ),
                          if (dist != null) ...[
                            const SizedBox(width: 6),
                            Text('• $dist', style: TextStyle(fontSize: 11, color: colorScheme.outline, fontWeight: FontWeight.w600)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'Close Preview',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _selectedHapiStore = null),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      if (store.latitude != null && store.longitude != null) {
                        _launchNavigation(store.latitude!, store.longitude!, store.storeName);
                      }
                    },
                    icon: const Icon(Icons.navigation_rounded, size: 15),
                    label: const Text('Directions', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                if (store.storeContact.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _makePhoneCall(store.storeContact),
                    icon: const Icon(Icons.phone_rounded, size: 15),
                    label: const Text('Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _showHapiStoreDetailsSheet(store),
                  icon: const Icon(Icons.info_outline_rounded, size: 15),
                  label: const Text('Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTab(ColorScheme colorScheme) {
    final prospects = _filteredProspects;

    // Aggregate metrics
    final totalCount = _allProspects.length;
    final highPotentialCount = _allProspects.where((p) => p.qualityScore == 3).length;
    final competitorCount = _allProspects.where((p) => p.hasCompetitorFreezer).length;
    final engagedCount = _allProspects.where((p) => p.status == ProspectStatus.engaged).length;
    final convertedCount = _allProspects.where((p) => p.status == ProspectStatus.converted).length;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {});
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // 1. KPI Metric Summary Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildKpiCard(title: 'Total Scouted', value: '$totalCount', icon: Icons.explore_rounded, color: colorScheme.primary, width: 104),
                const SizedBox(width: 8),
                _buildKpiCard(title: 'High Potential', value: '$highPotentialCount', icon: Icons.star_rounded, color: const Color(0xFF10B981), width: 104),
                const SizedBox(width: 8),
                _buildKpiCard(title: 'Has Competitor', value: '$competitorCount', icon: Icons.kitchen_rounded, color: const Color(0xFF8B5CF6), width: 104),
                const SizedBox(width: 8),
                _buildKpiCard(title: 'Engaged', value: '$engagedCount', icon: Icons.handshake_rounded, color: const Color(0xFFF59E0B), width: 104),
                const SizedBox(width: 8),
                _buildKpiCard(title: 'Converted', value: '$convertedCount', icon: Icons.verified_rounded, color: const Color(0xFF059669), width: 104),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 2. Search Field
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search store, notes, salesman, contact...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),

          const SizedBox(height: 12),

          // 3. Status Filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusFilterChip('All'),
                const SizedBox(width: 6),
                _buildStatusFilterChip(ProspectStatus.scouted),
                const SizedBox(width: 6),
                _buildStatusFilterChip(ProspectStatus.engaged),
                const SizedBox(width: 6),
                _buildStatusFilterChip(ProspectStatus.converted),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // 4. Sort controls & Active filter reset bar
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedSortBy,
                    isDense: true,
                    icon: const Icon(Icons.arrow_drop_down_rounded, size: 20),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                    items: const [
                      DropdownMenuItem(value: 'Nearest', child: Text('📍 Nearest First')),
                      DropdownMenuItem(value: 'Newest', child: Text('🕒 Newest First')),
                      DropdownMenuItem(value: 'Potential', child: Text('⭐ Highest Potential')),
                      DropdownMenuItem(value: 'Name', child: Text('🔤 Alphabetical')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedSortBy = val);
                    },
                  ),
                ),
              ),
              const Spacer(),
              if (_hasActiveFilters)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: Colors.redAccent,
                  ),
                  onPressed: _resetAllFilters,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                  label: const Text('Reset Filters', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
            ],
          ),

          const SizedBox(height: 14),

          // 5. Prospect Cards
          if (prospects.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.storefront_outlined, size: 54, color: colorScheme.outline),
                  const SizedBox(height: 12),
                  const Text('No prospects found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(
                    'Tap "Scout New Store" below to log your first field discovery!',
                    style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ...prospects.map((prospect) => _buildProspectListCard(prospect, colorScheme)),
        ],
      ),
    );
  }

  Widget _buildStatusFilterChip(String label) {
    final isSelected = _selectedStatusFilter == label;
    final color = label == 'All' ? Theme.of(context).colorScheme.primary : ProspectStatus.statusColor(label);

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: color.withValues(alpha: 0.18),
      side: BorderSide(color: isSelected ? color : Theme.of(context).colorScheme.outlineVariant),
      labelStyle: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? color : null, fontSize: 12),
      onSelected: (_) => setState(() => _selectedStatusFilter = label),
    );
  }

  Widget _buildKpiCard({required String title, required String value, required IconData icon, required Color color, double? width}) {
    final card = Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    return width != null ? card : Expanded(child: card);
  }

  Widget _buildProspectListCard(ProspectScout prospect, ColorScheme colorScheme) {
    final distanceText = _getDistanceText(prospect.latitude, prospect.longitude);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showProspectDetailsSheet(prospect),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (prospect.imageUrl != null && prospect.imageUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        prospect.imageUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(color: prospect.qualityColor.withValues(alpha: 0.14), shape: BoxShape.circle),
                          child: Icon(Icons.storefront_rounded, color: prospect.qualityColor, size: 22),
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: prospect.qualityColor.withValues(alpha: 0.14), shape: BoxShape.circle),
                      child: Icon(Icons.storefront_rounded, color: prospect.qualityColor, size: 22),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prospect.storeName.isNotEmpty ? prospect.storeName : 'Unnamed Prospect',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: prospect.qualityColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                              child: Text(
                                prospect.qualityLabel,
                                style: TextStyle(color: prospect.qualityColor, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: ProspectStatus.statusColor(prospect.status).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                prospect.status,
                                style: TextStyle(color: ProspectStatus.statusColor(prospect.status), fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                            if (distanceText != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.near_me_rounded, size: 10, color: Colors.blue),
                                    const SizedBox(width: 3),
                                    Text(distanceText, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.blue)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.navigation_rounded, color: Color(0xFF10B981), size: 22),
                    tooltip: 'Navigate',
                    onPressed: () => _launchNavigation(prospect.latitude, prospect.longitude, prospect.storeName),
                  ),
                ],
              ),

              if ((prospect.contactPerson != null && prospect.contactPerson!.trim().isNotEmpty) ||
                  (prospect.contactPhone != null && prospect.contactPhone!.trim().isNotEmpty)) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline_rounded, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          [
                            if (prospect.contactPerson != null && prospect.contactPerson!.trim().isNotEmpty) prospect.contactPerson!.trim(),
                            if (prospect.contactPhone != null && prospect.contactPhone!.trim().isNotEmpty) prospect.contactPhone!.trim(),
                          ].join(' • '),
                          style: const TextStyle(fontSize: 11.5, color: Colors.black87),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (prospect.contactPhone != null && prospect.contactPhone!.trim().isNotEmpty)
                        InkWell(
                          onTap: () => _makePhoneCall(prospect.contactPhone!),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.call_rounded, size: 12, color: Color(0xFF10B981)),
                                SizedBox(width: 3),
                                Text('Call', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // Competitor brand chips & action footer
              Row(
                children: [
                  if (prospect.hasCompetitorFreezer && prospect.competitorColors.isNotEmpty) ...[
                    const Text('Brands: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    Wrap(
                      spacing: 4,
                      children: prospect.competitorColors.map((c) {
                        return Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: CompetitorBrandColor.toColor(c),
                            shape: BoxShape.circle,
                            border: c == CompetitorBrandColor.white ? Border.all(color: Colors.grey.shade400) : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(width: 8),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                      child: const Text('No Competitor (?)', style: TextStyle(fontSize: 10.5, color: Colors.grey)),
                    ),
                    const SizedBox(width: 8),
                  ],

                  const Spacer(),

                  if (prospect.status != ProspectStatus.converted)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: const Color(0xFF10B981),
                      ),
                      onPressed: () => _showConvertToHapiStoreDialog(prospect),
                      icon: const Icon(Icons.store_rounded, size: 14),
                      label: const Text('Convert', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),

                  if (prospect.createdAt != null) ...[
                    const SizedBox(width: 8),
                    Text(DateFormat('MMM d, yyyy').format(prospect.createdAt!.toDate()), style: TextStyle(fontSize: 11, color: colorScheme.outline)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

