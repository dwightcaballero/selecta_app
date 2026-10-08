import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Follow-up conversion pipeline statuses for a scouted prospect
class ProspectStatus {
  static const String scouted = 'Scouted';
  static const String engaged = 'Engaged';
  static const String converted = 'Converted';

  static const List<String> all = [scouted, engaged, converted];

  static Color statusColor(String? status) {
    switch (status) {
      case engaged:
        return const Color(0xFFF59E0B); // Amber / In discussion
      case converted:
        return const Color(0xFF10B981); // Green / Deal closed (became Hapi Store)
      case scouted:
      default:
        return const Color(0xFF64748B); // Slate / Scouted
    }
  }

  static IconData statusIcon(String? status) {
    switch (status) {
      case engaged:
        return Icons.handshake_outlined;
      case converted:
        return Icons.check_circle_outline;
      case scouted:
      default:
        return Icons.explore_outlined;
    }
  }
}

/// 5 competitor brand colors recognized in the field
class CompetitorBrandColor {
  static const String blue = 'Blue';
  static const String pink = 'Pink';
  static const String green = 'Green';
  static const String yellow = 'Yellow';
  static const String white = 'White';

  static const List<String> all = [blue, pink, green, yellow, white];

  static Color toColor(String name) {
    switch (name.trim().toLowerCase()) {
      case 'blue':
        return const Color(0xFF2563EB);
      case 'pink':
        return const Color(0xFFEC4899);
      case 'green':
        return const Color(0xFF10B981);
      case 'yellow':
        return const Color(0xFFF59E0B);
      case 'white':
        return const Color(0xFFF8FAFC);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  static Color toTextColor(String name) {
    if (name.trim().toLowerCase() == 'white') {
      return const Color(0xFF1E293B);
    }
    return Colors.white;
  }
}

/// Data model representing a prospect or potential new store client scouted in the field.
class ProspectScout {
  String? id;
  String storeName;
  double latitude;
  double longitude;
  bool isAccessible;
  bool isStoreBig;
  bool hasCompetitorFreezer;
  List<String> competitorColors;
  String status;
  String? notes;
  String? contactPerson;
  String? contactPhone;
  String? imageUrl;
  String? scoutedBy;
  Timestamp? createdAt;
  Timestamp? updatedAt;

  ProspectScout({
    this.id,
    required this.storeName,
    required this.latitude,
    required this.longitude,
    required this.isAccessible,
    required this.isStoreBig,
    required this.hasCompetitorFreezer,
    required this.competitorColors,
    required this.status,
    this.notes,
    this.contactPerson,
    this.contactPhone,
    this.imageUrl,
    this.scoutedBy,
    this.createdAt,
    this.updatedAt,
  });

  static ProspectScout empty() => ProspectScout(
    storeName: '',
    latitude: 0.0,
    longitude: 0.0,
    isAccessible: true,
    isStoreBig: false,
    hasCompetitorFreezer: false,
    competitorColors: [],
    status: ProspectStatus.scouted,
    notes: '',
    contactPerson: '',
    contactPhone: '',
    imageUrl: null,
    scoutedBy: '',
    createdAt: null,
    updatedAt: null,
  );

  /// 0 to 3 potential score based on key assessment questions:
  /// +1 Accessible (good visibility, customers see inside clearly)
  /// +1 Big store (can afford starting capital)
  /// +1 Has competitor freezer (ready market, primed for replacement)
  int get qualityScore {
    int score = 0;
    if (isAccessible) score++;
    if (isStoreBig) score++;
    if (hasCompetitorFreezer) score++;
    return score;
  }

  String get qualityLabel {
    switch (qualityScore) {
      case 3:
        return 'High Potential (3/3)';
      case 2:
        return 'Good Prospect (2/3)';
      case 1:
        return 'Fair Prospect (1/3)';
      default:
        return 'Low Potential (0/3)';
    }
  }

  Color get qualityColor {
    switch (qualityScore) {
      case 3:
        return const Color(0xFF10B981); // Emerald
      case 2:
        return const Color(0xFF0284C7); // Sky blue
      case 1:
        return const Color(0xFFF59E0B); // Amber
      default:
        return const Color(0xFFEF4444); // Red
    }
  }

  factory ProspectScout.fromJson(Map<String, Object?> json, {String? docId}) {
    double lat = 0.0;
    double lng = 0.0;

    if (json['location'] is GeoPoint) {
      final geo = json['location'] as GeoPoint;
      lat = geo.latitude;
      lng = geo.longitude;
    } else {
      lat = (json['latitude'] as num?)?.toDouble() ?? 0.0;
      lng = (json['longitude'] as num?)?.toDouble() ?? 0.0;
    }

    final rawColors = json['competitorColors'];
    List<String> colors = [];
    if (rawColors is List) {
      colors = rawColors.map((e) => e.toString()).toList();
    }

    return ProspectScout(
      id: docId ?? json['id'] as String?,
      storeName: json['storeName'] as String? ?? '',
      latitude: lat,
      longitude: lng,
      isAccessible: json['isAccessible'] as bool? ?? true,
      isStoreBig: json['isStoreBig'] as bool? ?? false,
      hasCompetitorFreezer: json['hasCompetitorFreezer'] as bool? ?? false,
      competitorColors: colors,
      status: json['status'] as String? ?? ProspectStatus.scouted,
      notes: json['notes'] as String?,
      contactPerson: json['contactPerson'] as String?,
      contactPhone: json['contactPhone'] as String?,
      imageUrl: json['imageUrl'] as String?,
      scoutedBy: json['scoutedBy'] as String?,
      createdAt: json['createdAt'] as Timestamp?,
      updatedAt: json['updatedAt'] as Timestamp?,
    );
  }

  factory ProspectScout.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? {};
    return ProspectScout.fromJson(data, docId: snapshot.id);
  }

  Map<String, Object?> toJson() {
    return {
      'storeName': storeName.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'location': GeoPoint(latitude, longitude),
      'isAccessible': isAccessible,
      'isStoreBig': isStoreBig,
      'hasCompetitorFreezer': hasCompetitorFreezer,
      'competitorColors': competitorColors,
      'status': status,
      'notes': notes?.trim(),
      'contactPerson': contactPerson?.trim(),
      'contactPhone': contactPhone?.trim(),
      'imageUrl': imageUrl,
      'scoutedBy': scoutedBy,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
