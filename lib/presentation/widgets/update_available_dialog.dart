import 'package:flutter/material.dart';
import '../../services/update_service.dart';
import '../tokens/app_tokens.dart';

Future<void> showUpdateAvailableDialog(
  BuildContext context, {
  required String currentVersion,
  required String newVersion,
  required String dismissalTag,
  required Uri releaseUrl,
}) async {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: AppTokens.brLg),
      backgroundColor: colorScheme.surface,
      surfaceTintColor: colorScheme.primaryContainer,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.system_update_alt_rounded,
                size: 36,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              'Update Available',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),

            // Version comparison
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: AppTokens.brSm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _VersionChip(
                    label: 'Current',
                    version: currentVersion,
                    colorScheme: colorScheme,
                    isBold: false,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                  ),
                  _VersionChip(
                    label: 'New',
                    version: newVersion,
                    colorScheme: colorScheme,
                    isBold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Description
            Text(
              'A newer version of Wispie is ready to download.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      await UpdateService.dismissVersion(dismissalTag);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTokens.surface(2),
                      foregroundColor: AppTokens.fgPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppTokens.brSm,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Skip this version'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      await UpdateService().openLatestRelease(
                        url: releaseUrl,
                      );
                      await UpdateService.dismissVersion(dismissalTag);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: AppTokens.brSm,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Download'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // What's new link
            TextButton.icon(
              onPressed: () async {
                await UpdateService().openLatestRelease(url: releaseUrl);
                // Don't pop — let the user return and decide to download.
              },
              icon: Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: colorScheme.primary,
              ),
              label: Text(
                "What's new?",
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _VersionChip extends StatelessWidget {
  final String label;
  final String version;
  final ColorScheme colorScheme;
  final bool isBold;

  const _VersionChip({
    required this.label,
    required this.version,
    required this.colorScheme,
    required this.isBold,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          version,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: isBold ? colorScheme.primary : colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
