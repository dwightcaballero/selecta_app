import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/van_load.dart';
import 'package:selecta_ops/services/auth_service.dart';
import 'package:selecta_ops/services/inventory_service.dart';
import 'package:selecta_ops/services/van_load_service.dart';

class VanLoadController {
  final VanLoadService _vanLoadService;
  final InventoryService _inventoryService;

  VanLoadController({
    VanLoadService? vanLoadService,
    InventoryService? inventoryService,
  })  : _vanLoadService = vanLoadService ?? VanLoadService(),
        _inventoryService = inventoryService ?? InventoryService();

  /// Real-time stream of all van loads.
  Stream<List<VanLoad>> streamVanLoads({int limit = 50}) =>
      _vanLoadService.streamVanLoads(limit: limit);

  /// Real-time stream of active van load (loaded or in-route).
  Stream<VanLoad?> streamActiveVanLoad() =>
      _vanLoadService.streamActiveVanLoad();

  /// Fetch active van load once.
  Future<VanLoad?> getActiveVanLoad() =>
      _vanLoadService.getActiveVanLoad();

  /// Fetch a van load by ID.
  Future<VanLoad?> getVanLoad(String id) =>
      _vanLoadService.getVanLoad(id);

  /// Checks if current user is Dealer.
  Future<bool> checkIsDealer() => KVariables.getIsDealer();

  /// Gets current user display name.
  String getCurrentUserDisplayName() {
    try {
      return authService.value.currentUser?.displayName ?? 'Dealer';
    } catch (_) {
      return 'Dealer';
    }
  }

  /// Create and save a new draft Van Load manifest.
  Future<String> createDraftVanLoad(VanLoad vanLoad) async {
    return await _vanLoadService.addVanLoad(vanLoad);
  }

  /// Update an existing draft Van Load manifest.
  Future<void> updateDraftVanLoad(String id, VanLoad vanLoad) async {
    await _vanLoadService.updateVanLoad(id, vanLoad);
  }

  /// Confirms and loads the van:
  /// 1. Validates proof of van load photo is attached.
  /// 2. Deducts loaded items from warehouse inventory with 'Van Load' movement logs.
  /// 3. Sets status = 'loaded', isStockDeducted = true.
  Future<void> confirmAndLoadVan({
    required VanLoad vanLoad,
  }) async {
    if (vanLoad.id == null || vanLoad.id!.isEmpty) {
      throw ArgumentError('VanLoad must have a valid ID before confirming.');
    }

    if (vanLoad.imagePath.trim().isEmpty) {
      throw ArgumentError('Proof of van load photo is required before confirming.');
    }

    if (vanLoad.isStockDeducted) {
      throw StateError('VanLoad is already loaded and stock has already been deducted.');
    }

    // Deduct physical warehouse inventory
    await _inventoryService.deductVanLoadInventory(
      vanLoadId: vanLoad.id!,
      items: vanLoad.items,
    );

    // Update van load record
    final updated = vanLoad.copyWith(
      status: VanLoadStatus.loaded,
      isStockDeducted: true,
      lastUpdatedDate: Timestamp.now(),
      lastUpdatedBy: getCurrentUserDisplayName(),
    );

    await _vanLoadService.updateVanLoad(vanLoad.id!, updated);
  }

