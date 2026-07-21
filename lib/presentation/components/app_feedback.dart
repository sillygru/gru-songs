import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';

/// Severity of a transient message or banner. Replaces the
/// `Colors.blue.shade700` / `orange.shade800` / `green.shade700` /
/// `red.shade700` literals that the status indicators were using.
enum AppTone { neutral, info, success, warning, danger }

extension AppToneColor on AppTone {
  Color color(BuildContext context) => switch (this) {
        AppTone.neutral => Theme.of(context).colorScheme.primary,
        AppTone.info => AppTokens.info,
        AppTone.success => AppTokens.success,
        AppTone.warning => AppTokens.warning,
        AppTone.danger => AppTokens.danger,
      };
}

/// Shows a snack bar in the app's one style.
///
/// The app had 118 raw `showSnackBar` calls, each free to style itself; this is
/// the single entry point so tone and shape live in one place.
void appSnack(
  BuildContext context,
  String message, {
  AppTone tone = AppTone.neutral,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  final accent = tone.color(context);

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: duration,
        content: Row(
          children: [
            if (tone != AppTone.neutral) ...[
              Icon(_iconFor(tone), size: 18, color: accent),
              const SizedBox(width: AppTokens.s3),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        action: actionLabel == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                textColor: accent,
                onPressed: onAction ?? () {},
              ),
      ),
    );
}

IconData _iconFor(AppTone tone) => switch (tone) {
      AppTone.success => Icons.check_circle_rounded,
      AppTone.warning => Icons.warning_amber_rounded,
      AppTone.danger => Icons.error_rounded,
      _ => Icons.info_rounded,
    };

/// The floating status pill used for scanning, metadata saves and auto-backup
/// progress — one shape for all three, where each previously picked its own
/// Material colour.
class AppStatusBanner extends StatelessWidget {
  final String message;
  final AppTone tone;

  /// Shows a spinner in place of the icon, for in-flight work.
  final bool busy;

  final IconData? icon;

  /// Determinate progress, 0..1. Drawn as a hairline under the pill.
  final double? progress;

  const AppStatusBanner({
    super.key,
    required this.message,
    this.tone = AppTone.neutral,
    this.busy = false,
    this.icon,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final accent = tone.color(context);

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s2,
        ),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            accent.withValues(alpha: 0.16),
            Colors.black.withValues(alpha: 0.72),
          ),
          borderRadius: AppTokens.brPill,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                else
                  Icon(icon ?? _iconFor(tone), size: 15, color: accent),
                const SizedBox(width: AppTokens.s2),
                Flexible(
                  child: Text(
                    message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTokens.meta(context).copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: AppTokens.s1 + 2),
              ClipRRect(
                borderRadius: AppTokens.brPill,
                child: SizedBox(
                  width: 140,
                  child: LinearProgressIndicator(
                    value: progress!.clamp(0.0, 1.0),
                    minHeight: 2,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Empty, error and "nothing here yet" states.
///
/// Home alone had three variations of icon + headline + body + button; this is
/// all of them.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;

  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  final AppTone tone;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.tone = AppTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 56,
              color: tone == AppTone.neutral
                  ? AppTokens.fgTertiary
                  : tone.color(context),
            ),
            const SizedBox(height: AppTokens.s4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTokens.paneTitle(context),
            ),
            if (message != null) ...[
              const SizedBox(height: AppTokens.s2),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppTokens.rowSubtitle(context),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: AppTokens.s5),
              if (actionIcon != null)
                FilledButton.icon(
                  onPressed: onAction,
                  icon: Icon(actionIcon, size: 18),
                  label: Text(actionLabel!),
                )
              else
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The app's loading state. One spinner, one size, centred.
class AppLoading extends StatelessWidget {
  final String? message;

  const AppLoading({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: AppTokens.s4),
            Text(message!, style: AppTokens.meta(context)),
          ],
        ],
      ),
    );
  }
}

/// A single number-and-label statistic, as used on Profile.
class AppStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  const AppStatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: AppTokens.s1),
        ],
        Text(value, style: AppTokens.stat(context)),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          style: AppTokens.sectionLabel(context),
        ),
      ],
    );
  }
}
