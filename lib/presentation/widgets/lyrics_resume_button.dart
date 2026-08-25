import 'package:flutter/material.dart';

import '../tokens/player_tokens.dart';

/// Floating pill button shown when autoscroll is paused, allowing the user
/// to quickly re-anchor the lyrics viewport to the currently playing line.
class LyricsResumeButton extends StatelessWidget {
  final bool visible;
  final Color accent;
  final VoidCallback onTap;

  const LyricsResumeButton({
    super.key,
    required this.visible,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: visible
            ? PlayerTokens.dLyricsResumeSlideIn
            : PlayerTokens.dLyricsResumeSlideOut,
        curve: visible ? PlayerTokens.cLyricsResumeSlide : Curves.easeIn,
        offset: visible ? Offset.zero : const Offset(0, 0.75),
        child: AnimatedOpacity(
          duration: visible
              ? PlayerTokens.dLyricsResumeOpacityIn
              : PlayerTokens.dLyricsResumeOpacityOut,
          curve: Curves.linear,
          opacity: visible ? 1.0 : 0.0,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: PlayerTokens.brPill,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: PlayerTokens.s4,
                  vertical: PlayerTokens.s2,
                ),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    accent.withValues(alpha: 0.28),
                    const Color(0xFF1E1E1E),
                  ),
                  borderRadius: PlayerTokens.brPill,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sync_rounded,
                      size: 16,
                      color: accent,
                    ),
                    const SizedBox(width: PlayerTokens.s2),
                    Text(
                      'Resume Sync',
                      style: PlayerTokens.meta(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
