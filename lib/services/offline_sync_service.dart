import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selecta_ops/controllers/delivery_controller.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/services/error_log_service.dart';

/// Represents a queued offline operation that needs to be synchronized
/// with Cloud Firestore once internet connectivity is restored.
class OfflineSyncItem {
  final String id;
  final String action; // 'create_booked_order' | 'update_booked_order'
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final String? lastError;

  const OfflineSyncItem({
    required this.id,
    required this.action,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.lastError,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'action': action,
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
      'retryCount': retryCount,
      'lastError': lastError,
    };
  }

  factory OfflineSyncItem.fromMap(Map<String, dynamic> map) {
    return OfflineSyncItem(
      id: map['id'] as String? ?? '',
      action: map['action'] as String? ?? '',
      payload: Map<String, dynamic>.from(map['payload'] as Map? ?? {}),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      retryCount: (map['retryCount'] as num?)?.toInt() ?? 0,
      lastError: map['lastError'] as String?,
    );
  }

  OfflineSyncItem copyWith({
    int? retryCount,
    String? lastError,
  }) {
    return OfflineSyncItem(
      id: id,
      action: action,
      payload: payload,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
    );
  }
}

/// Service managing the local offline synchronization queue for orders and deliveries.
/// Stores pending transactions locally in [SharedPreferences] when salesmen lose connectivity,
/// and processes them sequentially once connectivity returns or when manual sync is invoked.
class OfflineSyncService {
  static const String _storageKey = 'selecta_offline_sync_queue_v1';
  static final OfflineSyncService instance = OfflineSyncService._internal();

  OfflineSyncService._internal() {
    refreshPendingCount();
  }

