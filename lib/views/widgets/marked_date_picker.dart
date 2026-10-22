import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Month-grid date picker dialog that shows a red dot on [markedDates].
Future<DateTime?> showMarkedDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required Set<DateTime> markedDates,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _MarkedDatePickerDialog(
      initialDate: initialDate,
      markedDates: markedDates,
      firstDate: firstDate ?? DateTime(2000),
      lastDate: lastDate ?? DateTime.now(),
    ),
  );
}

class _MarkedDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final Set<DateTime> markedDates;
  final DateTime firstDate;
  final DateTime lastDate;

  const _MarkedDatePickerDialog({
    required this.initialDate,
    required this.markedDates,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_MarkedDatePickerDialog> createState() => _MarkedDatePickerDialogState();
}

class _MarkedDatePickerDialogState extends State<_MarkedDatePickerDialog> {
  late DateTime _month = DateTime(widget.initialDate.year, widget.initialDate.month);

  DateTime _d(DateTime d) => DateTime(d.year, d.month, d.day);

  int _markedInMonth(DateTime m) => widget.markedDates.where((d) => d.year == m.year && d.month == m.month).length;

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
    final pending = _markedInMonth(_month);
    final labels = MaterialLocalizations.of(context).narrowWeekdays;
    final startDay = MaterialLocalizations.of(context).firstDayOfWeekIndex;

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
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.circle, size: 8, color: Colors.red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      pending > 0 ? '$pending day${pending == 1 ? '' : 's'} pending dealer verification this month' : 'Pending dealer verification',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
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
    final isMarked = widget.markedDates.contains(date);
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
            if (isMarked) const Positioned(bottom: 5, child: Icon(Icons.circle, size: 6, color: Colors.red)),
          ],
        ),
      ),
    );
  }
}
