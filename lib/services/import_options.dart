enum ImportDataCategory {
  favorites,
  suggestless,
  hidden,
  playlists,
  mergedGroups,
  recommendations,
  moods,
  userdata,
  playHistory,
  songs,
  finalStats,
  queueHistory,
  shuffleState,
  playbackState,
  themeSettings,
  scannerSettings,
  playbackSettings,
  uiSettings,
  backupSettings,
}

enum ImportDataType {
  database,
  storage,
  settings,
}

extension ImportDataCategoryExtension on ImportDataCategory {
  ImportDataType get type {
    switch (this) {
      case ImportDataCategory.favorites:
      case ImportDataCategory.suggestless:
      case ImportDataCategory.hidden:
      case ImportDataCategory.playlists:
      case ImportDataCategory.mergedGroups:
      case ImportDataCategory.recommendations:
      case ImportDataCategory.moods:
      case ImportDataCategory.userdata:
      case ImportDataCategory.playHistory:
        return ImportDataType.database;
      case ImportDataCategory.songs:
      case ImportDataCategory.finalStats:
      case ImportDataCategory.queueHistory:
      case ImportDataCategory.shuffleState:
      case ImportDataCategory.playbackState:
        return ImportDataType.storage;
      case ImportDataCategory.themeSettings:
      case ImportDataCategory.scannerSettings:
      case ImportDataCategory.playbackSettings:
      case ImportDataCategory.uiSettings:
      case ImportDataCategory.backupSettings:
        return ImportDataType.settings;
    }
  }

  String get displayName {
    switch (this) {
      case ImportDataCategory.favorites:
        return 'Favorites';
      case ImportDataCategory.suggestless:
        return 'Suggest-less';
      case ImportDataCategory.hidden:
        return 'Hidden';
      case ImportDataCategory.playlists:
        return 'Playlists';
      case ImportDataCategory.mergedGroups:
        return 'Merged Groups';
      case ImportDataCategory.recommendations:
        return 'Recommendations';
      case ImportDataCategory.moods:
        return 'Moods';
      case ImportDataCategory.userdata:
        return 'User Account';
      case ImportDataCategory.playHistory:
        return 'Play History';
      case ImportDataCategory.songs:
        return 'Songs Library';
      case ImportDataCategory.finalStats:
        return 'Statistics';
      case ImportDataCategory.queueHistory:
        return 'Queue History';
      case ImportDataCategory.shuffleState:
        return 'Shuffle State';
      case ImportDataCategory.playbackState:
        return 'Playback State';
      case ImportDataCategory.themeSettings:
        return 'Theme';
      case ImportDataCategory.scannerSettings:
        return 'Scanner';
      case ImportDataCategory.playbackSettings:
        return 'Playback';
      case ImportDataCategory.uiSettings:
        return 'UI';
      case ImportDataCategory.backupSettings:
        return 'Backup';
    }
  }

  String get description {
    switch (this) {
      case ImportDataCategory.favorites:
        return 'Favorite songs';
      case ImportDataCategory.suggestless:
        return 'Songs excluded from suggestions';
      case ImportDataCategory.hidden:
        return 'Hidden songs';
      case ImportDataCategory.playlists:
        return 'User-created playlists';
      case ImportDataCategory.mergedGroups:
        return 'Merged duplicate songs';
      case ImportDataCategory.recommendations:
        return 'Recommendation preferences and removals';
      case ImportDataCategory.moods:
        return 'Mood tags and song associations';
      case ImportDataCategory.userdata:
        return 'User authentication data';
      case ImportDataCategory.playHistory:
        return 'Play sessions and events';
      case ImportDataCategory.songs:
        return 'Song metadata library';
      case ImportDataCategory.finalStats:
        return 'Fun listening statistics';
      case ImportDataCategory.queueHistory:
        return 'Saved queue snapshots';
      case ImportDataCategory.shuffleState:
        return 'Custom shuffle configuration';
      case ImportDataCategory.playbackState:
        return 'Current playback position and queue';
      case ImportDataCategory.themeSettings:
        return 'Theme mode, colors';
      case ImportDataCategory.scannerSettings:
        return 'Music folders, excluded folders, file filters';
      case ImportDataCategory.playbackSettings:
        return 'Fade durations, gap playback';
      case ImportDataCategory.uiSettings:
        return 'Sort order, visualizer, waveform display';
      case ImportDataCategory.backupSettings:
        return 'Auto backup frequency';
    }
  }

  String get dbTableName {
    switch (this) {
      case ImportDataCategory.favorites:
        return 'favorite';
      case ImportDataCategory.suggestless:
        return 'suggestless';
      case ImportDataCategory.hidden:
        return 'hidden';
      case ImportDataCategory.playlists:
        return 'playlist';
      case ImportDataCategory.mergedGroups:
        return 'merged_song_group';
      case ImportDataCategory.recommendations:
        return 'recommendation_preference';
      case ImportDataCategory.moods:
        return 'mood_tag';
      case ImportDataCategory.userdata:
        return 'userdata';
      case ImportDataCategory.playHistory:
        return 'playevent';
      default:
        return '';
    }
  }
}

class ImportOptions {
  final Set<ImportDataCategory> categories;
  final bool additive;
  final bool restoreDatabases;
  final bool restorePlaybackState;

  const ImportOptions({
    this.categories = const {},
    this.additive = false,
    this.restoreDatabases = true,
    this.restorePlaybackState = true,
  });

  ImportOptions copyWith({
    Set<ImportDataCategory>? categories,
    bool? additive,
    bool? restoreDatabases,
    bool? restorePlaybackState,
  }) {
    return ImportOptions(
      categories: categories ?? this.categories,
      additive: additive ?? this.additive,
      restoreDatabases: restoreDatabases ?? this.restoreDatabases,
      restorePlaybackState: restorePlaybackState ?? this.restorePlaybackState,
    );
  }

  bool hasCategory(ImportDataCategory category) =>
      categories.contains(category);

  bool get hasDatabaseCategories => categories.any(
        (c) => c.type == ImportDataType.database,
      );

  bool get hasStorageCategories => categories.any(
        (c) => c.type == ImportDataType.storage,
      );

  bool get hasSettingsCategories => categories.any(
        (c) => c.type == ImportDataType.settings,
      );

  static const ImportOptions defaultImport = ImportOptions(
    categories: {
      ImportDataCategory.favorites,
      ImportDataCategory.suggestless,
      ImportDataCategory.hidden,
      ImportDataCategory.playlists,
      ImportDataCategory.mergedGroups,
      ImportDataCategory.recommendations,
      ImportDataCategory.moods,
      ImportDataCategory.userdata,
      ImportDataCategory.playHistory,
      ImportDataCategory.songs,
      ImportDataCategory.finalStats,
      ImportDataCategory.queueHistory,
      ImportDataCategory.shuffleState,
      ImportDataCategory.playbackState,
      ImportDataCategory.themeSettings,
      ImportDataCategory.scannerSettings,
      ImportDataCategory.playbackSettings,
      ImportDataCategory.uiSettings,
      ImportDataCategory.backupSettings,
    },
    additive: false,
    restoreDatabases: true,
    restorePlaybackState: true,
  );
}
