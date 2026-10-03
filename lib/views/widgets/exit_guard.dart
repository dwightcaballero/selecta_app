import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A widget that intercepts the Android system back button on root screens.
///
/// Behavior flow on back button press:
/// 1. Runs [onBackIntercept] first. If it returns `true` (e.g. closing an open drawer
///    or navigating from an inner tab back to Home tab 0), the exit prompt is skipped.
/// 2. If [onBackIntercept] returns `false` (or is null):
///    - First press: Displays a floating SnackBar prompt ("Press back again to exit") with a 2-second timeout.
///    - Second press within 2 seconds: Closes the app cleanly via [SystemNavigator.pop()].
class ExitGuard extends StatefulWidget {
  final Widget child;

  /// Optional callback to intercept back press before exit logic.
  /// Return `true` if the back press was handled (e.g. tab changed or drawer closed),
  /// or `false` to proceed to exit guard logic.
  final bool Function()? onBackIntercept;

  /// Time window within which the user must press back again to exit.
  final Duration exitTimeout;

  /// Custom message shown on the SnackBar. Defaults to 'Press back again to exit'.
  final String message;

  const ExitGuard({
    super.key,
    required this.child,
    this.onBackIntercept,
    this.exitTimeout = const Duration(seconds: 2),
    this.message = 'Press back again to exit',
  });

  @override
  State<ExitGuard> createState() => _ExitGuardState();
}

class _ExitGuardState extends State<ExitGuard> {
  DateTime? _lastBackTime;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;

        // 1. Give parent a chance to handle (e.g. close drawer or switch to tab 0)
        if (widget.onBackIntercept != null && widget.onBackIntercept!()) {
          _lastBackTime = null; // Reset exit timer on tab switch / intercept
          return;
        }

        // 2. Double-back detection
        final now = DateTime.now();
        if (_lastBackTime == null || now.difference(_lastBackTime!) > widget.exitTimeout) {
          _lastBackTime = now;

          final messenger = ScaffoldMessenger.maybeOf(context);
          if (messenger != null) {
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.exit_to_app_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                behavior: SnackBarBehavior.floating,
                duration: widget.exitTimeout,
                elevation: 4,
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
          return;
        }

        // Second press within the timeout -> exit app cleanly
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
        SystemNavigator.pop();
      },
      child: widget.child,
    );
  }
}
