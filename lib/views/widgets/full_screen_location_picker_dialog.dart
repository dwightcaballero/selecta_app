import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:selecta_ops/models/map_tile_style.dart';
import 'package:selecta_ops/views/widgets/map_style_switcher_button.dart';

/// Full-screen interactive map location picker (like Grab / Google Maps)
/// Allows salesman to pan/zoom so a center crosshair pin lands on the exact store across the road.
class FullScreenLocationPickerDialog extends StatefulWidget {
  final LatLng initialLocation;
  final MapTileStyle initialMapStyle;

  const FullScreenLocationPickerDialog({
    super.key,
    required this.initialLocation,
    this.initialMapStyle = MapTileStyle.standard,
  });

  @override
  State<FullScreenLocationPickerDialog> createState() =>
      _FullScreenLocationPickerDialogState();
}

class _FullScreenLocationPickerDialogState
    extends State<FullScreenLocationPickerDialog> {
  late final MapController _mapController;
  late LatLng _currentCenter;
  late MapTileStyle _mapStyle;
  bool _isMapReady = false;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _currentCenter = widget.initialLocation;
    _mapStyle = widget.initialMapStyle;
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _goToCurrentGps() async {
    setState(() => _isLocating = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      final target = LatLng(pos.latitude, pos.longitude);
      _currentCenter = target;
      if (_isMapReady) {
        _mapController.move(target, 17);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get GPS: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pin Exact Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: MapStyleSwitcherButton(
              currentStyle: _mapStyle,
              onStyleChanged: (newStyle) => setState(() => _mapStyle = newStyle),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter,
              initialZoom: 16.5,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onPositionChanged: (camera, hasGesture) {
                _currentCenter = camera.center;
                setState(() {});
              },
              onMapReady: () {
                _isMapReady = true;
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _mapStyle.url,
                userAgentPackageName: 'selecta_ops',
              ),
            ],
          ),

          // Center stationary Target Pin (Grab/Google Maps style)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36), // Align bottom tip of pin to exact center
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                    ),
                    child: const Text(
                      'Store Spot',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 46,
                        color: Color(0xFFEF4444),
                      ),
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  // Target Shadow/Dot on ground
                  Container(
                    width: 10,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.all(Radius.elliptical(10, 5)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Floating Controls (Top Left & Right)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_mapStyle.icon, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(_mapStyle.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),

          // Floating GPS Re-center button
          Positioned(
            top: 16,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'recenter_gps_btn',
              onPressed: _isLocating ? null : _goToCurrentGps,
              backgroundColor: Colors.white,
              foregroundColor: colorScheme.primary,
              child: _isLocating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded),
            ),
          ),

          // Zoom in/out buttons
          Positioned(
            right: 16,
            top: 76,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'zoom_in_btn',
                  onPressed: () {
                    if (_isMapReady) {
                      _mapController.move(_currentCenter, _mapController.camera.zoom + 1);
                    }
                  },
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom_out_btn',
                  onPressed: () {
                    if (_isMapReady) {
                      _mapController.move(_currentCenter, _mapController.camera.zoom - 1);
                    }
                  },
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),

          // Bottom Confirmation Card
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.pin_drop_rounded, color: Color(0xFFEF4444), size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Targeted Store Location',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            Text(
                              'Drag map until pin is on the store across the road',
                              style: TextStyle(fontSize: 11.5, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Lat: ${_currentCenter.latitude.toStringAsFixed(6)}   |   Lng: ${_currentCenter.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context, _currentCenter);
                    },
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Set This Exact Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
