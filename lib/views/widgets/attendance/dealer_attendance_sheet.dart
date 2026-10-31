import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/attendance_controller.dart';
import 'package:selecta_ops/models/attendance.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';

class DealerAttendanceSheet extends StatefulWidget {
  final Users dealer;

  const DealerAttendanceSheet({
    super.key,
    required this.dealer,
  });

  /// Static helper to show the dealer attendance management sheet
  static Future<void> show(BuildContext context, {required Users dealer}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DealerAttendanceSheet(dealer: dealer),
    );
  }

  @override
  State<DealerAttendanceSheet> createState() => _DealerAttendanceSheetState();
}

class _DealerAttendanceSheetState extends State<DealerAttendanceSheet> {
  final AttendanceController _controller = AttendanceController();
  final DateFormat _timeFormat = DateFormat('hh:mm a');
  final DateFormat _dateFormat = DateFormat('EEEE, MMM d, yyyy');

  final DateTime _selectedDate = DateTime.now();

  Future<void> _approveIn(Attendance record) async {
    try {
      await _controller.approveClockIn(record.id, widget.dealer.username);
      if (mounted) {
        ShowMessage.success(context, 'Clock-in approved for ${record.salesmanUsername}.');
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to approve clock-in: $e');
    }
  }

  Future<void> _approveOut(Attendance record) async {
    try {
      await _controller.approveClockOut(record.id, widget.dealer.username);
      if (mounted) {
        ShowMessage.success(context, 'Clock-out approved for ${record.salesmanUsername}.');
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to approve clock-out: $e');
    }
  }

  Future<void> _batchApproveAll() async {
    try {
      final count = await _controller.batchApproveAll(
        widget.dealer.dealerName,
        _selectedDate,
        widget.dealer.username,
      );
      if (mounted) {
        if (count > 0) {
          ShowMessage.success(context, 'Successfully approved $count pending attendance record(s).');
        } else {
          ShowMessage.info(context, 'No pending attendance records to approve.');
        }
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Batch approval failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.88;

    return Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.badge_outlined, color: colorScheme.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Salesman Attendance',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _dateFormat.format(_selectedDate),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                AsyncFilledButton.icon(
                  onPressed: _batchApproveAll,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.done_all_rounded, size: 16),
                  label: const Text('Approve All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content List
          Expanded(
            child: StreamBuilder<List<Attendance>>(
              stream: _controller.streamDealerAttendances(
                widget.dealer.dealerName,
                _selectedDate,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final attendances = snapshot.data ?? [];
                if (attendances.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.event_available_outlined,
                            size: 56,
                            color: colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No attendance records yet today',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Salesmen clock-in records will appear here live when they open their app.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: attendances.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final record = attendances[index];
                    return _buildAttendanceCard(record, theme, colorScheme);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard(Attendance record, ThemeData theme, ColorScheme colorScheme) {
    final inTimeStr = record.clockInTime != null
        ? _timeFormat.format(record.clockInTime!.toDate())
        : 'N/A';
    final outTimeStr = record.clockOutTime != null
        ? _timeFormat.format(record.clockOutTime!.toDate())
        : 'Active (On Duty)';

    final isInPending = record.clockInStatus == AttendanceStatus.pending;
    final isOutPending = record.clockOutStatus == AttendanceStatus.pending && record.isClockedOut;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isInPending || isOutPending)
              ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Salesman name & status
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                child: Text(
                  record.salesmanUsername.isNotEmpty
                      ? record.salesmanUsername[0].toUpperCase()
                      : 'S',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.salesmanUsername,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    if (record.clockInDistanceToDepot != null)
                      Text(
                        record.clockInWithinGeofence
                            ? 'At Depot (${record.clockInDistanceToDepot!.round()}m)'
                            : 'Off-site (${record.clockInDistanceToDepot!.round()}m from depot)',
                        style: TextStyle(
                          fontSize: 11,
                          color: record.clockInWithinGeofence
                              ? const Color(0xFF059669)
                              : const Color(0xFFD97706),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              if (record.isClockedOut)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${record.dayCredit} Day',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF059669),
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 20),

          // Clock In Row
          Row(
            children: [
              const Icon(Icons.login_rounded, size: 16, color: Color(0xFF10B981)),
              const SizedBox(width: 8),
              Text(
                'Clock In: $inTimeStr',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (record.isClockInApproved)
                const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
                    SizedBox(width: 4),
                    Text(
                      'Approved',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF059669),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              else if (isInPending)
                OutlinedButton.icon(
                  onPressed: () => _approveIn(record),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF10B981),
                    side: const BorderSide(color: Color(0xFF10B981)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 14),
                  label: const Text('Approve In', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Clock Out Row
          Row(
            children: [
              Icon(
                Icons.logout_rounded,
                size: 16,
                color: record.isClockedOut ? const Color(0xFFEF4444) : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                'Clock Out: $outTimeStr',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: record.isClockedOut ? null : Colors.grey,
                ),
              ),
              const Spacer(),
              if (record.isClockedOut) ...[
                if (record.isClockOutApproved)
                  const Row(
                    children: [
                      Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
                      SizedBox(width: 4),
                      Text(
                        'Approved',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF059669),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                else if (isOutPending)
                  OutlinedButton.icon(
                    onPressed: () => _approveOut(record),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF10B981),
                      side: const BorderSide(color: Color(0xFF10B981)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 14),
                    label: const Text('Approve Out', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
              ],
            ],
          ),

          if (record.isClockedOut) ...[
            const SizedBox(height: 6),
            Text(
              'Total Duration: ${record.totalHours} hrs',
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
