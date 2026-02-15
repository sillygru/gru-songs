import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'storage_service.dart';
import 'database_service.dart';
import '../models/song.dart';
import '../data/repositories/search_index_repository.dart';

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
    return 'Backup #$number - ${_formatDateTime(timestamp)}';
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}_${dt.month.toString().padLeft(2, '0')}_${dt.day.toString().padLeft(2, '0')}_${dt.hour.toString().padLeft(2, '0')}-${dt.minute.toString().padLeft(2, '0')}';
  }
}

class BackupService {
  static const String _backupsDirName = 'backups';
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

      // Sort by number (descending) so newest backups come first
      backups.sort((a, b) => b.number.compareTo(a.number));
      return backups;
    } catch (e) {
      debugPrint('Error getting backups list: $e');
      return [];
    }
  }

  Map<int, DateTime>? _parseBackupFilename(String filename) {
    // Expected format: [number]_[year]_[month]_[day]_[hour]-[minute].zip
    // Example: 05_2026_01_27_17-58.zip
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

  Future<String> createBackup() async {
    try {
      final backupsDir = await _backupsDir;
      final backupNumber = await _getNextBackupNumber();
      final now = DateTime.now();

      // Format: 05_2026_01_27_17-58.zip
      final backupFilename =
          '${backupNumber.toString().padLeft(3, '0')}_${now.year.toString().padLeft(4, '0')}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}.zip';
      final backupPath = p.join(backupsDir.path, backupFilename);

      // Create a temporary directory for gathering files
      final tempDir = await Directory.systemTemp.createTemp('gru_backup_');
      final dataDir = Directory(p.join(tempDir.path, 'data'));
      await dataDir.create(recursive: true);

      try {
        // Copy database files
        final appDir = await getApplicationDocumentsDirectory();
        final statsDb = File(p.join(appDir.path, 'wispie_stats.db'));
        final dataDb = File(p.join(appDir.path, 'wispie_data.db'));

        if (await statsDb.exists()) {
          await statsDb.copy(p.join(dataDir.path, 'wispie_stats.db'));
        }
        if (await dataDb.exists()) {
          await dataDb.copy(p.join(dataDir.path, 'wispie_data.db'));
        }

        // Export user data to JSON
        final storage = StorageService();
        final database = DatabaseService.instance;
        // Ensure initialized
        await database.init();

        final songs = await database.getAllSongs();
        final userData = await storage.loadUserData();
        final shuffleState = await storage.loadShuffleState();
        final playbackState = await storage.loadPlaybackState();

        // Create final stats JSON
        final funStats = await database.getFunStats();

        // Get merged song groups
        final mergedGroups = await database.getMergedSongGroups();

        // Save JSON files
        final songsJson = songs.map((s) => s.toJson()).toList();
        await File(p.join(dataDir.path, 'songs.json'))
            .writeAsString(encodeJson(songsJson));

        if (userData != null) {
          await File(p.join(dataDir.path, 'user_data.json'))
              .writeAsString(encodeJson(userData));
        }

        if (shuffleState != null) {
          await File(p.join(dataDir.path, 'shuffle_state.json'))
              .writeAsString(encodeJson(shuffleState));
        }

        if (playbackState != null) {
          await File(p.join(dataDir.path, 'playback_state.json'))
              .writeAsString(encodeJson(playbackState));
        }

        // Save merged song groups
        final mergedGroupsJson = mergedGroups.map((groupId, groupData) {
          return MapEntry(groupId, {
            'filenames': groupData.filenames,
            'priorityFilename': groupData.priorityFilename,
          });
        });
        await File(p.join(dataDir.path, 'merged_groups.json'))
            .writeAsString(encodeJson(mergedGroupsJson));

        await File(p.join(dataDir.path, 'final_stats.json'))
            .writeAsString(encodeJson(funStats));

        // Create ZIP file
        final zipFile = File(backupPath);
        final archive = Archive();

        await for (final entity in dataDir.list(recursive: true)) {
          if (entity is File) {
            // Skip search index database files
            final filename = p.basename(entity.path);
            if (filename.contains('_search_index.db')) {
              continue;
            }

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
        // Clean up temp directory
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('Error creating backup: $e');
      rethrow;
    }
  }

  Future<void> restoreFromBackup(BackupInfo backupInfo) async {
    try {
      final backupFile = backupInfo.file;

      // Create temp directory for extraction
      final tempDir = await Directory.systemTemp.createTemp('gru_restore_');

      try {
        // Extract ZIP
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

        // Close and delete existing databases
        await DatabaseService.instance.close();
        final dbSuffixes = ['', '-journal', '-wal', '-shm'];
        for (final suffix in dbSuffixes) {
          final statsFile = File(p.join(appDir.path, 'wispie_stats.db$suffix'));
          final dataFile = File(p.join(appDir.path, 'wispie_data.db$suffix'));
          if (await statsFile.exists()) {
            await statsFile.delete();
          }
          if (await dataFile.exists()) {
            await dataFile.delete();
          }
        }

        // Restore databases - look for wispie_* or any legacy *_stats.db
        // We'll search recursively in tempDir
        File? foundStatsDb;
        File? foundDataDb;
        File? foundSongsJson;
        File? foundUserDataJson;
        File? foundShuffleStateJson;
        File? foundPlaybackStateJson;
        File? foundMergedGroupsJson;

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
            if (name == 'songs.json') {
              foundSongsJson = entity;
            }
            if (name == 'user_data.json' || name.startsWith('user_data_')) {
              foundUserDataJson = entity;
            }
            if (name == 'shuffle_state.json' ||
                name.startsWith('shuffle_state_')) {
              foundShuffleStateJson = entity;
            }
            if (name == 'playback_state.json' ||
                name.startsWith('playback_state_')) {
              foundPlaybackStateJson = entity;
            }
            if (name == 'merged_groups.json') {
              foundMergedGroupsJson = entity;
            }
          }
        }

        if (foundStatsDb != null) {
          await foundStatsDb.copy(p.join(appDir.path, 'wispie_stats.db'));
        }
        if (foundDataDb != null) {
          await foundDataDb.copy(p.join(appDir.path, 'wispie_data.db'));
        }

        // 4. Re-init database
        await DatabaseService.instance.init();

        final storage = StorageService();

        // Restore songs
        if (foundSongsJson != null) {
          final content = await foundSongsJson.readAsString();
          final data = decodeJson(content);
          final songs =
              (data as List).map((json) => Song.fromJson(json)).toList();
          await DatabaseService.instance.insertSongsBatch(songs);
        }

        // Restore user data
        if (foundUserDataJson != null) {
          final content = await foundUserDataJson.readAsString();
          final data = decodeJson(content);
          await storage.saveUserData(data);
        }

        // Restore shuffle state
        if (foundShuffleStateJson != null) {
          final content = await foundShuffleStateJson.readAsString();
          final data = decodeJson(content);
          await storage.saveShuffleState(data);
        }

        // Restore playback state
        if (foundPlaybackStateJson != null) {
          final content = await foundPlaybackStateJson.readAsString();
          final data = decodeJson(content);
          await storage.savePlaybackState(data);
        }

        // Restore merged song groups
        if (foundMergedGroupsJson != null) {
          final content = await foundMergedGroupsJson.readAsString();
          final data = decodeJson(content);
          final groups =
              <String, ({List<String> filenames, String? priorityFilename})>{};
          if (data is Map) {
            for (final entry in data.entries) {
              final key = entry.key as String;
              final value = entry.value;
              if (value is Map) {
                final filenames =
                    (value['filenames'] as List?)?.cast<String>() ?? [];
                final priority = value['priorityFilename'] as String?;
                groups[key] =
                    (filenames: filenames, priorityFilename: priority);
              } else if (value is List) {
                groups[key] =
                    (filenames: value.cast<String>(), priorityFilename: null);
              }
            }
          }
          await DatabaseService.instance.setMergedGroups(groups);
        }

        // Delete any existing search index
        try {
          final searchIndexRepo = SearchIndexRepository();
          await searchIndexRepo.deleteDatabaseFile();
        } catch (e) {
          debugPrint('Note: Could not delete search index: $e');
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
      // Helper to get stats from a backup
      Future<({int songCount, int statsRows})> getBackupStats(
          BackupInfo info) async {
        final bytes = await info.file.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);

        int songCount = 0;
        int statsRows = 0;

        // Find and extract songs.json
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
              // Check if table exists first
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
