import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:selecta_ops/models/app_version_info.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/views/widgets/app_update_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateService {
  static const String _collectionName = 'configurations';
  static const String _versionDocName = 'app_version';
  static const String _legacyConfigDocName = 'app_config';

  static const String _githubRepoOwner = 'dwightcaballero';
  static const String _githubRepoName = 'selecta_app';
  static const String _githubReleaseUrl =
      'https://api.github.com/repos/$_githubRepoOwner/$_githubRepoName/releases/latest';

  static AppVersionInfo? _cachedVersionInfo;
  static DateTime? _lastCheckTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  final FirebaseFirestore _firestore;

  AppUpdateService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Retrieves the current application's version and build number.
  static Future<PackageInfo> getCurrentPackageInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      // Safe fallback if plugin channel not yet bound (e.g. before full native rebuild)
      return PackageInfo(
        appName: 'selecta_app',
        packageName: 'com.example.flutter_app',
        version: '1.0.0',
        buildNumber: '21',
        buildSignature: '',
      );
    }
  }

  /// Fetches the latest published release directly from GitHub Releases.
  Future<AppVersionInfo?> fetchFromGitHub() async {
    try {
      final response = await http.get(
        Uri.parse(_githubReleaseUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'SelectaOpsApp',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return AppVersionInfo.fromGitHubRelease(json);
      }
      return null;
    } catch (e, stack) {
      ErrorLogService.logError(
        action: 'AppUpdateService.fetchFromGitHub',
        error: e.toString(),
        stackTrace: stack,
        page: 'AppUpdateService',
      );
      return null;
    }
  }

  /// Fetches the latest published version information from GitHub Releases and Firestore.
  /// Prefers whichever source provides a newer version.
  Future<AppVersionInfo> getLatestVersionInfo({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedVersionInfo != null &&
        _lastCheckTime != null &&
        DateTime.now().difference(_lastCheckTime!) < _cacheDuration) {
      return _cachedVersionInfo!;
    }

    AppVersionInfo latestInfo = AppVersionInfo.empty();

    // 1. Fetch from GitHub Releases
    final githubInfo = await fetchFromGitHub();
    if (githubInfo != null && githubInfo.apkUrl.isNotEmpty) {
      latestInfo = githubInfo;
    }

    // 2. Fetch from Firestore (dedicated app_version document or legacy app_config)
    try {
      final firestoreInfo = await _fetchFromFirestore();
      if (firestoreInfo.apkUrl.isNotEmpty) {
        latestInfo = _pickNewer(latestInfo, firestoreInfo);
      }
    } catch (e, stack) {
      ErrorLogService.logError(
        action: 'AppUpdateService.getLatestVersionInfo',
        error: e.toString(),
        stackTrace: stack,
        page: 'AppUpdateService',
      );
    }

    if (latestInfo.apkUrl.isNotEmpty) {
      _cachedVersionInfo = latestInfo;
      _lastCheckTime = DateTime.now();
    }

    return latestInfo;
  }

  static AppVersionInfo _pickNewer(AppVersionInfo a, AppVersionInfo b) {
    if (a.apkUrl.isEmpty) return b;
    if (b.apkUrl.isEmpty) return a;
    if (a.latestVersionCode > b.latestVersionCode) return a;
    if (b.latestVersionCode > a.latestVersionCode) return b;
    if (AppVersionInfo.isVersionHigher(a.latestVersionName, b.latestVersionName)) return a;
    return a;
  }

  Future<AppVersionInfo> _fetchFromFirestore() async {
    try {
      // 1. Try dedicated app_version document
      final versionDoc =
          await _firestore.collection(_collectionName).doc(_versionDocName).get();
      if (versionDoc.exists && versionDoc.data() != null) {
        return AppVersionInfo.fromJson(versionDoc.data()!);
      }

      // 2. Fallback to app_config document if fields are placed there
      final configDoc = await _firestore
          .collection(_collectionName)
          .doc(_legacyConfigDocName)
          .get();
      if (configDoc.exists && configDoc.data() != null) {
        return AppVersionInfo.fromJson(configDoc.data()!);
      }

      return AppVersionInfo.empty();
    } catch (_) {
      return AppVersionInfo.empty();
    }
  }

  /// Saves or updates the latest version information in Firestore.
  Future<void> saveLatestVersionInfo(AppVersionInfo info) async {
    await _firestore
        .collection(_collectionName)
        .doc(_versionDocName)
        .set(info.toJson(), SetOptions(merge: true));
    _cachedVersionInfo = info;
    _lastCheckTime = DateTime.now();
  }

  /// Checks GitHub and Firestore and returns whether an update is available.
  Future<AppUpdateCheckResult> checkUpdate({bool forceRefresh = false}) async {
    final packageInfo = await getCurrentPackageInfo();
    final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
    final latestInfo = await getLatestVersionInfo(forceRefresh: forceRefresh);

    final isAvailable = latestInfo.isUpdateAvailable(
      currentBuild,
      currentVersionName: packageInfo.version,
    );
    final isMandatory = latestInfo.isMandatory(currentBuild);

    return AppUpdateCheckResult(
      isUpdateAvailable: isAvailable,
      isMandatory: isMandatory,
      currentVersion: packageInfo.version,
      currentBuildNumber: currentBuild,
      versionInfo: latestInfo,
    );
  }

  /// Convenient helper to check and present update prompt dialog to user.
  /// If [silent] is true, suppresses alerts if already on latest version or on network errors.
  static Future<void> checkAndPromptUpdate(
    BuildContext context, {
    bool silent = true,
    bool forceRefresh = false,
  }) async {
    try {
      final service = AppUpdateService();
      final result = await service.checkUpdate(forceRefresh: forceRefresh);

      if (!context.mounted) return;

      if (result.isUpdateAvailable) {
        await showDialog(
          context: context,
          barrierDismissible: !result.isMandatory,
          builder: (_) => AppUpdateDialog(
            versionInfo: result.versionInfo,
            currentVersion: result.currentVersion,
            currentBuildNumber: result.currentBuildNumber,
          ),
        );
      } else if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'You are already on the latest version (v${result.currentVersion}+${result.currentBuildNumber}).',
            ),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e, stack) {
      ErrorLogService.logError(
        action: 'AppUpdateService.checkAndPromptUpdate',
        error: e.toString(),
        stackTrace: stack,
        page: 'AppUpdateService',
      );
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to check for updates: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }
}

class AppUpdateCheckResult {
  final bool isUpdateAvailable;
  final bool isMandatory;
  final String currentVersion;
  final int currentBuildNumber;
  final AppVersionInfo versionInfo;

  AppUpdateCheckResult({
    required this.isUpdateAvailable,
    required this.isMandatory,
    required this.currentVersion,
    required this.currentBuildNumber,
    required this.versionInfo,
  });
}
