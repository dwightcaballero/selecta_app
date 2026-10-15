import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/dashboard_controller.dart';
import 'package:selecta_ops/models/users.dart';

/// Top header banner on the dashboard displaying the logged-in user, role badge,
/// live/relative last sync status with visual staleness warning, and secret multi-tap superadmin trigger.
class DashboardWelcomeBanner extends StatefulWidget {
  final Users? currentUser;
  final bool isDealer;
  final String lastSyncDateTime;
  final DateTime? lastSyncTime;
  final bool isSyncing;
  final VoidCallback? onSyncTap;
  final VoidCallback onSecretTap;

  const DashboardWelcomeBanner({
    super.key,
    required this.currentUser,
    required this.isDealer,
    required this.lastSyncDateTime,
    this.lastSyncTime,
    this.isSyncing = false,
    this.onSyncTap,
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

    final isAdmin = widget.currentUser?.isAdmin ?? false;
    final roleColor = isAdmin
        ? const Color(0xFF7C3AED)
        : (widget.isDealer ? colorScheme.primary : colorScheme.tertiary);
    final roleIcon = isAdmin
        ? Icons.admin_panel_settings_rounded
        : (widget.isDealer ? Icons.store_rounded : Icons.badge_outlined);
    final roleLabel = isAdmin ? 'Admin' : (widget.isDealer ? 'Dealer' : 'Salesman');

    // Parse timestamp to evaluate relative staleness
    final parsedTime = widget.lastSyncTime ?? (hasSyncTime ? DateTime.tryParse(widget.lastSyncDateTime) : null);
    final relativeTime = parsedTime != null ? DashboardController.formatRelativeTime(parsedTime) : '';
    final isStale = parsedTime == null || DashboardController.isStaleWarning(parsedTime);

    // Warning amber colors
    final amberColor = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);

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
            color: isStale && hasSyncTime
                ? amberColor.withValues(alpha: 0.35)
                : (isDark ? const Color(0xFF384152) : colorScheme.outlineVariant.withAlpha(80)),
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
                color: roleColor.withValues(alpha: isDark ? 0.22 : 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                roleIcon,
                color: roleColor,
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
                          color: roleColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          roleLabel,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: roleColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),

                  // Sync Status Row with Live Staleness & Tap-to-Sync
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: widget.isSyncing ? null : widget.onSyncTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (widget.isSyncing)
                            SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                            )
                          else if (!hasSyncTime || isStale)
                            Icon(Icons.warning_amber_rounded, size: 15, color: amberColor)
                          else
                            Icon(Icons.sync_rounded, size: 15, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
                          const SizedBox(width: 5),
                          Expanded(
                            child: widget.isSyncing
                                ? Text(
                                    'Syncing dashboard data...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : !hasSyncTime
                                    ? Text(
                                        'Not synced yet • Tap to sync',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: amberColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : isStale
                                        ? Text(
                                            'Synced $relativeTime • Stale (Tap to refresh)',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: amberColor,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          )
                                        : Text(
                                            'Synced $relativeTime (${widget.lastSyncDateTime})',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: colorScheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                          ),
                          if (isStale && !widget.isSyncing)
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: amberColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'REFRESH',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: amberColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
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
