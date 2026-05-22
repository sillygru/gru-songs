import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../services/update_service.dart';

class AboutSettingsScreen extends ConsumerWidget {
  const AboutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(updateCheckProvider);
    final updateNotifier = ref.read(updateCheckProvider.notifier);
    final theme = Theme.of(context);

    final statusTitle = updateState.isChecking
        ? 'Checking for updates...'
        : updateState.hasUpdate
            ? 'Update available: ${updateState.latestVersionLabel}'
            : updateState.latestVersionLabel != null
                ? 'You are up to date'
                : 'Check for updates';

    final statusSubtitle = updateState.isChecking
        ? 'Wispie is quietly checking GitHub Releases.'
        : updateState.hasUpdate
            ? 'A newer version is available on GitHub.'
            : updateState.latestVersionLabel != null
                ? 'Latest release: ${updateState.latestVersionLabel}'
                : 'Tap below to check manually.';

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.25),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      'assets/app_icon.png',
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Wispie',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Version ${updateState.currentVersion.isEmpty ? 'Unknown' : updateState.currentVersion}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.25),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      updateState.hasUpdate
                          ? Icons.system_update_alt_rounded
                          : Icons.verified_outlined,
                    ),
                    title: Text(statusTitle),
                    subtitle: Text(statusSubtitle),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: updateState.isChecking
                              ? null
                              : () => updateNotifier.checkForUpdate(
                                    force: true,
                                  ),
                          child: const Text('Check now'),
                        ),
                      ),
                      if (updateState.hasUpdate) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              await UpdateService().openLatestRelease(
                                url: updateState.releaseUrl,
                              );
                            },
                            child: const Text('View release'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
