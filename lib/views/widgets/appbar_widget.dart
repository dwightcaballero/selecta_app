import 'package:flutter/material.dart';

class CustomAppbar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final List<Widget>? actions;
  final Widget? leading;
  final Color? backgroundColor;

  static const Color borderLight = Color(0xFFE2E8F0);

  const CustomAppbar({
    super.key,
    required this.title,
    this.subtitle,
    this.showBackButton = true,
    this.onBackPressed,
    this.actions,
    this.leading,
    this.backgroundColor,
  });

  @override
  Size get preferredSize => Size.fromHeight(subtitle != null ? 72 : 62);

  Widget _buildIconButton({required Widget icon, required VoidCallback onTap, String? tooltip, bool isLightSurface = false}) {
    return Container(
      decoration: BoxDecoration(
        color: isLightSurface ? Colors.white : Colors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: isLightSurface ? borderLight : Colors.white.withValues(alpha: 0.3), width: 1),
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
    final effectiveColor = backgroundColor ?? Theme.of(context).colorScheme.primary;
    final isWhiteOrTransparent = backgroundColor == Colors.transparent || backgroundColor == Colors.white;

    final titleColor = isWhiteOrTransparent ? const Color(0xFF0F172A) : Colors.white;
    final subtitleColor = isWhiteOrTransparent ? const Color(0xFF64748B) : Colors.white.withValues(alpha: 0.85);
    final iconColor = isWhiteOrTransparent ? const Color(0xFF0F172A) : Colors.white;

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: effectiveColor,
      centerTitle: true,
      leadingWidth: 64,
      leading: leading != null
          ? Center(child: leading)
          : (showBackButton && Navigator.canPop(context)
                ? Center(
                    child: _buildIconButton(
                      icon: Icon(Icons.arrow_back_ios_new, size: 16, color: iconColor),
                      onTap: onBackPressed ?? () => Navigator.maybePop(context),
                      tooltip: 'Back',
                      isLightSurface: isWhiteOrTransparent,
                    ),
                  )
                : null),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: titleColor, letterSpacing: -0.3),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: subtitleColor),
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
