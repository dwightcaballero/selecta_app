import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:selecta_ops/services/error_log_service.dart';

/// Central handling for errors emitted by long-lived Firestore listeners.
class FirestoreStreamErrors {
  FirestoreStreamErrors._();

  static bool isPermissionDenied(Object error) =>
      error is FirebaseException && error.code == 'permission-denied';

  /// A permission-denied error while no user is signed in is expected: the
  /// listener outlived the session (e.g. during sign-out).
  static bool isExpectedSignedOutError(Object error) =>
      isPermissionDenied(error) && FirebaseAuth.instance.currentUser == null;

  /// Reports a listener error as non-fatal. Returns without reporting when the
  /// error is an expected signed-out permission-denied.
  static void report(Object error, StackTrace? stack, {required String source}) {
    if (isExpectedSignedOutError(error)) return;
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        reason: 'Firestore stream error: $source',
        fatal: false,
      );
    }
    ErrorLogService.logError(
      action: 'FirestoreStream_$source',
      error: error.toString(),
      stackTrace: stack,
    );
  }

  /// Returns an `onError` callback for `Stream.listen` for the given [source].
  static void Function(Object, StackTrace) handler(String source) {
    return (Object error, StackTrace stack) =>
        report(error, stack, source: source);
  }
}
