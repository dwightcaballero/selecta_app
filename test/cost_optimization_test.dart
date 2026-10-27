import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/services/product_catalog_cache.dart';
import 'package:selecta_ops/services/scout_tracking_service.dart';

void main() {
  group('Cost Optimization Tests', () {
    test('ProductCatalogCache singleton and cache invalidation works as expected', () {
      final cache1 = ProductCatalogCache();
      final cache2 = ProductCatalogCache();
      expect(identical(cache1, cache2), isTrue);

      // Verify TTL configuration
      expect(ProductCatalogCache.defaultTtl.inMinutes, equals(5));

      // Invalidate methods should not throw
      cache1.invalidateSelecta();
      cache1.invalidateOther();
      cache1.invalidateAdmin();
      cache1.invalidateAll();
    });

    test('ErrorLogItem generates 30-day expireAt TTL for cost optimization', () {
      final now = DateTime(2026, 10, 27, 12, 0, 0);
      final log = ErrorLogItem(
        id: 'test_id',
        timestamp: now,
        page: 'TestPage',
        action: 'TestAction',
        error: 'Test error message',
        platform: 'android',
      );

      final firestoreMap = log.toFirestore();
      expect(firestoreMap.containsKey('expireAt'), isTrue);

      // Verify timestamp is approximately 30 days later
      final expireTimestamp = firestoreMap['expireAt'];
      expect(expireTimestamp, isNotNull);
      final expireDate = expireTimestamp.toDate() as DateTime;
      expect(expireDate.difference(now).inDays, equals(30));
    });

    test('ScoutTrackingService max points per session is capped at 500', () {
      expect(ScoutTrackingService.maxPointsPerSession, equals(500));
    });
  });
}
