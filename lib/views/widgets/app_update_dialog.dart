import 'dart:io';
import 'package:flutter/material.dart';
import 'package:selecta_ops/models/app_version_info.dart';
import 'package:selecta_ops/services/app_update_service.dart';

/// Modal dialog displaying release notes and update actions.
class AppUpdateDialog extends StatelessWidget {
  final AppVersionInfo versionInfo;
  final String currentVersion;
  final int currentBuildNumber;
  final File? downloadedFile;

  const AppUpdateDialog({
    super.key,
    required this.versionInfo,
    required this.currentVersion,
    required this.currentBuildNumber,
    this.downloadedFile,
  });

  bool get isMandatory => versionInfo.isMandatory(currentBuildNumber);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ValueListenableBuilder<UpdateDownloadState>(
      valueListenable: AppUpdateService.downloadStateNotifier,
      builder: (context, downloadState, _) {
        final isReady = downloadedFile != null ||
            (downloadState.isReadyToInstall &&
                downloadState.versionInfo?.latestVersionCode ==
                    versionInfo.latestVersionCode);
        final isDownloading = downloadState.isDownloading &&
            downloadState.versionInfo?.latestVersionCode ==
                versionInfo.latestVersionCode;
        final localPath = downloadedFile?.path ?? downloadState.localFilePath;

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
                    color: isReady
                        ? Colors.greenAccent.withAlpha(40)
                        : colorScheme.primary.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isReady
                        ? Icons.check_circle_rounded
                        : Icons.system_update_rounded,
                    color: isReady ? Colors.green.shade600 : colorScheme.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isReady
                            ? 'Update Ready to Install'
                            : (isMandatory
                                ? 'Mandatory Update'
                                : 'Update Available'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'v${versionInfo.latestVersionName} (Build ${versionInfo.latestVersionCode})',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isReady ? Colors.green.shade600 : colorScheme.primary,
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
                  // Version comparison badge
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

                  // Ready or downloading banner
                  if (isReady)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade700.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade600.withAlpha(80)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.offline_pin_rounded, color: Colors.green.shade600, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'The update is already downloaded to your device. You can install it immediately without waiting.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isDownloading)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colorScheme.primary.withAlpha(60)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Downloading in background...',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              Text(
                                '${(downloadState.progress * 100).toInt()}%',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: downloadState.progress > 0
                                  ? downloadState.progress
                                  : null,
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    ),

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
                      constraints: const BoxConstraints(maxHeight: 150),
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

                  if (isMandatory && !isReady)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.error.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.error.withAlpha(60)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: colorScheme.error, size: 20),
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
              if (isReady && localPath != null) ...[
                if (!isMandatory)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Later'),
                  ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    AppUpdateService.installApk(localPath, context);
                  },
                  icon: const Icon(Icons.install_mobile_rounded, size: 18),
                  label: const Text('Install Now'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ] else if (isDownloading) ...[
                TextButton(
                  onPressed: () {
                    AppUpdateService.cancelDownload();
                  },
                  child: const Text('Cancel Download'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Continue Working'),
                ),
              ] else ...[
                if (!isMandatory)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Later'),
                  ),
                if (!isMandatory)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      AppUpdateService.startBackgroundDownload(
                        versionInfo,
                        context: context,
                        showNotificationOnComplete: true,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          content: Text(
                            'Downloading Selecta Ops v${versionInfo.latestVersionName} in background. You can continue working!',
                          ),
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    },
                    icon: const Icon(Icons.cloud_download_outlined, size: 16),
                    label: const Text('Download in Background'),
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
            ],
          ),
        );
      },
    );
  }

  void _startDownloadAndInstall(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppUpdateDownloadDialog(
        versionInfo: versionInfo,
      ),
    );
  }
}

/// Download progress dialog with real-time percentage, background option, and cancellation.
class AppUpdateDownloadDialog extends StatefulWidget {
  final AppVersionInfo versionInfo;

  const AppUpdateDownloadDialog({
    super.key,
    required this.versionInfo,
  });

  @override
  State<AppUpdateDownloadDialog> createState() => _AppUpdateDownloadDialogState();
}

class _AppUpdateDownloadDialogState extends State<AppUpdateDownloadDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppUpdateService.startBackgroundDownload(
        widget.versionInfo,
        context: context,
        showNotificationOnComplete: true,
      );
    });
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

    return ValueListenableBuilder<UpdateDownloadState>(
      valueListenable: AppUpdateService.downloadStateNotifier,
      builder: (context, downloadState, _) {
        final hasError = downloadState.isFailed;
        final isReady = downloadState.isReadyToInstall &&
            downloadState.localFilePath != null;
        final progress = downloadState.progress;
        final percentText = (progress * 100).toInt();

        // If download finished while dialog is displayed, close dialog and open installer
        if (isReady && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).pop();
              AppUpdateService.installApk(downloadState.localFilePath!, context);
            }
          });
        }

        return PopScope(
          canPop: true,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              hasError ? 'Download Error' : 'Downloading Update',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasError) ...[
                  Text(
                    'Failed to download update APK:\n${downloadState.errorMessage ?? "Unknown error"}',
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Please check your internet connection or verify the APK URL.',
                    style: theme.textTheme.bodySmall,
                  ),
                ] else ...[
                  Text(
                    'Downloading Selecta Ops v${widget.versionInfo.latestVersionName}...',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress > 0 ? progress : null,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$percentText%',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        downloadState.totalBytes > 0
                            ? '${_formatBytes(downloadState.receivedBytes)} / ${_formatBytes(downloadState.totalBytes)}'
                            : _formatBytes(downloadState.receivedBytes),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              if (hasError) ...[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
                FilledButton(
                  onPressed: () {
                    AppUpdateService.startBackgroundDownload(
                      widget.versionInfo,
                      context: context,
                      showNotificationOnComplete: true,
                    );
                  },
                  child: const Text('Retry'),
                ),
              ] else ...[
                TextButton(
                  onPressed: () {
                    AppUpdateService.cancelDownload();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        content: Text(
                          'Downloading Selecta Ops v${widget.versionInfo.latestVersionName} in background. You can keep working!',
                        ),
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  },
                  icon: const Icon(Icons.cloud_download_outlined, size: 16),
                  label: const Text('Download in Background'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
