import 'package:flutter/material.dart';
import 'package:selecta_ops/data/responsive.dart';

/// A reusable page body wrapper that:
///
/// 1. Centers the content horizontally and constrains it to [ScreenSize.contentMaxWidth].
/// 2. Applies responsive horizontal/vertical padding via [ScreenSize.pagePadding].
/// 3. Wraps everything in a [SingleChildScrollView] when [scrollable] is true.
///
/// Drop this around the body `Column`/`child` of any existing page:
///
/// ```dart
/// body: AdaptivePageBody(
///   child: Column(children: [...]),
/// )
/// ```
class AdaptivePageBody extends StatelessWidget {
  /// The page content to constrain and center.
  final Widget child;

  /// Whether to wrap in a [SingleChildScrollView]. Default: true.
  final bool scrollable;

  /// Override the scroll physics. Only used when [scrollable] is true.
  final ScrollPhysics? physics;

  /// Override the default responsive padding from [ScreenSize.pagePadding].
  final EdgeInsetsGeometry? padding;

  /// Override the max content width. Defaults to [ScreenSize.contentMaxWidth].
  final double? maxWidth;

  const AdaptivePageBody({
    super.key,
    required this.child,
    this.scrollable = true,
    this.physics,
    this.padding,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePadding = padding ?? ScreenSize.pagePadding(context);
    final effectiveMaxWidth = maxWidth ?? ScreenSize.contentMaxWidth(context);

    final constrained = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
        child: Padding(
          padding: effectivePadding,
          child: child,
        ),
      ),
    );

    if (!scrollable) return constrained;

    return SingleChildScrollView(
      physics: physics ?? const AlwaysScrollableScrollPhysics(),
      child: constrained,
    );
  }
}

/// A lighter variant of [AdaptivePageBody] that does NOT scroll —
/// useful for pages that manage their own scroll (e.g., ListView inside an Expanded).
///
/// It still centers and constrains the content width.
class AdaptivePageBodyStatic extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? maxWidth;

  const AdaptivePageBodyStatic({
    super.key,
    required this.child,
    this.padding,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePadding = padding ?? EdgeInsets.zero;
    final effectiveMaxWidth = maxWidth ?? ScreenSize.contentMaxWidth(context);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
        child: Padding(
          padding: effectivePadding,
          child: child,
        ),
      ),
    );
  }
}
