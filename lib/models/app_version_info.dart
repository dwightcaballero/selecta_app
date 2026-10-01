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

  bool isUpdateAvailable(int currentBuildNumber) {
    return latestVersionCode > currentBuildNumber && apkUrl.trim().isNotEmpty;
  }

  bool isMandatory(int currentBuildNumber) {
    return forceUpdate || currentBuildNumber < minSupportedVersionCode;
  }
}
