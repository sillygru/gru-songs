import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../components/ambient_scaffold.dart';
import '../components/app_settings.dart';
import '../components/app_screen_header.dart';
import '../tokens/app_icons.dart';
import '../tokens/app_tokens.dart';
import '../../providers/sync_provider.dart';
import '../../providers/settings_provider.dart';

class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncProvider);
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    return AmbientScaffold(
      appBar: const AppTopBar(
        title: 'Sync',
      ),
      body: AppSettingsList(children: [
        AppSettingsGroup(
          label: 'Account',
          children: [
            if (syncState.isAuthenticated) ...[
              AppSettingsTile(
                icon: AppIcons.checkCircle,
                title: syncState.accountEmail ?? 'Signed in',
                subtitle: 'Google Drive connected',
                trailing: TextButton(
                  onPressed: () => ref.read(syncProvider.notifier).signOut(),
                  child: const Text('Sign Out'),
                ),
              ),
              AppSettingsTile(
                icon: AppIcons.clock,
                title: 'Last Synced',
                subtitle: syncState.lastSyncedAt != null
                    ? _formatTimestamp(syncState.lastSyncedAt!)
                    : 'Never',
              ),
            ] else ...[
              AppSettingsTile(
                icon: AppIcons.cloudUpload,
                title: 'Not signed in',
                subtitle: syncState.lastError != null
                    ? syncState.lastError!
                    : 'Sign in to sync across devices',
                onTap: () => ref.read(syncProvider.notifier).signIn(),
              ),
            ],
          ],
        ),
        if (syncState.isAuthenticated) ...[
          AppSettingsGroup(
            label: 'Device Stats Attribution',
            children: [
              Padding(
                padding: const EdgeInsets.all(AppTokens.s4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'This Device',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${syncState.localPlayCount} plays',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.s2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Other Devices',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${syncState.remotePlayCount} plays',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.s2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Library Stats',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '${syncState.totalPlayCount} plays',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppSettingsGroup(
            label: 'Sync',
            children: [
              AppSettingsSwitch(
                icon: AppIcons.refresh,
                title: 'Auto Sync',
                subtitle: 'Sync passively on app foreground',
                value: settings.autoSyncEnabled,
                onChanged: (v) =>
                    ref.read(settingsProvider.notifier).setAutoSyncEnabled(v),
              ),
              AppSettingsSwitch(
                icon: AppIcons.settings,
                title: 'Sync App Settings',
                subtitle:
                    'Sync theme, playback, and UI preferences across devices',
                value: settings.syncSettingsEnabled,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .setSyncSettingsEnabled(v),
              ),
              if (syncState.isSyncing)
                Padding(
                  padding: const EdgeInsets.all(AppTokens.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        syncState.syncStatusMessage ?? 'Syncing...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: AppTokens.s2),
                      LinearProgressIndicator(
                        value: syncState.syncProgress,
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.2),
                        color: theme.colorScheme.primary,
                        borderRadius: AppTokens.brPill,
                      ),
                    ],
                  ),
                )
              else
                AppSettingsTile(
                  icon: AppIcons.syncAlt,
                  title: 'Sync Now',
                  subtitle: syncState.lastError != null
                      ? 'Last error: ${syncState.lastError}'
                      : 'Merge device data with cloud',
                  onTap: () => ref.read(syncProvider.notifier).sync(
                        syncSettings: settings.syncSettingsEnabled,
                      ),
                ),
            ],
          ),
          AppSettingsGroup(
            label: 'Force Sync Overwrite',
            children: [
              AppSettingsTile(
                icon: AppIcons.upload,
                title: 'Push Local to Cloud',
                subtitle: 'Overwrite online backup with this device\'s data',
                onTap: syncState.isSyncing
                    ? null
                    : () => _confirmPushLocalToCloud(context),
              ),
              AppSettingsTile(
                icon: AppIcons.download,
                title: 'Pull Cloud to Local',
                subtitle: 'Replace local device stats with online backup',
                onTap: syncState.isSyncing
                    ? null
                    : () => _confirmPullCloudToLocal(context),
              ),
            ],
          ),
          AppSettingsGroup(
            label: 'What gets synced',
            children: [
              _infoTile(AppIcons.analytics, 'Play Stats',
                  'Listening history, timestamps, and play counts'),
              _infoTile(AppIcons.favorite, 'Favorites', 'Your favorite songs'),
              _infoTile(AppIcons.playlist, 'Playlists',
                  'All playlists and merged groups'),
              _infoTile(
                  AppIcons.settings,
                  'Settings',
                  settings.syncSettingsEnabled
                      ? 'Theme, playback, and UI preferences'
                      : 'Settings sync disabled (per-device preferences)'),
              _infoTile(AppIcons.image, 'Artist/Album Art',
                  'Online cover links and song cover preferences'),
            ],
          ),
        ],
      ]),
    );
  }

  void _confirmPushLocalToCloud(BuildContext context) {
    final settings = ref.read(settingsProvider);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Push Local to Cloud'),
        content: const Text(
          'This will overwrite your online backup on Google Drive with current device data and stats. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(syncProvider.notifier).forcePushLocalToCloud(
                    syncSettings: settings.syncSettingsEnabled,
                  );
            },
            child: const Text('Overwrite Cloud'),
          ),
        ],
      ),
    );
  }

  void _confirmPullCloudToLocal(BuildContext context) {
    final settings = ref.read(settingsProvider);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pull Cloud to Local'),
        content: const Text(
          'This will clear local play stats on this device and replace them with your online cloud backup. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(syncProvider.notifier).forcePullCloudToLocal(
                    syncSettings: settings.syncSettingsEnabled,
                  );
            },
            child: const Text('Replace Local Data'),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(AppIconData icon, String title, String subtitle) {
    return AppSettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
    );
  }

  String _formatTimestamp(double epoch) {
    final dt = DateTime.fromMillisecondsSinceEpoch((epoch * 1000).toInt());
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}