  /// Fast probe check for active internet connectivity with a 2-second timeout.
  static Future<bool> isOnline() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);
  bool _isProcessing = false;

  /// Loads the current list of pending sync items from local storage.
  Future<List<OfflineSyncItem>> getQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_storageKey) ?? [];
      return rawList.map((str) {
        final decoded = jsonDecode(str) as Map<String, dynamic>;
        return OfflineSyncItem.fromMap(decoded);
      }).toList();
    } catch (e, s) {
      debugPrint('Error reading offline sync queue: $e');
      ErrorLogService.logError(page: 'OfflineSyncService', action: 'getQueue', error: e, stackTrace: s);
      return [];
    }
  }

  /// Refreshes the [pendingCountNotifier] so UI indicators update live.
  Future<int> refreshPendingCount() async {
    final queue = await getQueue();
    pendingCountNotifier.value = queue.length;
    return queue.length;
  }

  Future<void> _saveQueue(List<OfflineSyncItem> queue) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = queue.map((i) => jsonEncode(i.toMap())).toList();
    await prefs.setStringList(_storageKey, rawList);
    pendingCountNotifier.value = queue.length;
  }

  /// Enqueues a new order creation transaction to be persisted locally and synced later.
  Future<String> enqueueOrderCreation({
    required String storeName,
    required DateTime selectedDate,
    required List<OrderItem> items,
    String remarks = '',
  }) async {
    final itemId = 'order_create_${DateTime.now().millisecondsSinceEpoch}';
    final newItem = OfflineSyncItem(
      id: itemId,
      action: 'create_booked_order',
      payload: {
        'storeName': storeName,
        'selectedDate': selectedDate.toIso8601String(),
        'remarks': remarks,
        'items': items.map((i) => i.toJson()).toList(),
      },
      createdAt: DateTime.now(),
    );

    final queue = await getQueue();
    queue.add(newItem);
    await _saveQueue(queue);
    debugPrint('OfflineSync: Enqueued new order creation for $storeName (Queue length: ${queue.length})');
    return itemId;
  }

  /// Enqueues an existing order update to be synced later.
  Future<String> enqueueOrderUpdate({
    required String deliveryId,
    required String storeName,
    required DateTime selectedDate,
    required List<OrderItem> items,
    String remarks = '',
  }) async {
    final itemId = 'order_update_${DateTime.now().millisecondsSinceEpoch}';
    final newItem = OfflineSyncItem(
      id: itemId,
      action: 'update_booked_order',
      payload: {
        'deliveryId': deliveryId,
        'storeName': storeName,
        'selectedDate': selectedDate.toIso8601String(),
        'remarks': remarks,
        'items': items.map((i) => i.toJson()).toList(),
      },
      createdAt: DateTime.now(),
    );

    final queue = await getQueue();
    queue.add(newItem);
    await _saveQueue(queue);
    debugPrint('OfflineSync: Enqueued order update for $storeName (Queue length: ${queue.length})');
    return itemId;
  }

  /// Processes all pending items sequentially.
  /// If an item succeeds, it is removed from the queue.
  /// If a network error occurs, execution halts and remaining items are preserved.
  Future<({int succeeded, int failed, String? lastError})> processQueue() async {
    if (_isProcessing) {
      return (succeeded: 0, failed: 0, lastError: 'Sync already in progress');
    }

    _isProcessing = true;
    int succeeded = 0;
    int failed = 0;
    String? lastError;

    try {
      final queue = await getQueue();
      if (queue.isEmpty) {
        return (succeeded: 0, failed: 0, lastError: null);
      }

      debugPrint('OfflineSync: Processing ${queue.length} pending offline items...');
      final deliveryController = DeliveryController();
      final remaining = <OfflineSyncItem>[];

      for (final item in queue) {
        try {
          if (item.action == 'create_booked_order') {
            final storeName = item.payload['storeName'] as String;
            final selectedDate = DateTime.parse(item.payload['selectedDate'] as String);
            final remarks = item.payload['remarks'] as String? ?? '';
            final rawItems = item.payload['items'] as List<dynamic>? ?? [];
            final items = rawItems.map((e) => OrderItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();

            await deliveryController.createBookedOrder(
              storeName: storeName,
              selectedDate: selectedDate,
              items: items,
              remarks: remarks,
            );
            succeeded++;
          } else if (item.action == 'update_booked_order') {
            final deliveryId = item.payload['deliveryId'] as String;
            final storeName = item.payload['storeName'] as String;
            final selectedDate = DateTime.parse(item.payload['selectedDate'] as String);
            final remarks = item.payload['remarks'] as String? ?? '';
            final rawItems = item.payload['items'] as List<dynamic>? ?? [];
            final items = rawItems.map((e) => OrderItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();

            final deliveryService = DeliveryService();
            final existing = await deliveryService.getDeliveryById(deliveryId);
            if (existing != null) {
              await deliveryController.updateBookedOrder(
                deliveryId: deliveryId,
                currentDelivery: existing,
                storeName: storeName,
                selectedDate: selectedDate,
                items: items,
                remarks: remarks,
              );
            }
            succeeded++;
          }
        } catch (e, s) {
          debugPrint('OfflineSync: Failed to process item ${item.id}: $e');
          lastError = e.toString();
          failed++;
          remaining.add(item.copyWith(
            retryCount: item.retryCount + 1,
            lastError: e.toString(),
          ));
          ErrorLogService.logError(
            page: 'OfflineSyncService',
            action: 'processQueueItem:${item.action}',
            error: e,
            stackTrace: s,
          );
          // If network failed, stop further processing
          final isNetworkError = e is FirebaseException || e.toString().toLowerCase().contains('network') || e.toString().toLowerCase().contains('socket');
          if (isNetworkError) {
            final index = queue.indexOf(item);
            if (index + 1 < queue.length) {
              remaining.addAll(queue.sublist(index + 1));
            }
            break;
          }
        }
      }

      await _saveQueue(remaining);
      debugPrint('OfflineSync: Complete. Succeeded: $succeeded, Failed: $failed, Remaining: ${remaining.length}');
      return (succeeded: succeeded, failed: failed, lastError: lastError);
    } finally {
      _isProcessing = false;
      await refreshPendingCount();
    }
  }

  /// Clears the entire queue (used in testing or administrative resets).
  Future<void> clearQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    pendingCountNotifier.value = 0;
  }
}
