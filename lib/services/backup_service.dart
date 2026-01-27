import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'storage_service.dart';
import 'database_service.dart';
import '../models/song.dart';

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

  Future<String> createBackup(String username) async {
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
      final usernameDataDir =
          Directory(p.join(tempDir.path, '${username}_data'));
      await usernameDataDir.create(recursive: true);

      try {
        // Copy database files
        final appDir = await getApplicationDocumentsDirectory();
        final statsDb = File(p.join(appDir.path, '${username}_stats.db'));
        final dataDb = File(p.join(appDir.path, '${username}_data.db'));

        if (await statsDb.exists()) {
          await statsDb
              .copy(p.join(usernameDataDir.path, '${username}_stats.db'));
        }
        if (await dataDb.exists()) {
          await dataDb
              .copy(p.join(usernameDataDir.path, '${username}_data.db'));
        }

        // Export user data to JSON
        final storage = StorageService();
        final songs = await storage.loadSongs(username);
        final userData = await storage.loadUserData(username);
        final shuffleState = await storage.loadShuffleState(username);
        final playbackState = await storage.loadPlaybackState(username);

        // Create final stats JSON
        final database = DatabaseService.instance;
        await database.initForUser(username);
        final funStats = await database.getFunStats();

        // Save JSON files
        final songsJson = songs.map((s) => s.toJson()).toList();
        await File(p.join(usernameDataDir.path, 'songs.json'))
            .writeAsString(encodeJson(songsJson));

        if (userData != null) {
          await File(p.join(usernameDataDir.path, 'user_data.json'))
              .writeAsString(encodeJson(userData));
        }

        if (shuffleState != null) {
          await File(p.join(usernameDataDir.path, 'shuffle_state.json'))
              .writeAsString(encodeJson(shuffleState));
        }

        if (playbackState != null) {
          await File(p.join(usernameDataDir.path, 'playback_state.json'))
              .writeAsString(encodeJson(playbackState));
        }

        await File(p.join(usernameDataDir.path, '${username}_final_stats.json'))
            .writeAsString(encodeJson(funStats));

        // Create ZIP file
        final zipFile = File(backupPath);
        final archive = Archive();

        // Add all files from the temp directory to the archive
        await for (final entity in usernameDataDir.list(recursive: true)) {
          if (entity is File) {
            final relativePath =
                p.relative(entity.path, from: usernameDataDir.path);
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

  Future<void> restoreFromBackup(String username, BackupInfo backupInfo) async {
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

        // Restore databases - check both direct and in subdirectory
        final statsDbFile = File(p.join(tempDir.path, '${username}_stats.db'));
        final statsDbFileInDir = File(
            p.join(tempDir.path, '${username}_data', '${username}_stats.db'));
        final dataDbFile = File(p.join(tempDir.path, '${username}_data.db'));
        final dataDbFileInDir = File(
            p.join(tempDir.path, '${username}_data', '${username}_data.db'));

        if (await statsDbFile.exists()) {
          await statsDbFile.copy(p.join(appDir.path, '${username}_stats.db'));
        } else if (await statsDbFileInDir.exists()) {
          await statsDbFileInDir
              .copy(p.join(appDir.path, '${username}_stats.db'));
        }

        if (await dataDbFile.exists()) {
          await dataDbFile.copy(p.join(appDir.path, '${username}_data.db'));
        } else if (await dataDbFileInDir.exists()) {
          await dataDbFileInDir
              .copy(p.join(appDir.path, '${username}_data.db'));
        }

        // Restore JSON data - check both direct and in subdirectory
        final storage = StorageService();

        // Helper function to find and restore JSON files
        Future<void> restoreJsonFile(String filename, Future<void> Function(dynamic) restoreFunc) async {
          final directFile = File(p.join(tempDir.path, filename));
          final subDirFile =
              File(p.join(tempDir.path, '${username}_data', filename));

          if (await directFile.exists()) {
            final content = await directFile.readAsString();
            final data = decodeJson(content);
            await restoreFunc(data);
          } else if (await subDirFile.exists()) {
            final content = await subDirFile.readAsString();
            final data = decodeJson(content);
            await restoreFunc(data);
          }
        }

        // Restore songs
        await restoreJsonFile('songs.json', (data) async {
          final songs =
              (data as List).map((json) => Song.fromJson(json)).toList();
          await storage.saveSongs(username, songs);
        });

        // Restore user data
        await restoreJsonFile('user_data.json', (data) async {
          await storage.saveUserData(username, data);
        });

        // Restore shuffle state
        await restoreJsonFile('shuffle_state.json', (data) async {
          await storage.saveShuffleState(username, data);
        });

        // Restore playback state
        await restoreJsonFile('playback_state.json', (data) async {
          await storage.savePlaybackState(username, data);
        });

        // Reinitialize database service to pick up new data
        await DatabaseService.instance.initForUser(username);
      } finally {
        // Clean up temp directory
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
