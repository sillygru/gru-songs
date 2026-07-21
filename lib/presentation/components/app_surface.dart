import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';

/// The one raised surface in the app.
///
/// Depth comes from a lighter fill and nothing else — no border, no shadow, no
/// elevation. Nothing outside this file may build its own card fill, and a
/// surface never goes inside another surface: a row inside a group gets a fill
/// *change*, not a card of its own.
class AppSurface extends StatelessWidget {
  final Widget child;

  /// 1 = resting, 2 = selected / pressed / emphasised.
  final int level;

  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;

  /// Washes the fill toward the accent — used for the active item, replacing
  /// what would otherwise be an outline.
  final Color? accentTint;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Renders no fill at all. For grouping and padding without a visible box.
  final bool transparent;

  /// Clips the child to the surface's corners — needed when the child is an
  /// image or another widget that would otherwise paint past them.
  final bool clipContent;

  const AppSurface({
    super.key,
    required this.child,
    this.level = 1,
    this.padding = const EdgeInsets.all(AppTokens.s4),
    this.margin,
    this.borderRadius,
    this.accentTint,
    this.onTap,
    this.onLongPress,
    this.transparent = false,
    this.clipContent = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppTokens.brMd;

    Color fill = transparent ? Colors.transparent : AppTokens.surface(level);
    if (accentTint != null) {
      fill = Color.alphaBlend(
        accentTint!.withValues(alpha: AppTokens.accentWashAlpha),
        fill,
      );
    }

    Widget content = Container(
      padding: padding,
      clipBehavior: clipContent ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(color: fill, borderRadius: radius),
      child: child,
    );

    if (onTap != null || onLongPress != null) {
      content = Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: radius,
          child: content,
        ),
      );
    }

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }

    return content;
  }
}

/// A vertical stack of rows that reads as one block.
///
/// The group owns the fill; the rows inside it are transparent. That is the
/// rule that stops settings screens from stacking a card around every tile.
class AppSurfaceGroup extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;
  final int level;

  const AppSurfaceGroup({
    super.key,
    required this.children,
    this.margin,
    this.level = 1,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return AppSurface(
      level: level,
      margin: margin,
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}
