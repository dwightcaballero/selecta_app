import 'package:flutter_test/flutter_test.dart';
import 'package:selecta_ops/models/app_version_info.dart';

void main() {
  group('AppVersionInfo Tests', () {
    test('parses standard GitHub Release payload with +buildNumber and APK asset', () {
      final json = {
        'tag_name': 'v1.0.0+24',
        'name': 'Release v1.0.0+24',
        'body': 'Initial feature release with improved inventory.',
        'published_at': '2026-10-02T12:00:00Z',
        'assets': [
          {
            'name': 'other_file.txt',
            'browser_download_url': 'https://example.com/other_file.txt',
          },
          {
            'name': 'app-release.apk',
            'browser_download_url': 'https://github.com/dwightcaballero/selecta_app/releases/download/v1.0.0%2B24/app-release.apk',
          },
        ],
      };

      final info = AppVersionInfo.fromGitHubRelease(json);

      expect(info.latestVersionName, equals('1.0.0'));
      expect(info.latestVersionCode, equals(24));
      expect(info.apkUrl, equals('https://github.com/dwightcaballero/selecta_app/releases/download/v1.0.0%2B24/app-release.apk'));
      expect(info.releaseNotes, equals('Initial feature release with improved inventory.'));
      expect(info.forceUpdate, isFalse);
      expect(info.minSupportedVersionCode, equals(1));
      expect(info.publishedAt, isNotNull);
    });

    test('parses tag without v prefix and detects force update flag in body', () {
      final json = {
        'tag_name': '1.0.1+25',
        'name': 'Critical Patch',
        'body': 'Security fix [force-update] [min-version: 20]',
        'published_at': '2026-10-02T13:00:00Z',
        'assets': [
          {
            'name': 'SelectaOps-v1.0.1.apk',
            'browser_download_url': 'https://github.com/dwightcaballero/selecta_app/releases/download/1.0.1%2B25/SelectaOps-v1.0.1.apk',
          }
        ],
      };

      final info = AppVersionInfo.fromGitHubRelease(json);

      expect(info.latestVersionName, equals('1.0.1'));
      expect(info.latestVersionCode, equals(25));
      expect(info.apkUrl, contains('SelectaOps-v1.0.1.apk'));
      expect(info.forceUpdate, isTrue);
      expect(info.minSupportedVersionCode, equals(20));
      expect(info.isMandatory(19), isTrue);
      expect(info.isMandatory(24), isTrue); // true because forceUpdate is true
    });

    test('isUpdateAvailable correctly compares build numbers', () {
      final info = AppVersionInfo(
        latestVersionCode: 24,
        latestVersionName: '1.0.0',
        apkUrl: 'https://example.com/app.apk',
        releaseNotes: 'Update notes',
      );

      // Current build 23 is older than 24 -> update available
      expect(info.isUpdateAvailable(23, currentVersionName: '1.0.0'), isTrue);

      // Current build 24 is equal to 24 -> no update
      expect(info.isUpdateAvailable(24, currentVersionName: '1.0.0'), isFalse);

      // Current build 25 is newer than 24 -> no update
      expect(info.isUpdateAvailable(25, currentVersionName: '1.0.0'), isFalse);
    });

    test('isUpdateAvailable returns false when apkUrl is empty', () {
      final info = AppVersionInfo(
        latestVersionCode: 99,
        latestVersionName: '2.0.0',
        apkUrl: '',
        releaseNotes: 'No APK attached',
      );

      expect(info.isUpdateAvailable(1, currentVersionName: '1.0.0'), isFalse);
    });

    test('isUpdateAvailable uses semantic version fallback when build number is missing or 0', () {
      final info = AppVersionInfo(
        latestVersionCode: 0,
        latestVersionName: '1.1.0',
        apkUrl: 'https://example.com/app.apk',
        releaseNotes: 'Feature update',
      );

      expect(info.isUpdateAvailable(0, currentVersionName: '1.0.0'), isTrue);
      expect(info.isUpdateAvailable(0, currentVersionName: '1.1.0'), isFalse);
      expect(info.isUpdateAvailable(0, currentVersionName: '2.0.0'), isFalse);
    });

    test('isVersionHigher correctly compares semantic version strings', () {
      expect(AppVersionInfo.isVersionHigher('1.0.1', '1.0.0'), isTrue);
      expect(AppVersionInfo.isVersionHigher('1.1.0', '1.0.9'), isTrue);
      expect(AppVersionInfo.isVersionHigher('2.0.0', '1.9.9'), isTrue);
      expect(AppVersionInfo.isVersionHigher('v1.0.1', '1.0.0'), isTrue);
      expect(AppVersionInfo.isVersionHigher('1.0.0', '1.0.0'), isFalse);
      expect(AppVersionInfo.isVersionHigher('1.0.0', '1.0.1'), isFalse);
    });

    test('normalizeBuildNumber correctly normalizes Flutter split-per-abi version codes', () {
      expect(AppVersionInfo.normalizeBuildNumber(2028), equals(28)); // arm64-v8a
      expect(AppVersionInfo.normalizeBuildNumber(1028), equals(28)); // armeabi-v7a
      expect(AppVersionInfo.normalizeBuildNumber(3028), equals(28)); // x86_64
      expect(AppVersionInfo.normalizeBuildNumber(28), equals(28));   // standard
      expect(AppVersionInfo.normalizeBuildNumber(0), equals(0));
    });

    test('isUpdateAvailable correctly detects update when phone has ABI-split build code (e.g. 2028 vs 29 or 2029)', () {
      // Remote has standard build number 29 (e.g. from GitHub tag or pubspec)
      final infoFromGithub = AppVersionInfo(
        latestVersionCode: 29,
        latestVersionName: '1.0.0',
        apkUrl: 'https://example.com/app.apk',
        releaseNotes: 'Update notes',
      );

      // Phone running arm64-v8a v28 (reported as 2028) vs remote 29 -> update detected!
      expect(infoFromGithub.isUpdateAvailable(2028, currentVersionName: '1.0.0'), isTrue);

      // Phone running arm64-v8a v29 (reported as 2029) vs remote 29 -> up to date!
      expect(infoFromGithub.isUpdateAvailable(2029, currentVersionName: '1.0.0'), isFalse);

      // Remote has arm64 offset build number 2029 (e.g. from Firestore or Storage)
      final infoFromStorage = AppVersionInfo(
        latestVersionCode: 2029,
        latestVersionName: '1.0.0',
        apkUrl: 'https://example.com/app.apk',
        releaseNotes: 'Update notes',
      );

      // Phone running arm64-v8a v28 (2028) vs remote 2029 -> update detected!
      expect(infoFromStorage.isUpdateAvailable(2028, currentVersionName: '1.0.0'), isTrue);

      // Phone running standard v28 (28) vs remote 2029 -> update detected!
      expect(infoFromStorage.isUpdateAvailable(28, currentVersionName: '1.0.0'), isTrue);
    });

    test('isMandatory correctly handles ABI-split build numbers', () {
      final mandatoryInfo = AppVersionInfo(
        latestVersionCode: 29,
        latestVersionName: '1.0.0',
        apkUrl: 'https://example.com/app.apk',
        releaseNotes: 'Security patch',
        forceUpdate: false,
        minSupportedVersionCode: 29,
      );

      // Phone has 2028 (normalized to 28) which is < minSupported 29 -> mandatory!
      expect(mandatoryInfo.isMandatory(2028), isTrue);

      // Phone has 2029 (normalized to 29) which is >= minSupported 29 -> not mandatory
      expect(mandatoryInfo.isMandatory(2029), isFalse);
    });
  });
}
