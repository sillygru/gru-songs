import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';

/// Section label with an optional trailing action — the app's counterpart to
/// [PlayerSectionHeader], so a "Recent Queues / See All" row on Home and an
/// "Up Next / Clear" row in the queue have the same shape.
class AppSectionHeader extends StatelessWidget {
  final String label;

  /// Renders the label as a large title rather than a small-caps group label.
  /// Used for the top-level sections on Home; groups inside settings use the
  /// small-caps default.
  final bool large;

  /// Optional icon before the label, for settings groups.
  final IconData? icon;

  final String? actionLabel;
  final VoidCallback? onActionTap;

  final EdgeInsetsGeometry? padding;

  const AppSectionHeader({
    super.key,
    required this.label,
    this.large = false,
    this.icon,
    this.actionLabel,
    this.onActionTap,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    final labelStyle =
        large ? AppTokens.paneTitle(context) : AppTokens.sectionLabel(context);

    return Padding(
      padding: padding ??
          EdgeInsets.fromLTRB(
            AppTokens.s5,
            large ? AppTokens.s5 : AppTokens.s4,
            AppTokens.s3,
            AppTokens.s2,
          ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: AppTokens.s2),
          ],
          Expanded(
            child: Text(
              large ? label : label.toUpperCase(),
              style: labelStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onActionTap,
              style: TextButton.styleFrom(
                foregroundColor: AppTokens.fgSecondary,
                textStyle: AppTokens.meta(context)
                    .copyWith(fontWeight: FontWeight.w700),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s3,
                  vertical: AppTokens.s1,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}
