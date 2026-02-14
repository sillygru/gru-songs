import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'database_service.dart';
import '../models/playlist.dart';

/// Represents the type of import operation
enum NamidaImportMode {
  /// Adds imported data to existing data without removing anything
  additive,

  /// Replaces all existing data with imported data
  replace,
}

/// Result of a Namida import operation
class NamidaImportResult {
  final bool success;
  final String message;
  final int playlistsImported;
  final int favoritesImported;
  final int tracksWithStatsImported;

  const NamidaImportResult({
    required this.success,
    required this.message,
    this.playlistsImported = 0,
    this.favoritesImported = 0,
    this.tracksWithStatsImported = 0,
  });
}

/// Service for importing data from Namida backup files into Wispie
///
/// Namida stores data in JSON files within a specific directory structure.
/// Key files:
/// - Playlists: stored in Playlists/ directory as JSON files
/// - Favorites: stored as favs.json
/// - History: stored in History/ directory with date-based files
class NamidaImportService {
  static const String _namidaBackupPrefix = 'Namida Backup';

  /// Validates if a selected file is a valid Namida backup
  /// Returns a map with validation results and extracted path if valid
  Future<Map<String, dynamic>?> validateNamidaBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      dialogTitle: 'Select Namida Backup File',
    );

    if (result == null || result.files.isEmpty) return null;

    final file = File(result.files.first.path!);
    final tempDir = await getTemporaryDirectory();
    final decodeDir = Directory(join(tempDir.path,
        'namida_import_${DateTime.now().millisecondsSinceEpoch}'));
    await decodeDir.create(recursive: true);

    try {
      // Extract the zip file
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Track if we found Namida-specific files
      bool hasNamidaStructure = false;
      String? extractedPath;

      for (final archiveFile in archive) {
        final filename = archiveFile.name;

        // Check for Namida-specific file patterns (nested zip structure)
        if (filename.contains('LOCAL_FILES.zip') ||
            filename.contains('TEMPDIR_Playlists.zip') ||
            filename.contains('TEMPDIR_History.zip') ||
            filename.startsWith(_namidaBackupPrefix)) {
          hasNamidaStructure = true;
        }

        if (archiveFile.isFile) {
          final data = archiveFile.content as List<int>;
          File(join(decodeDir.path, filename))
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);

          // Track the root directory of extracted content
          extractedPath ??= decodeDir.path;
        } else {
          // Create directory
          Directory(join(decodeDir.path, filename)).createSync(recursive: true);
        }
      }

      if (!hasNamidaStructure) {
        await decodeDir.delete(recursive: true);
        return {
          'valid': false,
          'error': 'This does not appear to be a valid Namida backup file.',
        };
      }

      // Find the actual content directory (might be nested)
      String contentPath = decodeDir.path;
      final entities = decodeDir.listSync();
      if (entities.length == 1 && entities.first is Directory) {
        contentPath = entities.first.path;
      }

      // Extract nested LOCAL_FILES.zip if present
      final localFilesZip = File(join(contentPath, 'LOCAL_FILES.zip'));
      if (await localFilesZip.exists()) {
        final localBytes = await localFilesZip.readAsBytes();
        final localArchive = ZipDecoder().decodeBytes(localBytes);

        for (final file in localArchive) {
          if (file.isFile) {
            final data = file.content as List<int>;
            File(join(contentPath, file.name))
              ..createSync(recursive: true)
              ..writeAsBytesSync(data);
          } else {
            Directory(join(contentPath, file.name)).createSync(recursive: true);
          }
        }
      }

      // Extract nested TEMPDIR_Playlists.zip if present
      final playlistsZip = File(join(contentPath, 'TEMPDIR_Playlists.zip'));
      if (await playlistsZip.exists()) {
        try {
          final playlistBytes = await playlistsZip.readAsBytes();
          final playlistArchive = ZipDecoder().decodeBytes(playlistBytes);

          final playlistsDir = Directory(join(contentPath, 'Playlists'));
          await playlistsDir.create(recursive: true);

          for (final file in playlistArchive) {
            if (file.isFile && file.name.endsWith('.json')) {
              final data = file.content as List<int>;
              File(join(playlistsDir.path, basename(file.name)))
                ..createSync(recursive: true)
                ..writeAsBytesSync(data);
            }
          }
        } catch (e) {
          // Playlists zip might be empty, continue
          debugPrint('No playlists to extract: $e');
        }
      }

      // Extract nested TEMPDIR_History.zip if present
      final historyZip = File(join(contentPath, 'TEMPDIR_History.zip'));
      if (await historyZip.exists()) {
        try {
          final historyBytes = await historyZip.readAsBytes();
          final historyArchive = ZipDecoder().decodeBytes(historyBytes);

          final historyDir = Directory(join(contentPath, 'History'));
          await historyDir.create(recursive: true);

          for (final file in historyArchive) {
            if (file.isFile && file.name.endsWith('.json')) {
              final data = file.content as List<int>;
              File(join(historyDir.path, basename(file.name)))
                ..createSync(recursive: true)
                ..writeAsBytesSync(data);
            }
          }
        } catch (e) {
          // History zip might be empty, continue
          debugPrint('No history to extract: $e');
        }
      }

      return {
        'valid': true,
        'importPath': contentPath,
        'tempDir': decodeDir.path,
      };
    } catch (e) {
      await decodeDir.delete(recursive: true);
      return {
        'valid': false,
        'error': 'Error reading backup file: $e',
      };
    }
  }

  /// Performs the import of Namida data into the database
  Future<NamidaImportResult> performImport({
    required String importPath,
    required NamidaImportMode mode,
    required String? Function(String namidaPath) pathMapper,
  }) async {
    int playlistsImported = 0;
    int favoritesImported = 0;
    int tracksWithStatsImported = 0;

    try {
      final importDir = Directory(importPath);
      if (!await importDir.exists()) {
        return const NamidaImportResult(
          success: false,
          message: 'Import directory not found',
        );
      }

      // Load all local songs for smarter path mapping
      final localSongs = await DatabaseService.instance.getAllSongs();
      final Map<String, String> basenameToFullPath = {
        for (var s in localSongs) basename(s.filename): s.filename
      };

      // Smarter path mapper that falls back to basename matching
      String? smartPathMapper(String namidaPath) {
        // Normalize Namida path for easier basename extraction if it's from another OS
        final name = basename(namidaPath.replaceAll('\\\\', '/'));

        // 1. Try basename matching against scanned songs (BEST)
        if (basenameToFullPath.containsKey(name)) {
          return basenameToFullPath[name];
        }

        // 2. Try provided path mapper (usually joining musicFolder + basename)
        final mapped = pathMapper(namidaPath);
        if (mapped != null && File(mapped).existsSync()) {
          return mapped;
        }

        return null; // Return null if we can't find the file locally
      }

      // Load track metadata (durations) from Namida's tracks.db
      final Map<String, double> trackDurations = {};
      final tracksDbFile = File(join(importPath, 'tracks.db'));
      if (await tracksDbFile.exists()) {
        try {
          final db = await openDatabase(tracksDbFile.path);
          final List<Map<String, dynamic>> maps = await db.query('tracks');
          for (final map in maps) {
            final namidaPath = map['key'] as String;
            final valueStr = map['value'] as String;
            try {
              final valueJson = jsonDecode(valueStr) as Map<String, dynamic>;
              final durationMs = valueJson['durationMS'] as num? ?? 0;
              trackDurations[namidaPath] = durationMs / 1000.0;
            } catch (e) {
              debugPrint('Error decoding track metadata for $namidaPath: $e');
            }
          }
          await db.close();
          debugPrint('Loaded durations for ${trackDurations.length} tracks');
        } catch (e) {
          debugPrint('Error reading tracks.db: $e');
        }
      }

      // Import favorites
      final favsFile = File(join(importPath, 'favs.json'));
      if (await favsFile.exists()) {
        favoritesImported = await _importFavorites(
          favsFile: favsFile,
          mode: mode,
          pathMapper: smartPathMapper,
        );
      }

      // Import playlists
      final playlistsDir = Directory(join(importPath, 'Playlists'));
      if (await playlistsDir.exists()) {
        playlistsImported = await _importPlaylists(
          playlistsDir: playlistsDir,
          mode: mode,
          pathMapper: smartPathMapper,
        );
      }

      // Import history/stats
      final historyDir = Directory(join(importPath, 'History'));
      if (await historyDir.exists()) {
        tracksWithStatsImported = await _importHistory(
          historyDir: historyDir,
          mode: mode,
          pathMapper: smartPathMapper,
          trackDurations: trackDurations,
        );
      }

      // Cleanup temp directory
      final tempDir = Directory(importPath).parent;
      if (tempDir.path.contains('namida_import_')) {
        await tempDir.delete(recursive: true);
      }

      return NamidaImportResult(
        success: true,
        message: 'Import completed successfully',
        playlistsImported: playlistsImported,
        favoritesImported: favoritesImported,
        tracksWithStatsImported: tracksWithStatsImported,
      );
    } catch (e) {
      return NamidaImportResult(
        success: false,
        message: 'Import failed: $e',
      );
    }
  }

  /// Imports favorites from Namida's favs.json file
  Future<int> _importFavorites({
    required File favsFile,
    required NamidaImportMode mode,
    required String? Function(String namidaPath) pathMapper,
  }) async {
    try {
      final content = await favsFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      // Namida stores favorites as a playlist
      final tracks = json['tracks'] as List<dynamic>? ?? [];
      final List<String> favoritePaths = [];

      debugPrint('Importing ${tracks.length} favorites');

      for (final trackJson in tracks) {
        final trackMap = trackJson as Map<String, dynamic>;
        final trackPath = trackMap['track'] as String?;
        if (trackPath != null) {
          final mappedPath = pathMapper(trackPath);
          if (mappedPath != null) {
            favoritePaths.add(mappedPath);
          } else {
            debugPrint('Warning: Could not map favorite path: $trackPath');
          }
        }
      }

      debugPrint('Successfully mapped ${favoritePaths.length} favorites');

      if (mode == NamidaImportMode.replace) {
        await DatabaseService.instance.setFavorites(favoritePaths);
      } else {
        // Additive mode - merge with existing
        final existing = await DatabaseService.instance.getFavorites();
        final merged = {...existing, ...favoritePaths}.toList();
        await DatabaseService.instance.setFavorites(merged);
      }

      return favoritePaths.length;
    } catch (e) {
      debugPrint('Error importing favorites: $e');
      return 0;
    }
  }

  /// Imports playlists from Namida's Playlists directory
  Future<int> _importPlaylists({
    required Directory playlistsDir,
    required NamidaImportMode mode,
    required String? Function(String namidaPath) pathMapper,
  }) async {
    int count = 0;

    try {
      // In replace mode, delete all existing playlists first
      if (mode == NamidaImportMode.replace) {
        debugPrint('Replace mode: Deleting all existing playlists');
        final existingPlaylists = await DatabaseService.instance.getPlaylists();
        for (final playlist in existingPlaylists) {
          await DatabaseService.instance.deletePlaylist(playlist.id);
        }
        debugPrint('Deleted ${existingPlaylists.length} existing playlists');
      }

      final existingPlaylists = mode == NamidaImportMode.additive
          ? await DatabaseService.instance.getPlaylists()
          : <Playlist>[];

      final existingNames = existingPlaylists.map((p) => p.name).toSet();

      await for (final entity in playlistsDir.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;

        try {
          final content = await entity.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;

          final name = json['name'] as String? ?? 'Imported Playlist';
          final tracks = json['tracks'] as List<dynamic>? ?? [];

          debugPrint('Importing playlist: $name with ${tracks.length} tracks');

          // Skip if playlist already exists in additive mode
          if (mode == NamidaImportMode.additive &&
              existingNames.contains(name)) {
            debugPrint('Skipping existing playlist: $name');
            continue;
          }

          final List<PlaylistSong> songs = [];
          int skippedSongs = 0;
          int nonExistentFiles = 0;

          for (final trackJson in tracks) {
            final trackMap = trackJson as Map<String, dynamic>;
            final trackPath = trackMap['track'] as String?;
            final dateAdded = trackMap['dateAdded'] as int? ??
                DateTime.now().millisecondsSinceEpoch;

            if (trackPath != null) {
              final mappedPath = pathMapper(trackPath);
              if (mappedPath != null) {
                songs.add(PlaylistSong(
                  songFilename: mappedPath,
                  addedAt: dateAdded / 1000.0,
                ));
              } else {
                skippedSongs++;
                debugPrint(
                    'Warning: Could not map playlist song path: $trackPath');
              }
            }
          }

          if (skippedSongs > 0) {
            debugPrint(
                'Skipped $skippedSongs unmapped songs in playlist: $name');
          }
          if (nonExistentFiles > 0) {
            debugPrint(
                'Skipped $nonExistentFiles non-existent files in playlist: $name');
          }

          // Generate unique name if needed
          String finalName = name;
          int suffix = 1;
          while (existingNames.contains(finalName)) {
            finalName = '$name ($suffix)';
            suffix++;
          }

          final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
          final playlist = Playlist(
            id: '${DateTime.now().millisecondsSinceEpoch}_$count',
            name: finalName,
            createdAt: now,
            updatedAt: now,
            songs: songs,
          );

          debugPrint('Saving playlist: $finalName with ${songs.length} songs');
          await DatabaseService.instance.savePlaylist(playlist);
          existingNames.add(finalName);
          count++;

          debugPrint(
              'Successfully imported playlist: $finalName with ${songs.length} songs');
        } catch (e) {
          debugPrint('Error importing playlist ${entity.path}: $e');
        }
      }

      return count;
    } catch (e) {
      debugPrint('Error importing playlists: $e');
      return count;
    }
  }

  /// Imports history/play stats from Namida's History directory
  Future<int> _importHistory({
    required Directory historyDir,
    required NamidaImportMode mode,
    required String? Function(String namidaPath) pathMapper,
    required Map<String, double> trackDurations,
  }) async {
    int count = 0;

    try {
      // In replace mode, delete all existing play events and sessions
      if (mode == NamidaImportMode.replace) {
        debugPrint(
            'Replace mode: Deleting all existing play events and sessions');
        await DatabaseService.instance.clearStats();
      }

      final List<Map<String, dynamic>> playEvents = [];
      int skippedTracks = 0;
      int nonExistentFiles = 0;

      await for (final entity in historyDir.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;

        try {
          final content = await entity.readAsString();
          final json = jsonDecode(content) as List<dynamic>? ?? [];

          // Extract date from filename (Namida uses day-based files)
          final filename = basenameWithoutExtension(entity.path);
          final dayTimestamp =
              int.tryParse(filename) ?? DateTime.now().millisecondsSinceEpoch;

          for (final trackJson in json) {
            final trackMap = trackJson as Map<String, dynamic>;
            final trackPath = trackMap['track'] as String?;
            final dateAdded = trackMap['dateAdded'] as int? ?? dayTimestamp;

            if (trackPath != null) {
              final mappedPath = pathMapper(trackPath);
              if (mappedPath != null) {
                final duration = trackDurations[trackPath] ?? 0.0;

                // Create a play event for this track
                playEvents.add({
                  'session_id':
                      'namida_import_${DateTime.now().millisecondsSinceEpoch}_$count',
                  'song_filename': mappedPath,
                  'event_type': 'complete',
                  'timestamp': dateAdded / 1000.0,
                  'duration_played': duration,
                  'total_length': duration,
                  'play_ratio': 1.0, // Assume complete play
                  'foreground_duration': duration,
                  'background_duration': 0.0,
                });
                count++;
              } else {
                skippedTracks++;
                debugPrint(
                    'Warning: Could not map history track path: $trackPath');
              }
            }
          }
        } catch (e) {
          debugPrint('Error importing history file ${entity.path}: $e');
        }
      }

      if (skippedTracks > 0) {
        debugPrint('Skipped $skippedTracks unmapped tracks from history');
      }
      if (nonExistentFiles > 0) {
        debugPrint('Skipped $nonExistentFiles non-existent files from history');
      }

      // Batch insert play events
      if (playEvents.isNotEmpty) {
        debugPrint('Inserting ${playEvents.length} play events');
        await DatabaseService.instance.insertPlayEventsBatch(playEvents);
      }

      return count;
    } catch (e) {
      debugPrint('Error importing history: $e');
      return count;
    }
  }

  /// Maps a Namida file path to a local file path
  /// This is used to handle different storage locations between devices
  static String? defaultPathMapper(String namidaPath, String localMusicPath) {
    // Namida stores full paths like /storage/emulated/0/Music/song.mp3
    // We need to map these to the local music folder structure

    // Extract the filename
    final filename = basename(namidaPath);

    // Return the path relative to the local music folder
    return join(localMusicPath, filename);
  }
}
