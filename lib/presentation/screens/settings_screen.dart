import 'package:flutter/material.dart';
import '../components/ambient_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../widgets/scanning_progress_bar.dart';
import '../components/app_feedback.dart';
import '../components/app_screen_header.dart';
import '../components/app_settings.dart';
import '../components/app_surface.dart';
import '../components/app_icon.dart';
import '../tokens/app_tokens.dart';
import '../../domain/services/settings_search_service.dart';
import 'settings_registry.dart';
import '../routes/app_page_route.dart';
import 'folder_management_screen.dart';
import 'playback_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'data_management_settings_screen.dart';
import 'misc_settings_screen.dart';
import 'about_settings_screen.dart';
import 'indexer_screen.dart';
import 'sync_settings_screen.dart';
import '../tokens/app_icons.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _search = SettingsSearchService();

  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(isScanningProvider)) {
      return const ScanningProgressBar();
    }

    return AmbientScaffold(
      appBar: AppTopBar(
        title: 'Settings',
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.s4,
              0,
              AppTokens.s4,
              AppTokens.s3,
            ),
            child: AppSurface(
              depth: AppDepth.well,
              borderRadius: AppTokens.brPill,
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
              child: Row(
                children: [
                  AppIcon(
                    AppIcons.search,
                    size: AppTokens.iconSm,
                    color: AppTokens.fgTertiary,
                  ),
                  const SizedBox(width: AppTokens.s3),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Search settings',
                        hintStyle: AppTokens.rowSubtitle(context),
                      ),
                      style: AppTokens.rowTitle(context),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    IconButton(
                      icon:
                          const AppIcon(AppIcons.close, size: AppTokens.iconSm),
                      tooltip: 'Clear',
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _query.trim().isEmpty ? _buildGroups(context) : _buildResults(),
    );
  }

  /// Flat, breadcrumbed results — the categories are what search exists to
  /// skip, so they don't come back as headers here.
  Widget _buildResults() {
    final results = _search.search(settingsRegistry, _query);

    if (results.isEmpty) {
      return AppEmptyState(
        icon: AppIcons.search,
        title: 'No settings found',
        message: 'Nothing matches "${_query.trim()}".',
      );
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s4,
        AppTokens.s2,
        AppTokens.s4,
        AppTokens.scrollBottomInset,
      ),
      children: [
        AppSurfaceGroup(
          children: [
            for (final entry in results)
              AppSettingsTile(
                icon: entry.icon,
                title: entry.title,
                // The breadcrumb replaces the subtitle: from a result you need
                // to know *where* it lives more than what it does.
                subtitle: entry.breadcrumb,
                onTap: () => context.pushApp(entry.open()),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildGroups(BuildContext context) {
    return AppSettingsList(children: [
      AppSettingsGroup(
        label: 'Setup',
        children: [
          AppSettingsTile(
            icon: AppIcons.library,
            title: 'Library',
            subtitle: 'Music folders, scanning',
            onTap: () => context.pushApp(const LibrarySettingsScreen()),
          ),
          AppSettingsTile(
            icon: AppIcons.playCircle,
            title: 'Playback',
            subtitle: 'Audio settings, transitions',
            onTap: () => context.pushApp(const PlaybackSettingsScreen()),
          ),
          AppSettingsTile(
            icon: AppIcons.palette,
            title: 'Appearance',
            subtitle: 'Theme, display options',
            onTap: () => context.pushApp(const AppearanceSettingsScreen()),
          ),
        ],
      ),
      AppSettingsGroup(
        label: 'Sync',
        children: [
          AppSettingsTile(
            icon: AppIcons.cloudUpload,
            title: 'Sync',
            subtitle: 'Google Drive, cross-device sync',
            onTap: () => context.pushApp(const SyncSettingsScreen()),
          ),
        ],
      ),
      AppSettingsGroup(
        label: 'Data',
        children: [
          AppSettingsTile(
            icon: AppIcons.storage,
            title: 'Data Management',
            subtitle: 'Backup, restore, storage, optimize',
            onTap: () => context.pushApp(const DataManagementSettingsScreen()),
          ),
          AppSettingsTile(
            icon: AppIcons.dataObject,
            title: 'Indexer',
            subtitle: 'Manage and rebuild all app indexes and caches',
            onTap: () => context.pushApp(const IndexerScreen()),
          ),
        ],
      ),
      AppSettingsGroup(
        label: 'About',
        children: [
          AppSettingsTile(
            icon: AppIcons.misc,
            title: 'Misc',
            subtitle: 'Privacy, behavior',
            onTap: () => context.pushApp(const MiscSettingsScreen()),
          ),
          AppSettingsTile(
            icon: AppIcons.info,
            title: 'About',
            subtitle: 'Version, updates, release notes',
            onTap: () => context.pushApp(const AboutSettingsScreen()),
          ),
        ],
      ),
    ]);
  }
}

class LibrarySettingsScreen extends ConsumerWidget {
  /// Row to reveal when opened from settings search.
  final String? highlightId;

  const LibrarySettingsScreen({super.key, this.highlightId});

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

    return AmbientScaffold(
      appBar: const AppTopBar(title: 'Library'),
      body: AppSettingsList(
        highlightId: highlightId,
        children: [
          AppSettingsGroup(
            label: 'Library',
            icon: AppIcons.library,
            children: [
              AppSettingsTile(
                icon: AppIcons.folder,
                searchId: 'library.folders',
                title: 'Music Folders',
                subtitle: 'Manage music library folders',
                onTap: () => context.pushApp(const FolderManagementScreen()),
              ),
              AppSettingsTile(
                icon: AppIcons.refresh,
                searchId: 'library.rescan',
                title: 'Re-scan Library Now',
                subtitle: 'Manually refresh all songs from disk',
                onTap: () => appSnack(context, 'Scanning library…'),
              ),
            ],
          ),
          AppSettingsGroup(
            label: 'Filters',
            icon: AppIcons.filterList,
            children: [
              AppSettingsSwitch(
                icon: AppIcons.videoLibrary,
                searchId: 'library.include_videos',
                title: 'Include Videos',
                subtitle: 'Show video files in your song library',
                value: settings.includeVideos,
                onChanged: notifier.setIncludeVideos,
              ),
              AppSettingsSlider(
                icon: AppIcons.dataUsage,
                searchId: 'library.min_file_size',
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
                icon: AppIcons.timer,
                searchId: 'library.min_duration',
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
