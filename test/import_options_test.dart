import 'package:flutter_test/flutter_test.dart';
import 'package:gru_songs/services/import_options.dart';

void main() {
  group('ImportDataCategory', () {
    test('categories have correct display names', () {
      expect(ImportDataCategory.favorites.displayName, 'Favorites');
      expect(ImportDataCategory.suggestless.displayName, 'Suggest-less');
      expect(ImportDataCategory.hidden.displayName, 'Hidden');
      expect(ImportDataCategory.playlists.displayName, 'Playlists');
      expect(ImportDataCategory.mergedGroups.displayName, 'Merged Groups');
      expect(ImportDataCategory.recommendations.displayName, 'Recommendations');
      expect(ImportDataCategory.moods.displayName, 'Moods');
      expect(ImportDataCategory.userdata.displayName, 'User Account');
      expect(ImportDataCategory.playHistory.displayName, 'Play History');
      expect(ImportDataCategory.songs.displayName, 'Songs Library');
      expect(ImportDataCategory.finalStats.displayName, 'Statistics');
      expect(ImportDataCategory.queueHistory.displayName, 'Queue History');
      expect(ImportDataCategory.shuffleState.displayName, 'Shuffle State');
      expect(ImportDataCategory.playbackState.displayName, 'Playback State');
      expect(ImportDataCategory.themeSettings.displayName, 'Theme');
      expect(ImportDataCategory.scannerSettings.displayName, 'Scanner');
      expect(ImportDataCategory.playbackSettings.displayName, 'Playback');
      expect(ImportDataCategory.uiSettings.displayName, 'UI');
      expect(ImportDataCategory.backupSettings.displayName, 'Backup');
    });

    test('categories have correct descriptions', () {
      expect(ImportDataCategory.favorites.description, 'Favorite songs');
      expect(ImportDataCategory.suggestless.description,
          'Songs excluded from suggestions');
      expect(ImportDataCategory.hidden.description, 'Hidden songs');
      expect(
          ImportDataCategory.playlists.description, 'User-created playlists');
      expect(ImportDataCategory.mergedGroups.description,
          'Merged duplicate songs');
      expect(ImportDataCategory.recommendations.description,
          'Recommendation preferences and removals');
      expect(ImportDataCategory.moods.description,
          'Mood tags and song associations');
      expect(
          ImportDataCategory.userdata.description, 'User authentication data');
      expect(ImportDataCategory.playHistory.description,
          'Play sessions and events');
      expect(ImportDataCategory.songs.description, 'Song metadata library');
      expect(ImportDataCategory.finalStats.description,
          'Fun listening statistics');
      expect(
          ImportDataCategory.queueHistory.description, 'Saved queue snapshots');
      expect(ImportDataCategory.shuffleState.description,
          'Custom shuffle configuration');
      expect(ImportDataCategory.playbackState.description,
          'Current playback position and queue');
      expect(
          ImportDataCategory.themeSettings.description, 'Theme mode, colors');
      expect(ImportDataCategory.scannerSettings.description,
          'Music folders, excluded folders, file filters');
      expect(ImportDataCategory.playbackSettings.description,
          'Fade durations, gap playback');
      expect(ImportDataCategory.uiSettings.description,
          'Sort order, visualizer, waveform display');
      expect(ImportDataCategory.backupSettings.description,
          'Auto backup frequency');
    });

    test('categories have correct types', () {
      expect(ImportDataCategory.favorites.type, ImportDataType.database);
      expect(ImportDataCategory.suggestless.type, ImportDataType.database);
      expect(ImportDataCategory.hidden.type, ImportDataType.database);
      expect(ImportDataCategory.playlists.type, ImportDataType.database);
      expect(ImportDataCategory.mergedGroups.type, ImportDataType.database);
      expect(ImportDataCategory.recommendations.type, ImportDataType.database);
      expect(ImportDataCategory.moods.type, ImportDataType.database);
      expect(ImportDataCategory.userdata.type, ImportDataType.database);
      expect(ImportDataCategory.playHistory.type, ImportDataType.database);

      expect(ImportDataCategory.songs.type, ImportDataType.storage);
      expect(ImportDataCategory.finalStats.type, ImportDataType.storage);
      expect(ImportDataCategory.queueHistory.type, ImportDataType.storage);
      expect(ImportDataCategory.shuffleState.type, ImportDataType.storage);
      expect(ImportDataCategory.playbackState.type, ImportDataType.storage);

      expect(ImportDataCategory.themeSettings.type, ImportDataType.settings);
      expect(ImportDataCategory.scannerSettings.type, ImportDataType.settings);
      expect(ImportDataCategory.playbackSettings.type, ImportDataType.settings);
      expect(ImportDataCategory.uiSettings.type, ImportDataType.settings);
      expect(ImportDataCategory.backupSettings.type, ImportDataType.settings);
    });

    test('database categories return correct table names', () {
      expect(ImportDataCategory.favorites.dbTableName, 'favorite');
      expect(ImportDataCategory.suggestless.dbTableName, 'suggestless');
      expect(ImportDataCategory.hidden.dbTableName, 'hidden');
      expect(ImportDataCategory.playlists.dbTableName, 'playlist');
      expect(ImportDataCategory.mergedGroups.dbTableName, 'merged_song_group');
      expect(ImportDataCategory.recommendations.dbTableName,
          'recommendation_preference');
      expect(ImportDataCategory.moods.dbTableName, 'mood_tag');
      expect(ImportDataCategory.userdata.dbTableName, 'userdata');
      expect(ImportDataCategory.playHistory.dbTableName, 'playevent');
    });

    test('non-database categories return empty table name', () {
      expect(ImportDataCategory.songs.dbTableName, '');
      expect(ImportDataCategory.finalStats.dbTableName, '');
      expect(ImportDataCategory.queueHistory.dbTableName, '');
      expect(ImportDataCategory.shuffleState.dbTableName, '');
      expect(ImportDataCategory.playbackState.dbTableName, '');
      expect(ImportDataCategory.themeSettings.dbTableName, '');
      expect(ImportDataCategory.scannerSettings.dbTableName, '');
      expect(ImportDataCategory.playbackSettings.dbTableName, '');
      expect(ImportDataCategory.uiSettings.dbTableName, '');
      expect(ImportDataCategory.backupSettings.dbTableName, '');
    });
  });

  group('ImportOptions', () {
    test('defaultImport includes all categories', () {
      expect(ImportOptions.defaultImport.categories.length, 19);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.favorites),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.suggestless),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.hidden),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.playlists),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.mergedGroups),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.recommendations),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.moods),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.userdata),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.playHistory),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.songs),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.finalStats),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.queueHistory),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.shuffleState),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.playbackState),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.themeSettings),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.scannerSettings),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.playbackSettings),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.uiSettings),
          true);
      expect(
          ImportOptions.defaultImport.categories
              .contains(ImportDataCategory.backupSettings),
          true);
    });

    test('defaultImport has correct default values', () {
      expect(ImportOptions.defaultImport.additive, false);
      expect(ImportOptions.defaultImport.restoreDatabases, true);
      expect(ImportOptions.defaultImport.restorePlaybackState, true);
    });

    test('hasCategory returns correct value', () {
      final options = ImportOptions(
        categories: {
          ImportDataCategory.favorites,
          ImportDataCategory.playlists
        },
      );

      expect(options.hasCategory(ImportDataCategory.favorites), true);
      expect(options.hasCategory(ImportDataCategory.playlists), true);
      expect(options.hasCategory(ImportDataCategory.hidden), false);
      expect(options.hasCategory(ImportDataCategory.playHistory), false);
    });

    test('hasDatabaseCategories returns correct value', () {
      final optionsWithDb = ImportOptions(
        categories: {
          ImportDataCategory.favorites,
          ImportDataCategory.shuffleState
        },
      );
      expect(optionsWithDb.hasDatabaseCategories, true);

      final optionsWithoutDb = ImportOptions(
        categories: {
          ImportDataCategory.themeSettings,
          ImportDataCategory.songs
        },
      );
      expect(optionsWithoutDb.hasDatabaseCategories, false);
    });

    test('hasStorageCategories returns correct value', () {
      final optionsWithStorage = ImportOptions(
        categories: {ImportDataCategory.songs, ImportDataCategory.favorites},
      );
      expect(optionsWithStorage.hasStorageCategories, true);

      final optionsWithoutStorage = ImportOptions(
        categories: {
          ImportDataCategory.themeSettings,
          ImportDataCategory.favorites
        },
      );
      expect(optionsWithoutStorage.hasStorageCategories, false);
    });

    test('hasSettingsCategories returns correct value', () {
      final optionsWithSettings = ImportOptions(
        categories: {
          ImportDataCategory.themeSettings,
          ImportDataCategory.favorites
        },
      );
      expect(optionsWithSettings.hasSettingsCategories, true);

      final optionsWithoutSettings = ImportOptions(
        categories: {ImportDataCategory.songs, ImportDataCategory.favorites},
      );
      expect(optionsWithoutSettings.hasSettingsCategories, false);
    });

    test('copyWith creates new instance with updated values', () {
      final original = ImportOptions(
        categories: {ImportDataCategory.favorites},
        additive: false,
        restoreDatabases: true,
        restorePlaybackState: true,
      );

      final copied = original.copyWith(
        categories: {
          ImportDataCategory.favorites,
          ImportDataCategory.playlists
        },
        additive: true,
      );

      expect(copied.categories.length, 2);
      expect(copied.categories.contains(ImportDataCategory.favorites), true);
      expect(copied.categories.contains(ImportDataCategory.playlists), true);
      expect(copied.additive, true);
      expect(copied.restoreDatabases, true);
      expect(copied.restorePlaybackState, true);
    });

    test('copyWith preserves unchanged values', () {
      final original = ImportOptions(
        categories: {ImportDataCategory.favorites},
        additive: true,
        restoreDatabases: false,
        restorePlaybackState: false,
      );

      final copied = original.copyWith(
        categories: {ImportDataCategory.playlists},
      );

      expect(copied.additive, true);
      expect(copied.restoreDatabases, false);
      expect(copied.restorePlaybackState, false);
    });

    test('empty categories works correctly', () {
      final options = ImportOptions(categories: {});

      expect(options.hasDatabaseCategories, false);
      expect(options.hasStorageCategories, false);
      expect(options.hasSettingsCategories, false);
      expect(options.hasCategory(ImportDataCategory.favorites), false);
    });

    test('mixing all category types works correctly', () {
      final options = ImportOptions(
        categories: {
          ImportDataCategory.favorites, // database
          ImportDataCategory.songs, // storage
          ImportDataCategory.themeSettings, // settings
        },
      );

      expect(options.hasDatabaseCategories, true);
      expect(options.hasStorageCategories, true);
      expect(options.hasSettingsCategories, true);
    });
  });

  group('ImportDataType', () {
    test('enum values exist', () {
      expect(ImportDataType.values.length, 3);
      expect(ImportDataType.database, isNotNull);
      expect(ImportDataType.storage, isNotNull);
      expect(ImportDataType.settings, isNotNull);
    });
  });
}
