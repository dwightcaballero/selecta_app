import 'package:flutter/material.dart';
import 'package:flutter_app/views/widgets/snackbar_widget.dart';

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
          title: const Text('Validation Errors', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Please resolve the following issues before continuing:', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
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
                            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                          ),
                          Expanded(
                            child: Text(err, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: icon != null
              ? Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: (isDestructive ? Colors.red : colorScheme.primary).withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Icon(icon, color: isDestructive ? Colors.red : colorScheme.primary, size: 32),
                )
              : null,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: Text(message, style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant)),
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
        );
      },
    );
    return result ?? false;
  }
}
