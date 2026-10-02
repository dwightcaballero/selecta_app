import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/services/push_notification_service.dart';
import 'package:selecta_ops/views/pages/dashboard/picklist_list_page.dart';
import 'package:selecta_ops/views/pages/sidebar/tasklist_page.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/shimmer_loading.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NotificationType {
  task,
  delivery,
  picklist,
  fcmMessage,
}

enum NotificationPriority {
  urgent,
  warning,
  info,
}

class AppNotificationItem {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final NotificationType type;
  final NotificationPriority priority;
  final Widget? destinationPage;
  bool isRead;

  AppNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    required this.type,
    required this.priority,
    this.destinationPage,
    this.isRead = false,
  });
}

/// Centralized In-App Notifications Center displaying pending tasks, overdue deliveries,
/// and live FCM push notifications.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PushNotificationService _pushService = PushNotificationService();

  StreamSubscription<RemoteMessage>? _fcmSubscription;
  final List<RemoteMessage> _liveFcmMessages = [];
  Set<String> _readIds = {};
  bool _isLoading = true;
  String _activeFilter = 'All';

  List<AppNotificationItem> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadReadState();
    _fcmSubscription = _pushService.onForegroundMessage.listen((msg) {
      if (mounted) {
        setState(() {
          _liveFcmMessages.insert(0, msg);
          _compileNotifications();
        });
      }
    });
    _fetchOperationalAlerts();
  }

  @override
  void dispose() {
    _fcmSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadReadState() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('read_notification_ids') ?? [];
    if (mounted) {
      setState(() {
        _readIds = list.toSet();
      });
    }
  }

  Future<void> _saveReadState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('read_notification_ids', _readIds.toList());
  }

  Future<void> _fetchOperationalAlerts() async {
    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final items = <AppNotificationItem>[];

      // 1. Fetch Overdue & Pending Tasks
      final tasksSnap = await _firestore
          .collection('tasks')
          .where('status', isEqualTo: 'Pending')
          .limit(30)
          .get();

      for (final doc in tasksSnap.docs) {
        final data = doc.data();
        final title = (data['taskTitle'] as String? ?? 'Untitled Task').trim();
        final store = (data['storeName'] as String? ?? '').trim();
        final deadlineTs = data['deadline'] as Timestamp?;
        final deadline = deadlineTs?.toDate() ?? now;
        final isOverdue = deadline.isBefore(now);

        items.add(
          AppNotificationItem(
            id: 'task_${doc.id}',
            title: isOverdue ? 'Overdue Task: $title' : 'Pending Task: $title',
            message: store.isNotEmpty ? 'Store: $store • Due: ${DateFormat('MMM d, h:mm a').format(deadline)}' : 'Due: ${DateFormat('MMM d, h:mm a').format(deadline)}',
            timestamp: deadline,
            type: NotificationType.task,
            priority: isOverdue ? NotificationPriority.urgent : NotificationPriority.warning,
            destinationPage: const TaskListPage(),
            isRead: _readIds.contains('task_${doc.id}'),
          ),
        );
      }

      // 2. Fetch Pending Picklists
      final picklistSnap = await _firestore
          .collection('delivery')
          .where('status', isEqualTo: 'Pending Picklist')
          .limit(20)
          .get();

      for (final doc in picklistSnap.docs) {
        final data = doc.data();
        final store = (data['storeName'] as String? ?? 'Store Delivery').trim();
        final createdTs = data['createdDate'] as Timestamp?;
        final created = createdTs?.toDate() ?? now;

        items.add(
          AppNotificationItem(
            id: 'picklist_${doc.id}',
            title: 'Picklist Awaiting Prep',
            message: 'Pending picklist for $store',
            timestamp: created,
            type: NotificationType.picklist,
            priority: NotificationPriority.info,
            destinationPage: const PicklistListPage(),
            isRead: _readIds.contains('picklist_${doc.id}'),
          ),
        );
      }

      // 3. Fetch In-session FCM messages
      for (int i = 0; i < _liveFcmMessages.length; i++) {
        final msg = _liveFcmMessages[i];
        final id = 'fcm_${msg.messageId ?? i}';
        items.add(
          AppNotificationItem(
            id: id,
            title: msg.notification?.title ?? 'Notification',
            message: msg.notification?.body ?? 'New alert received from Selecta Ops',
            timestamp: msg.sentTime ?? now,
            type: NotificationType.fcmMessage,
            priority: NotificationPriority.warning,
            isRead: _readIds.contains(id),
          ),
        );
      }

      // Sort newest / highest priority first
      items.sort((a, b) {
        if (a.priority != b.priority) {
          return a.priority.index.compareTo(b.priority.index);
        }
        return b.timestamp.compareTo(a.timestamp);
      });

      if (mounted) {
        setState(() {
          _notifications = items;
          _isLoading = false;
        });
      }
    } catch (e, s) {
      ErrorLogService.logError(
        page: 'NotificationsPage',
        action: 'Fetch Operational Alerts',
        error: e,
        stackTrace: s,
      );
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _compileNotifications() {
    _fetchOperationalAlerts();
  }

  void _markAllAsRead() {
    setState(() {
      for (final item in _notifications) {
        item.isRead = true;
        _readIds.add(item.id);
      }
    });
    _saveReadState();
  }

  List<AppNotificationItem> get _filteredNotifications {
    if (_activeFilter == 'All') return _notifications;
    if (_activeFilter == 'Tasks') {
      return _notifications.where((n) => n.type == NotificationType.task).toList();
    }
    if (_activeFilter == 'Picklists') {
      return _notifications.where((n) => n.type == NotificationType.picklist).toList();
    }
    if (_activeFilter == 'Messages') {
      return _notifications.where((n) => n.type == NotificationType.fcmMessage).toList();
    }
    return _notifications;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final unreadCount = _notifications.where((n) => !n.isRead).length;

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Notifications',
        subtitle: unreadCount > 0 ? '$unreadCount unread alert${unreadCount == 1 ? "" : "s"}' : 'All caught up',
        actions: [
          if (_notifications.isNotEmpty && unreadCount > 0)
            IconButton(
              icon: const Icon(Icons.done_all_rounded, color: Colors.white),
              tooltip: 'Mark All as Read',
              onPressed: _markAllAsRead,
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Filter Chips ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: colorScheme.surface,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['All', 'Tasks', 'Picklists', 'Messages'].map((filter) {
                  final isSelected = _activeFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: isSelected,
                      label: Text(filter),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                      ),
                      selectedColor: colorScheme.primary,
                      checkmarkColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      onSelected: (_) {
                        setState(() => _activeFilter = filter);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── Notification Items ──────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const ListSkeleton(itemCount: 6)
                : _filteredNotifications.isEmpty
                    ? _buildEmptyState(colorScheme)
                    : RefreshIndicator(
                        onRefresh: _fetchOperationalAlerts,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _filteredNotifications.length,
                          itemBuilder: (context, index) {
                            final item = _filteredNotifications[index];
                            return _buildNotificationCard(item, colorScheme);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              'No Notifications',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              'You have no pending tasks, delayed deliveries, or unread alerts right now.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: _fetchOperationalAlerts,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(AppNotificationItem item, ColorScheme colorScheme) {
    final iconData = switch (item.type) {
      NotificationType.task => Icons.task_alt_outlined,
      NotificationType.delivery => Icons.local_shipping_outlined,
      NotificationType.picklist => Icons.fact_check_outlined,
      NotificationType.fcmMessage => Icons.campaign_outlined,
    };

    final badgeColor = switch (item.priority) {
      NotificationPriority.urgent => Colors.red,
      NotificationPriority.warning => Colors.orange,
      NotificationPriority.info => colorScheme.primary,
    };

    final timeLabel = DateFormat('MMM d • h:mm a').format(item.timestamp);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: item.isRead ? colorScheme.surface : colorScheme.primaryContainer.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: item.isRead
              ? colorScheme.outlineVariant.withValues(alpha: 0.4)
              : colorScheme.primary.withValues(alpha: 0.5),
          width: item.isRead ? 1.0 : 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          setState(() {
            item.isRead = true;
            _readIds.add(item.id);
          });
          _saveReadState();

          if (item.destinationPage != null) {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => item.destinationPage!));
            _fetchOperationalAlerts();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon container with priority color
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(iconData, color: badgeColor, size: 22),
              ),

              const SizedBox(width: 12),

              // Title and message
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontWeight: item.isRead ? FontWeight.w600 : FontWeight.bold,
                              fontSize: 14,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!item.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.message,
                      style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded, size: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Text(
                          timeLabel,
                          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (item.destinationPage != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, size: 20, color: colorScheme.outlineVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
