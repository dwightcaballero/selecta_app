import 'package:flutter/material.dart';
import 'package:selecta_ops/models/users.dart';

/// Top header banner on the dashboard displaying the logged-in user, role badge,
/// last sync timestamp, and secret multi-tap superadmin trigger.
class DashboardWelcomeBanner extends StatefulWidget {
  final Users? currentUser;
  final bool isDealer;
  final String lastSyncDateTime;
  final VoidCallback onSecretTap;

  const DashboardWelcomeBanner({
    super.key,
    required this.currentUser,
    required this.isDealer,
    required this.lastSyncDateTime,
    required this.onSecretTap,
  });

  @override
  State<DashboardWelcomeBanner> createState() => _DashboardWelcomeBannerState();
}

class _DashboardWelcomeBannerState extends State<DashboardWelcomeBanner> {
  int _secretTapCount = 0;
  DateTime? _lastSecretTapTime;

  void _handleTap() {
    final now = DateTime.now();
    if (_lastSecretTapTime != null && now.difference(_lastSecretTapTime!) > const Duration(seconds: 2)) {
      _secretTapCount = 0;
    }
    _lastSecretTapTime = now;
    _secretTapCount++;

    if (_secretTapCount >= 5) {
      _secretTapCount = 0;
      widget.onSecretTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final displayName = widget.currentUser?.username ?? (widget.isDealer ? 'Dealer' : 'Salesman');
    final hasSyncTime = widget.lastSyncDateTime.isNotEmpty && widget.lastSyncDateTime != 'Never';

    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: theme.cardTheme.color ?? Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF384152) : colorScheme.outlineVariant.withAlpha(80),
            width: isDark ? 1.2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 50 : 15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (widget.isDealer ? colorScheme.primary : colorScheme.tertiary).withValues(alpha: isDark ? 0.22 : 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.isDealer ? Icons.store_rounded : Icons.badge_outlined,
                color: widget.isDealer ? colorScheme.primary : colorScheme.tertiary,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Welcome, $displayName!',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (widget.isDealer ? colorScheme.primary : colorScheme.tertiary).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.isDealer ? 'Dealer' : 'Salesman',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: widget.isDealer ? colorScheme.primary : colorScheme.tertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.sync_rounded, size: 15, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          hasSyncTime ? 'Last synced: ${widget.lastSyncDateTime}' : 'Not synced yet',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
