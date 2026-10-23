import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/controllers/van_load_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/inventory_movement.dart';
import 'package:selecta_ops/models/van_load.dart';
import 'package:selecta_ops/services/inventory_service.dart';
import 'package:selecta_ops/services/van_load_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockVanLoadService extends Fake implements VanLoadService {
  final Map<String, VanLoad> store = {};
  int updateCallCount = 0;

  @override
  Future<void> updateVanLoad(String id, VanLoad vanLoad) async {
    updateCallCount++;
    store[id] = vanLoad;
  }
}

class MockInventoryService extends Fake implements InventoryService {
  int deductCallCount = 0;
  int adjustCallCount = 0;
  List<VanLoadItem> lastDeductedItems = [];
  List<VanLoadItem> lastOldAdjustedItems = [];
  List<VanLoadItem> lastNewAdjustedItems = [];

  @override
  Future<void> deductVanLoadInventory({
    required String vanLoadId,
    required List<VanLoadItem> items,
    String? driverName,
  }) async {
    deductCallCount++;
    lastDeductedItems = items;
  }

  @override
  Future<void> adjustVanLoadInventory({
    required String vanLoadId,
    required List<VanLoadItem> oldItems,
    required List<VanLoadItem> newItems,
    String? driverName,
  }) async {
    adjustCallCount++;
    lastOldAdjustedItems = oldItems;
    lastNewAdjustedItems = newItems;
  }
}

void mockCurrentUserRole(String role) {
  SharedPreferences.setMockInitialValues({
    'user_data': jsonEncode({
      'username': 'test_user',
      'email': 'user@selecta.com',
      'role': role,
      'dealerName': 'Selecta Main Dealer',
      'dailyRate': 500.0,
    }),
  });
}

