import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/attendance_controller.dart';
import 'package:selecta_ops/models/attendance.dart';

class WeeklyTimesheetCard extends StatefulWidget {
  final String salesmanUsername;
  final DateTime startDate;
  final DateTime endDate;
  final ValueChanged<double> onApplyCalculatedDays;

  const WeeklyTimesheetCard({
    super.key,
    required this.salesmanUsername,
    required this.startDate,
    required this.endDate,
    required this.onApplyCalculatedDays,
  });

  @override
  State<WeeklyTimesheetCard> createState() => _WeeklyTimesheetCardState();
}

class _WeeklyTimesheetCardState extends State<WeeklyTimesheetCard> {
  final AttendanceController _controller = AttendanceController();
  final DateFormat _dayFormat = DateFormat('EEE, MMM d');
  final DateFormat _shortTime = DateFormat('hh:mm a');

  bool _isLoading = true;
  List<Attendance> _attendances = [];
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _fetchTimesheet();
  }

  @override
  void didUpdateWidget(covariant WeeklyTimesheetCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.salesmanUsername != widget.salesmanUsername ||
        oldWidget.startDate != widget.startDate ||
        oldWidget.endDate != widget.endDate) {
      _fetchTimesheet();
    }
  }

  Future<void> _fetchTimesheet() async {
    setState(() => _isLoading = true);
    try {
      final list = await _controller.getWeeklyTimesheet(
        salesmanUsername: widget.salesmanUsername,
        startDate: widget.startDate,
        endDate: widget.endDate,
      );
      if (mounted) {
        setState(() {
          _attendances = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Builds a map of all days in the week range from startDate to endDate
  List<DateTime> get _daysInWeek {
    final List<DateTime> days = [];
    DateTime current = DateTime(widget.startDate.year, widget.startDate.month, widget.startDate.day);
    final end = DateTime(widget.endDate.year, widget.endDate.month, widget.endDate.day);
    while (!current.isAfter(end)) {
      days.add(current);
      current = current.add(const Duration(days: 1));
    }
    return days;
  }

  Attendance? _findAttendanceForDay(DateTime day) {
    final dateStr = DateFormat('yyyy-MM-dd').format(day);
    try {
      return _attendances.firstWhere((a) => a.dateString == dateStr);
    } catch (_) {
      return null;
    }
  }

  double get _totalCalculatedDays {
    double sum = 0.0;
    for (final a in _attendances) {
      sum += a.effectiveCredit;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalDays = _totalCalculatedDays;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        children: [
          // Header / Toggle
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.calendar_month_outlined, color: colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Weekly Attendance Timesheet',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _isLoading
                              ? 'Loading timecards...'
                              : 'Total: ${totalDays.toStringAsFixed(1)} days worked this week',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isLoading && totalDays > 0)
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => widget.onApplyCalculatedDays(totalDays),
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 14),
                      label: Text('Apply (${totalDays.toStringAsFixed(1)})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  IconButton(
                    icon: Icon(_isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _isExpanded = !_isExpanded),
                  ),
                ],
              ),
            ),
          ),

          if (_isExpanded) ...[
            const Divider(height: 1),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                itemCount: _daysInWeek.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final day = _daysInWeek[index];
                  final record = _findAttendanceForDay(day);
                  return _buildDayRow(day, record, theme, colorScheme);
                },
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildDayRow(DateTime day, Attendance? record, ThemeData theme, ColorScheme colorScheme) {
    final dayLabel = _dayFormat.format(day);
    final hasClockIn = record != null && record.isClockedIn;
    final hasClockOut = record != null && record.isClockedOut;

    final inStr = hasClockIn ? _shortTime.format(record.clockInTime!.toDate()) : '--';
    final outStr = hasClockOut ? _shortTime.format(record.clockOutTime!.toDate()) : '--';
    final durationStr = (record != null && record.totalHours > 0)
        ? '${record.totalHours} hrs'
        : (hasClockIn && !hasClockOut ? 'Active' : 'Absent');

    final credit = record?.effectiveCredit ?? 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Date
          SizedBox(
            width: 90,
            child: Text(
              dayLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: hasClockIn ? FontWeight.bold : FontWeight.normal,
                color: hasClockIn ? null : colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          // In & Out
          Expanded(
            child: Text(
              hasClockIn ? '$inStr - $outStr' : 'No Record',
              style: TextStyle(
                fontSize: 11,
                color: hasClockIn ? colorScheme.onSurface : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),

          // Duration
          SizedBox(
            width: 65,
            child: Text(
              durationStr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: durationStr == 'Active' ? const Color(0xFFF59E0B) : colorScheme.onSurfaceVariant,
                fontWeight: durationStr == 'Active' ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),

          // Day Credit Chip
          Container(
            width: 72,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: credit >= 1.0
                  ? const Color(0xFF10B981).withValues(alpha: 0.12)
                  : (credit > 0
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
                      : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              credit >= 1.0
                  ? '1.0 Day'
                  : (credit > 0 ? '0.5 Day' : '0.0 Day'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: credit >= 1.0
                    ? const Color(0xFF059669)
                    : (credit > 0 ? const Color(0xFFD97706) : colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
