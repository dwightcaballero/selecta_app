import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/models/unverified_summary.dart';
import 'package:selecta_ops/views/pages/sidebar/endofday_page.dart';

/// Bottom sheet listing all unverified breakdown dates within the backlog scan window.
class UnverifiedDatesSheet extends StatelessWidget {
  final UnverifiedSummary summary;
  final void Function(DateTime date)? onSelectDate;

  const UnverifiedDatesSheet({
    super.key,
    required this.summary,
    this.onSelectDate,
  });

  /// Static helper to display the sheet modal.
  static Future<void> show(
    BuildContext context, {
    required UnverifiedSummary summary,
    void Function(DateTime date)? onSelectDate,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UnverifiedDatesSheet(
        summary: summary,
        onSelectDate: onSelectDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final sortedDates = summary.dates.toList()..sort();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2430) : theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant.withAlpha(120),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade800.withAlpha(isDark ? 50 : 30),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.history_toggle_off_rounded, color: Colors.amber.shade800, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Needs Verification',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                        Text(
                          '${summary.count} unverified breakdown day${summary.count == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),

            // Date list
            if (sortedDates.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No unverified dates in backlog.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: sortedDates.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final date = sortedDates[index];
                    final age = UnverifiedAgeHelper.calculateAgeInDays(date);
                    final dotColor = age >= 3
                        ? Colors.red.shade700
                        : (age == 2 ? Colors.amber.shade800 : colorScheme.primary);

                    final ageText = age == 0
                        ? 'Today (pending)'
                        : (age == 1 ? '1 day overdue' : '$age days overdue');

                    return Material(
                      color: isDark ? const Color(0xFF283042) : colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.pop(context);
                          if (onSelectDate != null) {
                            onSelectDate!(date);
                          } else {
                            openEndOfDay(context, oldestUnverified: date);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: dotColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  DateFormat('EEE, d MMM yyyy').format(date),
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: dotColor.withAlpha(isDark ? 40 : 25),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  ageText,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: dotColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(Icons.chevron_right, size: 18, color: colorScheme.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
