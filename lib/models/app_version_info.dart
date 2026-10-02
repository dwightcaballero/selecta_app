import 'package:cloud_firestore/cloud_firestore.dart';

class AppVersionInfo {
  final int latestVersionCode;
  final String latestVersionName;
  final String apkUrl;
  final String releaseNotes;
  final bool forceUpdate;
  final int minSupportedVersionCode;
  final DateTime? publishedAt;

  AppVersionInfo({
    required this.latestVersionCode,
    required this.latestVersionName,
    required this.apkUrl,
    required this.releaseNotes,
    this.forceUpdate = false,
    this.minSupportedVersionCode = 1,
    this.publishedAt,
  });

  static AppVersionInfo empty() => AppVersionInfo(
        latestVersionCode: 0,
        latestVersionName: '1.0.0',
        apkUrl: '',
        releaseNotes: '',
        forceUpdate: false,
        minSupportedVersionCode: 0,
        publishedAt: null,
      );

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    DateTime? publishedDate;
    final rawPublished = json['publishedAt'];
    if (rawPublished is Timestamp) {
      publishedDate = rawPublished.toDate();
    } else if (rawPublished is String) {
      publishedDate = DateTime.tryParse(rawPublished);
    }

    return AppVersionInfo(
      latestVersionCode: (json['latestVersionCode'] as num?)?.toInt() ??
          (json['versionCode'] as num?)?.toInt() ??
          (json['buildNumber'] as num?)?.toInt() ??
          0,
      latestVersionName: json['latestVersionName'] as String? ??
          json['versionName'] as String? ??
          json['version'] as String? ??
          '1.0.0',
      apkUrl: json['apkUrl'] as String? ?? json['downloadUrl'] as String? ?? '',
      releaseNotes: json['releaseNotes'] as String? ??
          json['changelog'] as String? ??
          '',
      forceUpdate: json['forceUpdate'] as bool? ?? false,
      minSupportedVersionCode:
          (json['minSupportedVersionCode'] as num?)?.toInt() ?? 1,
      publishedAt: publishedDate,
    );
  }

  factory AppVersionInfo.fromGitHubRelease(Map<String, dynamic> json) {
    final rawTag = (json['tag_name'] as String? ?? '').trim();
    final cleanTag = rawTag.replaceFirst(RegExp(r'^[vV]'), '');

    String versionName = cleanTag;
    int versionCode = 0;

    if (cleanTag.contains('+')) {
      final parts = cleanTag.split('+');
      versionName = parts[0];
      versionCode = int.tryParse(parts[1]) ?? 0;
    } else if (cleanTag.isNotEmpty) {
      versionName = cleanTag;
      final name = json['name'] as String? ?? '';
      final match = RegExp(r'Build\s*(\d+)', caseSensitive: false).firstMatch(name);
      if (match != null) {
        versionCode = int.tryParse(match.group(1)!) ?? 0;
      }
    }

    String apkUrl = '';
    final assets = json['assets'] as List<dynamic>? ?? [];
    for (final asset in assets) {
      if (asset is Map<String, dynamic>) {
        final assetName = (asset['name'] as String? ?? '').toLowerCase();
        if (assetName.endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String? ?? '';
          if (assetName == 'app-release.apk') break;
        }
      }
    }

    final body = (json['body'] as String? ?? '').trim();
    final isForce = body.contains('[force-update]') || body.contains('[mandatory]');
    int minVersion = 1;
    final minMatch = RegExp(r'\[min-version:\s*(\d+)\]', caseSensitive: false).firstMatch(body);
    if (minMatch != null) {
      minVersion = int.tryParse(minMatch.group(1)!) ?? 1;
    }

    DateTime? publishedDate;
    final rawDate = json['published_at'];
    if (rawDate is String) {
      publishedDate = DateTime.tryParse(rawDate);
    }

    return AppVersionInfo(
      latestVersionCode: versionCode,
      latestVersionName: versionName.isEmpty ? '1.0.0' : versionName,
      apkUrl: apkUrl,
      releaseNotes: body,
      forceUpdate: isForce,
      minSupportedVersionCode: minVersion,
      publishedAt: publishedDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latestVersionCode': latestVersionCode,
      'latestVersionName': latestVersionName,
      'apkUrl': apkUrl,
      'releaseNotes': releaseNotes,
      'forceUpdate': forceUpdate,
      'minSupportedVersionCode': minSupportedVersionCode,
      'publishedAt': publishedAt != null ? Timestamp.fromDate(publishedAt!) : FieldValue.serverTimestamp(),
    };
  }

  /// Determines if this version is an update over [currentBuildNumber] and [currentVersionName].
  bool isUpdateAvailable(int currentBuildNumber, {String currentVersionName = ''}) {
    if (apkUrl.trim().isEmpty) return false;

    // Check build numbers first if both are available and positive
    if (latestVersionCode > 0 && currentBuildNumber > 0) {
      if (latestVersionCode > currentBuildNumber) return true;
      if (latestVersionCode < currentBuildNumber) return false;
    }

    // If build numbers are tied or missing, compare semantic versions
    if (currentVersionName.isNotEmpty && latestVersionName.isNotEmpty) {
      return isVersionHigher(latestVersionName, currentVersionName);
    }

    return false;
  }

  /// Compares two semver strings like "1.0.1" vs "1.0.0", returning true if [newVersion] > [currentVersion].
  static bool isVersionHigher(String newVersion, String currentVersion) {
    try {
      final cleanNew = newVersion.replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
      final cleanCurrent = currentVersion.replaceFirst(RegExp(r'^[vV]'), '').split('+').first;

      final newParts = cleanNew.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      final currentParts = cleanCurrent.split('.').map((p) => int.tryParse(p) ?? 0).toList();

      for (int i = 0; i < 3; i++) {
        final n = i < newParts.length ? newParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (n > c) return true;
        if (n < c) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  bool isMandatory(int currentBuildNumber) {
    return forceUpdate || currentBuildNumber < minSupportedVersionCode;
  }
}
