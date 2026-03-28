import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'database_service.dart';
import 'storage_service.dart';
import 'import_options.dart';

enum ExportContentType {
  userStats,
  userData,
  userSettings,
  coverCache,
  libraryCache,
  searchIndex,
  waveformCache,
  colorCache,
  lyricsCache,
}

class ExportOptions {
  final Set<ExportContentType> contentTypes;

  ExportOptions({Set<ExportContentType>? contentTypes})
      : contentTypes = contentTypes ??
            {
              ExportContentType.userStats,
              ExportContentType.userData,
              ExportContentType.userSettings,
            };

  bool get includeUserStats =>
      contentTypes.contains(ExportContentType.userStats);
  bool get includeUserData => contentTypes.contains(ExportContentType.userData);
  bool get includeUserSettings =>
      contentTypes.contains(ExportContentType.userSettings);
  bool get includeCoverCache =>
      contentTypes.contains(ExportContentType.coverCache);
  bool get includeLibraryCache =>
      contentTypes.contains(ExportContentType.libraryCache);
  bool get includeSearchIndex =>
      contentTypes.contains(ExportContentType.searchIndex);
  bool get includeWaveformCache =>
      contentTypes.contains(ExportContentType.waveformCache);
  bool get includeColorCache =>
      contentTypes.contains(ExportContentType.colorCache);
  bool get includeLyricsCache =>
      contentTypes.contains(ExportContentType.lyricsCache);
}

class DataExportService {
  static const String _metadataFile = 'metadata.json';

