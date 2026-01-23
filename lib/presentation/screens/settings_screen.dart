import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../providers/providers.dart';
import '../../providers/theme_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import 'cache_management_screen.dart';
import '../widgets/scanning_progress_bar.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _selectMusicFolder() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      final storage = ref.read(storageServiceProvider);
      await storage.setMusicFolderPath(selectedDirectory);
      ref.invalidate(songsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Music folder updated")));
      }
    }
  }

  Future<void> _selectLyricsFolder() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      final storage = ref.read(storageServiceProvider);
      await storage.setLyricsFolderPath(selectedDirectory);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Lyrics folder updated")));
      }
    }
  }

  void _showThemeSelector(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Consumer(builder: (context, ref, child) {
          final currentTheme = ref.watch(themeProvider);
          return AlertDialog(
            title: const Text("Select Theme"),
            content: RadioGroup<GruThemeMode>(
              groupValue: currentTheme.mode,
              onChanged: (val) {
                if (val != null) {
                  ref.read(themeProvider.notifier).setTheme(val);
                  Navigator.pop(context);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var theme in GruThemeMode.values)
                    RadioListTile<GruThemeMode>(
                      title:
                          Text(theme.toString().split('.').last.toUpperCase()),
                      value: theme,
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(isScanningProvider)) {
      return const ScanningProgressBar();
    }

    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSettingsGroup(
            title: 'Appearance',
            children: [
              _buildListTile(
                icon: Icons.palette_outlined,
                title: 'App Theme',
                subtitle: 'Choose your visual style',
                onTap: () => _showThemeSelector(context),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.waves_rounded),
                title: const Text('Audio Visualizer'),
                subtitle: const Text('Show animated wave while playing'),
                value: settings.visualizerEnabled,
                onChanged: (val) {
                  ref.read(settingsProvider.notifier).setVisualizerEnabled(val);
                },
              ),
              FutureBuilder<bool>(
                future: ref.read(storageServiceProvider).getIsLocalMode(),
                builder: (context, snapshot) {
                  final isLocalMode = snapshot.data ?? false;

                  if (isLocalMode) return const SizedBox.shrink();

                  final themeState = ref.watch(themeProvider);

                  return SwitchListTile(
                    secondary: const Icon(Icons.sync_rounded),
                    title: const Text('Sync Theme'),
                    subtitle:
                        const Text('Sync your visual style across devices'),
                    value: themeState.syncTheme,
                    onChanged: (val) {
                      ref.read(themeProvider.notifier).setSyncTheme(val);

                      ref.read(userDataProvider.notifier).refresh();
                    },
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSettingsGroup(
            title: 'Storage & Folders',
            children: [
              FutureBuilder<String?>(
                  future: ref.read(storageServiceProvider).getMusicFolderPath(),
                  builder: (context, snapshot) {
                    return _buildListTile(
                      icon: Icons.library_music_outlined,
                      title: 'Music Folder',
                      subtitle: snapshot.data ?? 'Not selected',
                      onTap: _selectMusicFolder,
                    );
                  }),
              FutureBuilder<String?>(
                  future:
                      ref.read(storageServiceProvider).getLyricsFolderPath(),
                  builder: (context, snapshot) {
                    return _buildListTile(
                      icon: Icons.lyrics_outlined,
                      title: 'Lyrics Folder',
                      subtitle: snapshot.data ?? 'Not selected (Optional)',
                      onTap: _selectLyricsFolder,
                    );
                  }),
              _buildListTile(
                icon: Icons.storage_outlined,
                title: 'Manage Cache',
                subtitle: 'Internal app cache management',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CacheManagementScreen()),
                  );
                },
              ),
              _buildListTile(
                icon: Icons.refresh_rounded,
                title: 'Re-scan Library Now',
                subtitle: 'Manually refresh all songs from disk',
                onTap: () {
                  ref.read(songsProvider.notifier).forceFullScan();

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Scanning library...")),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildPullToRefreshSettings(),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup(
      {required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Card(
          elevation: 0,
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.3),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildPullToRefreshSettings() {
    return FutureBuilder<bool>(
      future: ref.read(storageServiceProvider).getIsLocalMode(),
      builder: (context, snapshot) {
        final isLocalMode = snapshot.data ?? false;

        return _buildSettingsGroup(
          title: 'Pull to Refresh',
          children: [
            FutureBuilder<bool>(
              future:
                  ref.read(storageServiceProvider).getPullToRefreshEnabled(),
              builder: (context, snapshot) {
                return SwitchListTile(
                  secondary: const Icon(Icons.touch_app_outlined),
                  title: const Text('Enable Pull to Refresh'),
                  value: snapshot.data ?? true,
                  onChanged: (val) async {
                    await ref
                        .read(storageServiceProvider)
                        .setPullToRefreshEnabled(val);

                    setState(() {});
                  },
                );
              },
            ),
            if (!isLocalMode)
              FutureBuilder<String>(
                future: ref.read(storageServiceProvider).getServerRefreshMode(),
                builder: (context, snapshot) {
                  final mode = snapshot.data ?? 'sync_only';

                  return RadioGroup<String>(
                    groupValue: mode,
                    onChanged: (val) async {
                      if (val != null) {
                        await ref
                            .read(storageServiceProvider)
                            .setServerRefreshMode(val);

                        setState(() {});
                      }
                    },
                    child: const Column(
                      children: [
                        RadioListTile<String>(
                          title: Text('Sync with server only'),
                          value: 'sync_only',
                        ),
                        RadioListTile<String>(
                          title: Text('Sync and scan library'),
                          value: 'sync_and_scan',
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color? textColor,
    Color? iconColor,
  }) {
    return Card(
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.3),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(title,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
      ),
    );
  }
}
