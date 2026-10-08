import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/prospect_scout.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/services/prospect_scout_service.dart';

class ProspectScoutController {
  final ProspectScoutService _service = ProspectScoutService();

  Stream<List<ProspectScout>> getProspectsStream() {
    return _service.getProspectScoutsStream();
  }

  Future<List<ProspectScout>> getAllProspects() {
    return _service.getAllProspectScouts();
  }

  Future<String> saveProspect(ProspectScout scout) async {
    final user = await getCurrentUser();
    if (scout.scoutedBy == null || scout.scoutedBy!.isEmpty) {
      scout.scoutedBy = user?.username ?? 'Salesman';
    }
    return await _service.addProspectScout(scout);
  }

  Future<void> updateProspect(String id, ProspectScout scout) async {
    return await _service.updateProspectScout(id, scout);
  }

  Future<void> deleteProspect(String id) async {
    return await _service.deleteProspectScout(id);
  }

  Future<void> updateStatus(String id, String status) async {
    return await _service.updateProspectStatus(id, status);
  }

  /// Converts a scouted prospect into an active Selecta Hapi Store
  Future<void> convertToHapiStore({
    required ProspectScout prospect,
    required String storeAddress,
    String? pjpSchedule,
  }) async {
    final hapiStore = Hapistore(
      storeName: prospect.storeName,
      storeAddress: storeAddress,
      storeContact: prospect.contactPhone ?? '',
      openingDate: Timestamp.now(),
      pjpSchedule: pjpSchedule,
      latitude: prospect.latitude != 0.0 ? prospect.latitude : null,
      longitude: prospect.longitude != 0.0 ? prospect.longitude : null,
    );

    HapiStoreService().addHapiStore(hapiStore);

    if (prospect.id != null) {
      await updateStatus(prospect.id!, ProspectStatus.converted);
    }
  }

  Future<Users?> getCurrentUser() => KVariables.getUser();

  Future<bool> isCurrentUserDealer() => KVariables.getIsDealer();

  /// Fetches existing Hapi Stores for overlaying on the map
  Future<List<Hapistore>> getHapiStores() async {
    return await HapiStoreService.getListHapiStores();
  }

  /// Request current GPS location
  Future<Position> getCurrentLocation() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable GPS.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission was denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permissions are permanently denied. Please enable them in app settings.',
      );
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /// Distance helper
  static double calculateDistanceInMeters(double startLat, double startLng, double endLat, double endLng) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }

  /// Format distance to readable string: e.g. "150 m" or "1.8 km"
  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    } else {
      final km = meters / 1000;
      return '${km.toStringAsFixed(1)} km';
    }
  }

  /// Filter prospects by search query, status, competitor presence, and sorting
  List<ProspectScout> filterProspects({
    required List<ProspectScout> prospects,
    required String query,
    required String statusFilter,
    required String competitorFilter,
    String sortBy = 'Newest',
    Position? currentPosition,
  }) {
    final filtered = prospects.where((item) {
      // 1. Status Filter
      if (statusFilter != 'All' && item.status.toLowerCase() != statusFilter.toLowerCase()) {
        return false;
      }

      // 2. Competitor Filter
      if (competitorFilter == 'With Competitors' && !item.hasCompetitorFreezer) {
        return false;
      } else if (competitorFilter == 'No Competitor' && item.hasCompetitorFreezer) {
        return false;
      } else if (CompetitorBrandColor.all.contains(competitorFilter)) {
        if (!item.competitorColors.contains(competitorFilter)) {
          return false;
        }
      }

      // 3. Search query
      if (query.trim().isNotEmpty) {
        final q = query.trim().toLowerCase();
        final nameMatch = item.storeName.toLowerCase().contains(q);
        final notesMatch = (item.notes ?? '').toLowerCase().contains(q);
        final scoutedByMatch = (item.scoutedBy ?? '').toLowerCase().contains(q);
        final contactPersonMatch = (item.contactPerson ?? '').toLowerCase().contains(q);
        final contactPhoneMatch = (item.contactPhone ?? '').toLowerCase().contains(q);
        if (!nameMatch && !notesMatch && !scoutedByMatch && !contactPersonMatch && !contactPhoneMatch) {
          return false;
        }
      }

      return true;
    }).toList();

    // 4. Sort
    switch (sortBy) {
      case 'Nearest':
        if (currentPosition != null) {
          filtered.sort((a, b) {
            final hasA = a.latitude != 0.0 && a.longitude != 0.0;
            final hasB = b.latitude != 0.0 && b.longitude != 0.0;
            if (!hasA && !hasB) return 0;
            if (!hasA) return 1;
            if (!hasB) return -1;
            final distA = Geolocator.distanceBetween(currentPosition.latitude, currentPosition.longitude, a.latitude, a.longitude);
            final distB = Geolocator.distanceBetween(currentPosition.latitude, currentPosition.longitude, b.latitude, b.longitude);
            return distA.compareTo(distB);
          });
        }
        break;
      case 'Potential':
        filtered.sort((a, b) => b.qualityScore.compareTo(a.qualityScore));
        break;
      case 'Name':
        filtered.sort((a, b) => a.storeName.toLowerCase().compareTo(b.storeName.toLowerCase()));
        break;
      case 'Newest':
      default:
        filtered.sort((a, b) {
          final tA = a.createdAt?.millisecondsSinceEpoch ?? 0;
          final tB = b.createdAt?.millisecondsSinceEpoch ?? 0;
          return tB.compareTo(tA);
        });
        break;
    }

    return filtered;
  }
}
