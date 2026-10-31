import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/models/configuration.dart';
import 'package:selecta_ops/services/sms_gateway_service.dart';

void main() {
  group('SmsGatewayService Helper Unit Tests', () {
    test('sanitizePhoneNumber strips non-dialable characters', () {
      expect(SmsGatewayService.sanitizePhoneNumber('0917-123-4567'), '09171234567');
      expect(SmsGatewayService.sanitizePhoneNumber('+63 (917) 123 4567'), '+639171234567');
      expect(SmsGatewayService.sanitizePhoneNumber('0917 123 4567 #101'), '09171234567101');
    });

    test('formatPhoneNumberForPh standardizes to +639XXXXXXXXX format', () {
      // 11-digit starting with 09
      expect(SmsGatewayService.formatPhoneNumberForPh('09171234567'), '+639171234567');
      expect(SmsGatewayService.formatPhoneNumberForPh('0928 987 6543'), '+639289876543');

      // 10-digit starting with 9
      expect(SmsGatewayService.formatPhoneNumberForPh('9171234567'), '+639171234567');

      // 12-digit starting with 639
      expect(SmsGatewayService.formatPhoneNumberForPh('639171234567'), '+639171234567');

      // Already formatted with +63
      expect(SmsGatewayService.formatPhoneNumberForPh('+639171234567'), '+639171234567');
      expect(SmsGatewayService.formatPhoneNumberForPh('+63 917-123-4567'), '+639171234567');
    });

    test('SmsDispatchResult evaluates success states correctly', () {
      const gatewaySent = SmsDispatchResult(
        status: SmsDispatchStatus.sentViaGateway,
        messageId: 'msg_123',
      );
      expect(gatewaySent.isSuccessful, isTrue);

      const nativeSent = SmsDispatchResult(
        status: SmsDispatchStatus.dispatchedViaNativeApp,
      );
      expect(nativeSent.isSuccessful, isTrue);

      const failed = SmsDispatchResult(
        status: SmsDispatchStatus.failed,
        errorMessage: 'Invalid phone',
      );
      expect(failed.isSuccessful, isFalse);

      const cancelled = SmsDispatchResult(
        status: SmsDispatchStatus.cancelled,
      );
      expect(cancelled.isSuccessful, isFalse);
    });
  });

  group('Configuration SMS Gateway Model Serialization Tests', () {
    test('default Configuration.empty() contains sensible SMS Gateway defaults', () {
      final config = Configuration.empty();
      expect(config.smsGatewayEnabled, isTrue);
      expect(config.smsGatewayUrl, isEmpty);
      expect(config.smsGatewayToken, isEmpty);
      expect(config.smsGatewaySimSlot, equals(1));
    });

    test('fromJson and toJson round-trip preserves SMS Gateway fields', () {
      final json = <String, Object?>{
        'smsGatewayEnabled': true,
        'smsGatewayUrl': 'https://sms-gateway.selectaops.com/message',
        'smsGatewayToken': 'selecta_gateway:secretPass123',
        'smsGatewaySimSlot': 2,
      };

      final config = Configuration.fromJson(json);
      expect(config.smsGatewayEnabled, isTrue);
      expect(config.smsGatewayUrl, 'https://sms-gateway.selectaops.com/message');
      expect(config.smsGatewayToken, 'selecta_gateway:secretPass123');
      expect(config.smsGatewaySimSlot, 2);

      final exportedJson = config.toJson();
      expect(exportedJson['smsGatewayEnabled'], isTrue);
      expect(exportedJson['smsGatewayUrl'], 'https://sms-gateway.selectaops.com/message');
      expect(exportedJson['smsGatewayToken'], 'selecta_gateway:secretPass123');
      expect(exportedJson['smsGatewaySimSlot'], 2);
    });

    test('copyWith updates SMS Gateway settings properly', () {
      final initial = Configuration.empty();
      final updated = initial.copyWith(
        smsGatewayEnabled: false,
        smsGatewayUrl: 'http://192.168.1.50:8080/message',
        smsGatewayToken: 'Bearer test_token',
        smsGatewaySimSlot: 2,
      );

      expect(updated.smsGatewayEnabled, isFalse);
      expect(updated.smsGatewayUrl, 'http://192.168.1.50:8080/message');
      expect(updated.smsGatewayToken, 'Bearer test_token');
      expect(updated.smsGatewaySimSlot, 2);

      // Verify immutability of initial instance
      expect(initial.smsGatewayEnabled, isTrue);
      expect(initial.smsGatewayUrl, isEmpty);
    });
  });
}
