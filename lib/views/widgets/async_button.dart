import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A button that manages its own asynchronous execution lifecycle:
/// - Automatically disables itself while the async operation is running (prevents double-taps).
/// - Triggers subtle haptic feedback on press.
/// - Shows a matched spinner and optional loading label while processing.
/// - Catches unhandled errors gracefully without leaving the button locked.
class AsyncFilledButton extends StatefulWidget {
  final FutureOr<void> Function()? onPressed;
  final Widget? child;
  final Widget? icon;
  final String? loadingLabel;
  final ButtonStyle? style;
  final FocusNode? focusNode;
  final bool autofocus;
  final Clip clipBehavior;
  final bool enableHaptics;

  const AsyncFilledButton({
    super.key,
    required this.onPressed,
    required Widget this.child,
    this.loadingLabel,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
    this.enableHaptics = true,
  }) : icon = null;

  const AsyncFilledButton.icon({
    super.key,
    required this.onPressed,
    required Widget this.icon,
    required Widget label,
    this.loadingLabel,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
    this.enableHaptics = true,
  }) : child = label;

  @override
  State<AsyncFilledButton> createState() => _AsyncFilledButtonState();
}

class _AsyncFilledButtonState extends State<AsyncFilledButton> {
  bool _isLoading = false;

  Future<void> _handlePressed() async {
    if (_isLoading || widget.onPressed == null) return;

    if (widget.enableHaptics) {
      HapticFeedback.lightImpact();
    }

    final dynamic result = widget.onPressed!();
    if (result is Future) {
      setState(() => _isLoading = true);
      try {
        await result;
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final progressIndicator = SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(
          widget.style?.foregroundColor?.resolve({WidgetState.selected}) ??
              colorScheme.onPrimary,
        ),
      ),
    );

    if (widget.icon != null) {
      return FilledButton.icon(
        key: widget.key,
        style: widget.style,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        clipBehavior: widget.clipBehavior,
        onPressed: widget.onPressed == null || _isLoading ? null : _handlePressed,
        icon: _isLoading ? progressIndicator : widget.icon!,
        label: _isLoading && widget.loadingLabel != null
            ? Text(widget.loadingLabel!)
            : widget.child!,
      );
    }

    return FilledButton(
      key: widget.key,
      style: widget.style,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      clipBehavior: widget.clipBehavior,
      onPressed: widget.onPressed == null || _isLoading ? null : _handlePressed,
      child: _isLoading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                progressIndicator,
                if (widget.loadingLabel != null) ...[
                  const SizedBox(width: 8),
                  Text(widget.loadingLabel!),
                ],
              ],
            )
          : widget.child!,
    );
  }
}

/// Outlined variant of [AsyncFilledButton]
class AsyncOutlinedButton extends StatefulWidget {
  final FutureOr<void> Function()? onPressed;
  final Widget? child;
  final Widget? icon;
  final String? loadingLabel;
  final ButtonStyle? style;
  final FocusNode? focusNode;
  final bool autofocus;
  final Clip clipBehavior;
  final bool enableHaptics;

  const AsyncOutlinedButton({
    super.key,
    required this.onPressed,
    required Widget this.child,
    this.loadingLabel,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
    this.enableHaptics = true,
  }) : icon = null;

  const AsyncOutlinedButton.icon({
    super.key,
    required this.onPressed,
    required Widget this.icon,
    required Widget label,
    this.loadingLabel,
    this.style,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
    this.enableHaptics = true,
  }) : child = label;

  @override
  State<AsyncOutlinedButton> createState() => _AsyncOutlinedButtonState();
}

class _AsyncOutlinedButtonState extends State<AsyncOutlinedButton> {
  bool _isLoading = false;

  Future<void> _handlePressed() async {
    if (_isLoading || widget.onPressed == null) return;

    if (widget.enableHaptics) {
      HapticFeedback.lightImpact();
    }

    final dynamic result = widget.onPressed!();
    if (result is Future) {
      setState(() => _isLoading = true);
      try {
        await result;
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final progressIndicator = SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(
          widget.style?.foregroundColor?.resolve({WidgetState.selected}) ??
              colorScheme.primary,
        ),
      ),
    );

    if (widget.icon != null) {
      return OutlinedButton.icon(
        key: widget.key,
        style: widget.style,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        clipBehavior: widget.clipBehavior,
        onPressed: widget.onPressed == null || _isLoading ? null : _handlePressed,
        icon: _isLoading ? progressIndicator : widget.icon!,
        label: _isLoading && widget.loadingLabel != null
            ? Text(widget.loadingLabel!)
            : widget.child!,
      );
    }

    return OutlinedButton(
      key: widget.key,
      style: widget.style,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      clipBehavior: widget.clipBehavior,
      onPressed: widget.onPressed == null || _isLoading ? null : _handlePressed,
      child: _isLoading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                progressIndicator,
                if (widget.loadingLabel != null) ...[
                  const SizedBox(width: 8),
                  Text(widget.loadingLabel!),
                ],
              ],
            )
          : widget.child!,
    );
  }
}

/// IconButton variant that auto-disables and shows a spinner while executing
class AsyncIconButton extends StatefulWidget {
  final FutureOr<void> Function()? onPressed;
  final Widget icon;
  final ButtonStyle? style;
  final Color? color;
  final double? iconSize;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry? alignment;
  final String? tooltip;
  final bool enableHaptics;

  const AsyncIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.style,
    this.color,
    this.iconSize,
    this.padding,
    this.alignment,
    this.tooltip,
    this.enableHaptics = true,
  });

  @override
  State<AsyncIconButton> createState() => _AsyncIconButtonState();
}

class _AsyncIconButtonState extends State<AsyncIconButton> {
  bool _isLoading = false;

  Future<void> _handlePressed() async {
    if (_isLoading || widget.onPressed == null) return;

    if (widget.enableHaptics) {
      HapticFeedback.lightImpact();
    }

    final dynamic result = widget.onPressed!();
    if (result is Future) {
      setState(() => _isLoading = true);
      try {
        await result;
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = widget.iconSize ?? 20.0;

    return IconButton(
      key: widget.key,
      onPressed: widget.onPressed == null || _isLoading ? null : _handlePressed,
      icon: _isLoading
          ? SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  widget.color ?? colorScheme.primary,
                ),
              ),
            )
          : widget.icon,
      style: widget.style,
      color: widget.color,
      iconSize: widget.iconSize,
      padding: widget.padding,
      alignment: widget.alignment,
      tooltip: widget.tooltip,
    );
  }
}
