import 'package:flutter/material.dart';

class CustomAppbar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final List<Widget>? actions;
  final Widget? leading;
  final Color? backgroundColor;
  final bool? centerTitle;

  static const Color borderLight = Color(0xFFE2E8F0);

  final PreferredSizeWidget? bottom;

  const CustomAppbar({
    super.key,
    required this.title,
    this.subtitle,
    this.showBackButton = true,
    this.onBackPressed,
    this.actions,
    this.leading,
    this.backgroundColor,
    this.centerTitle,
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight((subtitle != null ? 72 : 62) + (bottom?.preferredSize.height ?? 0));

  Widget _buildIconButton({
    required Widget icon,
    required VoidCallback onTap,
    String? tooltip,
    bool isLightSurface = false,
    bool isDark = false,
  }) {
    final bgColor = isLightSurface
        ? Colors.white
        : (isDark ? const Color(0xFF28303F) : Colors.white.withValues(alpha: 0.18));
    final borderColor = isLightSurface
        ? borderLight
        : (isDark ? const Color(0xFF384152) : Colors.white.withValues(alpha: 0.3));

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1),
        boxShadow: isLightSurface
            ? [BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))]
            : null,
      ),
      child: IconButton(
        icon: icon,
        onPressed: onTap,
        tooltip: tooltip,
        splashRadius: 20,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final defaultAppbarBg = isDark
        ? (theme.appBarTheme.backgroundColor ?? const Color(0xFF1E2430))
        : theme.colorScheme.primary;

    final effectiveColor = backgroundColor ?? defaultAppbarBg;
    final isLightSurface = effectiveColor.computeLuminance() > 0.45;

    final titleColor = isLightSurface ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final subtitleColor = isLightSurface
        ? const Color(0xFF64748B)
        : (isDark ? const Color(0xFFCBD5E1) : Colors.white.withValues(alpha: 0.88));
    final iconColor = isLightSurface ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    final isCentered = centerTitle ?? true;

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: effectiveColor,
      centerTitle: isCentered,
      leadingWidth: 60,
      bottom: bottom ??
          (isDark
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Container(
                    color: const Color(0xFF2E3644),
                    height: 1,
                  ),
                )
              : null),
      leading: leading != null
          ? Center(child: leading)
          : (showBackButton && Navigator.canPop(context)
                ? Center(
                    child: _buildIconButton(
                      icon: Icon(Icons.arrow_back_ios_new, size: 16, color: iconColor),
                      onTap: onBackPressed ?? () => Navigator.maybePop(context),
                      tooltip: 'Back',
                      isLightSurface: isLightSurface,
                      isDark: isDark,
                    ),
                  )
                : null),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: isCentered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: titleColor, letterSpacing: -0.3),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: subtitleColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
      actions: actions != null
          ? [
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: actions!),
              ),
            ]
          : null,
    );
  }
}