  Future<void> exportUserData({ExportOptions? options}) async {
    options ??= ExportOptions();

    final docDir = await getApplicationDocumentsDirectory();
    final tempDir = await getTemporaryDirectory();
    final exportDir = Directory(p.join(
        tempDir.path, 'export_${DateTime.now().millisecondsSinceEpoch}'));
    await exportDir.create(recursive: true);

    try {
      final supportDir = await getApplicationSupportDirectory();

      if (options.includeUserStats) {
        final statsDbName = 'wispie_stats.db';
        final statsDbPath = p.join(docDir.path, statsDbName);
        if (await File(statsDbPath).exists()) {
          await File(statsDbPath).copy(p.join(exportDir.path, statsDbName));
        }
      }

      if (options.includeUserData) {
        final dataDbName = 'wispie_data.db';
        final dataDbPath = p.join(docDir.path, dataDbName);
        if (await File(dataDbPath).exists()) {
          await File(dataDbPath).copy(p.join(exportDir.path, dataDbName));
        }
      }

      if (options.includeUserStats || options.includeUserData) {
        final storage = StorageService();
        final database = DatabaseService.instance;
        await database.init();

        if (options.includeUserStats) {
          final songs = await database.getAllSongs();
          final songsJson = songs.map((s) => s.toJson()).toList();
          await File(p.join(exportDir.path, 'songs.json'))
              .writeAsString(jsonEncode(songsJson));

          final funStats = await database.getFunStats();
          await File(p.join(exportDir.path, 'final_stats.json'))
              .writeAsString(jsonEncode(funStats));

          final mergedGroups = await database.getMergedSongGroups();
          final mergedGroupsJson = mergedGroups.map((groupId, groupData) {
            return MapEntry(groupId, {
              'filenames': groupData.filenames,
              'priorityFilename': groupData.priorityFilename,
            });
          });
          await File(p.join(exportDir.path, 'merged_groups.json'))
              .writeAsString(jsonEncode(mergedGroupsJson));

          final queueHistory = await database.exportQueueHistory();
          if (queueHistory.isNotEmpty) {
            await File(p.join(exportDir.path, 'queue_history.json'))
                .writeAsString(jsonEncode(queueHistory));
          }
        }

        if (options.includeUserData) {
          final userData = await storage.loadUserData();
          final shuffleState = await storage.loadShuffleState();

          if (userData != null) {
            await File(p.join(exportDir.path, 'user_data.json'))
                .writeAsString(jsonEncode(userData));
          }

          if (shuffleState != null) {
            await File(p.join(exportDir.path, 'shuffle_state.json'))
                .writeAsString(jsonEncode(shuffleState));
          }
        }

        if (options.includeUserSettings) {
          final appSettings = await storage.exportAppSettings();
          if (appSettings.isNotEmpty) {
            await File(p.join(exportDir.path, 'app_settings.json'))
                .writeAsString(jsonEncode(appSettings));
          }
        }

        final playbackState = await storage.loadPlaybackState();
        if (playbackState != null) {
          await File(p.join(exportDir.path, 'playback_state.json'))
              .writeAsString(jsonEncode(playbackState));
        }
      }

      if (options.includeCoverCache ||
          options.includeLibraryCache ||
          options.includeSearchIndex ||
          options.includeWaveformCache ||
          options.includeColorCache ||
          options.includeLyricsCache) {
        final cacheDir = Directory(p.join(supportDir.path, 'gru_cache_v3'));

        if (await cacheDir.exists()) {
          final cacheDataDir = Directory(p.join(exportDir.path, 'cache'));
          await cacheDataDir.create(recursive: true);

          await for (final entity in cacheDir.list(recursive: true)) {
            if (entity is File) {
              final filename = p.basename(entity.path);
              final parentDir = p.basename(p.dirname(entity.path));

              bool include = false;

              if (options.includeLyricsCache && parentDir == 'lyrics_cache') {
                include = true;
              }

              if (options.includeWaveformCache &&
                  filename.contains('waveform')) {
                include = true;
              }

              if (options.includeColorCache && filename.contains('color')) {
                include = true;
              }

              if (options.includeLibraryCache &&
                  filename == 'cached_songs.json') {
                include = true;
              }

              if (options.includeSearchIndex &&
                  filename.contains('_search_index.db')) {
                include = true;
              }

              if (options.includeCoverCache &&
                  (filename.endsWith('.jpg') || filename.endsWith('.png'))) {
                include = true;
              }

              if (include) {
                final relativePath =
                    p.relative(entity.path, from: cacheDir.path);
                final targetDir =
                    p.join(cacheDataDir.path, p.dirname(relativePath));
                await Directory(targetDir).create(recursive: true);
                await entity.copy(p.join(targetDir, filename));
              }
            }
          }
        }
      }

      final metadata = {
        'export_date': DateTime.now().toIso8601String(),
        'version': '1.0',
        'options': {
          'includeUserStats': options.includeUserStats,
          'includeUserData': options.includeUserData,
          'includeUserSettings': options.includeUserSettings,
          'includeCoverCache': options.includeCoverCache,
          'includeLibraryCache': options.includeLibraryCache,
          'includeSearchIndex': options.includeSearchIndex,
          'includeWaveformCache': options.includeWaveformCache,
          'includeColorCache': options.includeColorCache,
          'includeLyricsCache': options.includeLyricsCache,
        },
      };
      await File(p.join(exportDir.path, _metadataFile))
          .writeAsString(jsonEncode(metadata));

      final encoder = ZipFileEncoder();
      final zipPath = p.join(tempDir.path, 'wispie_export.zip');
      encoder.create(zipPath);
      encoder.addDirectory(exportDir);
      encoder.close();

      final bytes = await File(zipPath).readAsBytes();
      final xFile = XFile.fromData(
        bytes,
        name: p.basename(zipPath),
        mimeType: 'application/zip',
      );
      await Share.shareXFiles([xFile], text: 'Wispie Export');
    } finally {
      if (await exportDir.exists()) {
        await exportDir.delete(recursive: true);
      }
    }
  }

