import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/models/app_version_info.dart';
import 'package:flutter_app/services/error_log_service.dart';
import 'package:flutter_app/views/widgets/app_update_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateService {
  static const String _collectionName = 'configurations';
  static const String _versionDocName = 'app_version';
  static const String _legacyConfigDocName = 'app_config';

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

  /// Fetches the latest published version information from Firestore.
  Future<AppVersionInfo> getLatestVersionInfo() async {
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
    } catch (e, stack) {
      ErrorLogService.logError(
        action: 'AppUpdateService.getLatestVersionInfo',
        error: e.toString(),
        stackTrace: stack,
        page: 'AppUpdateService',
      );
      return AppVersionInfo.empty();
    }
  }

  /// Saves or updates the latest version information in Firestore.
  Future<void> saveLatestVersionInfo(AppVersionInfo info) async {
    await _firestore
        .collection(_collectionName)
        .doc(_versionDocName)
        .set(info.toJson(), SetOptions(merge: true));
  }

  /// Checks Firestore and returns whether an update is available.
  Future<AppUpdateCheckResult> checkUpdate() async {
    final packageInfo = await getCurrentPackageInfo();
    final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
    final latestInfo = await getLatestVersionInfo();

    final isAvailable = latestInfo.isUpdateAvailable(currentBuild);
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
  }) async {
    try {
      final service = AppUpdateService();
      final result = await service.checkUpdate();

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
