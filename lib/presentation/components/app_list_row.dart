import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';

/// The one list row in the app — the counterpart to the player's
/// [PlayerTrackRow], with the same anatomy so a song in a library list and a
/// song in the queue read as the same object.
///
/// Active state is an accent wash plus an accent title. Never an outline.
class AppListRow extends StatelessWidget {
  /// Artwork, icon badge or collage. Sized by the caller; [AppRowIcon] and
  /// [AppRowArt] cover the common cases.
  final Widget? leading;

  final String title;

  /// Second line. A plain string covers most cases; pass [subtitleWidget] when
  /// it needs to be a duration display or a live-updating widget.
  final String? subtitle;
  final Widget? subtitleWidget;

  /// Right-hand slot: a chevron, an icon button, a switch, a drag handle.
  final Widget? trailing;

  /// Currently playing / currently selected.
  final bool isActive;

  /// De-emphasised — suggest-less tracks, already-played rows.
  final bool isDimmed;

  /// Struck through, for excluded items.
  final bool strikeThrough;

  final Color? accent;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Tighter vertical rhythm, for dense settings lists.
  final bool dense;

  const AppListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.isActive = false,
    this.isDimmed = false,
    this.strikeThrough = false,
    this.accent,
    this.onTap,
    this.onLongPress,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accent ?? Theme.of(context).colorScheme.primary;
    final hasSubtitle = subtitle != null || subtitleWidget != null;

    final titleColor = isActive
        ? effectiveAccent
        : AppTokens.fg(isDimmed ? AppTokens.aTertiary : AppTokens.aPrimary);

    final row = Container(
      constraints: BoxConstraints(
        minHeight: dense ? 56 : AppTokens.rowHeight,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: AppTokens.s3,
        vertical: dense ? AppTokens.s2 : AppTokens.s2 + 2,
      ),
      decoration: isActive
          ? BoxDecoration(
              color:
                  effectiveAccent.withValues(alpha: AppTokens.accentWashAlpha),
              borderRadius: AppTokens.brMd,
            )
          : null,
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppTokens.s3),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTokens.rowTitle(context).copyWith(
                    color: titleColor,
                    decoration:
                        strikeThrough ? TextDecoration.lineThrough : null,
                    decorationColor: titleColor,
                  ),
                ),
                if (hasSubtitle) ...[
                  const SizedBox(height: 2),
                  DefaultTextStyle(
                    style: AppTokens.rowSubtitle(context).copyWith(
                      color: AppTokens.fg(
                        isDimmed ? AppTokens.aTertiary : AppTokens.aSecondary,
                      ),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: subtitleWidget ?? Text(subtitle!),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppTokens.s2),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null && onLongPress == null) return row;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: AppTokens.brMd,
        child: row,
      ),
    );
  }
}

/// Tinted icon badge for the leading slot — replaces the hand-rolled
/// `Container` + `BoxDecoration` + `Icon` blocks scattered across the app.
class AppRowIcon extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;

  const AppRowIcon({
    super.key,
    required this.icon,
    this.color,
    this.size = AppTokens.artSize,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: AppTokens.accentWashAlpha),
        borderRadius: AppTokens.brSm,
      ),
      child: Icon(icon, color: tint, size: size * 0.5),
    );
  }
}

/// Rounded artwork slot at the row's standard size.
class AppRowArt extends StatelessWidget {
  final Widget child;
  final double size;

  const AppRowArt({
    super.key,
    required this.child,
    this.size = AppTokens.artSize,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppTokens.brSm,
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}
