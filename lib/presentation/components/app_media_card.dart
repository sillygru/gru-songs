import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';

/// Artwork-led card for carousels and grids.
///
/// Replaces three separate card styles: the Home "For You" cards (r28 +
/// drop shadow), the Recent Queues cards (r20) and the artist/album grid tiles
/// (`Card(elevation: 4)`, r16). One radius, no shadow, no elevation — the
/// artwork is the object, not a box drawn around it.
class AppMediaCard extends StatelessWidget {
  /// The artwork. Clipped and given the card radius by this widget.
  final Widget artwork;

  final String title;
  final String? subtitle;

  /// Square edge of the artwork. Also the card's width in a carousel.
  final double size;

  /// Lets a grid tile fill its cell instead of taking a fixed [size].
  final bool expand;

  /// Small overlay in the artwork's top-right — the pinned marker, a count.
  final Widget? badge;

  final TextAlign textAlign;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AppMediaCard({
    super.key,
    required this.artwork,
    required this.title,
    this.subtitle,
    this.size = 160,
    this.expand = false,
    this.badge,
    this.textAlign = TextAlign.start,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final art = ClipRRect(
      borderRadius: AppTokens.brMd,
      child: expand
          ? AspectRatio(aspectRatio: 1, child: artwork)
          : SizedBox(width: size, height: size, child: artwork),
    );

    final artStack = badge == null
        ? art
        : Stack(
            children: [
              art,
              Positioned(
                top: AppTokens.s2,
                right: AppTokens.s2,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: badge,
                ),
              ),
            ],
          );

    final crossAxis = switch (textAlign) {
      TextAlign.center => CrossAxisAlignment.center,
      TextAlign.end => CrossAxisAlignment.end,
      _ => CrossAxisAlignment.start,
    };

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxis,
      children: [
        expand ? Flexible(child: artStack) : artStack,
        const SizedBox(height: AppTokens.s3),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: AppTokens.cardTitle(context),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: AppTokens.meta(context),
          ),
        ],
      ],
    );

    final body = expand ? column : SizedBox(width: size, child: column);

    if (onTap == null && onLongPress == null) return body;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: body,
    );
  }
}
