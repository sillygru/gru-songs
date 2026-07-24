import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import 'press_highlight.dart';
import '../tokens/app_icons.dart';
import 'app_icon.dart';

/// The one list row in the app — the counterpart to the player's
/// [PlayerTrackRow], with the same anatomy so a song in a library list and a
/// song in the queue read as the same object.
///
/// Active state is an accent wash plus an accent title. Never an outline.
class AppListRow extends StatelessWidget {
  /// Artwork, icon or collage. Sized by the caller; [AppRowIcon] and
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

    return PressHighlight(
      onTap: onTap,
      onLongPress: onLongPress,
      child: row,
    );
  }
}

/// Icon for a row's leading slot — replaces the hand-rolled `Container` +
/// `BoxDecoration` + `Icon` blocks scattered across the app.
///
/// **A bare glyph, with no plate behind it.** It used to sit on a filled
/// rounded square, and at row size that plate boxed the glyph in: every row
/// looked like it was holding a button rather than showing an icon, and the
/// frame made each glyph's own proportions (a full-bleed circle next to a small
/// open mark) read as inconsistent sizing. Alignment now comes from the fixed
/// slot width instead, so icon rows still line up with [AppRowArt] rows.
///
/// The glyph carries the theme accent — the colour pulled from the current
/// cover — so rows pick up the artwork the way the rest of the app does. Pass
/// [color] for the rare row whose meaning is a colour (destructive →
/// [AppTokens.danger]).
class AppRowIcon extends StatelessWidget {
  final AppIconData icon;

  /// Semantic override, replacing the theme accent. Use only where the colour
  /// carries meaning, not for decoration.
  final Color? color;

  /// Whether this row is selected / currently in effect. Draws a heavier stroke;
  /// the row's own [AppListRow.isActive] wash carries the rest.
  final bool active;

  /// Width of the leading slot. The glyph is centred inside it.
  final double size;

  const AppRowIcon({
    super.key,
    required this.icon,
    this.color,
    this.active = false,
    this.size = _slotSize,
  });

  static const double _slotSize = 44;

  /// Glyph size as a fraction of the slot. Larger than it was on a plate — with
  /// no fill to give the slot a shape, the glyph alone has to hold the row.
  static const double _glyphRatio = 0.58;

  @override
  Widget build(BuildContext context) {
    // `colorScheme.primary` is the cover-derived accent — AppTheme seeds it
    // from the current artwork — so this needs no ref and restyles itself as
    // tracks change.
    final tint = color ?? Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: AppIcon(
          icon,
          color: tint,
          size: size * _glyphRatio,
          strokeWidth: active ? AppTokens.iconStrokeEmphasis : null,
        ),
      ),
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
