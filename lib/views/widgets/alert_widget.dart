import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/views/widgets/snackbar_widget.dart';

class ShowMessage {
  static void listError(BuildContext context, List<String> listError) {
    if (listError.isEmpty) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.error_outline_rounded, color: Colors.red, size: 32),
          ),
          title: const Text('Validation Errors', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, decoration: TextDecoration.none)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Please resolve the following issues before continuing:', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant, decoration: TextDecoration.none)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: listError.map((err) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '• ',
                            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
                          ),
                          Expanded(
                            child: Text(err, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, decoration: TextDecoration.none)),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  static void error(BuildContext context, String error) {
    SnackBarWidget.error(context, error);
  }

  static void warning(BuildContext context, String warning) {
    SnackBarWidget.warning(context, warning);
  }

  static void info(BuildContext context, String info) {
    SnackBarWidget.info(context, info);
  }

  static void success(BuildContext context, String message) {
    SnackBarWidget.success(context, message);
  }

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    bool isDestructive = false,
    IconData? icon,
    bool barrierDismissible = true,
    Color? iconColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        final effectiveIconColor = iconColor ?? (isDestructive ? Colors.red : colorScheme.primary);
        return PopScope(
          canPop: barrierDismissible,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            icon: icon != null
                ? Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: effectiveIconColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: Icon(icon, color: effectiveIconColor, size: 32),
                  )
                : null,
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, decoration: TextDecoration.none)),
            content: Text(message, style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant, decoration: TextDecoration.none)),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(cancelText)),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: isDestructive ? Colors.red.shade600 : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(confirmText),
              ),
            ],
          ),
        );
      },
    );
    return result ?? false;
  }

  static Future<void> alert(
    BuildContext context, {
    required String title,
    required String message,
    IconData? icon,
    String buttonText = 'OK',
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: icon != null
              ? Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Icon(icon, color: colorScheme.primary, size: 32),
                )
              : null,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, decoration: TextDecoration.none)),
          content: Text(message, style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant, decoration: TextDecoration.none)),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(buttonText),
            ),
          ],
        );
      },
    );
  }

  /// Runs an asynchronous [task] while presenting a non-dismissible loading overlay
  /// to communicate ongoing work to the user and prevent duplicate taps or navigation.
  ///
  /// If the task completes successfully, returns the result of type [T].
  /// If the task throws an error, the overlay is dismissed, and if [showError] is true,
  /// a snackbar error message is automatically displayed to the user.
  static Future<T?> runWithLoading<T>(
    BuildContext context, {
    required Future<T> Function() task,
    String message = 'Processing, please wait...',
    bool showError = true,
    bool rethrowError = false,
  }) async {
    HapticFeedback.lightImpact();

    BuildContext? dialogContext;
    var isDialogClosed = false;

    // Show non-dismissible loading dialog
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) {
        dialogContext = ctx;
        final colorScheme = Theme.of(ctx).colorScheme;
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.8),
                  ),
                  const SizedBox(width: 18),
                  Flexible(
                    child: Text(
                      message,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      final result = await task();
      return result;
    } catch (e) {
      if (showError && context.mounted) {
        error(context, e.toString().replaceAll('Exception: ', ''));
      }
      if (rethrowError) rethrow;
      return null;
    } finally {
      if (!isDialogClosed) {
        isDialogClosed = true;
        if (dialogContext != null && dialogContext!.mounted) {
          Navigator.of(dialogContext!).pop();
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (dialogContext != null && dialogContext!.mounted) {
              Navigator.of(dialogContext!).pop();
            }
          });
        }
      }
    }
  }
}
