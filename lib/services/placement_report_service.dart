import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/placement_report_models.dart';
import 'package:selecta_ops/models/selecta_product.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/services/placement_report_builder.dart';
import 'package:selecta_ops/services/placement_service.dart';
import 'package:selecta_ops/services/product_catalog_cache.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';

/// Data orchestration and aggregation service for the Monthly Placement Report.
class PlacementReportService {
  final FirebaseFirestore? _customFirestore;
  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;
  final SelectaProductService _selectaProductService;
  final ProductCatalogCache _catalogCache;

  PlacementReportService({
    FirebaseFirestore? firestore,
    SelectaProductService? selectaProductService,
    ProductCatalogCache? catalogCache,
  })  : _customFirestore = firestore,
        _selectaProductService = selectaProductService ?? SelectaProductService(),
        _catalogCache = catalogCache ?? ProductCatalogCache();

  /// Loads, filters, and structures all data required to generate the Monthly Placement Report.
  ///
  /// Throws [StateError] if caller is not a Dealer/Admin, or if no Best Seller products exist.
  Future<PlacementReportData> loadReportData({
    required DateTime month,
    required Set<String> selectedDays,
  }) async {
    // 1. Role verification (defense-in-depth)
    final isDealer = await KVariables.getIsDealer();
    if (!isDealer) {
      throw StateError('Access denied: Monthly Placement Report is restricted to Dealers and Admins.');
    }

    if (selectedDays.isEmpty) {
      throw ArgumentError('At least one PJP day must be selected.');
    }

    // 2. Fetch Best Sellers and placement pairs
    final bestSellers = await _selectaProductService.getBestSellerProducts();
    if (bestSellers.isEmpty) {
      throw StateError('No active Best Seller products found in catalog.');
    }

    final config = await ConfigurationService().getConfiguration();
    final pairs = config.placementPairs;

    // 3. Build sorted columns
    final columns = PlacementReportBuilder.buildColumns(
      bestSellers: bestSellers,
      pairs: pairs,
    );

    // 4. Fetch all stores
    final allStores = await HapiStoreService.getListHapiStores();

    // 5. Fetch placements within the specified month
    final placements = await PlacementService.getListOfPlacementsWithinCurrentMonth(month);
    final placementsByStore = {
      for (final p in placements) p.storeName: p,
    };

    // 6. Fetch delivered orders for the month and resolve stores with New Product orders
    final deliveredOrders = await _fetchDeliveredOrdersForMonth(month);
    final allSelecta = await _catalogCache.getSelectaProducts();
    final productTagsById = {
      for (final p in allSelecta) p.id: p.tag,
    };

    final storesWithNewProduct = PlacementReportBuilder.findStoresWithNewProductOrders(
      deliveries: deliveredOrders,
      productTagsById: productTagsById,
    );

    // 7. Active products tagged as New Product for header thumbnails
    final newProducts = allSelecta
        .where((p) => p.isActive && ProductTag.isNewProduct(p.tag))
        .toList()
      ..sort(PlacementReportBuilder.compareReportProducts);

    // 8. Build sections per picked PJP day (preserving Monday..Sunday order)
    final sections = <PlacementReportDaySection>[];
    for (final day in PjpScheduleDays.all) {
      if (!selectedDays.contains(day)) continue;

      final dayStores = allStores
          .where((s) => (s.pjpSchedule?.trim().toLowerCase() ?? '') == day.toLowerCase())
          .toList();

      final sortedDayStores = PlacementReportBuilder.sortStoresForDay(dayStores);

      final rows = PlacementReportBuilder.buildRows(
        stores: sortedDayStores,
        columns: columns,
        placementsByStore: placementsByStore,
        pairs: pairs,
        storesWithNewProduct: storesWithNewProduct,
      );

      final section = PlacementReportBuilder.buildDaySection(
        day: day,
        rows: rows,
        columns: columns,
      );

      sections.add(section);
    }

    // 9. Summary & cover statistics
    final totalScheduledStores = allStores
        .where((s) => s.pjpSchedule != null && s.pjpSchedule!.trim().isNotEmpty)
        .length;
    final unscheduledStoresCount = allStores.length - totalScheduledStores;

    final summary = PlacementReportBuilder.buildSummary(
      sections: sections,
      columns: columns,
      totalStoresOverall: allStores.length,
      totalScheduledStores: totalScheduledStores,
      unscheduledStoresCount: unscheduledStoresCount,
    );

    // 10. Pitch List
    final pitchList = PlacementReportBuilder.buildPitchList(
      sections: sections,
      columns: columns,
    );

    // 11. Company/Dealer branding
    final user = await KVariables.getUser();
    final companyName = (user?.dealerName.trim().isNotEmpty ?? false)
        ? user!.dealerName.trim()
        : 'SELECTA DISTRIBUTION DEALER';

    // Filter selected days in standard day order
    final orderedSelectedDays = PjpScheduleDays.all.where(selectedDays.contains).toList();

    return PlacementReportData(
      month: month,
      companyName: companyName,
      selectedDays: orderedSelectedDays,
      columns: columns,
      sections: sections,
      summary: summary,
      pitchList: pitchList,
      newProducts: newProducts,
      generatedDate: DateTime.now(),
    );
  }

  /// Queries delivered orders within the specified month boundary.
  Future<List<Delivery>> _fetchDeliveredOrdersForMonth(DateTime month) async {
    final startOfMonth = DateTime(month.year, month.month, 1);
    final startOfNextMonth = DateTime(month.year, month.month + 1, 1);

    try {
      final snapshot = await _firestore
          .collection(DELIVERY_COLLECTION_REF)
          .where(DeliveryModelString.deliveryDate, isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .where(DeliveryModelString.deliveryDate, isLessThan: Timestamp.fromDate(startOfNextMonth))
          .get();

      return snapshot.docs
          .map((doc) => Delivery.fromJson(doc.data()))
          .where((d) => d.transactionStatus == DeliveryStatus.delivered)
          .toList();
    } catch (_) {
      // Fallback in case of missing index on deliveryDate
      try {
        final snapshot = await _firestore
            .collection(DELIVERY_COLLECTION_REF)
            .where(DeliveryModelString.transactionStatus, isEqualTo: DeliveryStatus.delivered)
            .get();

        return snapshot.docs
            .map((doc) => Delivery.fromJson(doc.data()))
            .where((d) {
              final date = d.deliveryDate?.toDate() ?? d.createdDate.toDate();
              return !date.isBefore(startOfMonth) && date.isBefore(startOfNextMonth);
            })
            .toList();
      } catch (_) {
        return const [];
      }
    }
  }
}
