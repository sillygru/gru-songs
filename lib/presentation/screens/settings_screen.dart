import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../widgets/scanning_progress_bar.dart';
import 'folder_management_screen.dart';
import 'playback_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'data_management_settings_screen.dart';
import 'misc_settings_screen.dart';
import 'indexer_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isScanningProvider)) {
      return const ScanningProgressBar();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCategoryTile(
            context: context,
            icon: const Icon(Icons.library_music_outlined),
            title: 'Library',
            subtitle: 'Music folders, scanning',
            color: Colors.blue,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LibrarySettingsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _buildCategoryTile(
            context: context,
            icon: const Icon(Icons.play_circle_outline),
            title: 'Playback',
            subtitle: 'Audio settings, transitions',
            color: Colors.green,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PlaybackSettingsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _buildCategoryTile(
            context: context,
            icon: const Icon(Icons.palette_outlined),
            title: 'Appearance',
            subtitle: 'Theme, display options',
            color: Colors.purple,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AppearanceSettingsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _buildCategoryTile(
            context: context,
            icon: const Icon(Icons.settings_backup_restore_rounded),
            title: 'Data Management',
            subtitle: 'Backup, restore, storage, optimize',
            color: Colors.teal,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const DataManagementSettingsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _buildCategoryTile(
            context: context,
            icon: Builder(
              builder: (context) => Transform.rotate(
                angle: 0.785398,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: IconTheme.of(context).color ?? Colors.black,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
            title: 'Indexer',
            subtitle: 'Manage and rebuild all app indexes and caches',
            color: Colors.orange,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IndexerScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _buildCategoryTile(
            context: context,
            icon: const Icon(Icons.miscellaneous_services_outlined),
            title: 'Misc',
            subtitle: 'Privacy, behavior',
            color: Colors.grey,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MiscSettingsScreen()),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildCategoryTile({
    required BuildContext context,
    required Widget icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.3),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconTheme(
              data: IconThemeData(color: color, size: 28), child: icon),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onTap: onTap,
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
      appBar: AppBar(
        title: const Text("Library"),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: [
          _buildSettingsGroup(
            context: context,
            title: 'Library',
            icon: Icons.library_music_outlined,
            children: [
              _buildListTile(
                context: context,
                icon: Icons.folder_outlined,
                title: 'Music Folders',
                subtitle: 'Manage music library folders',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const FolderManagementScreen(),
                    ),
                  );
                },
              ),
              _buildListTile(
                context: context,
                icon: Icons.refresh_rounded,
                title: 'Re-scan Library Now',
                subtitle: 'Manually refresh all songs from disk',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Scanning library...")),
                  );
                },
              ),
            ],
          ),
          _buildSettingsGroup(
            context: context,
            title: 'Filters',
            icon: Icons.filter_list_rounded,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.video_library_outlined),
                title: const Text('Include Videos'),
                subtitle: const Text(
                  'Show video files in your song library',
                ),
                value: settings.includeVideos,
                onChanged: (val) => notifier.setIncludeVideos(val),
              ),
              _buildCompactSlider(
                context: context,
                icon: Icons.data_usage_rounded,
                title: 'Minimum File Size',
                valueLabel: _formatFileSize(settings.minimumFileSizeBytes),
                sliderValue:
                    _nearestFileSizeIndex(settings.minimumFileSizeBytes)
                        .toDouble(),
                min: 0,
                max: (_fileSizeSteps.length - 1).toDouble(),
                divisions: _fileSizeSteps.length - 1,
                onChanged: (val) => notifier
                    .setMinimumFileSizeBytes(_fileSizeSteps[val.round()]),
              ),
              _buildCompactSlider(
                context: context,
                icon: Icons.timer_outlined,
                title: 'Minimum Duration',
                valueLabel: _formatDuration(settings.minimumTrackDurationMs),
                sliderValue:
                    _nearestDurationIndex(settings.minimumTrackDurationMs)
                        .toDouble(),
                min: 0,
                max: (_durationSteps.length - 1).toDouble(),
                divisions: _durationSteps.length - 1,
                onChanged: (val) => notifier
                    .setMinimumTrackDurationMs(_durationSteps[val.round()]),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup({
    required BuildContext context,
    required String title,
    required List<Widget> children,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final List<Widget> childrenWithDividers = [];

    for (int i = 0; i < children.length; i++) {
      childrenWithDividers.add(children[i]);
      if (i < children.length - 1) {
        childrenWithDividers.add(
          Divider(
            height: 1,
            indent: 56,
            endIndent: 16,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
          child: Row(
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        Card(
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: childrenWithDividers,
          ),
        ),
      ],
    );
  }

  Widget _buildListTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading:
          Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildCompactSlider({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String valueLabel,
    required double sliderValue,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Text(
                valueLabel,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: sliderValue,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