VanLoad createTestLoad({
  String? id,
  String status = VanLoadStatus.draft,
  List<VanLoadItem> items = const [],
  String remarks = '',
  String imagePath = '',
  bool isStockDeducted = false,
  bool isStockSettled = false,
  double totalLoadedAmount = 0.0,
  double totalSoldAmount = 0.0,
}) {
  final now = Timestamp.now();
  return VanLoad(
    id: id,
    date: now,
    status: status,
    items: items,
    remarks: remarks,
    imagePath: imagePath,
    totalLoadedAmount: totalLoadedAmount,
    totalSoldAmount: totalSoldAmount,
    isStockDeducted: isStockDeducted,
    isStockSettled: isStockSettled,
    createdDate: now,
    createdBy: 'Dealer User',
    lastUpdatedDate: now,
    lastUpdatedBy: 'Dealer User',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = Timestamp.now();

  group('VanLoad Model Proof of Load & Serialization', () {
    test('imagePath serialization and hasProofOfLoad getter', () {
      final item = VanLoadItem(
        productId: 'prod_1',
        productName: 'Cornetto Choc',
        category: 'By Piece',
        productSource: 'selecta',
        loadedQuantity: 10,
        buyingPrice: 20,
        sellingPrice: 25,
      );

      final loadWithProof = createTestLoad(
        id: 'load_1',
        items: [item],
        imagePath: 'https://storage.googleapis.com/test_van_load.jpg',
      );
      expect(loadWithProof.hasProofOfLoad, isTrue);
      expect(loadWithProof.imagePath, 'https://storage.googleapis.com/test_van_load.jpg');

      final json = loadWithProof.toJson();
      expect(json[VanLoadModelString.imagePath], 'https://storage.googleapis.com/test_van_load.jpg');

      final parsed = VanLoad.fromJson(json, 'load_1');
      expect(parsed.imagePath, 'https://storage.googleapis.com/test_van_load.jpg');
      expect(parsed.hasProofOfLoad, isTrue);

      final loadWithoutProof = createTestLoad(
        id: 'load_2',
        items: [item],
        imagePath: '   ',
      );
      expect(loadWithoutProof.hasProofOfLoad, isFalse);
    });

    test('VanLoad.fromJson supports legacy proofImageUrl field', () {
      final json = {
        'date': now,
        'createdDate': now,
        'createdBy': 'Dealer',
        'lastUpdatedDate': now,
        'lastUpdatedBy': 'Dealer',
        'status': 'loaded',
        'items': [],
        'proofImageUrl': 'https://legacy.img/van.png',
      };
      final parsed = VanLoad.fromJson(json, 'legacy_load');
      expect(parsed.imagePath, 'https://legacy.img/van.png');
      expect(parsed.hasProofOfLoad, isTrue);
    });
  });

  group('VanLoadController Creation Requires Proof of Van Load', () {
    late MockVanLoadService mockVanLoadService;
    late MockInventoryService mockInventoryService;
    late VanLoadController controller;

    setUp(() {
      mockVanLoadService = MockVanLoadService();
      mockInventoryService = MockInventoryService();
      controller = VanLoadController(
        vanLoadService: mockVanLoadService,
        inventoryService: mockInventoryService,
      );
    });

    test('confirmAndLoadVan throws ArgumentError when imagePath is empty', () async {
      final loadWithoutProof = createTestLoad(
        id: 'load_no_proof',
        status: VanLoadStatus.draft,
        items: [
          VanLoadItem(
            productId: 'p1',
            productName: 'Magnum Almond',
            category: 'By Piece',
            productSource: 'selecta',
            loadedQuantity: 20,
            buyingPrice: 50,
            sellingPrice: 60,
          ),
        ],
        imagePath: '',
      );

      expect(
        () => controller.confirmAndLoadVan(vanLoad: loadWithoutProof),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Proof of van load photo is required before confirming'),
        )),
      );

      expect(mockInventoryService.deductCallCount, 0);
      expect(mockVanLoadService.updateCallCount, 0);
    });

    test('confirmAndLoadVan succeeds when proof image is present', () async {
      final loadWithProof = createTestLoad(
        id: 'load_valid_proof',
        status: VanLoadStatus.draft,
        items: [
          VanLoadItem(
            productId: 'p1',
            productName: 'Magnum Almond',
            category: 'By Piece',
            productSource: 'selecta',
            loadedQuantity: 20,
            buyingPrice: 50,
            sellingPrice: 60,
          ),
        ],
        imagePath: 'https://storage.googleapis.com/proofs/van_loaded.jpg',
      );

      await controller.confirmAndLoadVan(vanLoad: loadWithProof);

      expect(mockInventoryService.deductCallCount, 1);
      expect(mockInventoryService.lastDeductedItems.length, 1);
      expect(mockVanLoadService.updateCallCount, 1);

      final updated = mockVanLoadService.store['load_valid_proof'];
      expect(updated, isNotNull);
      expect(updated!.status, VanLoadStatus.loaded);
      expect(updated.isStockDeducted, isTrue);
      expect(updated.imagePath, 'https://storage.googleapis.com/proofs/van_loaded.jpg');
    });
  });

  group('VanLoadController Dealer Van Load Record Editing', () {
    late MockVanLoadService mockVanLoadService;
    late MockInventoryService mockInventoryService;
    late VanLoadController controller;

    setUp(() {
      mockVanLoadService = MockVanLoadService();
      mockInventoryService = MockInventoryService();
      controller = VanLoadController(
        vanLoadService: mockVanLoadService,
        inventoryService: mockInventoryService,
      );
    });

    test('editVanLoadRecord throws StateError when user is not a dealer', () async {
      mockCurrentUserRole(BusinessRole.salesman);

      final originalLoad = createTestLoad(
        id: 'load_100',
        status: VanLoadStatus.loaded,
        isStockDeducted: true,
        items: [
          VanLoadItem(
            productId: 'p1',
            productName: 'Cornetto',
            category: 'By Piece',
            productSource: 'selecta',
            loadedQuantity: 10,
            buyingPrice: 20,
            sellingPrice: 25,
          ),
        ],
        imagePath: 'https://storage/proof.jpg',
      );

      expect(
        () => controller.editVanLoadRecord(
          originalVanLoad: originalLoad,
          newItems: originalLoad.items,
          remarks: 'New remarks',
          imagePath: 'https://storage/proof.jpg',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Only dealers are authorized to edit van load records'),
        )),
      );
    });

    test('editVanLoadRecord throws ArgumentError when imagePath is empty', () async {
      mockCurrentUserRole(BusinessRole.dealer);

      final originalLoad = createTestLoad(
        id: 'load_101',
        status: VanLoadStatus.loaded,
        isStockDeducted: true,
        items: [
          VanLoadItem(
            productId: 'p1',
            productName: 'Cornetto',
            category: 'By Piece',
            productSource: 'selecta',
            loadedQuantity: 10,
            buyingPrice: 20,
            sellingPrice: 25,
          ),
        ],
        imagePath: 'https://storage/proof.jpg',
      );

      expect(
        () => controller.editVanLoadRecord(
          originalVanLoad: originalLoad,
          newItems: originalLoad.items,
          remarks: 'Updated remarks',
          imagePath: '',
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Proof of van load photo is required'),
        )),
      );
    });

    test('editVanLoadRecord throws when reducing loadedQuantity below soldQuantity', () async {
      mockCurrentUserRole(BusinessRole.dealer);

      final originalLoad = createTestLoad(
        id: 'load_102',
        status: VanLoadStatus.loaded,
        isStockDeducted: true,
        items: [
          VanLoadItem(
            productId: 'p1',
            productName: 'Cornetto',
            category: 'By Piece',
            productSource: 'selecta',
            loadedQuantity: 20,
            soldQuantity: 15, // 15 sold on van
            buyingPrice: 20,
            sellingPrice: 25,
          ),
        ],
        imagePath: 'https://storage/proof.jpg',
      );

      final editedItems = [
        VanLoadItem(
          productId: 'p1',
          productName: 'Cornetto',
          category: 'By Piece',
          productSource: 'selecta',
          loadedQuantity: 10, // Attempting to reduce below 15!
          buyingPrice: 20,
          sellingPrice: 25,
        ),
      ];

      expect(
        () => controller.editVanLoadRecord(
          originalVanLoad: originalLoad,
          newItems: editedItems,
          remarks: 'Attempting invalid reduction',
          imagePath: 'https://storage/proof.jpg',
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('already sold on the van'),
        )),
      );
    });

    test('editVanLoadRecord throws when removing an item that already has sales', () async {
      mockCurrentUserRole(BusinessRole.dealer);

      final originalLoad = createTestLoad(
        id: 'load_103',
        status: VanLoadStatus.loaded,
        isStockDeducted: true,
        items: [
          VanLoadItem(
            productId: 'p1',
            productName: 'Cornetto',
            category: 'By Piece',
            productSource: 'selecta',
            loadedQuantity: 20,
            soldQuantity: 5,
            buyingPrice: 20,
            sellingPrice: 25,
          ),
        ],
        imagePath: 'https://storage/proof.jpg',
      );

      // New items list does not contain p1 (trying to remove it)
      expect(
        () => controller.editVanLoadRecord(
          originalVanLoad: originalLoad,
          newItems: [],
          remarks: 'Trying to clear',
          imagePath: 'https://storage/proof.jpg',
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('units have already been sold'),
        )),
      );
    });

    test('editVanLoadRecord adjusts warehouse inventory atomically for active load', () async {
      mockCurrentUserRole(BusinessRole.dealer);

      final originalLoad = createTestLoad(
        id: 'load_104',
        status: VanLoadStatus.loaded,
        isStockDeducted: true,
        isStockSettled: false,
        items: [
          VanLoadItem(
            productId: 'p1',
            productName: 'Cornetto',
            category: 'By Piece',
            productSource: 'selecta',
            loadedQuantity: 20,
            soldQuantity: 5,
            buyingPrice: 20,
            sellingPrice: 25,
          ),
          VanLoadItem(
            productId: 'p2',
            productName: 'Pint Vanilla',
            category: 'By Case',
            productSource: 'selecta',
            loadedQuantity: 10,
            soldQuantity: 0,
            buyingPrice: 100,
            sellingPrice: 150,
          ),
        ],
        imagePath: 'https://storage/proof_v1.jpg',
        remarks: 'Initial remarks',
      );

      final editedItems = [
        VanLoadItem(
          productId: 'p1',
          productName: 'Cornetto',
          category: 'By Piece',
          productSource: 'selecta',
          loadedQuantity: 25, // +5 units
          buyingPrice: 20,
          sellingPrice: 25,
        ),
        VanLoadItem(
          productId: 'p2',
          productName: 'Pint Vanilla',
          category: 'By Case',
          productSource: 'selecta',
          loadedQuantity: 6, // -4 units
          buyingPrice: 100,
          sellingPrice: 150,
        ),
      ];

      await controller.editVanLoadRecord(
        originalVanLoad: originalLoad,
        newItems: editedItems,
        remarks: 'Updated remarks by dealer',
        imagePath: 'https://storage/proof_v2.jpg',
      );

      expect(mockInventoryService.adjustCallCount, 1);
      expect(mockInventoryService.lastOldAdjustedItems.length, 2);
      expect(mockInventoryService.lastNewAdjustedItems.length, 2);

      // Verify soldQuantity was preserved from original item (5 on p1)
      final p1Preserved = mockInventoryService.lastNewAdjustedItems.firstWhere((i) => i.productId == 'p1');
      expect(p1Preserved.soldQuantity, 5);
      expect(p1Preserved.loadedQuantity, 25);

      final saved = mockVanLoadService.store['load_104'];
      expect(saved, isNotNull);
      expect(saved!.remarks, 'Updated remarks by dealer');
      expect(saved.imagePath, 'https://storage/proof_v2.jpg');
      expect(saved.totalLoadedAmount, (25 * 25.0) + (6 * 150.0));
      expect(saved.totalSoldAmount, 5 * 25.0);
    });

    test('editVanLoadRecord updates settled load proof & remarks without adjusting stock', () async {
      mockCurrentUserRole(BusinessRole.dealer);

      final settledLoad = createTestLoad(
        id: 'load_settled',
        status: VanLoadStatus.completed,
        isStockDeducted: true,
        isStockSettled: true,
        items: [
          VanLoadItem(
            productId: 'p1',
            productName: 'Cornetto',
            category: 'By Piece',
            productSource: 'selecta',
            loadedQuantity: 20,
            soldQuantity: 18,
            returnedQuantity: 2,
            buyingPrice: 20,
            sellingPrice: 25,
          ),
        ],
        imagePath: 'https://storage/old_proof.jpg',
        remarks: 'Old remarks',
      );

      await controller.editVanLoadRecord(
        originalVanLoad: settledLoad,
        newItems: settledLoad.items,
        remarks: 'Corrected remarks post-settlement',
        imagePath: 'https://storage/new_proof.jpg',
      );

      // Crucial: stock was not adjusted because day is already settled
      expect(mockInventoryService.adjustCallCount, 0);

      final saved = mockVanLoadService.store['load_settled'];
      expect(saved, isNotNull);
      expect(saved!.remarks, 'Corrected remarks post-settlement');
      expect(saved.imagePath, 'https://storage/new_proof.jpg');
      expect(saved.isStockSettled, isTrue);
    });
  });

  group('OnHand Quantity Van Load Logic', () {
    test('InventoryItem onHandQuantity reflects physical warehouse stock even when reservedQuantity exhausts availableQuantity', () {
      const itemWithReservations = InventoryItem(
        id: 'tub_1',
        productName: 'P99 BIRTHDAY TUB 3IN1 CHOCO - KESO - UBE 700ML',
        imageUrl: '',
        buyingPrice: 70,
        sellingPrice: 90.90,
        isActive: true,
        stockQuantity: 15, // 15 physical tubs in the warehouse
        reservedQuantity: 15, // Fully reserved for store orders
        incomingQuantity: 0,
        lowStockThreshold: 5,
        source: InventoryProductSource.selecta,
      );

      // availableQuantity is 0 due to customer order reservations
      expect(itemWithReservations.availableQuantity, 0);

      // onHandQuantity is 15 because physical stock is in the warehouse
      expect(itemWithReservations.onHandQuantity, 15);
      expect(itemWithReservations.stockQuantity, 15);

      // For van load calculation:
      final onHandWarehouseStock = itemWithReservations.stockQuantity;
      final maxAllowedForDraft = onHandWarehouseStock;
      expect(maxAllowedForDraft, 15, reason: 'Warehouse physical stock is available to load into van');
    });

    test('Draft and edited van load calculation adds back previously loaded quantities to physical on-hand stock', () {
      const item = InventoryItem(
        id: 'p_ice',
        productName: 'Ice Cream Tub',
        imageUrl: '',
        buyingPrice: 50,
        sellingPrice: 75,
        isActive: true,
        stockQuantity: 5, // 5 left in warehouse
        reservedQuantity: 10,
        incomingQuantity: 0,
        lowStockThreshold: 2,
        source: InventoryProductSource.selecta,
      );

      final oldVanItem = VanLoadItem(
        productId: 'p_ice',
        productName: 'Ice Cream Tub',
        category: 'By Piece',
        productSource: 'selecta',
        loadedQuantity: 10,
        soldQuantity: 3,
        buyingPrice: 50,
        sellingPrice: 75,
      );

      final onHandWarehouseStock = item.stockQuantity;
      final minAllowed = oldVanItem.soldQuantity; // 3
      final maxAllowedEditing = onHandWarehouseStock + oldVanItem.loadedQuantity; // 5 + 10 = 15
      final effectiveMax = maxAllowedEditing < minAllowed ? minAllowed : maxAllowedEditing;

      expect(effectiveMax, 15);
      expect(minAllowed, 3);
    });
  });
}
