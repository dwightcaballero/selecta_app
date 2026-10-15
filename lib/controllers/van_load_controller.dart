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
    return authService.value.currentUser?.displayName ?? 'Dealer';
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
  /// 1. Deducts loaded items from warehouse inventory with 'Van Load' movement logs.
  /// 2. Sets status = 'loaded', isStockDeducted = true.
  Future<void> confirmAndLoadVan({
    required VanLoad vanLoad,
  }) async {
    if (vanLoad.id == null || vanLoad.id!.isEmpty) {
      throw ArgumentError('VanLoad must have a valid ID before confirming.');
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
