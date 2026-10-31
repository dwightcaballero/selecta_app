import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Result status returned by [SmsGatewayService.sendSms].
enum SmsDispatchStatus {
  /// Message successfully forwarded and accepted by the Office Android SMS Gateway.
  sentViaGateway,

  /// Gateway was offline or unavailable, but user dispatched via native device SMS app.
  dispatchedViaNativeApp,

  /// User cancelled device SMS fallback or dispatch was aborted.
  cancelled,

  /// An error occurred (e.g. invalid phone number).
  failed,
}

/// Consolidated dispatch result containing status, optional message ID, and error detail.
class SmsDispatchResult {
  final SmsDispatchStatus status;
  final String? messageId;
  final String? errorMessage;

  const SmsDispatchResult({
    required this.status,
    this.messageId,
    this.errorMessage,
  });

  bool get isSuccessful =>
      status == SmsDispatchStatus.sentViaGateway ||
      status == SmsDispatchStatus.dispatchedViaNativeApp;
}

/// Health check result for the Office SMS Gateway.
class SmsGatewayHealthResult {
  final bool isOnline;
  final bool isEnabled;
  final int? latencyMs;
  final String status;

  const SmsGatewayHealthResult({
    required this.isOnline,
    required this.isEnabled,
    this.latencyMs,
    required this.status,
  });
}

/// Centralized service managing SMS dispatches via the Office Android SMS Gateway
/// and providing seamless, zero-permission fallback to the device's native SMS app.
class SmsGatewayService {
  static final SmsGatewayService _instance = SmsGatewayService._internal();
  factory SmsGatewayService() => _instance;
  SmsGatewayService._internal();

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-east1');

  /// Sanitizes phone number by stripping formatting and normalizing to dialable digits.
  static String sanitizePhoneNumber(String phone) {
    return phone.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  /// Formats phone number for Philippine telcos (+639XXXXXXXXX).
  static String formatPhoneNumberForPh(String phone) {
    var cleaned = sanitizePhoneNumber(phone);
    if (cleaned.startsWith('+63')) {
      return cleaned;
    }
    if (cleaned.startsWith('639') && cleaned.length == 12) {
      return '+$cleaned';
    }
    if (cleaned.startsWith('09') && cleaned.length == 11) {
      return '+63${cleaned.substring(1)}';
    }
    if (cleaned.startsWith('9') && cleaned.length == 10) {
      return '+63$cleaned';
    }
    return cleaned;
  }

  /// Dispatches an SMS via the Office Android SMS Gateway Cloud Function.
  ///
  /// If the gateway is offline or unavailable, automatically prompts the user
  /// to open their native SMS app with the recipient and message pre-populated.
  Future<SmsDispatchResult> sendSms({
    required BuildContext context,
    required String phoneNumber,
    required String message,
    String? storeId,
    String? storeName,
    String category = 'general',
    bool showSuccessSnackBar = true,
    bool allowFallbackPrompt = true,
  }) async {
    final sanitizedNumber = formatPhoneNumberForPh(phoneNumber);
    if (sanitizedNumber.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid or empty phone number.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return const SmsDispatchResult(
        status: SmsDispatchStatus.failed,
        errorMessage: 'Invalid phone number',
      );
    }

    try {
      final callable = _functions.httpsCallable('dispatchSms');
      final response = await callable.call<Map<String, dynamic>>({
        'phoneNumber': sanitizedNumber,
        'message': message,
        'storeId': storeId,
        'storeName': storeName,
        'category': category,
      });

      final data = Map<String, dynamic>.from(response.data);

      if (data['success'] == true) {
        if (showSuccessSnackBar && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('SMS dispatched via Office SMS Gateway.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return SmsDispatchResult(
          status: SmsDispatchStatus.sentViaGateway,
          messageId: data['messageId']?.toString(),
        );
      }

      // Gateway reported an issue (offline, disabled, or unreachable)
      if (data['allowDeviceFallback'] == true && allowFallbackPrompt && context.mounted) {
        final reason = data['error'] == 'gateway_not_configured'
            ? 'Office SMS Gateway is not yet configured'
            : 'Office SMS Gateway is currently unreachable';

        return await _handleFallbackPrompt(
          context: context,
          phoneNumber: sanitizedNumber,
          message: message,
          reason: reason,
        );
      }

      return SmsDispatchResult(
        status: SmsDispatchStatus.failed,
        errorMessage: data['details']?.toString() ?? data['error']?.toString(),
      );
    } catch (e) {
      debugPrint('SmsGatewayService dispatch error: $e');

      if (allowFallbackPrompt && context.mounted) {
        return await _handleFallbackPrompt(
          context: context,
          phoneNumber: sanitizedNumber,
          message: message,
          reason: 'Could not reach Office SMS Gateway server',
        );
      }

      return SmsDispatchResult(
        status: SmsDispatchStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  /// Opens the device default SMS messenger pre-populated with recipient and message body.
  ///
  /// This operates via standard Android/iOS URL schemes and does NOT require
  /// the dangerous SEND_SMS permission.
  Future<bool> launchNativeSmsApp({
    required String phoneNumber,
    required String message,
  }) async {
    final cleaned = sanitizePhoneNumber(phoneNumber);
    if (cleaned.isEmpty) return false;

    final uri = Uri(
      scheme: 'sms',
      path: cleaned,
      queryParameters: <String, String>{
        'body': message,
      },
    );

    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri);
    }
    return false;
  }

  /// Displays an interactive modal dialog offering device fallback when the gateway is offline.
  Future<SmsDispatchResult> _handleFallbackPrompt({
    required BuildContext context,
    required String phoneNumber,
    required String message,
    required String reason,
  }) async {
    final shouldFallback = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.sms_outlined, color: Colors.orange),
            SizedBox(width: 8),
            Text('SMS Gateway Offline', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Text(
          '$reason.\n\nWould you like to open your device\'s SMS messenger to send this message directly?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.send, size: 16),
            label: const Text('Open SMS App'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (shouldFallback == true) {
      final launched = await launchNativeSmsApp(
        phoneNumber: phoneNumber,
        message: message,
      );
      if (launched) {
        return const SmsDispatchResult(
          status: SmsDispatchStatus.dispatchedViaNativeApp,
        );
      }
    }

    return const SmsDispatchResult(status: SmsDispatchStatus.cancelled);
  }

  /// Queries the gateway health status via Cloud Function `checkSmsGatewayHealth`.
  Future<SmsGatewayHealthResult> checkHealth() async {
    try {
      final callable = _functions.httpsCallable('checkSmsGatewayHealth');
      final response = await callable.call<Map<String, dynamic>>();
      final data = Map<String, dynamic>.from(response.data);

      return SmsGatewayHealthResult(
        isOnline: data['online'] == true,
        isEnabled: data['enabled'] == true,
        latencyMs: (data['latencyMs'] as num?)?.toInt(),
        status: data['status']?.toString() ?? 'Unknown status',
      );
    } catch (e) {
      return SmsGatewayHealthResult(
        isOnline: false,
        isEnabled: false,
        status: 'Health check failed: $e',
      );
    }
  }
}
