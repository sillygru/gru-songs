import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import 'pressable.dart';

/// A selectable pill — filter chips, choice chips, tag toggles.
///
/// Replaces Material's [FilterChip]/[ChoiceChip], whose selected state is an
/// outline. Here selection is an accent wash with accent text (the same active
/// language as a list row), the resting state is a flat tonal fill, and the tap
/// springs. Never an outline.
class AppChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Leading glyph, e.g. a filter icon.
  final IconData? icon;

  /// Accent for the selected state. Defaults to the theme (cover) accent.
  final Color? accent;

  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final acc = accent ?? Theme.of(context).colorScheme.primary;
    final fg = selected ? acc : AppTokens.fg(AppTokens.aSecondary);

    return Pressable(
      onTap: onTap,
      haptic: PressHaptic.selection,
      child: AnimatedContainer(
        duration: AppTokens.dFast,
        curve: AppTokens.cStandard,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s3,
          vertical: AppTokens.s2,
        ),
        decoration: BoxDecoration(
          color: selected
              ? acc.withValues(alpha: AppTokens.accentWashAlpha)
              : AppTokens.surface(1),
          borderRadius: AppTokens.brPill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: AppTokens.s1),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                letterSpacing: -0.1,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
