import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../widgets/scanning_progress_bar.dart';
import '../components/app_feedback.dart';
import '../components/app_screen_header.dart';
import '../components/app_settings.dart';
import 'folder_management_screen.dart';
import 'playback_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'data_management_settings_screen.dart';
import 'misc_settings_screen.dart';
import 'about_settings_screen.dart';
import 'indexer_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isScanningProvider)) {
      return const ScanningProgressBar();
    }

    return Scaffold(
      appBar: const AppTopBar(title: 'Settings'),
      body: AppSettingsList(
        children: [
          AppSettingsGroup(
            label: 'Setup',
            children: [
              AppSettingsTile(
                icon: Icons.library_music_outlined,
                title: 'Library',
                subtitle: 'Music folders, scanning',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const LibrarySettingsScreen()),
                ),
              ),
              AppSettingsTile(
                icon: Icons.play_circle_outline_rounded,
                title: 'Playback',
                subtitle: 'Audio settings, transitions',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PlaybackSettingsScreen()),
                ),
              ),
              AppSettingsTile(
                icon: Icons.palette_outlined,
                title: 'Appearance',
                subtitle: 'Theme, display options',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AppearanceSettingsScreen()),
                ),
              ),
            ],
          ),
          AppSettingsGroup(
            label: 'Data',
            children: [
              AppSettingsTile(
                icon: Icons.settings_backup_restore_rounded,
                title: 'Data Management',
                subtitle: 'Backup, restore, storage, optimize',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DataManagementSettingsScreen()),
                ),
              ),
              AppSettingsTile(
                icon: Icons.data_object_rounded,
                title: 'Indexer',
                subtitle: 'Manage and rebuild all app indexes and caches',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const IndexerScreen()),
                ),
              ),
            ],
          ),
          AppSettingsGroup(
            label: 'About',
            children: [
              AppSettingsTile(
                icon: Icons.miscellaneous_services_outlined,
                title: 'Misc',
                subtitle: 'Privacy, behavior',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MiscSettingsScreen()),
                ),
              ),
              AppSettingsTile(
                icon: Icons.info_outline_rounded,
                title: 'About',
                subtitle: 'Version, updates, release notes',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AboutSettingsScreen()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LibrarySettingsScreen extends ConsumerWidget {
  const LibrarySettingsScreen({super.key});

  // Discrete steps for file size slider (in bytes)
  static const List<int> _fileSizeSteps = [
    0,
    10240,
    51200,
    102400,
    204800,
    512000,
    1048576,
    2097152,
    5242880,
    10485760,
    26214400,
    52428800,
    104857600,
  ];

  // Discrete steps for track duration slider (in milliseconds)
  static const List<int> _durationSteps = [
    0,
    5000,
    10000,
    15000,
    20000,
    30000,
    45000,
    60000,
    120000,
    300000,
  ];

  static int _nearestFileSizeIndex(int bytes) {
    int best = 0;
    int bestDiff = (bytes - _fileSizeSteps[0]).abs();
    for (int i = 1; i < _fileSizeSteps.length; i++) {
      final diff = (bytes - _fileSizeSteps[i]).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return best;
  }

  static int _nearestDurationIndex(int ms) {
    int best = 0;
    int bestDiff = (ms - _durationSteps[0]).abs();
    for (int i = 1; i < _durationSteps.length; i++) {
      final diff = (ms - _durationSteps[i]).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return best;
  }

  static String _formatFileSize(int bytes) {
    if (bytes == 0) return 'None';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) {
      final kb = bytes / 1024;
      return '${kb == kb.truncateToDouble() ? kb.toInt() : kb.toStringAsFixed(2)} KB';
    }
    final mb = bytes / 1048576;
    return '${mb == mb.truncateToDouble() ? mb.toInt() : mb.toStringAsFixed(1)} MB';
  }

  static String _formatDuration(int ms) {
    if (ms == 0) return 'None';
    if (ms < 60000) return '${(ms / 1000).round()} s';
    final min = ms ~/ 60000;
    final sec = (ms % 60000) ~/ 1000;
    return sec == 0 ? '$min min' : '${min}m ${sec}s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: const AppTopBar(title: 'Library'),
      body: AppSettingsList(
        children: [
          AppSettingsGroup(
            label: 'Library',
            icon: Icons.library_music_outlined,
            children: [
              AppSettingsTile(
                icon: Icons.folder_outlined,
                title: 'Music Folders',
                subtitle: 'Manage music library folders',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const FolderManagementScreen(),
                  ),
                ),
              ),
              AppSettingsTile(
                icon: Icons.refresh_rounded,
                title: 'Re-scan Library Now',
                subtitle: 'Manually refresh all songs from disk',
                onTap: () => appSnack(context, 'Scanning library…'),
              ),
            ],
          ),
          AppSettingsGroup(
            label: 'Filters',
            icon: Icons.filter_list_rounded,
            children: [
              AppSettingsSwitch(
                icon: Icons.video_library_outlined,
                title: 'Include Videos',
                subtitle: 'Show video files in your song library',
                value: settings.includeVideos,
                onChanged: notifier.setIncludeVideos,
              ),
              AppSettingsSlider(
                icon: Icons.data_usage_rounded,
                title: 'Minimum File Size',
                valueLabel: _formatFileSize(settings.minimumFileSizeBytes),
                value: _nearestFileSizeIndex(settings.minimumFileSizeBytes)
                    .toDouble(),
                min: 0,
                max: (_fileSizeSteps.length - 1).toDouble(),
                divisions: _fileSizeSteps.length - 1,
                onChanged: (val) => notifier
                    .setMinimumFileSizeBytes(_fileSizeSteps[val.round()]),
              ),
              AppSettingsSlider(
                icon: Icons.timer_outlined,
                title: 'Minimum Duration',
                valueLabel: _formatDuration(settings.minimumTrackDurationMs),
                value: _nearestDurationIndex(settings.minimumTrackDurationMs)
                    .toDouble(),
                min: 0,
                max: (_durationSteps.length - 1).toDouble(),
                divisions: _durationSteps.length - 1,
                onChanged: (val) => notifier
                    .setMinimumTrackDurationMs(_durationSteps[val.round()]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
