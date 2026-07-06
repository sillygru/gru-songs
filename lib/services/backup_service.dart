import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'storage_service.dart';
import 'database_service.dart';
import 'import_options.dart';
import '../models/song.dart';
import '../data/repositories/search_index_repository.dart';

enum BackupContentType {
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

class BackupOptions {
  final Set<BackupContentType> contentTypes;

  BackupOptions({Set<BackupContentType>? contentTypes})
      : contentTypes = contentTypes ??
            {
              BackupContentType.userStats,
              BackupContentType.userData,
            };

  bool get includeUserStats =>
      contentTypes.contains(BackupContentType.userStats);
  bool get includeUserData => contentTypes.contains(BackupContentType.userData);
  bool get includeUserSettings =>
      contentTypes.contains(BackupContentType.userSettings);
  bool get includeCoverCache =>
      contentTypes.contains(BackupContentType.coverCache);
  bool get includeLibraryCache =>
      contentTypes.contains(BackupContentType.libraryCache);
  bool get includeSearchIndex =>
      contentTypes.contains(BackupContentType.searchIndex);
  bool get includeWaveformCache =>
      contentTypes.contains(BackupContentType.waveformCache);
  bool get includeColorCache =>
      contentTypes.contains(BackupContentType.colorCache);
  bool get includeLyricsCache =>
      contentTypes.contains(BackupContentType.lyricsCache);
}

class BackupDiff {
  final int songCountDiff;
  final int statsRowsDiff;
  final int sizeBytesDiff;

  BackupDiff({
    required this.songCountDiff,
    required this.statsRowsDiff,
    required this.sizeBytesDiff,
  });
}

class BackupInfo {
  final int number;
  final DateTime timestamp;
  final String filename;
  final File file;
  final int sizeBytes;

  BackupInfo({
    required this.number,
    required this.timestamp,
    required this.filename,
    required this.file,
    required this.sizeBytes,
  });

  String get formattedSize {
    if (sizeBytes < 1024) {
      return '${sizeBytes}B';
    }
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  String get displayName {
    return _formatDateTime(timestamp);
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final month = months[dt.month - 1];
    final day = dt.day;
    final year = dt.year;
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';

    return '$month $day, $year at $hour:$minute $amPm';
  }
}

class BackupService {
  static const String _backupsDirName = 'backups';
  static const String _metadataFile = 'metadata.json';
  static BackupService? _instance;
  static BackupService get instance => _instance ??= BackupService._();
  BackupService._();

  Future<Directory> get _backupsDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final backupsDir = Directory(p.join(appDir.path, _backupsDirName));
    if (!await backupsDir.exists()) {
      await backupsDir.create(recursive: true);
    }
    return backupsDir;
  }

  Future<List<BackupInfo>> getBackupsList() async {
    try {
      final backupsDir = await _backupsDir;
      final files = await backupsDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.zip'))
          .cast<File>()
          .toList();

      final backups = <BackupInfo>[];
      for (final file in files) {
        final filename = p.basename(file.path);
        final backupInfo = _parseBackupFilename(filename);
        if (backupInfo != null) {
          final stat = await file.stat();
          final number = backupInfo.keys.first;
          final timestamp = backupInfo.values.first;
          backups.add(BackupInfo(
            number: number,
            timestamp: timestamp,
            filename: filename,
            file: file,
            sizeBytes: stat.size,
          ));
        }
      }

      backups.sort((a, b) => b.number.compareTo(a.number));
      return backups;
    } catch (e) {
      debugPrint('Error getting backups list: $e');
      return [];
    }
  }

  Map<int, DateTime>? _parseBackupFilename(String filename) {
    final regex =
        RegExp(r'^(\d+)_(\d{4})_(\d{2})_(\d{2})_(\d{2})-(\d{2})\.zip$');
    final match = regex.firstMatch(filename);

    if (match == null) return null;

    try {
      final number = int.parse(match.group(1)!);
      final year = int.parse(match.group(2)!);
      final month = int.parse(match.group(3)!);
      final day = int.parse(match.group(4)!);
      final hour = int.parse(match.group(5)!);
      final minute = int.parse(match.group(6)!);

      final timestamp = DateTime(year, month, day, hour, minute);
      return {number: timestamp};
    } catch (e) {
      debugPrint('Error parsing backup filename $filename: $e');
      return null;
    }
  }

  Future<int> _getNextBackupNumber() async {
    final backups = await getBackupsList();
    if (backups.isEmpty) return 1;
    return backups.first.number + 1;
  }

