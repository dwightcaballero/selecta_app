import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Recency / Freshness tiers for route tracking
enum RecencyTier {
  live(
    label: 'Live / Active Now',
    color: Color(0xFF10B981), // Emerald
    badgeBg: Color(0x2610B981),
  ),
  fresh(
    label: 'Recent (< 30 days)',
    color: Color(0xFF0284C7), // Blue
    badgeBg: Color(0x260284C7),
  ),
  aging(
    label: 'Aging (1 - 3 months)',
    color: Color(0xFFF59E0B), // Amber
    badgeBg: Color(0x26F59E0B),
  ),
  stale(
    label: 'Due for Re-Scout (> 3 months)',
    color: Color(0xFFEF4444), // Coral Red
    badgeBg: Color(0x26EF4444),
  );

  const RecencyTier({
    required this.label,
    required this.color,
    required this.badgeBg,
  });

  final String label;
  final Color color;
  final Color badgeBg;
}

class ScoutTrackPoint {
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  ScoutTrackPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  LatLng get toLatLng => LatLng(latitude, longitude);

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ScoutTrackPoint.fromJson(Map<String, dynamic> json) => ScoutTrackPoint(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      );
}

class ScoutRouteSession {
  final String id;
  final String salesmanName;
  final String dateString; // YYYY-MM-DD
  final DateTime startedAt;
  final DateTime? endedAt;
  final bool isActive;
  final double distanceMeters;
  final bool needsRescout;
  final String? notes;
  final List<ScoutTrackPoint> points;

  ScoutRouteSession({
    required this.id,
    required this.salesmanName,
    required this.dateString,
    required this.startedAt,
    this.endedAt,
    this.isActive = true,
    this.distanceMeters = 0.0,
    this.needsRescout = false,
    this.notes,
    required this.points,
  });

  List<LatLng> get polylinePoints => points.map((p) => p.toLatLng).toList();

  RecencyTier get recencyTier {
    if (isActive) return RecencyTier.live;
    final ageDays = DateTime.now().difference(startedAt).inDays;
    if (ageDays < 30) return RecencyTier.fresh;
    if (ageDays <= 90) return RecencyTier.aging;
    return RecencyTier.stale;
  }

  String get ageLabel {
    if (isActive) return 'Active Now';
    final diff = DateTime.now().difference(startedAt);
    if (diff.inDays <= 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 30) return '${diff.inDays} days ago';
    final months = (diff.inDays / 30).floor();
    if (months == 1) return '1 month ago';
    if (months < 3) return '$months months ago';
    return '$months mos ago (Due for Re-Scout)';
  }

  Duration get duration {
    final end = endedAt ?? DateTime.now();
    return end.difference(startedAt);
  }

  String get formattedDuration {
    final d = duration;
    final hours = d.inHours;
    final mins = d.inMinutes % 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  String get formattedDistance {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(2)} km';
    }
    return '${distanceMeters.toStringAsFixed(0)} m';
  }

  Map<String, dynamic> toJson() => {
        'salesmanName': salesmanName,
        'dateString': dateString,
        'startedAt': Timestamp.fromDate(startedAt),
        'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
        'isActive': isActive,
        'distanceMeters': distanceMeters,
        'needsRescout': needsRescout,
        'notes': notes,
        'points': points.map((p) => p.toJson()).toList(),
      };

  factory ScoutRouteSession.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final rawPoints = data['points'] as List<dynamic>? ?? [];
    final pointsList = rawPoints
        .map((p) => ScoutTrackPoint.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();

    return ScoutRouteSession(
      id: doc.id,
      salesmanName: data['salesmanName'] as String? ?? 'Salesman',
      dateString: data['dateString'] as String? ?? '',
      startedAt: (data['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endedAt: (data['endedAt'] as Timestamp?)?.toDate(),
      isActive: data['isActive'] as bool? ?? false,
      distanceMeters: (data['distanceMeters'] as num?)?.toDouble() ?? 0.0,
      needsRescout: data['needsRescout'] as bool? ?? false,
      notes: data['notes'] as String?,
      points: pointsList,
    );
  }
}
