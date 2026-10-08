import 'package:flutter/material.dart';

/// Available map tile styles for territory and location scouting
enum MapTileStyle {
  standard(
    id: 'standard',
    label: 'Standard',
    icon: Icons.map_outlined,
    url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    description: 'Detailed OpenStreetMap view with streets and labels',
  ),
  satellite(
    id: 'satellite',
    label: 'Satellite',
    icon: Icons.satellite_alt_outlined,
    url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    description: 'High-res satellite aerial imagery to see rooftops and stores',
    isDark: true,
  ),
  roads(
    id: 'roads',
    label: 'Roads Only',
    icon: Icons.alt_route_rounded,
    url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
    description: 'High-contrast street and highway network',
  ),
  voyager(
    id: 'voyager',
    label: 'Clean Navigation',
    icon: Icons.navigation_outlined,
    url: 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
    description: 'Clean cartographic style highlighting streets and routes',
  );

  const MapTileStyle({
    required this.id,
    required this.label,
    required this.icon,
    required this.url,
    required this.description,
    this.isDark = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final String url;
  final String description;
  final bool isDark;

  static MapTileStyle fromId(String? id) {
    return MapTileStyle.values.firstWhere(
      (s) => s.id == id,
      orElse: () => MapTileStyle.standard,
    );
  }
}
