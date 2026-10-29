import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/services/notification_badge_service.dart';
import 'package:selecta_ops/views/pages/others/notifications_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Notification Pipeline & Badge Service Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('NotificationAudience contains expected role groupings', () {
      expect(NotificationAudience.dealer, containsAll(['Dealer', 'Admin', 'Staff']));
      expect(NotificationAudience.salesman, containsAll(['Salesman', 'Staff']));
      expect(NotificationAudience.salesman, isNot(contains('Dealer')));
      expect(NotificationAudience.salesman, isNot(contains('Admin')));
    });

    test('NotificationBadgeService singleton and local push incrementing', () async {
      final service1 = NotificationBadgeService();
      final service2 = NotificationBadgeService();
      expect(identical(service1, service2), isTrue);

      // Reset count
      await service1.markAllSeen();
      expect(service1.unreadCount.value, equals(0));

      // onPushReceived bumps locally without Firestore reads
      service1.onPushReceived();
      expect(service1.unreadCount.value, equals(1));
      service1.onPushReceived();
      expect(service1.unreadCount.value, equals(2));

      // markAllSeen resets back to 0
      final customDate = DateTime(2026, 10, 29, 12, 0, 0);
      await service1.markAllSeen(newest: customDate);
      expect(service1.unreadCount.value, equals(0));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('notif_last_seen_ms'), equals(customDate.millisecondsSinceEpoch));
    });

    test('NotificationsPage accepts role configuration', () {
      const defaultPage = NotificationsPage();
      expect(defaultPage.roles, equals(const ['Dealer', 'Admin', 'Staff']));

      const salesmanPage = NotificationsPage(roles: NotificationAudience.salesman);
      expect(salesmanPage.roles, equals(const ['Salesman', 'Staff']));
    });

    test('AppNotificationItem model instantiation and fields', () {
      final now = DateTime.now();
      final item = AppNotificationItem(
        id: 'queued_123',
        title: 'New Store Order Received',
        message: 'Store submitted order #1001',
        timestamp: now,
        type: NotificationType.fcmMessage,
        priority: NotificationPriority.warning,
      );

      expect(item.id, equals('queued_123'));
      expect(item.title, equals('New Store Order Received'));
      expect(item.isRead, isFalse);
      expect(item.type, equals(NotificationType.fcmMessage));
      expect(item.priority, equals(NotificationPriority.warning));

      item.isRead = true;
      expect(item.isRead, isTrue);
    });
  });
}
