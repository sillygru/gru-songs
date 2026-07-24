import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../tokens/app_icons.dart';
import '../tokens/app_tokens.dart';

/// Renders an [AppIconData] (a Hugeicons SVG glyph) with the ergonomics of
/// Flutter's [Icon]: size and colour fall back to the ambient [IconTheme], so
/// it drops into `IconButton`, `ListTile.leading`, buttons and rows unchanged.
///
/// This is the *only* place the app talks to [HugeIcon]. Everything else uses
/// `AppIcon(AppIcons.something)`, which keeps call sites decoupled from the
/// icon package.
///
/// [strokeWidth] is the app's emphasis lever: a selected or active glyph asks
/// for a heavier stroke so icon weight echoes the layered-depth language, the
/// same way a raised surface reads heavier than the canvas. It defaults to
/// [AppTokens.iconStroke] rather than the glyph's baked-in hairline — that
/// default is what keeps every icon in the app on one weight, and what pairs
/// them with the type ramp. Pass [AppTokens.iconStrokeEmphasis] for active
/// states.
class AppIcon extends StatelessWidget {
  final AppIconData icon;
  final double? size;
  final Color? color;
  final double? strokeWidth;

  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.strokeWidth,
  });

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final base = color ?? iconTheme.color ?? Colors.white;
    // Preserve the caller's alpha (e.g. AppTokens.fgTertiary at 0.42); only
    // fold in IconTheme.opacity when it is explicitly set, matching [Icon].
    final opacity = iconTheme.opacity;
    final resolvedColor = opacity == null
        ? base
        : base.withValues(alpha: (base.a * opacity).clamp(0.0, 1.0));
    return HugeIcon(
      icon: icon,
      size: size ?? iconTheme.size ?? AppTokens.iconMd,
      color: resolvedColor,
      strokeWidth: strokeWidth ?? AppTokens.iconStroke,
    );
  }
}
