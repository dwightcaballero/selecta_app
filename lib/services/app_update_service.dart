import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:selecta_ops/models/app_version_info.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/views/widgets/app_update_dialog.dart';

enum UpdateDownloadStatus {
  idle,
  downloading,
  readyToInstall,
  failed,
}

class UpdateDownloadState {
  final UpdateDownloadStatus status;
  final double progress; // 0.0 to 1.0
  final int receivedBytes;
  final int totalBytes;
  final String? localFilePath;
  final String? errorMessage;
  final AppVersionInfo? versionInfo;

  const UpdateDownloadState({
    this.status = UpdateDownloadStatus.idle,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.localFilePath,
    this.errorMessage,
    this.versionInfo,
  });

  bool get isDownloading => status == UpdateDownloadStatus.downloading;
  bool get isReadyToInstall => status == UpdateDownloadStatus.readyToInstall;
  bool get isFailed => status == UpdateDownloadStatus.failed;
}

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

  /// Global notifier for tracking background APK download progress and state.
  static final ValueNotifier<UpdateDownloadState> downloadStateNotifier =
      ValueNotifier<UpdateDownloadState>(const UpdateDownloadState());

  static CancelToken? _activeCancelToken;

  final FirebaseFirestore _firestore;

  AppUpdateService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Retrieves the current application's version and build number.
  static Future<PackageInfo> getCurrentPackageInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return PackageInfo(
        appName: 'selecta_app',
        packageName: 'com.example.flutter_app',
        version: '1.0.0',
        buildNumber: '21',
        buildSignature: '',
      );
    }
  }

  /// Checks if an APK for this update has already been completely downloaded and verified on disk.
  static Future<File?> getDownloadedApkFile(AppVersionInfo info) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final sanitizedVersion =
          '${info.latestVersionName}_${info.latestVersionCode}'
              .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final expectedPath = '${tempDir.path}/selecta_app_$sanitizedVersion.apk';
      final file = File(expectedPath);

      if (await file.exists()) {
        final length = await file.length();
        // A compiled release APK is expected to be >= 12MB.
        final isSizeValid = info.fileSize > 0
            ? length >= (info.fileSize * 0.95)
            : length > (12 * 1024 * 1024);

        if (isSizeValid) {
          return file;
        } else {
          // File was corrupted or truncated, delete it
          await file.delete().catchError((_) => file);
        }
      }

      // Cleanup stale APK and .part files from older versions to save storage
      try {
        final dir = Directory(tempDir.path);
        final entities = await dir.list().toList();
        for (final entity in entities) {
          if (entity is File) {
            final name = entity.uri.pathSegments.last;
            if (name.startsWith('selecta_app_') &&
                (name.endsWith('.apk') || name.endsWith('.part')) &&
                name != 'selecta_app_$sanitizedVersion.apk') {
              await entity.delete().catchError((_) => entity);
            }
          }
        }
      } catch (_) {}

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Downloads the update APK silently in the background.
  /// If [showNotificationOnComplete] is true, shows an instant "Install Now" banner when done.
  static Future<void> startBackgroundDownload(
    AppVersionInfo info, {
    BuildContext? context,
    bool showNotificationOnComplete = true,
  }) async {
    if (downloadStateNotifier.value.isDownloading &&
        downloadStateNotifier.value.versionInfo?.latestVersionCode ==
            info.latestVersionCode) {
      return;
    }

    // Check if already downloaded
    final existingFile = await getDownloadedApkFile(info);
    if (existingFile != null) {
      downloadStateNotifier.value = UpdateDownloadState(
        status: UpdateDownloadStatus.readyToInstall,
        progress: 1.0,
        localFilePath: existingFile.path,
        receivedBytes: existingFile.lengthSync(),
        totalBytes: existingFile.lengthSync(),
        versionInfo: info,
      );
      if (showNotificationOnComplete && context != null && context.mounted) {
        showReadyToInstallBanner(context, info, existingFile.path);
      }
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final sanitizedVersion =
          '${info.latestVersionName}_${info.latestVersionCode}'
              .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final finalPath = '${tempDir.path}/selecta_app_$sanitizedVersion.apk';
      final partPath = '$finalPath.part';

      final partFile = File(partPath);
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }

      _activeCancelToken?.cancel('Restarting background download');
      _activeCancelToken = CancelToken();

      downloadStateNotifier.value = UpdateDownloadState(
        status: UpdateDownloadStatus.downloading,
        progress: 0.0,
        versionInfo: info,
      );

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 15),
          headers: {
            'User-Agent': 'SelectaOpsApp',
          },
        ),
      );

      await dio.download(
        info.apkUrl,
        partPath,
        cancelToken: _activeCancelToken,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          final effectiveTotal = total > 0 ? total : info.fileSize;
          final progress = effectiveTotal > 0
              ? (received / effectiveTotal).clamp(0.0, 1.0)
              : 0.0;
          downloadStateNotifier.value = UpdateDownloadState(
            status: UpdateDownloadStatus.downloading,
            progress: progress,
            receivedBytes: received,
            totalBytes: effectiveTotal,
            versionInfo: info,
          );
        },
      );

      // Successfully finished download, rename .part to final .apk
      final downloadedPart = File(partPath);
      if (await downloadedPart.exists()) {
        await downloadedPart.rename(finalPath);
      }

      downloadStateNotifier.value = UpdateDownloadState(
        status: UpdateDownloadStatus.readyToInstall,
        progress: 1.0,
        localFilePath: finalPath,
        receivedBytes: File(finalPath).lengthSync(),
        totalBytes: File(finalPath).lengthSync(),
        versionInfo: info,
      );

      if (showNotificationOnComplete && context != null && context.mounted) {
        showReadyToInstallBanner(context, info, finalPath);
      }
    } catch (e, stack) {
      if (_activeCancelToken?.isCancelled ?? false) {
        downloadStateNotifier.value =
            const UpdateDownloadState(status: UpdateDownloadStatus.idle);
        return;
      }
      downloadStateNotifier.value = UpdateDownloadState(
        status: UpdateDownloadStatus.failed,
        errorMessage: e.toString(),
        versionInfo: info,
      );
      ErrorLogService.logError(
        action: 'AppUpdateService.startBackgroundDownload',
        error: e.toString(),
        stackTrace: stack,
        page: 'AppUpdateService',
      );
    }
  }

  /// Cancels an in-progress background download.
  static void cancelDownload() {
    _activeCancelToken?.cancel('Cancelled by user');
    downloadStateNotifier.value =
        const UpdateDownloadState(status: UpdateDownloadStatus.idle);
  }

  /// Triggers the native Android installer for a downloaded APK file.
  static Future<bool> installApk(String filePath, BuildContext context) async {
    try {
      if (Platform.isAndroid) {
        final installPermissionStatus =
            await Permission.requestInstallPackages.status;
        if (!installPermissionStatus.isGranted) {
          final requested = await Permission.requestInstallPackages.request();
          if (!requested.isGranted && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Permission needed: Please enable "Install unknown apps" for Selecta Ops to update.',
                ),
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: 'Settings',
                  onPressed: () => openAppSettings(),
                ),
              ),
            );
            return false;
          }
        }
      }

      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open installer: ${result.message}. If prompted, please allow "Install unknown apps" in Settings.',
            ),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
        return false;
      }
      return true;
    } catch (e, stack) {
      ErrorLogService.logError(
        action: 'AppUpdateService.installApk',
        error: e.toString(),
        stackTrace: stack,
        page: 'AppUpdateService',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open installer: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return false;
    }
  }

  /// Shows a non-intrusive bottom notification banner when an update is downloaded and ready to install.
  static void showReadyToInstallBanner(
    BuildContext context,
    AppVersionInfo info,
    String filePath,
  ) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 15),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: const Color(0xFF1E293B),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withAlpha(40),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Colors.greenAccent,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Update Ready to Install',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Selecta Ops v${info.latestVersionName} is downloaded.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withAlpha(200),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'INSTALL NOW',
          textColor: Colors.greenAccent,
          onPressed: () {
            installApk(filePath, context);
          },
        ),
      ),
    );
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

    // 1. Fetch from Firestore (configurations/app_version)
    try {
      final firestoreInfo = await _fetchFromFirestore();
      if (firestoreInfo.apkUrl.isNotEmpty) {
        latestInfo = firestoreInfo;
      }
    } catch (e, stack) {
      ErrorLogService.logError(
        action: 'AppUpdateService.getLatestVersionInfo (Firestore)',
        error: e.toString(),
        stackTrace: stack,
        page: 'AppUpdateService',
      );
    }

    // 2. Fetch directly from Firebase Storage (releases/)
    try {
      final storageInfo = await _fetchFromFirebaseStorage();
      if (storageInfo != null && storageInfo.apkUrl.isNotEmpty) {
        latestInfo = _pickNewer(latestInfo, storageInfo);
      }
    } catch (e, stack) {
      ErrorLogService.logError(
        action: 'AppUpdateService.getLatestVersionInfo (FirebaseStorage)',
        error: e.toString(),
        stackTrace: stack,
        page: 'AppUpdateService',
      );
    }

    // 3. Fetch from GitHub Releases (as fallback)
    final githubInfo = await fetchFromGitHub();
    if (githubInfo != null && githubInfo.apkUrl.isNotEmpty) {
      latestInfo = _pickNewer(latestInfo, githubInfo);
    }

    if (latestInfo.apkUrl.isNotEmpty) {
      _cachedVersionInfo = latestInfo;
      _lastCheckTime = DateTime.now();
    }

    return latestInfo;
  }

  /// Checks Firebase Storage for release APKs published in `releases/`.
  Future<AppVersionInfo?> _fetchFromFirebaseStorage() async {
    try {
      final storage = FirebaseStorage.instance;
      Reference? ref;
      FullMetadata? metadata;

      // 1. Check arm64-v8a first (modern mobile phones)
      try {
        final r = storage.ref('releases/app-arm64-v8a-release.apk');
        metadata = await r.getMetadata();
        ref = r;
      } catch (_) {}

      // 2. Fallback to app-release.apk
      if (ref == null) {
        try {
          final r = storage.ref('releases/app-release.apk');
          metadata = await r.getMetadata();
          ref = r;
        } catch (_) {}
      }

      if (ref == null || metadata == null) return null;

      final downloadUrl = await ref.getDownloadURL();
      final custom = metadata.customMetadata ?? {};

      final versionCode = int.tryParse(custom['versionCode'] ?? custom['buildNumber'] ?? '') ?? 0;
      final versionName = custom['versionName'] ?? custom['version'] ?? '1.0.0';
      final releaseNotes = custom['releaseNotes'] ?? '';
      final forceUpdate = custom['forceUpdate'] == 'true';

      return AppVersionInfo(
        latestVersionCode: versionCode,
        latestVersionName: versionName,
        apkUrl: downloadUrl,
        releaseNotes: releaseNotes,
        forceUpdate: forceUpdate,
        fileSize: metadata.size ?? 0,
        publishedAt: metadata.updated,
      );
    } catch (_) {
      return null;
    }
  }

  static AppVersionInfo _pickNewer(AppVersionInfo a, AppVersionInfo b) {
    if (a.apkUrl.isEmpty) return b;
    if (b.apkUrl.isEmpty) return a;

    final isAFastCdn = a.apkUrl.contains('firebasestorage') || a.apkUrl.contains('storage.googleapis.com');
    final isBFastCdn = b.apkUrl.contains('firebasestorage') || b.apkUrl.contains('storage.googleapis.com');

    // If version codes differ significantly
    if (a.latestVersionCode > b.latestVersionCode) {
      // If version code of a is higher, but b is the same semver and hosted on fast Firebase CDN
      if (a.latestVersionName == b.latestVersionName && isBFastCdn && !isAFastCdn) {
        return b;
      }
      return a;
    }
    if (b.latestVersionCode > a.latestVersionCode) {
      return b;
    }

    // When versions are tied, ALWAYS prefer the Firebase Storage / Google CDN URL over GitHub
    if (isBFastCdn && !isAFastCdn) return b;
    if (isAFastCdn && !isBFastCdn) return a;

    if (AppVersionInfo.isVersionHigher(a.latestVersionName, b.latestVersionName)) return a;
    if (AppVersionInfo.isVersionHigher(b.latestVersionName, a.latestVersionName)) return b;
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

  /// Helper to check and present update prompt dialog or start silent background download.
  /// If [silent] is true:
  /// - If the APK is already downloaded, shows the "Ready to Install" banner.
  /// - If not downloaded and update is optional, starts downloading silently in the background!
  /// - If not downloaded and update is mandatory, presents the mandatory update dialog.
  static Future<void> checkAndPromptUpdate(
    BuildContext context, {
    bool silent = true,
    bool forceRefresh = false,
  }) async {
    ScaffoldMessengerState? messenger;
    if (!silent && context.mounted) {
      messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Checking for updates...'),
            ],
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }

    try {
      final service = AppUpdateService();
      final result = await service.checkUpdate(forceRefresh: forceRefresh);

      messenger?.hideCurrentSnackBar();

      if (!context.mounted) return;

      if (result.isUpdateAvailable) {
        final downloadedApk = await getDownloadedApkFile(result.versionInfo);

        if (downloadedApk != null) {
          downloadStateNotifier.value = UpdateDownloadState(
            status: UpdateDownloadStatus.readyToInstall,
            progress: 1.0,
            localFilePath: downloadedApk.path,
            receivedBytes: downloadedApk.lengthSync(),
            totalBytes: downloadedApk.lengthSync(),
            versionInfo: result.versionInfo,
          );

          if (!context.mounted) return;

          if (silent) {
            showReadyToInstallBanner(context, result.versionInfo, downloadedApk.path);
          } else {
            await showDialog(
              context: context,
              barrierDismissible: !result.isMandatory,
              builder: (_) => AppUpdateDialog(
                versionInfo: result.versionInfo,
                currentVersion: result.currentVersion,
                currentBuildNumber: result.currentBuildNumber,
                downloadedFile: downloadedApk,
              ),
            );
          }
        } else if (result.isMandatory) {
          if (!context.mounted) return;
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AppUpdateDialog(
              versionInfo: result.versionInfo,
              currentVersion: result.currentVersion,
              currentBuildNumber: result.currentBuildNumber,
            ),
          );
        } else if (silent) {
          if (!context.mounted) return;
          // Silent mode: Start downloading in background so user can continue work!
          startBackgroundDownload(
            result.versionInfo,
            context: context,
            showNotificationOnComplete: true,
          );
        } else {
          if (!context.mounted) return;
          // Manual trigger from menu
          await showDialog(
            context: context,
            barrierDismissible: true,
            builder: (_) => AppUpdateDialog(
              versionInfo: result.versionInfo,
              currentVersion: result.currentVersion,
              currentBuildNumber: result.currentBuildNumber,
            ),
          );
        }
      } else if (!silent) {
        messenger?.showSnackBar(
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
      messenger?.hideCurrentSnackBar();
      ErrorLogService.logError(
        action: 'AppUpdateService.checkAndPromptUpdate',
        error: e.toString(),
        stackTrace: stack,
        page: 'AppUpdateService',
      );
      if (!silent && context.mounted) {
        messenger?.showSnackBar(
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
