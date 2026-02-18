import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../widgets/scanning_progress_bar.dart';
import 'folder_management_screen.dart';
import 'storage_management_screen.dart';
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
            subtitle: 'Music folders, scanning, storage',
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
            subtitle: 'Backup, restore, optimize, re-index',
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

class LibrarySettingsScreen extends StatelessWidget {
  const LibrarySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
              _buildListTile(
                context: context,
                icon: Icons.storage_outlined,
                title: 'Manage Storage',
                subtitle: 'Disk usage and data management',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const StorageManagementScreen()),
                  );
                },
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
}
