import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum DayStatus {
  pending,
  done,
}

/// Month-grid date picker dialog that shows red dots on pending dates and green dots on verified/done dates.
Future<DateTime?> showMarkedDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  Set<DateTime>? markedDates,
  Map<DateTime, DayStatus>? dayStatuses,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final Map<DateTime, DayStatus> effectiveStatuses = {};
  if (dayStatuses != null) {
    for (final entry in dayStatuses.entries) {
      effectiveStatuses[DateTime(entry.key.year, entry.key.month, entry.key.day)] = entry.value;
    }
  } else if (markedDates != null) {
    for (final d in markedDates) {
      effectiveStatuses[DateTime(d.year, d.month, d.day)] = DayStatus.pending;
    }
  }

  return showDialog<DateTime>(
    context: context,
    builder: (_) => _MarkedDatePickerDialog(
      initialDate: initialDate,
      dayStatuses: effectiveStatuses,
      firstDate: firstDate ?? DateTime(2000),
      lastDate: lastDate ?? DateTime.now(),
    ),
  );
}

class _MarkedDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final Map<DateTime, DayStatus> dayStatuses;
  final DateTime firstDate;
  final DateTime lastDate;

  const _MarkedDatePickerDialog({
    required this.initialDate,
    required this.dayStatuses,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_MarkedDatePickerDialog> createState() => _MarkedDatePickerDialogState();
}

class _MarkedDatePickerDialogState extends State<_MarkedDatePickerDialog> {
  late DateTime _month = DateTime(widget.initialDate.year, widget.initialDate.month);

  DateTime _d(DateTime d) => DateTime(d.year, d.month, d.day);

  int _pendingInMonth(DateTime m) => widget.dayStatuses.entries
      .where((e) => e.key.year == m.year && e.key.month == m.month && e.value == DayStatus.pending)
      .length;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final offset = DateUtils.firstDayOffset(_month.year, _month.month, MaterialLocalizations.of(context));
    final today = _d(DateTime.now());
    final selected = _d(widget.initialDate);
    final first = _d(widget.firstDate);
    final last = _d(widget.lastDate);
    final canPrev = DateTime(_month.year, _month.month).isAfter(DateTime(first.year, first.month));
    final canNext = DateTime(_month.year, _month.month).isBefore(DateTime(last.year, last.month));
    final pending = _pendingInMonth(_month);
    final labels = MaterialLocalizations.of(context).narrowWeekdays;
    final startDay = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final hasDoneStatuses = widget.dayStatuses.values.contains(DayStatus.done);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: canPrev ? () => setState(() => _month = DateTime(_month.year, _month.month - 1)) : null,
                  ),
                  Expanded(
                    child: Text(
                      DateFormat('MMMM yyyy').format(_month),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: canNext ? () => setState(() => _month = DateTime(_month.year, _month.month + 1)) : null,
                  ),
                ],
              ),
              Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(child: Center(child: Text(labels[(startDay + i) % 7], style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)))),
                ],
              ),
              const SizedBox(height: 4),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (var i = 0; i < offset; i++) const SizedBox.shrink(),
                  for (var day = 1; day <= daysInMonth; day++) _dayCell(cs, DateTime(_month.year, _month.month, day), today, selected, first, last),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.circle, size: 7, color: Colors.red),
                            const SizedBox(width: 4),
                            Text(
                              pending > 0 ? '$pending Pending' : 'Pending',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                        if (hasDoneStatuses)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.circle, size: 7, color: Colors.green),
                              const SizedBox(width: 4),
                              Text(
                                'Verified',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayCell(ColorScheme cs, DateTime date, DateTime today, DateTime selected, DateTime first, DateTime last) {
    final enabled = !date.isBefore(first) && !date.isAfter(last);
    final isSelected = date == selected;
    final status = widget.dayStatuses[date];
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: enabled ? () => Navigator.pop(context, date) : null,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? cs.primary : null,
          border: date == today && !isSelected ? Border.all(color: cs.primary) : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(color: !enabled ? cs.onSurface.withValues(alpha: 0.38) : isSelected ? cs.onPrimary : cs.onSurface),
            ),
            if (status != null)
              Positioned(
                bottom: 5,
                child: Icon(
                  Icons.circle,
                  size: 6,
                  color: status == DayStatus.done ? Colors.green : Colors.red,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
