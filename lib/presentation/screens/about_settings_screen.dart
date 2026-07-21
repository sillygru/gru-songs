import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../services/update_service.dart';
import '../components/app_screen_header.dart';
import '../components/app_settings.dart';
import '../components/app_surface.dart';
import '../tokens/app_tokens.dart';

class AboutSettingsScreen extends ConsumerWidget {
  const AboutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(updateCheckProvider);
    final updateNotifier = ref.read(updateCheckProvider.notifier);
    final accent = AppTokens.accentOf(context, ref);

    final statusTitle = updateState.isChecking
        ? 'Checking for updates…'
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
      appBar: const AppTopBar(title: 'About'),
      body: AppSettingsList(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppTokens.s4),
            child: AppSurface(
              padding: const EdgeInsets.all(AppTokens.s5),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: AppTokens.brSm,
                    child: Image.asset(
                      'assets/app_icon.png',
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: AppTokens.s4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Wispie', style: AppTokens.screenTitle(context)),
                        const SizedBox(height: 2),
                        Text(
                          'Version ${updateState.currentVersion.isEmpty ? 'Unknown' : updateState.currentVersion}',
                          style: AppTokens.meta(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.s3),
          AppSurface(
            padding: const EdgeInsets.all(AppTokens.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      updateState.hasUpdate
                          ? Icons.system_update_alt_rounded
                          : Icons.verified_outlined,
                      color: accent,
                      size: 20,
                    ),
                    const SizedBox(width: AppTokens.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(statusTitle, style: AppTokens.rowTitle(context)),
                          const SizedBox(height: 2),
                          Text(statusSubtitle,
                              style: AppTokens.rowSubtitle(context)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.s4),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: updateState.isChecking
                            ? null
                            : () => updateNotifier.checkForUpdate(force: true),
                        child: const Text('Check now'),
                      ),
                    ),
                    if (updateState.hasUpdate) ...[
                      const SizedBox(width: AppTokens.s3),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => UpdateService().openLatestRelease(
                            url: updateState.releaseUrl,
                          ),
                          child: const Text('View release'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