  /// Allows dealer to edit an existing van load record:
  /// - Draft: updates items, remarks, imagePath, totalLoadedAmount without inventory movements.
  /// - Loaded / In-Route: adjusts warehouse inventory for any item differences, preserves sales, updates items, remarks, imagePath.
  /// - Completed: updates remarks and imagePath (items remain locked to protect settled inventory).
  Future<void> editVanLoadRecord({
    required VanLoad originalVanLoad,
    required List<VanLoadItem> newItems,
    required String remarks,
    required String imagePath,
  }) async {
    final isDealer = await checkIsDealer();
    if (!isDealer) {
      throw StateError('Only dealers are authorized to edit van load records.');
    }

    if (originalVanLoad.id == null || originalVanLoad.id!.isEmpty) {
      throw ArgumentError('VanLoad must have a valid ID.');
    }

    if (imagePath.trim().isEmpty) {
      throw ArgumentError('Proof of van load photo is required.');
    }

    final now = Timestamp.now();
    final user = getCurrentUserDisplayName();

    // If load is completed (stock already settled), protect settled stock and update remarks/proof
    if (originalVanLoad.isStockSettled) {
      final updated = originalVanLoad.copyWith(
        remarks: remarks.trim(),
        imagePath: imagePath.trim(),
        lastUpdatedDate: now,
        lastUpdatedBy: user,
      );
      await _vanLoadService.updateVanLoad(originalVanLoad.id!, updated);
      return;
    }

    final oldMap = {for (final item in originalVanLoad.items) item.productId: item};

    // Validate that loadedQuantity is not reduced below soldQuantity
    for (final newItem in newItems) {
      final old = oldMap[newItem.productId];
      if (old != null && newItem.loadedQuantity < old.soldQuantity) {
        throw ArgumentError(
          'Cannot reduce loaded quantity for ${newItem.productName} below ${old.soldQuantity} (already sold on the van).',
        );
      }
    }

    // Check removed items: if an old item had soldQuantity > 0, it cannot be removed
    final newIds = newItems.map((i) => i.productId).toSet();
    for (final old in originalVanLoad.items) {
      if (!newIds.contains(old.productId) && old.soldQuantity > 0) {
        throw ArgumentError(
          'Cannot remove ${old.productName} because ${old.soldQuantity} units have already been sold.',
        );
      }
    }

    // Preserve sold and returned quantities on matching items
    final preservedItems = newItems.map((item) {
      final old = oldMap[item.productId];
      return item.copyWith(
        soldQuantity: old?.soldQuantity ?? 0,
        returnedQuantity: old?.returnedQuantity ?? 0,
      );
    }).toList();

    // If stock was already deducted and not settled, atomically adjust warehouse inventory
    if (originalVanLoad.isStockDeducted) {
      await _inventoryService.adjustVanLoadInventory(
        vanLoadId: originalVanLoad.id!,
        oldItems: originalVanLoad.items,
        newItems: preservedItems,
      );
    }

    final totalLoadedAmount = preservedItems.fold<double>(0.0, (acc, i) => acc + i.lineTotalLoaded);
    final totalSoldAmount = preservedItems.fold<double>(0.0, (acc, i) => acc + i.lineTotalSold);

    final updated = originalVanLoad.copyWith(
      items: preservedItems,
      remarks: remarks.trim(),
      imagePath: imagePath.trim(),
      totalLoadedAmount: totalLoadedAmount,
      totalSoldAmount: totalSoldAmount,
      lastUpdatedDate: now,
      lastUpdatedBy: user,
    );

    await _vanLoadService.updateVanLoad(originalVanLoad.id!, updated);
  }

  /// Completes the Van Load at End of Day:
  /// 1. Updates items with actual returned quantities.
  /// 2. Replenishes returned items back to warehouse stock with 'Van Return' movement logs.
  /// 3. Marks status = 'completed', isStockSettled = true.
  Future<void> completeVanLoadAndReturnStock({
    required VanLoad vanLoad,
    required List<VanLoadItem> returnedItems,
    String? remarks,
  }) async {
    if (vanLoad.id == null || vanLoad.id!.isEmpty) {
      throw ArgumentError('VanLoad must have a valid ID.');
    }

    if (vanLoad.isStockSettled) {
      throw StateError('VanLoad is already settled.');
    }

    final now = Timestamp.now();
    final user = getCurrentUserDisplayName();

    // Replenish unsold goods back into warehouse inventory
    await _inventoryService.returnVanLoadInventory(
      vanLoadId: vanLoad.id!,
      returnedItems: returnedItems,
    );

    // Compute total returned amount
    final totalReturnedAmount = returnedItems.fold<double>(
      0.0,
      (acc, item) => acc + item.lineTotalReturned,
    );

    final updated = vanLoad.copyWith(
      items: returnedItems,
      status: VanLoadStatus.completed,
      isStockSettled: true,
      totalReturnedAmount: totalReturnedAmount,
      completedDate: now,
      completedBy: user,
      lastUpdatedDate: now,
      lastUpdatedBy: user,
      remarks: remarks ?? vanLoad.remarks,
    );

    await _vanLoadService.updateVanLoad(vanLoad.id!, updated);
  }

  /// Delete a draft van load (only if stock was never deducted).
  Future<void> deleteDraftVanLoad(String id, VanLoad vanLoad) async {
    if (vanLoad.isStockDeducted) {
      throw StateError('Cannot delete a van load whose stock was already deducted.');
    }
    await _vanLoadService.deleteVanLoad(id);
  }
}
