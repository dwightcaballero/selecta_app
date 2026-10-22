import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/unverified_summary.dart';
import 'package:selecta_ops/views/pages/sidebar/endofday_page.dart';
import 'package:selecta_ops/views/widgets/dashboard/unverified_dates_sheet.dart';

/// In-app reminder banner displayed on the dashboard when unverified breakdown backlog exists.
/// Escalates severity and colors based on age (amber at 2 days, red at 3+ days).
class UnverifiedBanner extends StatefulWidget {
  final UnverifiedSummary summary;
  final Stream<UnverifiedSummary>? summaryStream;
  final Future<void> Function(Widget page)? onNavigate;

  const UnverifiedBanner({
    super.key,
    required this.summary,
    this.summaryStream,
    this.onNavigate,
  });

  /// Static in-memory session flag for dismissal (re-appears next app start).
  static bool sessionDismissed = false;

  @override
  State<UnverifiedBanner> createState() => _UnverifiedBannerState();
}

class _UnverifiedBannerState extends State<UnverifiedBanner> {
  void _openReview(DateTime? date) {
    if (widget.onNavigate != null) {
      widget.onNavigate!(EndofdayPage(initialDate: date));
    } else {
      openEndOfDay(context, oldestUnverified: date);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.summaryStream != null) {
      return StreamBuilder<UnverifiedSummary>(
        stream: widget.summaryStream,
        initialData: widget.summary,
        builder: (context, snapshot) {
          final effectiveSummary = snapshot.data ?? widget.summary;
          return _buildBannerContent(effectiveSummary);
        },
      );
    }

    return _buildBannerContent(widget.summary);
  }

  Widget _buildBannerContent(UnverifiedSummary summary) {
    if (UnverifiedBanner.sessionDismissed || !summary.hasUnverified) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final age = summary.oldestAgeDays;

    final bgColor = UnverifiedAgeHelper.getBannerColor(age, isDark: isDark);
    final borderColor = UnverifiedAgeHelper.getBannerBorderColor(age, isDark: isDark);
    final textColor = UnverifiedAgeHelper.getBannerTextColor(age, isDark: isDark);
    final iconColor = age >= 3
        ? Colors.red.shade700
        : (age == 2 ? Colors.amber.shade800 : theme.colorScheme.primary);

    final count = summary.count;
    final titleText = '$count day${count == 1 ? '' : 's'} need verification';
    final oldestText = age <= 0
        ? (summary.oldest != null ? 'Today: ${DateFormat('d MMM').format(summary.oldest!)}' : 'Today')
        : 'Oldest: $age day${age == 1 ? '' : 's'} overdue (${DateFormat('d MMM').format(summary.oldest!)})';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(isDark ? 50 : 30),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.assignment_late_outlined, size: 20, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleText,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      oldestText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: textColor.withAlpha(220),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.close, size: 18, color: textColor.withAlpha(180)),
                tooltip: 'Dismiss for this session',
                onPressed: () {
                  setState(() {
                    UnverifiedBanner.sessionDismissed = true;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: textColor,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => UnverifiedDatesSheet.show(
                  context,
                  summary: summary,
                  onSelectDate: (d) => _openReview(d),
                ),
                child: const Text('View all dates', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: iconColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                label: const Text('Review', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                onPressed: () => _openReview(summary.oldest),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
