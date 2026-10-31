import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/attendance_controller.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';

class ClockInGateDialog extends StatefulWidget {
  final Users salesman;
  final VoidCallback onClockedIn;

  const ClockInGateDialog({
    super.key,
    required this.salesman,
    required this.onClockedIn,
  });

  /// Static helper to display the modal gate
  static Future<void> show(
    BuildContext context, {
    required Users salesman,
    required VoidCallback onClockedIn,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ClockInGateDialog(
        salesman: salesman,
        onClockedIn: onClockedIn,
      ),
    );
  }

  @override
  State<ClockInGateDialog> createState() => _ClockInGateDialogState();
}

class _ClockInGateDialogState extends State<ClockInGateDialog> {
  final AttendanceController _controller = AttendanceController();
  final DateFormat _timeFormat = DateFormat('hh:mm:ss a');
  final DateFormat _dateFormat = DateFormat('EEEE, MMMM d, yyyy');

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

  Future<void> _handleClockIn() async {
    try {
      await _controller.clockIn(
        salesman: widget.salesman,
        position: _locationResult?.position,
        distanceMeters: _locationResult?.distanceMeters,
        isWithinGeofence: _locationResult?.isWithinGeofence ?? false,
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onClockedIn();
        ShowMessage.success(
          context,
          'Clock-in recorded! You may now begin your route.',
        );
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Clock-in failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      child: Dialog(
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
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.access_time_filled_rounded,
                  size: 38,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                'Good Morning!',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.salesman.username,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Please clock in to start your day. Your work dashboard will unlock immediately upon clocking in.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 20),

              // Live Time Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      _dateFormat.format(_currentTime),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _timeFormat.format(_currentTime),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Geofence / Location Status
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isAcquiringLocation
                                ? 'Acquiring GPS location...'
                                : (_locationResult?.locationSummary ?? 'Location checked'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _getLocationTextColor(colorScheme),
                            ),
                          ),
                          if (!_isAcquiringLocation &&
                              _locationResult?.errorMessage != null)
                            Text(
                              _locationResult!.errorMessage!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.error,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_isAcquiringLocation)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Refresh Location',
                        onPressed: _checkLocation,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Clock-In Action Button
              AsyncFilledButton.icon(
                onPressed: _handleClockIn,
                label: const Text('Clock In Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                icon: const Icon(Icons.login_rounded),
                loadingLabel: 'Clocking In...',
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
