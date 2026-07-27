import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../components/ambient_scaffold.dart';
import '../components/app_settings.dart';
import '../components/app_screen_header.dart';
import '../tokens/app_icons.dart';
import '../../providers/sync_provider.dart';
import '../../providers/providers.dart';
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

    return AmbientScaffold(
      appBar: AppTopBar(
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
            label: 'Sync',
            children: [
              AppSettingsSwitch(
                icon: AppIcons.refresh,
                title: 'Auto Sync',
                subtitle: 'Sync on app foreground',
                value: settings.autoSyncEnabled,
                onChanged: (v) =>
                    ref.read(settingsProvider.notifier).setAutoSyncEnabled(v),
              ),
              AppSettingsTile(
                icon: AppIcons.syncAlt,
                title: syncState.isSyncing ? 'Syncing...' : 'Sync Now',
                subtitle: syncState.lastError != null
                    ? 'Last error: ${syncState.lastError}'
                    : null,
                onTap: syncState.isSyncing
                    ? null
                    : () => ref.read(syncProvider.notifier).sync(),
              ),
            ],
          ),
          AppSettingsGroup(
            label: 'What gets synced',
            children: [
              _infoTile(AppIcons.analytics, 'Play Stats',
                  'Listening history and play counts'),
              _infoTile(AppIcons.favorite, 'Favorites', 'Your favorite songs'),
              _infoTile(AppIcons.playlist, 'Playlists',
                  'All playlists and merged groups'),
              _infoTile(AppIcons.settings, 'Settings',
                  'Theme, playback, and UI preferences'),
              _infoTile(AppIcons.image, 'Artist/Album Art',
                  'Online-sourced cover art with images'),
            ],
          ),
        ],
      ]),
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
