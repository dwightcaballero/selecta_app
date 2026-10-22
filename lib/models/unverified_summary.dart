import 'package:flutter/material.dart';

/// Exception thrown when attempting to verify a date while an older unverified date exists.
class OlderUnverifiedException implements Exception {
  final String message;
  final DateTime oldestDate;

  OlderUnverifiedException(this.message, {required this.oldestDate});

  @override
  String toString() => message;
}

/// Consolidated summary of unverified breakdown records within the backlog window.
class UnverifiedSummary {
  final int count;
  final DateTime? oldest;
  final Set<DateTime> dates;

  const UnverifiedSummary({
    required this.count,
    this.oldest,
    required this.dates,
  });

  factory UnverifiedSummary.fromDates(Set<DateTime> dates) {
    if (dates.isEmpty) return empty;
    final sorted = dates.toList()..sort();
    return UnverifiedSummary(
      count: dates.length,
      oldest: sorted.first,
      dates: dates,
    );
  }

  static const empty = UnverifiedSummary(
    count: 0,
    oldest: null,
    dates: <DateTime>{},
  );

  bool get hasUnverified => count > 0;
  DateTime? get oldestDate => oldest;

  /// Whole local days between today and oldest unverified date.
  /// If today is the only unverified date, returns 0 (today is not overdue).
  int get oldestAgeDays => UnverifiedAgeHelper.calculateAgeInDays(oldest);
}

/// Helper methods for determining backlog age and associated visual severity styling.
class UnverifiedAgeHelper {
  /// Returns the age in whole days from [oldestDate] relative to [relativeTo] (or today).
  /// Excludes today / future dates by returning 0.
  static int calculateAgeInDays(DateTime? oldestDate, {DateTime? relativeTo}) {
    if (oldestDate == null) return 0;
    final now = relativeTo ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(oldestDate.year, oldestDate.month, oldestDate.day);
    final diff = today.difference(target).inDays;
    return diff > 0 ? diff : 0;
  }

  /// Badge color according to age thresholds:
  /// - 0-1 days: neutral / default color
  /// - 2 days: amber (Colors.amber.shade800)
  /// - 3+ days: red (Colors.red.shade700)
  static Color getBadgeColor(int ageInDays, ColorScheme colorScheme) {
    if (ageInDays >= 3) {
      return Colors.red.shade700;
    } else if (ageInDays == 2) {
      return Colors.amber.shade800;
    } else {
      return colorScheme.primary;
    }
  }

  /// Banner background color according to age thresholds.
  static Color getBannerColor(int ageInDays, {required bool isDark}) {
    if (ageInDays >= 3) {
      return isDark ? const Color(0xFF7F1D1D).withAlpha(120) : const Color(0xFFFEE2E2);
    } else if (ageInDays == 2) {
      return isDark ? const Color(0xFF78350F).withAlpha(120) : const Color(0xFFFEF3C7);
    } else {
      return isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    }
  }

  /// Banner border color according to age thresholds.
  static Color getBannerBorderColor(int ageInDays, {required bool isDark}) {
    if (ageInDays >= 3) {
      return isDark ? Colors.red.shade800 : Colors.red.shade300;
    } else if (ageInDays == 2) {
      return isDark ? Colors.amber.shade800 : Colors.amber.shade400;
    } else {
      return isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1);
    }
  }

  /// Banner text / icon color according to age thresholds.
  static Color getBannerTextColor(int ageInDays, {required bool isDark}) {
    if (ageInDays >= 3) {
      return isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B);
    } else if (ageInDays == 2) {
      return isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E);
    } else {
      return isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);
    }
  }

  /// Text subtitle or tooltip describing the backlog age.
  static String getOverdueText(int ageInDays) {
    if (ageInDays <= 0) return 'Today';
    if (ageInDays == 1) return 'Oldest: 1 day overdue';
    return 'Oldest: $ageInDays days overdue';
  }
}
