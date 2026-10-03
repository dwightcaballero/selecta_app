import 'package:flutter/material.dart';

/// Central breakpoint and layout helper for the Selecta Ops app.
///
/// Breakpoints (based on Material 3 / Flutter adaptive guidelines):
///   Phone   : width <  600dp
///   Tablet  : width >= 600dp && < 840dp
///   Desktop : width >= 840dp  (Windows, Linux, Browser, large tablet landscape)
///   Wide    : width >= 1200dp (large monitors / browsers)
class ScreenSize {
  ScreenSize._();

  static const double _kTablet = 600.0;
  static const double _kDesktop = 840.0;
  static const double _kWideDesktop = 1200.0;

  // ── Tier checks ──────────────────────────────────────────────────────────

  /// True when width < 600dp (phone portrait/landscape)
  static bool isPhone(BuildContext ctx) =>
      MediaQuery.sizeOf(ctx).width < _kTablet;

  /// True when 600dp <= width < 840dp (tablet portrait / small tablet landscape)
  static bool isTablet(BuildContext ctx) {
    final w = MediaQuery.sizeOf(ctx).width;
    return w >= _kTablet && w < _kDesktop;
  }

  /// True when width >= 840dp (desktop, browser, large tablet landscape)
  static bool isDesktop(BuildContext ctx) =>
      MediaQuery.sizeOf(ctx).width >= _kDesktop;

  /// True when width >= 1200dp (wide monitors, maximised browser windows)
  static bool isWideDesktop(BuildContext ctx) =>
      MediaQuery.sizeOf(ctx).width >= _kWideDesktop;

  /// True when running on a device that is NOT a phone
  static bool isLargeScreen(BuildContext ctx) =>
      MediaQuery.sizeOf(ctx).width >= _kTablet;

  // ── Content width helpers ────────────────────────────────────────────────

  /// Maximum width for the main content area.
  /// Returns [double.infinity] on phones (full width).
  static double contentMaxWidth(BuildContext ctx) {
    final w = MediaQuery.sizeOf(ctx).width;
    if (w >= _kWideDesktop) return 1100;
    if (w >= _kDesktop) return 920;
    return double.infinity;
  }

  /// Responsive horizontal padding for page bodies.
  static EdgeInsets pagePadding(BuildContext ctx) {
    if (isWideDesktop(ctx)) {
      return const EdgeInsets.symmetric(horizontal: 56, vertical: 24);
    }
    if (isDesktop(ctx)) {
      return const EdgeInsets.symmetric(horizontal: 32, vertical: 20);
    }
    if (isTablet(ctx)) {
      return const EdgeInsets.symmetric(horizontal: 20, vertical: 16);
    }
    return const EdgeInsets.fromLTRB(14, 14, 14, 28);
  }

  // ── Convenience picker ───────────────────────────────────────────────────

  /// Returns [phone], [tablet], or [desktop] value based on the current width.
  static T pick<T>(
    BuildContext ctx, {
    required T phone,
    required T tablet,
    required T desktop,
    T? wideDesktop,
  }) {
    if (wideDesktop != null && isWideDesktop(ctx)) return wideDesktop;
    if (isDesktop(ctx)) return desktop;
    if (isTablet(ctx)) return tablet;
    return phone;
  }
}
