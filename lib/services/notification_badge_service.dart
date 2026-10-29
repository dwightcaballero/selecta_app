import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Audience roles whose `notifications` docs each dashboard shows.
class NotificationAudience {
  static const dealer = ['Dealer', 'Admin', 'Staff'];
  static const salesman = ['Salesman', 'Staff'];
}

/// Unread count for the dashboard bell. One count() aggregation
/// (~1 Firestore read) per refresh; refreshes are throttled.
class NotificationBadgeService {
  static final NotificationBadgeService _instance =
      NotificationBadgeService._internal();
  factory NotificationBadgeService() => _instance;
  NotificationBadgeService._internal();

  static const _lastSeenKey = 'notif_last_seen_ms';
  static const _minRefreshGap = Duration(seconds: 60);

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);
  DateTime? _lastRefresh;

  /// Recounts notifications newer than the last time the list was
  /// opened. First run (no saved time) starts from "now" so a fresh
  /// install does not show a backlog of old alerts.
  Future<void> refresh(List<String> roles, {bool force = false}) async {
    final last = _lastRefresh;
    if (!force && last != null &&
        DateTime.now().difference(last) < _minRefreshGap) {
      return;
    }
    _lastRefresh = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_lastSeenKey);
      if (ms == null) {
        await prefs.setInt(_lastSeenKey, DateTime.now().millisecondsSinceEpoch);
        unreadCount.value = 0;
        return;
      }
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('role', whereIn: roles)
          .where('createdAt',
              isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(ms))
          .count()
          .get();
      unreadCount.value = snap.count ?? 0;
    } catch (e) {
      debugPrint('NotificationBadgeService.refresh failed: $e');
    }
  }

  /// Foreground push arrived: bump the badge locally (0 reads). The
  /// next resume/refresh corrects the number from Firestore.
  void onPushReceived() => unreadCount.value = unreadCount.value + 1;

  /// Call when the Notifications page is opened. [newest] is the
  /// createdAt of the newest queued doc shown (server clock, avoids
  /// device clock skew); falls back to device time.
  Future<void> markAllSeen({DateTime? newest}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _lastSeenKey,
      (newest ?? DateTime.now()).millisecondsSinceEpoch,
    );
    unreadCount.value = 0;
  }
}
