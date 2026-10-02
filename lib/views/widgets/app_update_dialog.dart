import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/models/app_version_info.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Modal dialog displaying release notes and update action.
class AppUpdateDialog extends StatelessWidget {
  final AppVersionInfo versionInfo;
  final String currentVersion;
  final int currentBuildNumber;

  const AppUpdateDialog({
    super.key,
    required this.versionInfo,
    required this.currentVersion,
    required this.currentBuildNumber,
  });

  bool get isMandatory => versionInfo.isMandatory(currentBuildNumber);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: !isMandatory,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primary.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.system_update_rounded,
                color: colorScheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isMandatory ? 'Mandatory Update' : 'Update Available',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'v${versionInfo.latestVersionName} (Build ${versionInfo.latestVersionCode})',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // Version info badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(120),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Current: v$currentVersion+$currentBuildNumber',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withAlpha(180),
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded, size: 14),
                    Text(
                      'New: v${versionInfo.latestVersionName}+${versionInfo.latestVersionCode}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Release notes section
              if (versionInfo.releaseNotes.trim().isNotEmpty) ...[
                Text(
                  "What's New:",
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 160),
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLowest,
                    border: Border.all(color: theme.dividerColor.withAlpha(50)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      versionInfo.releaseNotes,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (isMandatory)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.error.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.error.withAlpha(60)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This update is required to continue using the application.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.error,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (!isMandatory)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _startDownloadAndInstall(context);
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Update Now'),
          ),
        ],
      ),
    );
  }

  void _startDownloadAndInstall(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppUpdateDownloadDialog(
        apkUrl: versionInfo.apkUrl,
        versionName: versionInfo.latestVersionName,
      ),
    );
  }
}

/// Download progress dialog with real-time percentage and cancellation.
class AppUpdateDownloadDialog extends StatefulWidget {
  final String apkUrl;
  final String versionName;

  const AppUpdateDownloadDialog({
    super.key,
    required this.apkUrl,
    required this.versionName,
  });

  @override
  State<AppUpdateDownloadDialog> createState() => _AppUpdateDownloadDialogState();
}

class _AppUpdateDownloadDialogState extends State<AppUpdateDownloadDialog> {
  final CancelToken _cancelToken = CancelToken();
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String _statusMessage = 'Connecting...';
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  @override
  void dispose() {
    _cancelToken.cancel('Dialog closed');
    super.dispose();
  }

  Future<void> _startDownload() async {
    try {
      // 1. Check install permission on Android
      if (Platform.isAndroid) {
        final installPermissionStatus = await Permission.requestInstallPackages.status;
        if (!installPermissionStatus.isGranted) {
          final requested = await Permission.requestInstallPackages.request();
          if (!requested.isGranted) {
            // Some devices require opening settings manually
            if (mounted) {
              setState(() {
                _statusMessage = 'Permission needed to install apps';
              });
            }
          }
        }
      }

      // 2. Prepare file destination
      final tempDir = await getTemporaryDirectory();
      final sanitizedVersion = widget.versionName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final savePath = '${tempDir.path}/selecta_app_$sanitizedVersion.apk';

      final file = File(savePath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      setState(() {
        _statusMessage = 'Downloading update...';
      });

      // 3. Download APK via Dio
      final dio = Dio();
      await dio.download(
        widget.apkUrl,
        savePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (mounted) {
            setState(() {
              _receivedBytes = received;
              _totalBytes = total;
              if (total > 0) {
                _progress = received / total;
              }
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _progress = 1.0;
        _statusMessage = 'Opening installer...';
      });

      // Close download dialog
      Navigator.of(context).pop();

      // 4. Trigger Android APK Installer via OpenFilex
      final result = await OpenFilex.open(
        savePath,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done && mounted) {
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
      }
    } catch (e) {
      if (_cancelToken.isCancelled) return;
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _statusMessage = 'Download failed';
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final percentText = (_progress * 100).toInt();

    return PopScope(
      canPop: _hasError,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _hasError ? 'Update Error' : 'Downloading Update',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_hasError) ...[
              Text(
                'Failed to download update APK:\n$_errorMessage',
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
              ),
              const SizedBox(height: 12),
              Text(
                'Please check your internet connection or verify the APK URL.',
                style: theme.textTheme.bodySmall,
              ),
            ] else ...[
              Text(
                _statusMessage,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _totalBytes > 0 ? _progress : null,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$percentText%',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _totalBytes > 0
                        ? '${_formatBytes(_receivedBytes)} / ${_formatBytes(_totalBytes)}'
                        : _formatBytes(_receivedBytes),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          if (_hasError) ...[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _errorMessage = '';
                  _progress = 0.0;
                });
                _startDownload();
              },
              child: const Text('Retry'),
            ),
          ] else
            TextButton(
              onPressed: () {
                _cancelToken.cancel();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
        ],
      ),
    );
  }
}
