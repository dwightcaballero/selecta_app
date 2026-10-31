import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/attendance_controller.dart';
import 'package:selecta_ops/models/attendance.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';

class ClockOutDialog extends StatefulWidget {
  final Users salesman;
  final Attendance currentAttendance;
  final VoidCallback onClockedOut;

  const ClockOutDialog({
    super.key,
    required this.salesman,
    required this.currentAttendance,
    required this.onClockedOut,
  });

  /// Static helper to display the clock-out dialog
  static Future<void> show(
    BuildContext context, {
    required Users salesman,
    required Attendance currentAttendance,
    required VoidCallback onClockedOut,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => ClockOutDialog(
        salesman: salesman,
        currentAttendance: currentAttendance,
        onClockedOut: onClockedOut,
      ),
    );
  }

  @override
  State<ClockOutDialog> createState() => _ClockOutDialogState();
}

class _ClockOutDialogState extends State<ClockOutDialog> {
  final AttendanceController _controller = AttendanceController();
  final DateFormat _shortTime = DateFormat('hh:mm a');

  Timer? _timer;
  DateTime _currentTime = DateTime.now();

  bool _isAcquiringLocation = true;
  LocationCheckResult? _locationResult;

  @override
  void initState() {
    super.initState();
    _startClock();
    _checkLocation();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startClock() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _currentTime = DateTime.now());
      }
    });
  }

  Future<void> _checkLocation() async {
    setState(() => _isAcquiringLocation = true);
    final result = await _controller.checkCurrentLocation();
    if (mounted) {
      setState(() {
        _isAcquiringLocation = false;
        _locationResult = result;
      });
    }
  }

  double get _currentDurationHours {
    if (widget.currentAttendance.clockInTime == null) return 0.0;
    final inTime = widget.currentAttendance.clockInTime!.toDate();
    final diff = _currentTime.difference(inTime).inMinutes / 60.0;
    return diff > 0 ? double.parse(diff.toStringAsFixed(2)) : 0.0;
  }

  String _formatDuration(double hours) {
    final int h = hours.floor();
    final int m = ((hours - h) * 60).round();
    return '${h}h ${m}m';
  }

  Future<void> _handleClockOut() async {
    try {
      await _controller.clockOut(
        salesman: widget.salesman,
        position: _locationResult?.position,
        distanceMeters: _locationResult?.distanceMeters,
        isWithinGeofence: _locationResult?.isWithinGeofence ?? false,
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onClockedOut();
        ShowMessage.success(
          context,
          'Clock-out recorded! You have clocked out for the day.',
        );
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Clock-out failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hoursWorked = _currentDurationHours;
    final creditPreview = Attendance.calculateStandardCredit(hoursWorked);

    final clockInString = widget.currentAttendance.clockInTime != null
        ? _shortTime.format(widget.currentAttendance.clockInTime!.toDate())
        : 'N/A';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Icon
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.logout_rounded,
                size: 38,
                color: Color(0xFFEF4444),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              'Clock Out',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'End of day sign-off for ${widget.salesman.username}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 20),

            // Time & Metrics Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMetric(
                        label: 'Clocked In',
                        value: clockInString,
                        icon: Icons.login_rounded,
                        color: const Color(0xFF10B981),
                      ),
                      Container(
                        width: 1,
                        height: 36,
                        color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                      _buildMetric(
                        label: 'Clock Out (Now)',
                        value: _shortTime.format(_currentTime),
                        icon: Icons.logout_rounded,
                        color: const Color(0xFFEF4444),
                      ),
                      Container(
                        width: 1,
                        height: 36,
                        color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                      _buildMetric(
                        label: 'Total Hours',
                        value: _formatDuration(hoursWorked),
                        icon: Icons.timer_outlined,
                        color: colorScheme.primary,
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Day Credit Earned:',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: creditPreview >= 1.0
                              ? const Color(0xFF10B981).withValues(alpha: 0.15)
                              : (creditPreview > 0
                                  ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                                  : colorScheme.surfaceContainerHighest),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          creditPreview >= 1.0
                              ? '1.0 Day'
                              : (creditPreview > 0 ? '0.5 Day' : '0.0 Day'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: creditPreview >= 1.0
                                ? const Color(0xFF059669)
                                : (creditPreview > 0
                                    ? const Color(0xFFD97706)
                                    : colorScheme.onSurface),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Location Check Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: _getLocationBackgroundColor(colorScheme),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _getLocationBorderColor(colorScheme)),
              ),
              child: Row(
                children: [
                  _buildLocationIcon(colorScheme),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isAcquiringLocation
                          ? 'Checking location...'
                          : (_locationResult?.locationSummary ?? 'Location checked'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _getLocationTextColor(colorScheme),
                      ),
                    ),
                  ),
                  if (_isAcquiringLocation)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AsyncFilledButton.icon(
                    onPressed: _handleClockOut,
                    label: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.bold)),
                    icon: const Icon(Icons.logout_rounded),
                    loadingLabel: 'Clocking Out...',
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }

  Color _getLocationBackgroundColor(ColorScheme colorScheme) {
    if (_isAcquiringLocation) {
      return colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
    }
    if (_locationResult?.isWithinGeofence ?? false) {
      return const Color(0xFF10B981).withValues(alpha: 0.12);
    }
    return const Color(0xFFF59E0B).withValues(alpha: 0.12);
  }

  Color _getLocationBorderColor(ColorScheme colorScheme) {
    if (_isAcquiringLocation) {
      return colorScheme.outlineVariant.withValues(alpha: 0.4);
    }
    if (_locationResult?.isWithinGeofence ?? false) {
      return const Color(0xFF10B981).withValues(alpha: 0.4);
    }
    return const Color(0xFFF59E0B).withValues(alpha: 0.4);
  }

  Color _getLocationTextColor(ColorScheme colorScheme) {
    if (_isAcquiringLocation) return colorScheme.onSurface;
    if (_locationResult?.isWithinGeofence ?? false) {
      return const Color(0xFF059669);
    }
    return const Color(0xFFD97706);
  }

  Widget _buildLocationIcon(ColorScheme colorScheme) {
    if (_isAcquiringLocation) {
      return Icon(Icons.gps_fixed_rounded, size: 20, color: colorScheme.primary);
    }
    if (_locationResult?.isWithinGeofence ?? false) {
      return const Icon(Icons.check_circle_rounded,
          size: 20, color: Color(0xFF10B981));
    }
    return const Icon(Icons.location_on_rounded,
        size: 20, color: Color(0xFFF59E0B));
  }
}
