import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:selecta_ops/services/error_log_service.dart';

/// Top-level background handler for FCM messages when the application is terminated or in the background.
/// Must be annotated with `@pragma('vm:entry-point')` so the Flutter engine can invoke it.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase may already be initialized
  }
  debugPrint('FCM Background message received: ${message.messageId}, title: ${message.notification?.title}');
}

/// Service managing Firebase Cloud Messaging (FCM) push notifications, device tokens,
/// topic subscriptions, and foreground/background message lifecycle.
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _currentToken;
  bool _isInitialized = false;

  /// Stream controller broadcasting incoming foreground messages across the app.
  final StreamController<RemoteMessage> _foregroundMessageController = StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get onForegroundMessage => _foregroundMessageController.stream;

  /// Initializes the notification service, registers background handler,
  /// requests user permissions, and sets up message streams.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Set background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Request notification permissions (required for iOS and Android 13+)
      final NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('FCM Authorization Status: ${settings.authorizationStatus}');

      // Configure foreground presentation options for iOS
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Retrieve device token
      _currentToken = await _fcm.getToken();
      debugPrint('FCM Device Token: $_currentToken');

      // Auto-register token if user is already logged in
      final currentUser = _auth.currentUser;
      if (currentUser != null && _currentToken != null) {
        await saveTokenForUser(email: currentUser.email, uid: currentUser.uid);
      }

      // Listen for token refreshes
      _fcm.onTokenRefresh.listen((newToken) {
        _currentToken = newToken;
        final user = _auth.currentUser;
        if (user != null) {
          saveTokenForUser(email: user.email, uid: user.uid, token: newToken);
        }
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('FCM Foreground message: ${message.notification?.title} - ${message.notification?.body}');
        _foregroundMessageController.add(message);
      });

      // Handle notification opened app while in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('FCM Notification opened from background: ${message.data}');
      });

      // Check if app was opened directly from a terminated state via a notification
      final RemoteMessage? initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('FCM App opened from terminated state: ${initialMessage.data}');
      }

      // Subscribe to general announcement topic
      await subscribeToTopic('all_devices');

      _isInitialized = true;
    } catch (e, s) {
      debugPrint('Error initializing PushNotificationService: $e');
      ErrorLogService.logError(
        page: 'PushNotificationService',
        action: 'Initialize Push Notifications',
        error: e,
        stackTrace: s,
      );
    }
  }

  /// Returns the cached device FCM token or fetches a fresh one.
  Future<String?> getDeviceToken() async {
    if (_currentToken != null) return _currentToken;
    try {
      _currentToken = await _fcm.getToken();
      return _currentToken;
    } catch (e) {
      debugPrint('Failed to get FCM device token: $e');
      return null;
    }
  }

  /// Persists the FCM device token to Firestore under the user record and a dedicated `fcm_tokens` collection.
  Future<void> saveTokenForUser({String? email, String? uid, String? role, String? token}) async {
    final activeToken = token ?? _currentToken ?? await getDeviceToken();
    if (activeToken == null || activeToken.isEmpty) return;

    try {
      final now = FieldValue.serverTimestamp();
      final userKey = email?.toLowerCase().trim() ?? uid;

      if (userKey != null && userKey.isNotEmpty) {
        // Save under fcm_tokens collection indexed by token
        await _firestore.collection('fcm_tokens').doc(activeToken).set({
          'token': activeToken,
          'userKey': userKey,
          'email': email ?? '',
          'uid': uid ?? '',
          'role': role ?? '',
          'platform': defaultTargetPlatform.name,
          'updatedAt': now,
        }, SetOptions(merge: true));

        // Also merge into users document if email exists
        if (email != null && email.isNotEmpty) {
          final userQuery = await _firestore.collection('users').where('email', isEqualTo: email.trim()).limit(1).get();
          if (userQuery.docs.isNotEmpty) {
            await userQuery.docs.first.reference.set({
              'fcmToken': activeToken,
              'fcmTokenUpdatedAt': now,
            }, SetOptions(merge: true));
          }
        }
      }
    } catch (e, s) {
      debugPrint('Failed to save FCM token for user: $e');
      ErrorLogService.logError(
        page: 'PushNotificationService',
        action: 'Save User FCM Token',
        error: e,
        stackTrace: s,
      );
    }
  }

  /// Subscribes this device to an FCM topic (e.g., 'dealers', 'salesmen', 'blitz').
  Future<void> subscribeToTopic(String topic) async {
    try {
      final cleanTopic = topic.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '_');
      await _fcm.subscribeToTopic(cleanTopic);
      debugPrint('Subscribed to FCM topic: $cleanTopic');
    } catch (e) {
      debugPrint('Error subscribing to topic $topic: $e');
    }
  }

  /// Unsubscribes this device from an FCM topic.
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      final cleanTopic = topic.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '_');
      await _fcm.unsubscribeFromTopic(cleanTopic);
      debugPrint('Unsubscribed from FCM topic: $cleanTopic');
    } catch (e) {
      debugPrint('Error unsubscribing from topic $topic: $e');
    }
  }

  /// Syncs role-based topic subscriptions (dealers vs salesmen).
  Future<void> syncRoleTopics(String role) async {
    final normalized = role.toLowerCase().trim();
    if (normalized == 'dealer') {
      await subscribeToTopic('dealers');
      await unsubscribeFromTopic('salesmen');
    } else if (normalized == 'salesman') {
      await subscribeToTopic('salesmen');
      await unsubscribeFromTopic('dealers');
    }
  }

  /// Cleans up resources.
  void dispose() {
    _foregroundMessageController.close();
  }
}
