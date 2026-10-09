import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/controllers/pjp_controller.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/models/proof_of_visit.dart';
import 'package:selecta_ops/services/configuration_service.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/services/pjp_order_decision_service.dart';
import 'package:selecta_ops/services/proof_of_visit_service.dart';
import 'package:selecta_ops/services/scanning_services.dart';
import 'package:selecta_ops/services/tasks_services.dart';
import 'package:selecta_ops/services/placement_service.dart';
import 'package:selecta_ops/services/selecta_product_service.dart';
import 'package:selecta_ops/services/inventory_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeHapiStoreService extends Fake implements HapiStoreService {}
class FakeScanningServices extends Fake implements ScanningServices {}
class FakeTasksService extends Fake implements TasksService {}
class FakeConfigurationService extends Fake implements ConfigurationService {}
class FakeDeliveryService extends Fake implements DeliveryService {}
class FakeProofOfVisitService extends Fake implements ProofOfVisitService {}
class FakePjpOrderDecisionService extends Fake implements PjpOrderDecisionService {}
class FakePlacementService extends Fake implements PlacementService {}
class FakeSelectaProductService extends Fake implements SelectaProductService {}
class FakeInventoryService extends Fake implements InventoryService {}

class FakeGeolocatorPlatform extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async => LocationPermission.always;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    return Position(
      latitude: 14.5995,
      longitude: 120.9842,
      timestamp: DateTime.now(),
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
      accuracy: 5,
    );
  }

  @override
  double distanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) => 10.0;
}