  Future<Map<String, dynamic>?> validateBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result == null || result.files.isEmpty) return null;

    final file = File(result.files.first.path!);
    final tempDir = await getTemporaryDirectory();
    final decodeDir = Directory(p.join(
        tempDir.path, 'import_${DateTime.now().millisecondsSinceEpoch}'));
    await decodeDir.create(recursive: true);

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          File(p.join(decodeDir.path, filename))
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        }
      }

      File? metadataFile;
      String contentPath = decodeDir.path;

      final entities = decodeDir.listSync();
      if (entities.length == 1 && entities.first is Directory) {
        contentPath = entities.first.path;
      }

      metadataFile = File(p.join(contentPath, _metadataFile));

      if (!await metadataFile.exists()) {
        throw Exception('Invalid backup: metadata.json missing');
      }

      File? foundStats;
      File? foundData;

      final statsDbName = 'wispie_stats.db';
      final dataDbName = 'wispie_data.db';

      await for (final entity in Directory(contentPath).list(recursive: true)) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name == statsDbName ||
              (name.endsWith('_stats.db') && !name.startsWith('wispie_'))) {
            foundStats = entity;
          }
          if (name == dataDbName ||
              (name.endsWith('_data.db') && !name.startsWith('wispie_'))) {
            foundData = entity;
          }
        }
      }

      if (foundStats == null || foundData == null) {
        throw Exception('Invalid backup: Database files missing');
      }

      bool hasSongsJson = false;
      bool hasUserDataJson = false;
      bool hasShuffleStateJson = false;
      bool hasPlaybackStateJson = false;
      bool hasMergedGroupsJson = false;
      bool hasQueueHistoryJson = false;
      bool hasAppSettingsJson = false;

      await for (final entity in Directory(contentPath).list(recursive: true)) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name == 'songs.json') {
            hasSongsJson = true;
          }
          if (name == 'user_data.json' || name.startsWith('user_data_')) {
            hasUserDataJson = true;
          }
          if (name == 'shuffle_state.json' ||
              name.startsWith('shuffle_state_')) {
            hasShuffleStateJson = true;
          }
          if (name == 'playback_state.json' ||
              name.startsWith('playback_state_')) {
            hasPlaybackStateJson = true;
          }
          if (name == 'merged_groups.json') {
            hasMergedGroupsJson = true;
          }
          if (name == 'queue_history.json') {
            hasQueueHistoryJson = true;
          }
          if (name == 'app_settings.json') {
            hasAppSettingsJson = true;
          }
        }
      }

      return {
        'valid': true,
        'importPath': contentPath,
        'statsDbPath': foundStats.path,
        'dataDbPath': foundData.path,
        'hasSongsJson': hasSongsJson,
        'hasUserDataJson': hasUserDataJson,
        'hasShuffleStateJson': hasShuffleStateJson,
        'hasPlaybackStateJson': hasPlaybackStateJson,
        'hasMergedGroupsJson': hasMergedGroupsJson,
        'hasQueueHistoryJson': hasQueueHistoryJson,
        'hasAppSettingsJson': hasAppSettingsJson,
      };
    } catch (e) {
      if (await decodeDir.exists()) await decodeDir.delete(recursive: true);
      rethrow;
    }
  }

  Set<ImportDataCategory> getAvailableCategories(
      Map<String, dynamic> validation) {
    final categories = <ImportDataCategory>{};

    if (validation['hasSongsJson'] == true) {
      categories.add(ImportDataCategory.songs);
    }
    if (validation['hasShuffleStateJson'] == true) {
      categories.add(ImportDataCategory.shuffleState);
    }
    if (validation['hasPlaybackStateJson'] == true) {
      categories.add(ImportDataCategory.playbackState);
    }
    if (validation['hasQueueHistoryJson'] == true) {
      categories.add(ImportDataCategory.queueHistory);
    }
    if (validation['hasAppSettingsJson'] == true) {
      categories.add(ImportDataCategory.themeSettings);
      categories.add(ImportDataCategory.scannerSettings);
      categories.add(ImportDataCategory.playbackSettings);
      categories.add(ImportDataCategory.uiSettings);
      categories.add(ImportDataCategory.backupSettings);
    }
    if (validation['hasMergedGroupsJson'] == true) {
      categories.add(ImportDataCategory.mergedGroups);
    }

    categories.add(ImportDataCategory.favorites);
    categories.add(ImportDataCategory.suggestless);
    categories.add(ImportDataCategory.hidden);
    categories.add(ImportDataCategory.playlists);
    categories.add(ImportDataCategory.recommendations);
    categories.add(ImportDataCategory.moods);
    categories.add(ImportDataCategory.userdata);
    categories.add(ImportDataCategory.playHistory);

    return categories;
  }

  Future<void> performImport({
    required String statsDbPath,
    required String dataDbPath,
    required ImportOptions options,
  }) async {
    final importPath = p.dirname(statsDbPath);
    final categories = options.categories;
    final storage = StorageService();

    if (categories.contains(ImportDataCategory.playHistory) ||
        categories.contains(ImportDataCategory.favorites) ||
        categories.contains(ImportDataCategory.suggestless) ||
        categories.contains(ImportDataCategory.hidden) ||
        categories.contains(ImportDataCategory.playlists) ||
        categories.contains(ImportDataCategory.mergedGroups) ||
        categories.contains(ImportDataCategory.recommendations) ||
        categories.contains(ImportDataCategory.moods) ||
        categories.contains(ImportDataCategory.userdata)) {
      await DatabaseService.instance.importWithOptions(
        statsDbPath: statsDbPath,
        dataDbPath: dataDbPath,
        options: options,
      );
    }

    if (categories.contains(ImportDataCategory.shuffleState)) {
      final shuffleStateFile = File(p.join(importPath, 'shuffle_state.json'));
      if (await shuffleStateFile.exists()) {
        final content = await shuffleStateFile.readAsString();
        final data = jsonDecode(content);
        await storage.saveShuffleState(data);
      }
    }

    if (options.restorePlaybackState &&
        categories.contains(ImportDataCategory.playbackState)) {
      final playbackStateFile = File(p.join(importPath, 'playback_state.json'));
      if (await playbackStateFile.exists()) {
        final content = await playbackStateFile.readAsString();
        final data = jsonDecode(content);
        await storage.savePlaybackState(data);
      }
    }

    if (categories.contains(ImportDataCategory.themeSettings) ||
        categories.contains(ImportDataCategory.scannerSettings) ||
        categories.contains(ImportDataCategory.playbackSettings) ||
        categories.contains(ImportDataCategory.uiSettings) ||
        categories.contains(ImportDataCategory.backupSettings)) {
      final appSettingsFile = File(p.join(importPath, 'app_settings.json'));
      if (await appSettingsFile.exists()) {
        final content = await appSettingsFile.readAsString();
        final data = jsonDecode(content);
        if (data is Map) {
          await storage.importSettingsWithOptions(
            Map<String, dynamic>.from(data),
            options,
          );
        }
      }
    }

    if (categories.contains(ImportDataCategory.queueHistory)) {
      final queueHistoryFile = File(p.join(importPath, 'queue_history.json'));
      if (await queueHistoryFile.exists()) {
        final content = await queueHistoryFile.readAsString();
        final data = jsonDecode(content);
        if (data is List) {
          final queueHistoryData = data.cast<Map<String, dynamic>>();
          await DatabaseService.instance.importQueueHistory(queueHistoryData);
        }
      }
    }

    final importDir = Directory(p.dirname(statsDbPath));
    Directory? toDelete = importDir;
    while (toDelete != null && !p.basename(toDelete.path).contains('import_')) {
      if (toDelete.path == toDelete.parent.path) break;
      toDelete = toDelete.parent;
    }

    if (toDelete != null && p.basename(toDelete.path).contains('import_')) {
      await toDelete.delete(recursive: true);
    }
  }
}
