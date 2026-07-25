import 'package:flutter/widgets.dart';

import '../../domain/models/settings_entry.dart';
import '../tokens/app_icons.dart';
import 'about_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'backup_management_screen.dart';
import 'custom_shuffle_settings_screen.dart';
import 'data_management_settings_screen.dart';
import 'folder_management_screen.dart';
import 'indexer_screen.dart';
import 'misc_settings_screen.dart';
import 'playback_settings_screen.dart';
import 'quick_actions_settings_screen.dart';
import 'settings_screen.dart';
import 'storage_management_screen.dart';

/// A registry entry that also knows how to draw itself and where to go.
class SettingsDestination extends SettingsEntry {
  final AppIconData icon;

  /// Builds the screen this entry lives on, with the row already flagged for
  /// highlighting where the page supports it.
  final Widget Function() open;

  const SettingsDestination({
    required this.icon,
    required this.open,
    required super.title,
    required super.breadcrumb,
    super.anchorId,
    super.subtitle,
    super.keywords,
  });
}

/// Every setting the search can reach.
///
/// This is hand-maintained: Dart can't enumerate widget trees, so a row and its
/// entry are two edits. `test/settings_search_test.dart` guards the join by
/// checking that each [SettingsEntry.anchorId] here really appears as a
/// `searchId:` in a settings screen — a row renamed or removed without its
/// entry fails the suite rather than silently going missing from search.
final List<SettingsDestination> settingsRegistry = [
  // ------------------------------------------------------------------ pages
  SettingsDestination(
    icon: AppIcons.library,
    title: 'Library',
    subtitle: 'Music folders, scanning',
    breadcrumb: 'Settings',
    keywords: const ['scan', 'folders', 'filters', 'songs'],
    open: () => const LibrarySettingsScreen(),
  ),
  SettingsDestination(
    icon: AppIcons.playCircle,
    title: 'Playback',
    subtitle: 'Audio settings, transitions',
    breadcrumb: 'Settings',
    keywords: const ['audio', 'sound', 'transitions'],
    open: () => const PlaybackSettingsScreen(),
  ),
  SettingsDestination(
    icon: AppIcons.palette,
    title: 'Appearance',
    subtitle: 'Theme, display options',
    breadcrumb: 'Settings',
    keywords: const ['theme', 'colour', 'color', 'display', 'look'],
    open: () => const AppearanceSettingsScreen(),
  ),
  SettingsDestination(
    icon: AppIcons.storage,
    title: 'Data Management',
    subtitle: 'Backup, restore, storage, optimize',
    breadcrumb: 'Settings',
    keywords: const ['backup', 'restore', 'export', 'import'],
    open: () => const DataManagementSettingsScreen(),
  ),
  SettingsDestination(
    icon: AppIcons.dataObject,
    title: 'Indexer',
    subtitle: 'Manage and rebuild all app indexes and caches',
    breadcrumb: 'Settings',
    keywords: const ['index', 'rebuild', 'cache', 'reindex'],
    open: () => const IndexerScreen(),
  ),
  SettingsDestination(
    icon: AppIcons.misc,
    title: 'Misc',
    subtitle: 'Privacy, behavior',
    breadcrumb: 'Settings',
    keywords: const ['privacy', 'behaviour', 'other'],
    open: () => const MiscSettingsScreen(),
  ),
  SettingsDestination(
    icon: AppIcons.info,
    title: 'About',
    subtitle: 'Version, updates, release notes',
    breadcrumb: 'Settings',
    keywords: const ['version', 'update', 'changelog', 'release'],
    open: () => const AboutSettingsScreen(),
  ),

  // ---------------------------------------------------------------- library
  SettingsDestination(
    anchorId: 'library.folders',
    icon: AppIcons.folder,
    title: 'Music Folders',
    subtitle: 'Manage music library folders',
    breadcrumb: 'Settings › Library',
    keywords: const ['directory', 'path', 'add folder', 'sources'],
    open: () => const LibrarySettingsScreen(highlightId: 'library.folders'),
  ),
  SettingsDestination(
    anchorId: 'library.rescan',
    icon: AppIcons.refresh,
    title: 'Re-scan Library Now',
    subtitle: 'Manually refresh all songs from disk',
    breadcrumb: 'Settings › Library',
    keywords: const ['refresh', 'reload', 'sync'],
    open: () => const LibrarySettingsScreen(highlightId: 'library.rescan'),
  ),
  SettingsDestination(
    anchorId: 'library.include_videos',
    icon: AppIcons.videoLibrary,
    title: 'Include Videos',
    subtitle: 'Show video files in your song library',
    breadcrumb: 'Settings › Library › Filters',
    keywords: const ['video', 'mp4', 'clips'],
    open: () =>
        const LibrarySettingsScreen(highlightId: 'library.include_videos'),
  ),
  SettingsDestination(
    anchorId: 'library.min_file_size',
    icon: AppIcons.dataUsage,
    title: 'Minimum File Size',
    subtitle: 'Ignore files smaller than this',
    breadcrumb: 'Settings › Library › Filters',
    keywords: const ['size', 'skip', 'small', 'filter'],
    open: () =>
        const LibrarySettingsScreen(highlightId: 'library.min_file_size'),
  ),
  SettingsDestination(
    anchorId: 'library.min_duration',
    icon: AppIcons.timer,
    title: 'Minimum Duration',
    subtitle: 'Ignore tracks shorter than this',
    breadcrumb: 'Settings › Library › Filters',
    keywords: const ['length', 'short', 'skip', 'filter', 'interlude'],
    open: () =>
        const LibrarySettingsScreen(highlightId: 'library.min_duration'),
  ),
  SettingsDestination(
    icon: AppIcons.folder,
    title: 'Manage music folders',
    subtitle: 'Add, remove and rescan individual folders',
    breadcrumb: 'Settings › Library › Music Folders',
    keywords: const ['folder', 'directory', 'storage', 'sd card'],
    open: () => const FolderManagementScreen(),
  ),

  // --------------------------------------------------------------- playback
  SettingsDestination(
    anchorId: 'playback.auto_pause_mute',
    icon: AppIcons.volumeOff,
    title: 'Auto-Pause on Mute',
    subtitle: 'Pause playback when volume reaches 0',
    breadcrumb: 'Settings › Playback › Audio',
    keywords: const ['volume', 'silent', 'mute'],
    open: () =>
        const PlaybackSettingsScreen(highlightId: 'playback.auto_pause_mute'),
  ),
  SettingsDestination(
    anchorId: 'playback.auto_resume_unmute',
    icon: AppIcons.volumeUp,
    title: 'Auto-Resume on Unmute',
    subtitle: 'Resume playback when volume is restored',
    breadcrumb: 'Settings › Playback › Audio',
    keywords: const ['volume', 'unmute', 'continue'],
    open: () => const PlaybackSettingsScreen(
      highlightId: 'playback.auto_resume_unmute',
    ),
  ),
  SettingsDestination(
    anchorId: 'playback.keep_screen_awake',
    icon: AppIcons.screenLock,
    title: 'Keep Screen Awake on Lyrics',
    subtitle: 'Prevent sleep while the lyrics pane is open',
    breadcrumb: 'Settings › Playback › Audio',
    keywords: const ['sleep', 'wakelock', 'display', 'lyrics'],
    open: () => const PlaybackSettingsScreen(
      highlightId: 'playback.keep_screen_awake',
    ),
  ),
  SettingsDestination(
    anchorId: 'playback.gap',
    icon: AppIcons.hourglass,
    title: 'Gap / Delay',
    subtitle: 'Silence between tracks',
    breadcrumb: 'Settings › Playback › Transitions',
    keywords: const ['pause', 'silence', 'between', 'transition'],
    open: () => const PlaybackSettingsScreen(highlightId: 'playback.gap'),
  ),
  SettingsDestination(
    anchorId: 'playback.fade_out',
    icon: AppIcons.volumeDown,
    title: 'Fade Out',
    subtitle: 'Fade the outgoing track',
    breadcrumb: 'Settings › Playback › Transitions',
    keywords: const ['crossfade', 'gapless', 'transition', 'blend'],
    open: () => const PlaybackSettingsScreen(highlightId: 'playback.fade_out'),
  ),
  SettingsDestination(
    anchorId: 'playback.fade_in',
    icon: AppIcons.volumeUp,
    title: 'Fade In',
    subtitle: 'Fade the incoming track',
    breadcrumb: 'Settings › Playback › Transitions',
    keywords: const ['crossfade', 'gapless', 'transition', 'blend'],
    open: () => const PlaybackSettingsScreen(highlightId: 'playback.fade_in'),
  ),
  SettingsDestination(
    anchorId: 'playback.fade_play',
    icon: AppIcons.play,
    title: 'Fade on Play',
    subtitle: 'Ease the volume up when playback starts',
    breadcrumb: 'Settings › Playback › Play / Pause',
    keywords: const ['ramp', 'volume', 'start'],
    open: () => const PlaybackSettingsScreen(highlightId: 'playback.fade_play'),
  ),
  SettingsDestination(
    anchorId: 'playback.fade_pause',
    icon: AppIcons.pause,
    title: 'Fade on Pause',
    subtitle: 'Ease the volume down when playback stops',
    breadcrumb: 'Settings › Playback › Play / Pause',
    keywords: const ['ramp', 'volume', 'stop'],
    open: () =>
        const PlaybackSettingsScreen(highlightId: 'playback.fade_pause'),
  ),

  // ------------------------------------------------------------- appearance
  SettingsDestination(
    anchorId: 'appearance.visualizer',
    icon: AppIcons.waves,
    title: 'Audio Visualizer',
    subtitle: 'Show animated wave while playing',
    breadcrumb: 'Settings › Appearance › Display',
    keywords: const ['wave', 'animation', 'spectrum'],
    open: () =>
        const AppearanceSettingsScreen(highlightId: 'appearance.visualizer'),
  ),
  SettingsDestination(
    anchorId: 'appearance.waveform',
    icon: AppIcons.graphicEq,
    title: 'Waveform Progress Bar',
    subtitle: 'Show song waveform in player',
    breadcrumb: 'Settings › Appearance › Display',
    keywords: const ['seek', 'progress', 'wave'],
    open: () =>
        const AppearanceSettingsScreen(highlightId: 'appearance.waveform'),
  ),
  SettingsDestination(
    anchorId: 'appearance.song_duration',
    icon: AppIcons.timer,
    title: 'Show Song Duration',
    subtitle: 'Display duration in song lists',
    breadcrumb: 'Settings › Appearance › Display',
    keywords: const ['length', 'time', 'lists'],
    open: () =>
        const AppearanceSettingsScreen(highlightId: 'appearance.song_duration'),
  ),
  SettingsDestination(
    anchorId: 'appearance.auto_hide_bars',
    icon: AppIcons.swapVert,
    title: 'Auto-Hide Bars',
    subtitle: 'Header and bottom dock hide on downward scroll',
    breadcrumb: 'Settings › Appearance › Display',
    keywords: const ['navigation', 'dock', 'header', 'scroll', 'hide'],
    open: () => const AppearanceSettingsScreen(
      highlightId: 'appearance.auto_hide_bars',
    ),
  ),
  SettingsDestination(
    anchorId: 'appearance.lyrics_blur',
    icon: AppIcons.blur,
    title: 'Lyrics blur overlay',
    subtitle: 'Progressive blur on the lyrics top and bottom edges',
    breadcrumb: 'Settings › Appearance › Display',
    keywords: const ['blur', 'lyrics', 'fade'],
    open: () =>
        const AppearanceSettingsScreen(highlightId: 'appearance.lyrics_blur'),
  ),
  SettingsDestination(
    anchorId: 'appearance.header_blur',
    icon: AppIcons.blur,
    title: 'Progressive blur on list headers',
    subtitle: 'Blur behind scrolling headers (performance heavy)',
    breadcrumb: 'Settings › Appearance › Display',
    keywords: const ['blur', 'header', 'performance'],
    open: () =>
        const AppearanceSettingsScreen(highlightId: 'appearance.header_blur'),
  ),
  SettingsDestination(
    anchorId: 'appearance.cover_sizing',
    icon: AppIcons.photoSize,
    title: 'Player Cover Sizing',
    subtitle: 'Auto-fit or preserve source aspect ratio',
    breadcrumb: 'Settings › Appearance › Display',
    keywords: const ['artwork', 'album art', 'aspect', 'crop'],
    open: () =>
        const AppearanceSettingsScreen(highlightId: 'appearance.cover_sizing'),
  ),
  SettingsDestination(
    anchorId: 'appearance.beat_cover',
    icon: AppIcons.album,
    title: 'Beat-reactive cover',
    subtitle: 'Album art pulses with the beat',
    breadcrumb: 'Settings › Appearance › Player motion',
    keywords: const ['pulse', 'beat', 'artwork', 'motion'],
    open: () =>
        const AppearanceSettingsScreen(highlightId: 'appearance.beat_cover'),
  ),
  SettingsDestination(
    anchorId: 'appearance.beat_particles',
    icon: AppIcons.autoAwesome,
    title: 'Beat-reactive particles',
    subtitle: 'Floating particles that drift and breathe with the music',
    breadcrumb: 'Settings › Appearance › Player motion',
    keywords: const ['particles', 'motes', 'beat', 'motion'],
    open: () => const AppearanceSettingsScreen(
      highlightId: 'appearance.beat_particles',
    ),
  ),
  SettingsDestination(
    anchorId: 'appearance.motion_intensity',
    icon: AppIcons.tune,
    title: 'Motion intensity',
    subtitle: 'How strongly the player reacts',
    breadcrumb: 'Settings › Appearance › Player motion',
    keywords: const ['subtle', 'balanced', 'bold', 'custom', 'strength'],
    open: () => const AppearanceSettingsScreen(
      highlightId: 'appearance.motion_intensity',
    ),
  ),
  SettingsDestination(
    anchorId: 'appearance.beat_offset',
    icon: AppIcons.syncAlt,
    title: 'Beat sync offset',
    subtitle: 'Compensate for Bluetooth output latency',
    breadcrumb: 'Settings › Appearance › Player motion',
    keywords: const ['bluetooth', 'latency', 'delay', 'sync', 'early'],
    open: () =>
        const AppearanceSettingsScreen(highlightId: 'appearance.beat_offset'),
  ),
  SettingsDestination(
    anchorId: 'appearance.quick_picks',
    icon: AppIcons.autoAwesome,
    title: 'Quick Picks',
    subtitle: 'Show quick pick recommendations',
    breadcrumb: 'Settings › Appearance › Home screen',
    keywords: const ['home', 'recommendations', 'suggestions'],
    open: () =>
        const AppearanceSettingsScreen(highlightId: 'appearance.quick_picks'),
  ),
  SettingsDestination(
    anchorId: 'appearance.recent_queues',
    icon: AppIcons.clock,
    title: 'Recent Queues',
    subtitle: 'Show recently played queues',
    breadcrumb: 'Settings › Appearance › Home screen',
    keywords: const ['home', 'history', 'queue'],
    open: () =>
        const AppearanceSettingsScreen(highlightId: 'appearance.recent_queues'),
  ),
  SettingsDestination(
    anchorId: 'appearance.for_you',
    icon: AppIcons.explore,
    title: 'For You',
    subtitle: 'Show recommended playlists',
    breadcrumb: 'Settings › Appearance › Home screen',
    keywords: const ['home', 'mixes', 'recommendations'],
    open: () =>
        const AppearanceSettingsScreen(highlightId: 'appearance.for_you'),
  ),
  SettingsDestination(
    anchorId: 'appearance.quick_actions',
    icon: AppIcons.flashOn,
    title: 'Quick Actions',
    subtitle: 'Customize long-press actions',
    breadcrumb: 'Settings › Appearance › Interaction',
    keywords: const ['long press', 'menu', 'shortcuts'],
    open: () => const AppearanceSettingsScreen(
      highlightId: 'appearance.quick_actions',
    ),
  ),
  SettingsDestination(
    icon: AppIcons.flashOn,
    title: 'Reorder quick actions',
    subtitle: 'Choose and order the long-press actions on a song',
    breadcrumb: 'Settings › Appearance › Quick Actions',
    keywords: const ['long press', 'order', 'menu', 'shortcuts'],
    open: () => const QuickActionsSettingsScreen(),
  ),

  // ------------------------------------------------------------------- data
  SettingsDestination(
    anchorId: 'data.export',
    icon: AppIcons.upload,
    title: 'Export App Data',
    subtitle: 'Backup your stats, favorites, and playlists',
    breadcrumb: 'Settings › Data Management › Backup & Restore',
    keywords: const ['backup', 'save', 'export'],
    open: () => const DataManagementSettingsScreen(highlightId: 'data.export'),
  ),
  SettingsDestination(
    anchorId: 'data.import',
    icon: AppIcons.download,
    title: 'Import App Data',
    subtitle: 'Restore data from a backup (replaces all)',
    breadcrumb: 'Settings › Data Management › Backup & Restore',
    keywords: const ['restore', 'load', 'import'],
    open: () => const DataManagementSettingsScreen(highlightId: 'data.import'),
  ),
  SettingsDestination(
    anchorId: 'data.namida',
    icon: AppIcons.download,
    title: 'Import from Namida',
    subtitle: 'Import playlists and favorites from Namida',
    breadcrumb: 'Settings › Data Management › Backup & Restore',
    keywords: const ['namida', 'migrate', 'import'],
    open: () => const DataManagementSettingsScreen(highlightId: 'data.namida'),
  ),
  SettingsDestination(
    anchorId: 'data.backups',
    icon: AppIcons.cloudUpload,
    title: 'Manage Backups',
    subtitle: 'Create, restore, and manage app backups',
    breadcrumb: 'Settings › Data Management › Backup & Restore',
    keywords: const ['backup', 'restore', 'delete'],
    open: () => const DataManagementSettingsScreen(highlightId: 'data.backups'),
  ),
  SettingsDestination(
    anchorId: 'data.storage',
    icon: AppIcons.storage,
    title: 'Manage Storage',
    subtitle: 'Disk usage and data management',
    breadcrumb: 'Settings › Data Management › Storage',
    keywords: const ['disk', 'space', 'cache', 'cleanup'],
    open: () => const DataManagementSettingsScreen(highlightId: 'data.storage'),
  ),
  SettingsDestination(
    icon: AppIcons.cloudUpload,
    title: 'Backups',
    subtitle: 'Browse, restore and delete saved backups',
    breadcrumb: 'Settings › Data Management › Manage Backups',
    keywords: const ['backup', 'restore', 'archive'],
    open: () => const BackupManagementScreen(),
  ),
  SettingsDestination(
    icon: AppIcons.storage,
    title: 'Storage',
    subtitle: 'Disk usage by covers, waveforms, lyrics and caches',
    breadcrumb: 'Settings › Data Management › Manage Storage',
    keywords: const ['disk', 'space', 'clear cache', 'usage'],
    open: () => const StorageManagementScreen(),
  ),

  // ------------------------------------------------------------------- misc
  SettingsDestination(
    anchorId: 'misc.telemetry',
    icon: AppIcons.analytics,
    title: 'Telemetry',
    subtitle: 'Anonymous usage stats. No personal data is collected.',
    breadcrumb: 'Settings › Misc › Privacy',
    keywords: const ['analytics', 'privacy', 'tracking', 'stats'],
    open: () => const MiscSettingsScreen(highlightId: 'misc.telemetry'),
  ),
  SettingsDestination(
    anchorId: 'misc.auto_backup',
    icon: AppIcons.cloudUpload,
    title: 'Auto Backup',
    subtitle: 'How often a backup is taken',
    breadcrumb: 'Settings › Misc › Backup',
    keywords: const ['schedule', 'frequency', 'automatic'],
    open: () => const MiscSettingsScreen(highlightId: 'misc.auto_backup'),
  ),
  SettingsDestination(
    anchorId: 'misc.auto_backup_content',
    icon: AppIcons.tune,
    title: 'Auto Backup Content',
    subtitle: 'What data is included in automatic backups',
    breadcrumb: 'Settings › Misc › Backup',
    keywords: const ['contents', 'categories', 'automatic'],
    open: () =>
        const MiscSettingsScreen(highlightId: 'misc.auto_backup_content'),
  ),
  SettingsDestination(
    anchorId: 'misc.auto_delete_backups',
    icon: AppIcons.delete,
    title: 'Auto-Delete Old Backups',
    subtitle: 'Discard backups older than this',
    breadcrumb: 'Settings › Misc › Backup',
    keywords: const ['prune', 'cleanup', 'retention', 'old'],
    open: () =>
        const MiscSettingsScreen(highlightId: 'misc.auto_delete_backups'),
  ),
  SettingsDestination(
    anchorId: 'misc.pull_to_refresh',
    icon: AppIcons.touchApp,
    title: 'Pull to Refresh',
    subtitle: 'Swipe down to refresh the library',
    breadcrumb: 'Settings › Misc › Behavior',
    keywords: const ['swipe', 'gesture', 'reload'],
    open: () => const MiscSettingsScreen(highlightId: 'misc.pull_to_refresh'),
  ),

  // ---------------------------------------------------------------- shuffle
  SettingsDestination(
    icon: AppIcons.tune,
    title: 'Configure Custom Shuffle',
    subtitle: 'Adjust shuffle behavior settings',
    breadcrumb: 'Profile › Shuffle',
    keywords: const [
      'shuffle',
      'personality',
      'weights',
      'random',
      'explorer',
    ],
    open: () => const CustomShuffleSettingsScreen(),
  ),
];