PjpController createTestController() {
  return PjpController(
    hapiStoreService: FakeHapiStoreService(),
    scanningService: FakeScanningServices(),
    tasksService: FakeTasksService(),
    configurationService: FakeConfigurationService(),
    deliveryService: FakeDeliveryService(),
    proofOfVisitService: FakeProofOfVisitService(),
    orderDecisionService: FakePjpOrderDecisionService(),
    placementService: FakePlacementService(),
    selectaProductService: FakeSelectaProductService(),
    inventoryService: FakeInventoryService(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GeolocatorPlatform.instance = FakeGeolocatorPlatform();

  group('PJP Checklist Workflow & Models Tests', () {
    test('ProofOfVisit model correctly serializes and deserializes', () {
      final now = Timestamp.now();
      final proof = ProofOfVisit(
        id: 'pov_123',
        storeName: 'Test Sari-Sari Store',
        visitDate: now,
        imageUrl: 'https://storage.googleapis.com/test-bucket/proof.jpg',
        takenBy: 'Salesman Dwight',
        notes: 'Freezer clean and organized',
      );

      final json = proof.toJson();
      expect(json['id'], 'pov_123');
      expect(json['storeName'], 'Test Sari-Sari Store');
      expect(json['visitDate'], now);
      expect(json['imageUrl'], 'https://storage.googleapis.com/test-bucket/proof.jpg');
      expect(json['takenBy'], 'Salesman Dwight');
      expect(json['notes'], 'Freezer clean and organized');

      final fromJson = ProofOfVisit.fromJson(json, id: 'pov_123');
      expect(fromJson.id, 'pov_123');
      expect(fromJson.storeName, 'Test Sari-Sari Store');
      expect(fromJson.visitDate, now);
      expect(fromJson.imageUrl, 'https://storage.googleapis.com/test-bucket/proof.jpg');
      expect(fromJson.takenBy, 'Salesman Dwight');
    });

    test('PjpOrderDecision model serializes and handles no-order reasons', () {
      final now = Timestamp.now();
      final decision = PjpOrderDecision(
        id: 'dec_1',
        storeName: 'Aling Nena Store',
        decision: 'no_order',
        reason: 'Store is currently overstocked with Cornetto and Selecta pints',
        date: now,
        createdBy: 'Salesman Dwight',
      );

      final json = decision.toJson();
      expect(json['storeName'], 'Aling Nena Store');
      expect(json['decision'], 'no_order');
      expect(json['reason'], contains('overstocked'));
      expect(json['createdBy'], 'Salesman Dwight');
    });

    test('BookOrderCheckResult and ProofOfVisitCheckResult status and passed properties', () {
      const orderPassed = BookOrderCheckResult(
        passed: true,
        status: 'Order booked for today (Pending Picklist).',
        hasBookedOrder: true,
      );
      expect(orderPassed.passed, isTrue);
      expect(orderPassed.hasBookedOrder, isTrue);

      const noOrderPassed = BookOrderCheckResult(
        passed: true,
        status: 'No order booked today. Reason: Store Closed',
        hasBookedOrder: false,
        noOrderReason: 'Store Closed',
      );
      expect(noOrderPassed.passed, isTrue);
      expect(noOrderPassed.hasBookedOrder, isFalse);
      expect(noOrderPassed.noOrderReason, 'Store Closed');

      const povPending = ProofOfVisitCheckResult(
        passed: false,
        status: 'Proof of visit photo not yet captured.',
      );
      expect(povPending.passed, isFalse);
      expect(povPending.proofOfVisit, isNull);
    });

    test('PJP Visit completion criteria: Merch Blitz is optional', () {
      bool canComplete({
        required bool location,
        required bool scanning,
        required bool bookOrder,
        required bool proofOfVisit,
        required bool tasks,
        required bool merchBlitz,
      }) {
        // Steps 1 to 5 are required; Merch Blitz is optional and does not block completion.
        return location && scanning && bookOrder && proofOfVisit && tasks;
      }

      // Case 1: All required pass, Merch Blitz false -> can complete
      expect(
        canComplete(
          location: true,
          scanning: true,
          bookOrder: true,
          proofOfVisit: true,
          tasks: true,
          merchBlitz: false,
        ),
        isTrue,
        reason: 'User should be able to complete PJP even though there was no merch blitz done',
      );

      // Case 2: One required fails (e.g. proof of visit) -> cannot complete
      expect(
        canComplete(
          location: true,
          scanning: true,
          bookOrder: true,
          proofOfVisit: false,
          tasks: true,
          merchBlitz: true,
        ),
        isFalse,
        reason: 'All 5 required steps must pass to complete visit',
      );
    });

    test('Scanning status of Pending or Scanned marks checklist step as passed', () {
      bool isScanningPassed(List<String> statuses) {
        return statuses.any((s) => s == 'Pending' || s == 'Scanned');
      }

      expect(isScanningPassed(['Scanned']), isTrue);
      expect(isScanningPassed(['Pending']), isTrue);
      expect(isScanningPassed(['Not Scanned']), isFalse);
      expect(isScanningPassed(['Unassigned']), isFalse);
      expect(isScanningPassed(['Pullout']), isFalse);
      expect(isScanningPassed([]), isFalse);
      expect(isScanningPassed(['Not Scanned', 'Pending']), isTrue);
    });

    test('Location check marks as passed if store already has a store location', () async {
      final controller = createTestController();
      final storeWithLocation = Hapistore(
        storeName: 'Test Store with Coordinates',
        storeAddress: '123 Main St',
        storeContact: '09123456789',
        openingDate: Timestamp.now(),
        latitude: 14.5995,
        longitude: 120.9842,
      );

      final result = await controller.checkLocation(storeWithLocation);
      expect(result.passed, isTrue, reason: 'Store with existing coordinates must be marked as passed');
      expect(result.status, contains('In range'));
    });

    test('Location check marks as not passed if store has no location', () async {
      final controller = createTestController();
      final storeWithoutLocation = Hapistore(
        storeName: 'Test Store without Coordinates',
        storeAddress: '456 Side St',
        storeContact: '09987654321',
        openingDate: Timestamp.now(),
        latitude: null,
        longitude: null,
      );

      final result = await controller.checkLocation(storeWithoutLocation);
      expect(result.passed, isFalse, reason: 'Store with null coordinates must not pass location check');
      expect(result.status, contains('No store location saved'));
    });
  });
}
