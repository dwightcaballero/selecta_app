import 'package:flutter/material.dart';

/// Reusable pulsating shimmer loading effect for placeholder UI widgets.
///
/// Wraps children with a smooth pulsing animation that indicates loading state
/// without relying on external dependencies or heavy native shaders.
class ShimmerLoading extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const ShimmerLoading({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat(reverse: true);
    _opacityAnimation = Tween<double>(begin: 0.32, end: 0.80).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: widget.child,
        );
      },
    );
  }
}

/// A placeholder rectangular box with rounded corners for skeleton layouts.
class ShimmerBox extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;
  final Color? color;

  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// A circular placeholder for avatars and icon buttons.
class ShimmerCircle extends StatelessWidget {
  final double size;
  final Color? color;

  const ShimmerCircle({
    super.key,
    required this.size,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// A ready-to-use skeleton placeholder that mimics standard operational cards in Selecta Ops.
class ListSkeleton extends StatelessWidget {
  final int itemCount;
  final EdgeInsetsGeometry padding;
  final bool hasLeading;
  final bool isLeadingCircle;
  final double leadingSize;

  const ListSkeleton({
    super.key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.all(16),
    this.hasLeading = true,
    this.isLeadingCircle = false,
    this.leadingSize = 48,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ShimmerLoading(
      child: ListView.builder(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: itemCount,
        itemBuilder: (context, index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (hasLeading) ...[
                  isLeadingCircle
                      ? ShimmerCircle(size: leadingSize)
                      : ShimmerBox(width: leadingSize, height: leadingSize, borderRadius: 10),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Title line
                      FractionallySizedBox(
                        widthFactor: index.isEven ? 0.75 : 0.60,
                        child: const ShimmerBox(height: 14, borderRadius: 4),
                      ),
                      const SizedBox(height: 8),
                      // Subtitle line
                      FractionallySizedBox(
                        widthFactor: index.isEven ? 0.45 : 0.52,
                        child: const ShimmerBox(height: 11, borderRadius: 4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Trailing pill/badge
                const ShimmerBox(width: 48, height: 20, borderRadius: 10),
              ],
            ),
          );
        },
      ),
    );
  }
}
