import 'package:flutter/material.dart';

import '../tokens/player_tokens.dart';

/// Small-caps section label with an optional trailing action.
/// Used by both Queue segments so their headers match exactly.
class PlayerSectionHeader extends StatelessWidget {
  final String label;
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;
  final IconData? trailingIcon;

  const PlayerSectionHeader({
    super.key,
    required this.label,
    this.trailingLabel,
    this.onTrailingTap,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PlayerTokens.s5,
        PlayerTokens.s4,
        PlayerTokens.s3,
        PlayerTokens.s2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: PlayerTokens.sectionLabel(context),
            ),
          ),
          if (trailingLabel != null || trailingIcon != null)
            TextButton.icon(
              onPressed: onTrailingTap,
              icon: trailingIcon == null
                  ? const SizedBox.shrink()
                  : Icon(trailingIcon, size: 16),
              label: Text(trailingLabel ?? ''),
              style: TextButton.styleFrom(
                foregroundColor:
                    Colors.white.withValues(alpha: PlayerTokens.aSecondary),
                textStyle: PlayerTokens.meta(context)
                    .copyWith(fontWeight: FontWeight.w700),
                padding: const EdgeInsets.symmetric(
                  horizontal: PlayerTokens.s3,
                  vertical: PlayerTokens.s1,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }
}
