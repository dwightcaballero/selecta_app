import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/configuration.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/configuration_service.dart';
import 'package:flutter_app/services/hapistore_service.dart';

/// Available sorting options for Merch Blitz store listings.
enum StoreSortOption {
  nameAsc('Name (A - Z)'),
  nameDesc('Name (Z - A)'),
  openingDateDesc('Opening Date (Newest)'),
  openingDateAsc('Opening Date (Oldest)'),
  surveyDateDesc('Survey Date (Latest)');

  final String label;
  const StoreSortOption(this.label);
}

/// Controller responsible for managing Merch Blitz campaigns,
/// store merchandising survey workflows, role permissions, and status transitions.
class MerchBlitzController {
  final ConfigurationService _configService;
  final HapiStoreService _hapiStoreService;

  MerchBlitzController({
    ConfigurationService? configService,
    HapiStoreService? hapiStoreService,
  })  : _configService = configService ?? ConfigurationService(),
        _hapiStoreService = hapiStoreService ?? HapiStoreService();

  /// Checks if the logged-in user is a dealer.
  Future<bool> checkIsDealer() async {
    return await KVariables.getIsDealer();
  }

  /// Real-time stream of configuration settings (including Merch Blitz campaign window).
  Stream<Configuration?> getConfigurationStream() {
    return _configService.getConfigurationStream();
  }

  /// Real-time stream of all stores.
  Stream<QuerySnapshot> getStoresStream() {
    return _hapiStoreService.getListHapiStoresAsStream();
  }

  /// Determines whether today falls within the promotional blitz date range.
  bool isTodayInBlitz(DateTime start, DateTime end) {
    final now = DateTime.now();
    final s = DateTime(start.year, start.month, start.day, 0, 0, 0);
    final e = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    return !now.isBefore(s) && !now.isAfter(e);
  }

  /// Filters store snapshots by tab index, role visibility, and search keyword,
  /// then applies the chosen sorting comparator.
  List<QueryDocumentSnapshot> filterAndSortStores({
    required List<QueryDocumentSnapshot> docs,
    required DateTime startDate,
    required DateTime endDate,
    required int selectedTabIndex,
    required bool isDealer,
    required String searchQuery,
    required StoreSortOption sortOption,
  }) {
    final query = searchQuery.trim().toLowerCase();

    final filtered = docs.where((doc) {
      final raw = doc.data();
      final store = raw is Hapistore ? raw : Hapistore.fromJson(raw as Map<String, Object?>);
      final storeStatus = store.getMerchBlitzStatus(startDate, endDate);

      // Non-dealers only see Pending Survey
      final targetTabIndex = isDealer ? selectedTabIndex : 0;

      if (targetTabIndex == 0 && storeStatus != MerchBlitzStatus.pendingSurvey) return false;
      if (targetTabIndex == 1 && storeStatus != MerchBlitzStatus.forFinalSurvey) return false;
      if (targetTabIndex == 2 && storeStatus != MerchBlitzStatus.surveyed) return false;

      if (query.isNotEmpty) {
        final name = store.storeName.toLowerCase();
        final address = store.storeAddress.toLowerCase();
        final contact = store.storeContact.toLowerCase();
        if (!name.contains(query) && !address.contains(query) && !contact.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();

    filtered.sort((a, b) {
      final rawA = a.data();
      final rawB = b.data();
      final storeA = rawA is Hapistore ? rawA : Hapistore.fromJson(rawA as Map<String, Object?>);
      final storeB = rawB is Hapistore ? rawB : Hapistore.fromJson(rawB as Map<String, Object?>);

      switch (sortOption) {
        case StoreSortOption.nameAsc:
          return storeA.storeName.toLowerCase().compareTo(storeB.storeName.toLowerCase());
        case StoreSortOption.nameDesc:
          return storeB.storeName.toLowerCase().compareTo(storeA.storeName.toLowerCase());
        case StoreSortOption.openingDateDesc:
          final dateA = storeA.openingDate?.toDate() ?? DateTime(1970);
          final dateB = storeB.openingDate?.toDate() ?? DateTime(1970);
          return dateB.compareTo(dateA);
        case StoreSortOption.openingDateAsc:
          final dateA = storeA.openingDate?.toDate() ?? DateTime(2099);
          final dateB = storeB.openingDate?.toDate() ?? DateTime(2099);
          return dateA.compareTo(dateB);
        case StoreSortOption.surveyDateDesc:
          final dateA = storeA.lastMerchBlitzDate?.toDate() ?? DateTime(1970);
          final dateB = storeB.lastMerchBlitzDate?.toDate() ?? DateTime(1970);
          return dateB.compareTo(dateA);
      }
    });

    return filtered;
  }

  /// Calculates counts for each Merch Blitz status category across all stores.
  ({int pending, int forFinal, int surveyed}) calculateStatusCounts({
    required List<QueryDocumentSnapshot> docs,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    int pending = 0;
    int forFinal = 0;
    int surveyed = 0;

    for (final doc in docs) {
      final raw = doc.data();
      final store = raw is Hapistore ? raw : Hapistore.fromJson(raw as Map<String, Object?>);
      final status = store.getMerchBlitzStatus(startDate, endDate);

      if (status == MerchBlitzStatus.pendingSurvey) {
        pending++;
      } else if (status == MerchBlitzStatus.forFinalSurvey) {
        forFinal++;
      } else if (status == MerchBlitzStatus.surveyed) {
        surveyed++;
      }
    }

    return (pending: pending, forFinal: forFinal, surveyed: surveyed);
  }

  // ==========================================
  // Survey Status Transitions
  // ==========================================

  /// Submits a salesman survey for dealer review.
  Future<void> submitForFinalSurvey(String storeId) async {
    await _hapiStoreService.updateMerchBlitzStatus(
      storeId,
      status: MerchBlitzStatus.forFinalSurvey,
      timestamp: Timestamp.now(),
    );
  }

  /// Approves a store survey as completely surveyed.
  Future<void> approveFinalSurvey(String storeId) async {
    await _hapiStoreService.updateMerchBlitzStatus(
      storeId,
      status: MerchBlitzStatus.surveyed,
      timestamp: Timestamp.now(),
    );
  }

  /// Reverts a store survey back to Pending Survey status.
  Future<void> revertToPending(String storeId) async {
    await _hapiStoreService.updateMerchBlitzStatus(
      storeId,
      status: MerchBlitzStatus.pendingSurvey,
      timestamp: null,
    );
  }

  /// Moves a surveyed store back to For Final Survey status.
  Future<void> revertToFinalSurvey(String storeId, [Timestamp? existingTimestamp]) async {
    await _hapiStoreService.updateMerchBlitzStatus(
      storeId,
      status: MerchBlitzStatus.forFinalSurvey,
      timestamp: existingTimestamp ?? Timestamp.now(),
    );
  }
}
