import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'backup_manifest.dart';
import 'storage_service.dart';
import 'database_service.dart';
import 'import_options.dart';
import '../models/song.dart';
import '../data/repositories/search_index_repository.dart';

export 'backup_manifest.dart' show BackupContentType;

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
  static const String statsDbName = 'wispie_stats.db';
  static const String dataDbName = 'wispie_data.db';
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

  /// The content types used for automatic backups and pre-selected when
  /// creating one manually.
  Future<BackupOptions> defaultBackupOptions() async {
    final types = await StorageService().loadBackupContentTypes();
    return BackupOptions(contentTypes: types);
  }

  /// Writes every selected content type into [stagingDir].
  ///
  /// Shared by [createBackup] and [exportUserData] so both archives always
  /// carry the same content for the same options.
  Future<void> _stageBackup(BackupOptions options, Directory stagingDir) async {
    final appDir = await getApplicationDocumentsDirectory();
    final storage = StorageService();

    if (options.includeUserStats) {
      final statsDb = File(p.join(appDir.path, statsDbName));
      if (await statsDb.exists()) {
        await statsDb.copy(p.join(stagingDir.path, statsDbName));
      }
    }

    if (options.includeUserData) {
      final dataDb = File(p.join(appDir.path, dataDbName));
      if (await dataDb.exists()) {
        await dataDb.copy(p.join(stagingDir.path, dataDbName));
      }
    }

    if (options.includeUserStats || options.includeUserData) {
      final database = DatabaseService.instance;
      await database.init();

      if (options.includeUserStats) {
        final songs = await database.getAllSongs();
        final songsJson = songs.map((s) => s.toJson()).toList();
        await File(p.join(stagingDir.path, 'songs.json'))
            .writeAsString(encodeJson(songsJson));

        final funStats = await database.getFunStats();
        await File(p.join(stagingDir.path, 'final_stats.json'))
            .writeAsString(encodeJson(funStats));

        final mergedGroups = await database.getMergedSongGroups();
        final mergedGroupsJson = mergedGroups.map((groupId, groupData) {
          return MapEntry(groupId, {
            'filenames': groupData.filenames,
            'priorityFilename': groupData.priorityFilename,
          });
        });
        await File(p.join(stagingDir.path, 'merged_groups.json'))
            .writeAsString(encodeJson(mergedGroupsJson));

        final queueHistory = await database.exportQueueHistory();
        if (queueHistory.isNotEmpty) {
          await File(p.join(stagingDir.path, 'queue_history.json'))
              .writeAsString(encodeJson(queueHistory));
        }
      }

      if (options.includeUserData) {
        final userData = await storage.loadUserData();
        final shuffleState = await storage.loadShuffleState();
        final playbackState = await storage.loadPlaybackState();

        if (userData != null) {
          await File(p.join(stagingDir.path, 'user_data.json'))
              .writeAsString(encodeJson(userData));
        }

        if (shuffleState != null) {
          await File(p.join(stagingDir.path, 'shuffle_state.json'))
              .writeAsString(encodeJson(shuffleState));
        }

        if (playbackState != null) {
          await File(p.join(stagingDir.path, 'playback_state.json'))
              .writeAsString(encodeJson(playbackState));
        }
      }
    }

    // Settings stand on their own: a settings-only backup must still contain
    // app_settings.json.
    if (options.includeUserSettings) {
      final appSettings = await storage.exportAppSettings();
      if (appSettings.isNotEmpty) {
        await File(p.join(stagingDir.path, 'app_settings.json'))
            .writeAsString(encodeJson(appSettings));
      }
    }

    final artifacts = await cacheArtifacts();
    for (final artifact in artifacts) {
      if (!options.contentTypes.contains(artifact.type)) continue;
      await stageArtifact(artifact, stagingDir.path);
    }

    await File(p.join(stagingDir.path, _metadataFile))
        .writeAsString(jsonEncode(_buildMetadata(options)));
  }

  Map<String, dynamic> _buildMetadata(BackupOptions options) {
    return {
      'export_date': DateTime.now().toIso8601String(),
      'version': '2.0',
      'options': {
        for (final type in BackupContentType.values)
          type.name: options.contentTypes.contains(type),
      },
    };
  }

  Future<String> createBackup([BackupOptions? options]) async {
    options ??= await defaultBackupOptions();

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
        await _stageBackup(options, dataDir);

        final archive = Archive();
        await for (final entity in dataDir.list(recursive: true)) {
          if (entity is File) {
            final relativePath = p.relative(entity.path, from: dataDir.path);
            final bytes = await entity.readAsBytes();
            archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
          }
        }

        final zipBytes = ZipEncoder().encode(archive);
        if (zipBytes == null) {
          throw Exception('Failed to encode backup archive');
        }
        await File(backupPath).writeAsBytes(zipBytes);

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
    options ??= await defaultBackupOptions();

    final tempDir = await getTemporaryDirectory();
    final exportDir = Directory(p.join(
        tempDir.path, 'export_${DateTime.now().millisecondsSinceEpoch}'));
    await exportDir.create(recursive: true);

    try {
      await _stageBackup(options, exportDir);

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

  /// Archives produced by `ZipFileEncoder.addDirectory` wrap their content in a
  /// single top-level folder; descend into it, but only when it really is the
  /// wrapper (a bucket folder such as `cache/` is not).
  String _resolveContentRoot(Directory extractRoot) {
    final entities = extractRoot.listSync();
    if (entities.length != 1 || entities.first is! Directory) {
      return extractRoot.path;
    }

    final inner = entities.first as Directory;
    if (File(p.join(inner.path, _metadataFile)).existsSync() ||
        File(p.join(inner.path, statsDbName)).existsSync() ||
        File(p.join(inner.path, dataDbName)).existsSync() ||
        File(p.join(inner.path, 'app_settings.json')).existsSync()) {
      return inner.path;
    }
    return extractRoot.path;
  }

  /// Extracts [zipFile] into [target], skipping entries that would escape it.
  Future<void> _extractArchive(File zipFile, Directory target) async {
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final entry in archive) {
      if (!entry.isFile) continue;
      final outputFile = safeArchiveTarget(target.path, entry.name);
      if (outputFile == null) continue;
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(entry.content as List<int>);
    }
  }

  /// Prompts for a backup archive and validates it.
  ///
  /// Returns null when the user cancels the picker. The caller owns the
  /// extracted content afterwards and must pass the result to either
  /// [performImport] or [discardValidation].
  Future<Map<String, dynamic>?> pickAndValidateBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result == null || result.files.isEmpty) return null;

    return validateBackupFile(File(result.files.first.path!));
  }

  /// Extracts [file] and reports what it actually contains.
  ///
  /// Detection is authoritative: `metadata.json` is only a hint, because it can
  /// disagree with the archive (older versions, hand-edited archives).
  Future<Map<String, dynamic>> validateBackupFile(File file) async {
    final tempDir = await getTemporaryDirectory();
    final decodeDir = Directory(p.join(
        tempDir.path, 'import_${DateTime.now().millisecondsSinceEpoch}'));
    await decodeDir.create(recursive: true);

    try {
      await _extractArchive(file, decodeDir);

      // Archives produced by ZipFileEncoder.addDirectory are wrapped in a
      // single top-level folder.
      final contentPath = _resolveContentRoot(decodeDir);

      File? foundStats;
      File? foundData;
      bool hasSongsJson = false;
      bool hasUserDataJson = false;
      bool hasShuffleStateJson = false;
      bool hasPlaybackStateJson = false;
      bool hasMergedGroupsJson = false;
      bool hasQueueHistoryJson = false;
      bool hasAppSettingsJson = false;

      await for (final entity in Directory(contentPath).list(recursive: true)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);

        if (name == statsDbName ||
            (name.endsWith('_stats.db') && !name.startsWith('wispie_'))) {
          foundStats = entity;
        }
        if (name == dataDbName ||
            (name.endsWith('_data.db') && !name.startsWith('wispie_'))) {
          foundData = entity;
        }
        if (name == 'songs.json') hasSongsJson = true;
        if (name == 'user_data.json' || name.startsWith('user_data_')) {
          hasUserDataJson = true;
        }
        if (name == 'shuffle_state.json' || name.startsWith('shuffle_state_')) {
          hasShuffleStateJson = true;
        }
        if (name == 'playback_state.json' ||
            name.startsWith('playback_state_')) {
          hasPlaybackStateJson = true;
        }
        if (name == 'merged_groups.json') hasMergedGroupsJson = true;
        if (name == 'queue_history.json') hasQueueHistoryJson = true;
        if (name == 'app_settings.json') hasAppSettingsJson = true;
      }

      final hasFavorites = foundData != null &&
          await _checkTableExists(foundData.path, 'favorite');
      final hasSuggestless = foundData != null &&
          await _checkTableExists(foundData.path, 'suggestless');
      final hasHidden = foundData != null &&
          await _checkTableExists(foundData.path, 'hidden');
      final hasPlaylists = foundData != null &&
          await _checkTableExists(foundData.path, 'playlist');
      final hasMergedGroups = foundData != null &&
          await _checkTableExists(foundData.path, 'merged_song_group');
      final hasRecommendations = foundData != null &&
          await _checkTableExists(foundData.path, 'recommendation_preference');
      final hasUserdata = foundData != null &&
          await _checkTableExists(foundData.path, 'userdata');
      final hasPlayHistory = foundStats != null &&
          await _checkTableExists(foundStats.path, 'playsession');

      final artifacts = await cacheArtifacts();
      final cacheFlags = <BackupContentType, bool>{};
      for (final type in BackupContentType.values) {
        cacheFlags[type] =
            await archiveHasContent(artifacts, type, contentPath);
      }

      final validation = <String, dynamic>{
        'valid': true,
        'importPath': contentPath,
        'extractRoot': decodeDir.path,
        'statsDbPath': foundStats?.path,
        'dataDbPath': foundData?.path,
        'hasStatsDb': foundStats != null,
        'hasDataDb': foundData != null,
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
        'hasUserdata': hasUserdata,
        'hasPlayHistory': hasPlayHistory,
        'hasCoverCache': cacheFlags[BackupContentType.coverCache],
        'hasLibraryCache': cacheFlags[BackupContentType.libraryCache],
        'hasSearchIndex': cacheFlags[BackupContentType.searchIndex],
        'hasWaveformCache': cacheFlags[BackupContentType.waveformCache],
        'hasColorCache': cacheFlags[BackupContentType.colorCache],
        'hasLyricsCache': cacheFlags[BackupContentType.lyricsCache],
      };

      final hasAnything = validation.entries
          .where((e) => e.key.startsWith('has'))
          .any((e) => e.value == true);
      if (!hasAnything) {
        throw Exception('Invalid backup: no restorable content found');
      }

      return validation;
    } catch (e) {
      if (await decodeDir.exists()) await decodeDir.delete(recursive: true);
      rethrow;
    }
  }

  /// Deletes the content extracted by [validateBackupFile] when the user backs
  /// out of the import dialog.
  Future<void> discardValidation(Map<String, dynamic>? validation) async {
    final root = validation?['extractRoot'] as String?;
    if (root == null) return;
    try {
      final dir = Directory(root);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('Error cleaning up import temp files: $e');
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
    // Merged groups are only restorable from the database table; the JSON copy
    // is informational.
    if (validation['hasMergedGroups'] == true) {
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
    if (validation['hasUserdata'] == true) {
      categories.add(ImportDataCategory.userdata);
    }
    if (validation['hasPlayHistory'] == true) {
      categories.add(ImportDataCategory.playHistory);
    }

    if (validation['hasCoverCache'] == true) {
      categories.add(ImportDataCategory.coverCache);
    }
    if (validation['hasLibraryCache'] == true) {
      categories.add(ImportDataCategory.libraryCache);
    }
    if (validation['hasSearchIndex'] == true) {
      categories.add(ImportDataCategory.searchIndex);
    }
    if (validation['hasWaveformCache'] == true) {
      categories.add(ImportDataCategory.waveformCache);
    }
    if (validation['hasColorCache'] == true) {
      categories.add(ImportDataCategory.colorCache);
    }
    if (validation['hasLyricsCache'] == true) {
      categories.add(ImportDataCategory.lyricsCache);
    }

    return categories;
  }

  /// Applies every selected category from an extracted archive rooted at
  /// [importPath].
  ///
  /// Used by both the "import a zip" and "restore a backup" flows so they can
  /// never diverge in what they support.
  Future<void> _applyImport({
    required String importPath,
    String? statsDbPath,
    String? dataDbPath,
    required ImportOptions options,
  }) async {
    final categories = options.categories;
    final storage = StorageService();

    if (options.hasDatabaseCategories) {
      if (statsDbPath != null && dataDbPath != null) {
        await DatabaseService.instance.importWithOptions(
          statsDbPath: statsDbPath,
          dataDbPath: dataDbPath,
          options: options,
        );
      } else {
        debugPrint(
            'Skipping database categories: backup contains no database files');
      }
    }

    if (categories.contains(ImportDataCategory.songs)) {
      final songsFile = File(p.join(importPath, 'songs.json'));
      if (await songsFile.exists()) {
        final data = decodeJson(await songsFile.readAsString());
        if (data is List) {
          final songs = data.map((json) => Song.fromJson(json)).toList();
          await DatabaseService.instance.insertSongsBatch(songs);
        }
      }
    }

    if (categories.contains(ImportDataCategory.shuffleState)) {
      final shuffleStateFile = File(p.join(importPath, 'shuffle_state.json'));
      if (await shuffleStateFile.exists()) {
        final data = decodeJson(await shuffleStateFile.readAsString());
        if (data is Map) {
          await storage.saveShuffleState(Map<String, dynamic>.from(data));
        }
      }
    }

    if (categories.contains(ImportDataCategory.playbackState)) {
      final playbackStateFile = File(p.join(importPath, 'playback_state.json'));
      if (await playbackStateFile.exists()) {
        final data = decodeJson(await playbackStateFile.readAsString());
        if (data is Map) {
          await storage.savePlaybackState(Map<String, dynamic>.from(data));
        }
      }
    }

    if (categories.contains(ImportDataCategory.queueHistory)) {
      final queueHistoryFile = File(p.join(importPath, 'queue_history.json'));
      if (await queueHistoryFile.exists()) {
        final data = decodeJson(await queueHistoryFile.readAsString());
        if (data is List) {
          await DatabaseService.instance
              .importQueueHistory(data.cast<Map<String, dynamic>>());
        }
      }
    }

    if (options.hasSettingsCategories) {
      final appSettingsFile = File(p.join(importPath, 'app_settings.json'));
      if (await appSettingsFile.exists()) {
        final data = decodeJson(await appSettingsFile.readAsString());
        if (data is Map) {
          await storage.importSettingsWithOptions(
            Map<String, dynamic>.from(data),
            options,
          );
        }
      }
    }

    if (options.hasCacheCategories) {
      final artifacts = await cacheArtifacts();
      final wantedTypes = categories
          .map((c) => c.cacheContentType)
          .whereType<BackupContentType>()
          .toSet();

      for (final artifact in artifacts) {
        if (!wantedTypes.contains(artifact.type)) continue;
        await restoreArtifact(artifact, importPath);
      }
    }
  }

  /// Imports a previously validated archive, then removes the extracted copy.
  Future<void> performImport({
    required Map<String, dynamic> validation,
    required ImportOptions options,
  }) async {
    try {
      await _applyImport(
        importPath: validation['importPath'] as String,
        statsDbPath: validation['statsDbPath'] as String?,
        dataDbPath: validation['dataDbPath'] as String?,
        options: options,
      );
      await _invalidateSearchIndexIfStale(options);
    } finally {
      await discardValidation(validation);
    }
  }

  /// The search index is derived from the library, so a library-changing import
  /// must drop it — unless the archive restored an index of its own.
  Future<void> _invalidateSearchIndexIfStale(ImportOptions options) async {
    final categories = options.categories;
    if (categories.contains(ImportDataCategory.searchIndex)) return;
    if (!categories.contains(ImportDataCategory.songs) &&
        !categories.contains(ImportDataCategory.libraryCache)) {
      return;
    }

    try {
      final searchIndexRepo = SearchIndexRepository();
      await searchIndexRepo.close();
      await searchIndexRepo.deleteDatabaseFile();
    } catch (e) {
      debugPrint('Note: Could not delete search index: $e');
    }
  }

  Future<void> restoreFromBackup(BackupInfo backupInfo,
      {ImportOptions? options}) async {
    final importOptions = options ?? ImportOptions.defaultImport;

    try {
      final tempDir = await Directory.systemTemp.createTemp('gru_restore_');

      try {
        await _extractArchive(backupInfo.file, tempDir);

        final contentPath = _resolveContentRoot(tempDir);

        final appDir = await getApplicationDocumentsDirectory();

        File? foundStatsDb;
        File? foundDataDb;
        await for (final entity in tempDir.list(recursive: true)) {
          if (entity is! File) continue;
          final name = p.basename(entity.path);
          if (name == statsDbName ||
              (name.endsWith('_stats.db') && !name.startsWith('wispie_'))) {
            foundStatsDb = entity;
          }
          if (name == dataDbName ||
              (name.endsWith('_data.db') && !name.startsWith('wispie_'))) {
            foundDataDb = entity;
          }
        }

        String? statsDbPath = foundStatsDb?.path;
        String? dataDbPath = foundDataDb?.path;

        // Wholesale file replacement only makes sense when the archive
        // actually carries databases; otherwise fall through and restore the
        // JSON/settings/cache content as usual.
        if (importOptions.restoreDatabases &&
            (foundStatsDb != null || foundDataDb != null)) {
          await DatabaseService.instance.close();
          const dbSuffixes = ['', '-journal', '-wal', '-shm'];
          for (final suffix in dbSuffixes) {
            if (foundStatsDb != null) {
              final statsFile =
                  File(p.join(appDir.path, '$statsDbName$suffix'));
              if (await statsFile.exists()) await statsFile.delete();
            }
            if (foundDataDb != null) {
              final dataFile = File(p.join(appDir.path, '$dataDbName$suffix'));
              if (await dataFile.exists()) await dataFile.delete();
            }
          }

          if (foundStatsDb != null) {
            await foundStatsDb.copy(p.join(appDir.path, statsDbName));
            statsDbPath = p.join(appDir.path, statsDbName);
          }
          if (foundDataDb != null) {
            await foundDataDb.copy(p.join(appDir.path, dataDbName));
            dataDbPath = p.join(appDir.path, dataDbName);
          }

          await DatabaseService.instance.init();
        }

        await _applyImport(
          importPath: contentPath,
          statsDbPath: statsDbPath,
          dataDbPath: dataDbPath,
          options: importOptions,
        );

        await _invalidateSearchIndexIfStale(importOptions);
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
          if (name == statsDbName ||
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
