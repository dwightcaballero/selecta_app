import 'package:flutter/material.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class SnackBarWidget {
  const SnackBarWidget._();

  static void success(BuildContext context, String message) {
    _show(context, message: message, icon: Icons.check_circle_outline_rounded, backgroundColor: const Color(0xFF2E7D32));
  }

  static void error(BuildContext context, String message) {
    _show(context, message: message, icon: Icons.error_outline_rounded, backgroundColor: const Color(0xFFD32F2F));
  }

  static void warning(BuildContext context, String message) {
    _show(context, message: message, icon: Icons.warning_amber_rounded, backgroundColor: const Color(0xFFE65100));
  }

  static void info(BuildContext context, String message) {
    _show(context, message: message, icon: Icons.info_outline_rounded, backgroundColor: Theme.of(context).colorScheme.primary);
  }

  /// Displays a floating retry toast to reassure the user when network or Gemini request slows down.
  static void showRetryToast(String message) {
    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFE65100),
          margin: const EdgeInsets.all(16),
          elevation: 6,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
  }

  static void _show(BuildContext context, {required String message, required IconData icon, required Color backgroundColor}) {
    final messenger = ScaffoldMessenger.maybeOf(context) ?? rootScaffoldMessengerKey.currentState;

    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: backgroundColor,
          margin: const EdgeInsets.all(16),
          elevation: 4,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
  }
}
