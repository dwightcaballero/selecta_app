import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/services/offline_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('OfflineSyncService Tests', () {
    test('OfflineSyncItem serializes and deserializes correctly', () {
      final now = DateTime.now();
      final item = OfflineSyncItem(
        id: 'test_123',
        action: 'create_booked_order',
        payload: {
          'storeName': 'Test Store',
          'selectedDate': now.toIso8601String(),
          'remarks': 'Priority order',
          'items': [
            {
              'productId': 'prod_1',
              'productName': 'Cornetto Chocolate',
              'sellingPrice': 30.0,
              'orderedQuantity': 5,
              'pickedQuantity': 5,
            }
          ],
        },
        createdAt: now,
      );

      final map = item.toMap();
      final deserialized = OfflineSyncItem.fromMap(map);

      expect(deserialized.id, equals('test_123'));
      expect(deserialized.action, equals('create_booked_order'));
      expect(deserialized.payload['storeName'], equals('Test Store'));
      expect(deserialized.payload['remarks'], equals('Priority order'));
      final items = deserialized.payload['items'] as List;
      expect(items.length, equals(1));
      expect(items.first['productId'], equals('prod_1'));
    });

    test('enqueueOrderCreation correctly persists item to queue', () async {
      final service = OfflineSyncService.instance;
      await service.clearQueue();

      final now = DateTime.now();
      final orderItem = const OrderItem(
        productId: 'prod_1',
        productName: 'Cornetto Vanilla',
        sellingPrice: 30.0,
        orderedQuantity: 10,
        pickedQuantity: 10,
      );

      final itemId = await service.enqueueOrderCreation(
        storeName: 'Hapi Store 1',
        selectedDate: now,
        items: [orderItem],
        remarks: 'Handle with care',
      );

      expect(itemId, isNotEmpty);
      final queue = await service.getQueue();
      expect(queue.length, equals(1));
      expect(queue.first.payload['storeName'], equals('Hapi Store 1'));
      expect(service.pendingCountNotifier.value, equals(1));

      await service.clearQueue();
      final cleared = await service.getQueue();
      expect(cleared.isEmpty, isTrue);
      expect(service.pendingCountNotifier.value, equals(0));
    });
  });
}