  Future<String> createBackup([BackupOptions? options]) async {
    options ??= BackupOptions();

    try {
      final backupsDir = await _backupsDir;
      final backupNumber = await _getNextBackupNumber();
      final now = DateTime.now();

      final backupFilename =
          '${backupNumber.toString().padLeft(3, '0')}_${now.year.toString().padLeft(4, '0')}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}.zip';
      final backupPath = p.join(backupsDir.path, backupFilename);

      final tempDir = await Directory.systemTemp.createTemp('gru_backup_');
      final dataDir = Directory(p.join(tempDir.path, 'data'));
      await dataDir.create(recursive: true);

      try {
        final appDir = await getApplicationDocumentsDirectory();

        if (options.includeUserStats) {
          final statsDb = File(p.join(appDir.path, 'wispie_stats.db'));
          if (await statsDb.exists()) {
            await statsDb.copy(p.join(dataDir.path, 'wispie_stats.db'));
          }
        }

        if (options.includeUserData) {
          final dataDb = File(p.join(appDir.path, 'wispie_data.db'));
          if (await dataDb.exists()) {
            await dataDb.copy(p.join(dataDir.path, 'wispie_data.db'));
          }
        }

        if (options.includeUserData || options.includeUserStats) {
          final storage = StorageService();
          final database = DatabaseService.instance;
          await database.init();

          if (options.includeUserStats) {
            final songs = await database.getAllSongs();
            final songsJson = songs.map((s) => s.toJson()).toList();
            await File(p.join(dataDir.path, 'songs.json'))
                .writeAsString(encodeJson(songsJson));

            final funStats = await database.getFunStats();
            await File(p.join(dataDir.path, 'final_stats.json'))
                .writeAsString(encodeJson(funStats));

            final mergedGroups = await database.getMergedSongGroups();
            final mergedGroupsJson = mergedGroups.map((groupId, groupData) {
              return MapEntry(groupId, {
                'filenames': groupData.filenames,
                'priorityFilename': groupData.priorityFilename,
              });
            });
            await File(p.join(dataDir.path, 'merged_groups.json'))
                .writeAsString(encodeJson(mergedGroupsJson));

            final queueHistory = await database.exportQueueHistory();
            if (queueHistory.isNotEmpty) {
              await File(p.join(dataDir.path, 'queue_history.json'))
                  .writeAsString(encodeJson(queueHistory));
            }
          }

          if (options.includeUserData) {
            final userData = await storage.loadUserData();
            final shuffleState = await storage.loadShuffleState();

            if (userData != null) {
              await File(p.join(dataDir.path, 'user_data.json'))
                  .writeAsString(encodeJson(userData));
            }

            if (shuffleState != null) {
              await File(p.join(dataDir.path, 'shuffle_state.json'))
                  .writeAsString(encodeJson(shuffleState));
            }
          }

          if (options.includeUserSettings) {
            final appSettings = await storage.exportAppSettings();
            if (appSettings.isNotEmpty) {
              await File(p.join(dataDir.path, 'app_settings.json'))
                  .writeAsString(encodeJson(appSettings));
            }
          }

          if (options.includeUserData || options.includeUserStats) {
            final playbackState = await storage.loadPlaybackState();
            if (playbackState != null) {
              await File(p.join(dataDir.path, 'playback_state.json'))
                  .writeAsString(encodeJson(playbackState));
            }
          }
        }

        if (options.includeCoverCache ||
            options.includeLibraryCache ||
            options.includeSearchIndex ||
            options.includeWaveformCache ||
            options.includeColorCache ||
            options.includeLyricsCache) {
          final supportDir = await getApplicationSupportDirectory();
          final cacheDir = Directory(p.join(supportDir.path, 'gru_cache_v3'));

          if (await cacheDir.exists()) {
            final cacheDataDir = Directory(p.join(dataDir.path, 'cache'));
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
        await File(p.join(dataDir.path, _metadataFile))
            .writeAsString(jsonEncode(metadata));

        final zipFile = File(backupPath);
        final archive = Archive();

        await for (final entity in dataDir.list(recursive: true)) {
          if (entity is File) {
            final relativePath = p.relative(entity.path, from: dataDir.path);
            final bytes = await entity.readAsBytes();
            final file = ArchiveFile(relativePath, bytes.length, bytes);
            archive.addFile(file);
          }
        }

        final zipBytes = ZipEncoder().encode(archive);
        if (zipBytes != null) {
          await zipFile.writeAsBytes(zipBytes);
        }

        return backupFilename;
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('Error creating backup: $e');
      rethrow;
    }
  }

  Future<void> exportUserData({BackupOptions? options}) async {
    options ??= BackupOptions();

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

  Future<bool> _checkTableExists(String dbPath, String tableName) async {
    try {
      final db = await openDatabase(dbPath, readOnly: true);
      final result = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='$tableName'");
      await db.close();
      return result.isNotEmpty;
    } catch (e) {
      return false;
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
        final reconstructed = <String, dynamic>{
          'export_date': DateTime.now().toIso8601String(),
          'version': '1.0',
          'options': {
            'includeUserStats':
                await File(p.join(contentPath, 'wispie_stats.db')).exists(),
            'includeUserData':
                await File(p.join(contentPath, 'wispie_data.db')).exists(),
            'includeUserSettings':
                await File(p.join(contentPath, 'app_settings.json')).exists(),
            'includeCoverCache': false,
            'includeLibraryCache': false,
            'includeSearchIndex': false,
            'includeWaveformCache': false,
            'includeColorCache': false,
            'includeLyricsCache': false,
          },
        };

        final cacheDir = Directory(p.join(contentPath, 'cache'));
        if (await cacheDir.exists()) {
          await for (final entity in cacheDir.list(recursive: true)) {
            if (entity is File) {
              final name = p.basename(entity.path);
              final parentDir = p.basename(p.dirname(entity.path));
              if (name.endsWith('.jpg') || name.endsWith('.png')) {
                reconstructed['options']['includeCoverCache'] = true;
              }
              if (name == 'cached_songs.json') {
                reconstructed['options']['includeLibraryCache'] = true;
              }
              if (name.contains('_search_index.db')) {
                reconstructed['options']['includeSearchIndex'] = true;
              }
              if (name.contains('waveform')) {
                reconstructed['options']['includeWaveformCache'] = true;
              }
              if (name.contains('color')) {
                reconstructed['options']['includeColorCache'] = true;
              }
              if (parentDir == 'lyrics_cache') {
                reconstructed['options']['includeLyricsCache'] = true;
              }
            }
          }
        }

        await metadataFile.writeAsString(jsonEncode(reconstructed));
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

      final hasFavorites = await _checkTableExists(foundData.path, 'favorite');
      final hasSuggestless =
          await _checkTableExists(foundData.path, 'suggestless');
      final hasHidden = await _checkTableExists(foundData.path, 'hidden');
      final hasPlaylists = await _checkTableExists(foundData.path, 'playlist');
      final hasMergedGroups =
          await _checkTableExists(foundData.path, 'merged_song_group');
      final hasRecommendations =
          await _checkTableExists(foundData.path, 'recommendation_preference');
      final hasMoods = await _checkTableExists(foundData.path, 'mood_tag');
      final hasUserdata = await _checkTableExists(foundData.path, 'userdata');
      final hasPlayHistory =
          await _checkTableExists(foundStats.path, 'playsession');

      final dbHasUserData = hasFavorites ||
          hasSuggestless ||
          hasHidden ||
          hasPlaylists ||
          hasMergedGroups ||
          hasRecommendations ||
          hasMoods ||
          hasUserdata;
      final metadataContent = await metadataFile.readAsString();
      final metadata = jsonDecode(metadataContent) as Map<String, dynamic>;
      final options = metadata['options'] as Map<String, dynamic>;

      final actualUserStats = hasPlayHistory;
      final actualUserData = dbHasUserData;
      final actualUserSettings = hasAppSettingsJson;

      if (options['includeUserStats'] != actualUserStats ||
          options['includeUserData'] != actualUserData ||
          options['includeUserSettings'] != actualUserSettings) {
        options['includeUserStats'] = actualUserStats;
        options['includeUserData'] = actualUserData;
        options['includeUserSettings'] = actualUserSettings;
        metadata['options'] = options;
        await metadataFile.writeAsString(jsonEncode(metadata));
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
        'hasFavorites': hasFavorites,
        'hasSuggestless': hasSuggestless,
        'hasHidden': hasHidden,
        'hasPlaylists': hasPlaylists,
        'hasMergedGroups': hasMergedGroups,
        'hasRecommendations': hasRecommendations,
        'hasMoods': hasMoods,
        'hasUserdata': hasUserdata,
        'hasPlayHistory': hasPlayHistory,
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
    if (validation['hasMergedGroupsJson'] == true ||
        validation['hasMergedGroups'] == true) {
      categories.add(ImportDataCategory.mergedGroups);
    }

    if (validation['hasFavorites'] == true) {
      categories.add(ImportDataCategory.favorites);
    }
    if (validation['hasSuggestless'] == true) {
      categories.add(ImportDataCategory.suggestless);
    }
    if (validation['hasHidden'] == true) {
      categories.add(ImportDataCategory.hidden);
    }
    if (validation['hasPlaylists'] == true) {
      categories.add(ImportDataCategory.playlists);
    }
    if (validation['hasRecommendations'] == true) {
      categories.add(ImportDataCategory.recommendations);
    }
    if (validation['hasMoods'] == true) {
      categories.add(ImportDataCategory.moods);
    }
    if (validation['hasUserdata'] == true) {
      categories.add(ImportDataCategory.userdata);
    }
    if (validation['hasPlayHistory'] == true) {
      categories.add(ImportDataCategory.playHistory);
    }

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

    if (categories.contains(ImportDataCategory.playbackState)) {
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

  Future<void> restoreFromBackup(BackupInfo backupInfo,
      {ImportOptions? options}) async {
    final importOptions = options ?? ImportOptions.defaultImport;
    final categories = importOptions.categories;
    final restoreDatabases = importOptions.restoreDatabases;

    try {
      final backupFile = backupInfo.file;

      final tempDir = await Directory.systemTemp.createTemp('gru_restore_');

      try {
        final bytes = await backupFile.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);

        for (final file in archive) {
          if (file.isFile) {
            final filePath = p.join(tempDir.path, file.name);
            final fileDir = Directory(p.dirname(filePath));
            if (!await fileDir.exists()) {
              await fileDir.create(recursive: true);
            }
            final outputFile = File(filePath);
            await outputFile.writeAsBytes(file.content as List<int>);
          }
        }

        final appDir = await getApplicationDocumentsDirectory();
        final storage = StorageService();

        File? foundStatsDb;
        File? foundDataDb;

        await for (final entity in tempDir.list(recursive: true)) {
          if (entity is File) {
            final name = p.basename(entity.path);
            if (name == 'wispie_stats.db' ||
                (name.endsWith('_stats.db') && !name.startsWith('wispie_'))) {
              foundStatsDb = entity;
            }
            if (name == 'wispie_data.db' ||
                (name.endsWith('_data.db') && !name.startsWith('wispie_'))) {
              foundDataDb = entity;
            }
          }
        }

        String statsDbPath;
        String dataDbPath;

        if (restoreDatabases) {
          await DatabaseService.instance.close();
          final dbSuffixes = ['', '-journal', '-wal', '-shm'];
          for (final suffix in dbSuffixes) {
            final statsFile =
                File(p.join(appDir.path, 'wispie_stats.db$suffix'));
            final dataFile = File(p.join(appDir.path, 'wispie_data.db$suffix'));
            if (await statsFile.exists()) {
              await statsFile.delete();
            }
            if (await dataFile.exists()) {
              await dataFile.delete();
            }
          }

          if (foundStatsDb != null) {
            await foundStatsDb.copy(p.join(appDir.path, 'wispie_stats.db'));
          }
          if (foundDataDb != null) {
            await foundDataDb.copy(p.join(appDir.path, 'wispie_data.db'));
          }

          await DatabaseService.instance.init();
          statsDbPath = p.join(appDir.path, 'wispie_stats.db');
          dataDbPath = p.join(appDir.path, 'wispie_data.db');
        } else {
          if (foundStatsDb == null || foundDataDb == null) {
            debugPrint(
                'Warning: Backup DB files not found, skipping database imports');
            return;
          }
          statsDbPath = foundStatsDb.path;
          dataDbPath = foundDataDb.path;
        }

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
            options: importOptions,
          );
        }

        await for (final entity in tempDir.list(recursive: true)) {
          if (entity is File) {
            final name = p.basename(entity.path);

            if (name == 'songs.json' &&
                categories.contains(ImportDataCategory.songs)) {
              final content = await entity.readAsString();
              final data = decodeJson(content);
              final songs =
                  (data as List).map((json) => Song.fromJson(json)).toList();
              await DatabaseService.instance.insertSongsBatch(songs);
            }

            if ((name == 'shuffle_state.json' ||
                    name.startsWith('shuffle_state_')) &&
                categories.contains(ImportDataCategory.shuffleState)) {
              final content = await entity.readAsString();
              final data = decodeJson(content);
              await storage.saveShuffleState(data);
            }

            if ((name == 'playback_state.json' ||
                    name.startsWith('playback_state_')) &&
                categories.contains(ImportDataCategory.playbackState)) {
              final content = await entity.readAsString();
              final data = decodeJson(content);
              await storage.savePlaybackState(data);
            }

            if (name == 'queue_history.json' &&
                categories.contains(ImportDataCategory.queueHistory)) {
              final content = await entity.readAsString();
              final data = decodeJson(content);
              if (data is List) {
                final queueHistoryData = data.cast<Map<String, dynamic>>();
                await DatabaseService.instance
                    .importQueueHistory(queueHistoryData);
              }
            }

            if (name == 'app_settings.json' &&
                (categories.contains(ImportDataCategory.themeSettings) ||
                    categories.contains(ImportDataCategory.scannerSettings) ||
                    categories.contains(ImportDataCategory.playbackSettings) ||
                    categories.contains(ImportDataCategory.uiSettings) ||
                    categories.contains(ImportDataCategory.backupSettings))) {
              final content = await entity.readAsString();
              final data = decodeJson(content);
              if (data is Map) {
                await storage.importSettingsWithOptions(
                  Map<String, dynamic>.from(data),
                  importOptions,
                );
              }
            }
          }
        }

        if (categories.isNotEmpty) {
          try {
            final searchIndexRepo = SearchIndexRepository();
            await searchIndexRepo.deleteDatabaseFile();
          } catch (e) {
            debugPrint('Note: Could not delete search index: $e');
          }
        }
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('Error restoring from backup: $e');
      rethrow;
    }
  }

  Future<void> deleteBackup(BackupInfo backupInfo) async {
    try {
      if (await backupInfo.file.exists()) {
        await backupInfo.file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting backup: $e');
      rethrow;
    }
  }

  Future<BackupDiff> compareBackups(
      BackupInfo oldBackup, BackupInfo newBackup) async {
    final tempDir = await Directory.systemTemp.createTemp('gru_compare_');
    try {
      Future<({int songCount, int statsRows})> getBackupStats(
          BackupInfo info) async {
        final bytes = await info.file.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);

        int songCount = 0;
        int statsRows = 0;

        ArchiveFile? songsFile;
        ArchiveFile? statsFile;

        for (final file in archive) {
          final name = p.basename(file.name);
          if (name == 'songs.json') {
            songsFile = file;
          }
          if (name == 'wispie_stats.db' ||
              (name.endsWith('_stats.db') && !name.startsWith('wispie_'))) {
            statsFile = file;
          }
        }

        if (songsFile != null) {
          final content = utf8.decode(songsFile.content as List<int>);
          final List data = jsonDecode(content);
          songCount = data.length;
        }

        if (statsFile != null) {
          final dbPath = p.join(tempDir.path, '${info.filename}_stats.db');
          await File(dbPath).writeAsBytes(statsFile.content as List<int>);

          try {
            final db = await openDatabase(dbPath, readOnly: true);
            try {
              final tables = await db.rawQuery(
                  "SELECT name FROM sqlite_master WHERE type='table' AND name='playevent'");
              if (tables.isNotEmpty) {
                final result = await db
                    .rawQuery('SELECT COUNT(*) as count FROM playevent');
                statsRows = Sqflite.firstIntValue(result) ?? 0;
              }
            } finally {
              await db.close();
            }
          } catch (e) {
            debugPrint(
                'Error reading stats db from backup ${info.filename}: $e');
          }
        }

        return (songCount: songCount, statsRows: statsRows);
      }

      final oldStats = await getBackupStats(oldBackup);
      final newStats = await getBackupStats(newBackup);

      return BackupDiff(
        songCountDiff: newStats.songCount - oldStats.songCount,
        statsRowsDiff: newStats.statsRows - oldStats.statsRows,
        sizeBytesDiff: newBackup.sizeBytes - oldBackup.sizeBytes,
      );
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<void> exportBackup(BackupInfo backupInfo, String exportPath) async {
    try {
      if (await backupInfo.file.exists()) {
        await backupInfo.file.copy(exportPath);
      }
    } catch (e) {
      debugPrint('Error exporting backup: $e');
      rethrow;
    }
  }

  String encodeJson(dynamic data) {
    return jsonEncode(data);
  }

  dynamic decodeJson(String jsonString) {
    return jsonDecode(jsonString);
  }
}
