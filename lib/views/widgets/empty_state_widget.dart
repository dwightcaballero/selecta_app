import 'package:flutter/material.dart';

/// Reusable empty state placeholder widget.
/// Displays an icon in a themed pill, a bold title, descriptive subtitle,
/// and an optional primary call-to-action button.
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? description;
  final String? actionLabel;
  final String? actionText;
  final VoidCallback? onAction;
  final VoidCallback? onActionPressed;
  final IconData? actionIcon;
  final Color? iconColor;
  final double iconSize;
  final EdgeInsetsGeometry padding;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.description,
    this.actionLabel,
    this.actionText,
    this.onAction,
    this.onActionPressed,
    this.actionIcon,
    this.iconColor,
    this.iconSize = 38,
    this.padding = const EdgeInsets.all(32.0),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final effectiveIconColor = iconColor ?? colorScheme.primary;
    final effectiveMessage = message ?? description;
    final effectiveActionLabel = actionLabel ?? actionText;
    final effectiveOnAction = onAction ?? onActionPressed;

    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: iconSize + 36,
              height: iconSize + 36,
              decoration: BoxDecoration(
                color: effectiveIconColor.withValues(alpha: isDark ? 0.18 : 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: effectiveIconColor.withValues(alpha: isDark ? 0.35 : 0.18),
                  width: 1.2,
                ),
              ),
              child: Icon(
                icon,
                size: iconSize,
                color: effectiveIconColor,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: colorScheme.onSurface,
              ) ?? TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            if (effectiveMessage != null && effectiveMessage.isNotEmpty) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Text(
                  effectiveMessage,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ) ?? TextStyle(
                    fontSize: 13.5,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            if (effectiveActionLabel != null && effectiveOnAction != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                onPressed: effectiveOnAction,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: Icon(actionIcon ?? Icons.refresh_rounded, size: 18),
                label: Text(
                  effectiveActionLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
