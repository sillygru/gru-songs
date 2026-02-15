import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../services/stats_service.dart';
import '../services/audio_player_manager.dart';
import '../services/storage_service.dart';
import '../services/scanner_service.dart';
import '../services/database_service.dart';
import '../services/bulk_metadata_service.dart';
import '../services/file_manager_service.dart';
import '../services/waveform_service.dart';
import '../services/cache_service.dart';
import '../data/repositories/song_repository.dart';
import '../models/song.dart';
import 'user_data_provider.dart';

enum SyncStatus { idle }

enum MetadataSaveStatus { idle, saving, success, error }

class MetadataSaveState {
  final MetadataSaveStatus status;
  final String message;

  const MetadataSaveState({
    this.status = MetadataSaveStatus.idle,
    this.message = '',
  });
}

class SyncState {
  final Map<String, SyncStatus> tasks;
  final bool hasError;

  SyncState({
    this.tasks = const {},
    this.hasError = false,
  });

  SyncStatus get status {
    if (hasError) return SyncStatus.idle;
    return SyncStatus.idle;
  }

  SyncState copyWith({
    Map<String, SyncStatus>? tasks,
    bool? hasError,
  }) {
    return SyncState(
      tasks: tasks ?? this.tasks,
      hasError: hasError ?? this.hasError,
    );
  }
}

class SyncNotifier extends Notifier<SyncState> {
  @override
  SyncState build() => SyncState();

  void updateTask(String task, SyncStatus status) {
    final newTasks = Map<String, SyncStatus>.from(state.tasks);
    newTasks[task] = status;
    state = state.copyWith(tasks: newTasks, hasError: false);
  }

  void setError() => state = state.copyWith(hasError: true);

  void setUpToDate() {
    final newTasks = Map<String, SyncStatus>.from(state.tasks);
    newTasks.forEach((key, value) => newTasks[key] = SyncStatus.idle);
    state = state.copyWith(tasks: newTasks, hasError: false);
  }
}

class MetadataSaveNotifier extends Notifier<MetadataSaveState> {
  int _token = 0;

  @override
  MetadataSaveState build() => const MetadataSaveState();

  void start() {
    _token += 1;
    state = const MetadataSaveState(
        status: MetadataSaveStatus.saving,
        message: 'Saving metadata changes...');
  }

  void success([String message = 'Metadata changes saved']) {
    final token = ++_token;
    state =
        MetadataSaveState(status: MetadataSaveStatus.success, message: message);
    _scheduleReset(token);
  }

  void error([String message = 'Failed to save metadata changes']) {
    final token = ++_token;
    state = MetadataSaveState(
      status: MetadataSaveStatus.error,
      message: message,
    );
    _scheduleReset(token);
  }

  void _scheduleReset(int token) {
    Future.delayed(const Duration(seconds: 2), () {
      if (!ref.mounted) return;
      if (_token == token) {
        state = const MetadataSaveState();
      }
    });
  }
}

final syncProvider =
    NotifierProvider<SyncNotifier, SyncState>(SyncNotifier.new);

final metadataSaveProvider =
    NotifierProvider<MetadataSaveNotifier, MetadataSaveState>(
        MetadataSaveNotifier.new);

class ScanProgressNotifier extends Notifier<double> {
  @override
  double build() => 0.0;
  @override
  set state(double value) => super.state = value;
}

class IsScanningNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  @override
  set state(bool value) => super.state = value;
}

final scanProgressProvider =
    NotifierProvider<ScanProgressNotifier, double>(ScanProgressNotifier.new);
final isScanningProvider =
    NotifierProvider<IsScanningNotifier, bool>(IsScanningNotifier.new);

// Services & Repositories
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

final statsServiceProvider = Provider<StatsService>((ref) {
  return StatsService();
});

final scannerServiceProvider = Provider<ScannerService>((ref) {
  return ScannerService();
});

final fileManagerServiceProvider = Provider<FileManagerService>((ref) {
  return FileManagerService();
});

final waveformServiceProvider = Provider<WaveformService>((ref) {
  final service = WaveformService(CacheService.instance);
  ref.onDispose(() => service.dispose());
  return service;
});

final songRepositoryProvider = Provider<SongRepository>((ref) {
  return SongRepository();
});

final audioPlayerManagerProvider = Provider<AudioPlayerManager>((ref) {
  final manager = AudioPlayerManager(
    ref.watch(statsServiceProvider),
    ref.watch(storageServiceProvider),
    ref,
  );

  ref.onDispose(() => manager.dispose());
  return manager;
});

// Data Providers
class SongsNotifier extends AsyncNotifier<List<Song>> {
  bool _isRefreshing = false;
  DateTime? _lastRefreshTime;
  Timer? _debounceTimer;

  @override
  Future<List<Song>> build() async {
    final userData = ref.watch(userDataProvider);

    // 2. Load from SQLite
    final cached = await DatabaseService.instance.getAllSongs();
    if (cached.isNotEmpty) {
      final filtered =
          cached.where((s) => !userData.isHidden(s.filename)).toList();
      // Trigger background scan on startup to ensure library is up to date
      _scheduleBackgroundScanUpdate(cached, showIndicator: false);
      return filtered;
    }

    // 3. If no cache, perform initial scan
    final scanned = await _performFullScan();
    return scanned.where((s) => !userData.isHidden(s.filename)).toList();
  }

  void _scheduleBackgroundScanUpdate(List<Song> existingSongs,
      {bool showIndicator = false}) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _backgroundScanUpdate(existingSongs, showIndicator: showIndicator);
    });
  }

  Future<List<Song>> _performFullScan(
      {bool isBackground = false,
      List<Song>? existingSongs,
      bool showIndicator = false}) async {
    final storage = ref.read(storageServiceProvider);
    final scanner = ref.read(scannerServiceProvider);

    final musicFolders = await storage.getMusicFolders();

    if (musicFolders.isEmpty) {
      debugPrint('No music folders configured. Cannot scan.');
      return [];
    }

    // Only show scanning indicator for non-background scans or if explicitly requested
    if (!isBackground || showIndicator) {
      ref.read(isScanningProvider.notifier).state = true;
    }
    ref.read(scanProgressProvider.notifier).state = 0.0;

    try {
      final List<Song> allSongs = [];

      // Scan each music folder
      for (int i = 0; i < musicFolders.length; i++) {
        final folder = musicFolders[i];
        final path = folder['path'];
        if (path == null || path.isEmpty) continue;

        final folderSongs = await scanner.scanDirectory(
          path,
          existingSongs: existingSongs,
          lyricsPath: null, // Use lyricsFolders instead
          onProgress: (progress) {
            // Overall progress across all folders
            final overallProgress = (i + progress) / musicFolders.length;
            ref.read(scanProgressProvider.notifier).state = overallProgress;
          },
        );

        allSongs.addAll(folderSongs);
      }

      // De-duplicate by filename
      final seenFilenames = <String>{};
      final uniqueSongs = allSongs.where((s) {
        if (seenFilenames.contains(s.filename)) return false;
        seenFilenames.add(s.filename);
        return true;
      }).toList();

      await DatabaseService.instance.insertSongsBatch(uniqueSongs);

      // Return all songs from scan, build() will filter them
      return uniqueSongs;
    } finally {
      if (!isBackground || showIndicator) {
        ref.read(isScanningProvider.notifier).state = false;
      }
      ref.read(scanProgressProvider.notifier).state = 0.0;
    }
  }

  Future<void> _backgroundScanUpdate(List<Song> existingSongs,
      {bool showIndicator = false}) async {
    try {
      // Background scan doesn't trigger the scanning indicator by default
      final songs = await _performFullScan(
          isBackground: true,
          existingSongs: existingSongs,
          showIndicator: showIndicator);

      final userData = ref.read(userDataProvider);
      final filteredSongs =
          songs.where((s) => !userData.isHidden(s.filename)).toList();

      // Only update if there are actual changes to avoid unnecessary rebuilds
      // We compare length and a few other things as a quick check
      bool hasChanges = filteredSongs.length != (state.value?.length ?? 0);
      if (!hasChanges) {
        final currentSongs = state.value ?? [];
        // More thorough check: compare URLs and mtimes
        for (int i = 0; i < filteredSongs.length; i++) {
          if (filteredSongs[i].url != currentSongs[i].url ||
              filteredSongs[i].mtime != currentSongs[i].mtime) {
            hasChanges = true;
            break;
          }
        }
      }

      if (hasChanges) {
        ref.read(audioPlayerManagerProvider).refreshSongs(songs);
        state = AsyncValue.data(filteredSongs);
      }
    } catch (e) {
      debugPrint('Background scan failed: $e');
    }
  }

  Future<void> refresh({bool isBackground = false}) async {
    final storage = ref.read(storageServiceProvider);
    final pullEnabled = await storage.getPullToRefreshEnabled();
    if (!pullEnabled && !isBackground) return;

    if (_isRefreshing) {
      debugPrint('SongsNotifier: Refresh already in progress, skipping');
      return;
    }

    if (isBackground && _lastRefreshTime != null) {
      final diff = DateTime.now().difference(_lastRefreshTime!);
      if (diff.inSeconds < 30) {
        // Reduced from 60 seconds for better responsiveness
        return;
      }
    }

    _isRefreshing = true;
    _lastRefreshTime = DateTime.now();

    try {
      // Capture current progress and flush to DB on manual refresh
      ref.read(audioPlayerManagerProvider).forceFlushCurrentStats();

      final newState = await AsyncValue.guard<List<Song>>(() async {
        // Local-only refresh - just scan files
        final songs = await _performFullScan(
            isBackground: isBackground, existingSongs: state.value);
        ref.read(audioPlayerManagerProvider).refreshSongs(songs);

        final userData = ref.read(userDataProvider);
        return songs.where((s) => !userData.isHidden(s.filename)).toList();
      });

      if (isBackground) {
        // Only update if not null and actually has changes
        if (newState.hasValue) {
          final newSongs = newState.value!;
          final oldSongs = state.value ?? [];
          bool hasChanges = newSongs.length != oldSongs.length;
          if (!hasChanges) {
            for (int i = 0; i < newSongs.length; i++) {
              if (newSongs[i].url != oldSongs[i].url ||
                  newSongs[i].mtime != oldSongs[i].mtime) {
                hasChanges = true;
                break;
              }
            }
          }
          if (hasChanges) {
            state = newState;
          }
        }
      } else {
        state = newState;
      }
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> forceFullScan() async {
    state = await AsyncValue.guard<List<Song>>(() async {
      final songs = await _performFullScan(); // No existingSongs = full scan
      ref.read(audioPlayerManagerProvider).refreshSongs(songs);
      final userData = ref.read(userDataProvider);
      return songs.where((s) => !userData.isHidden(s.filename)).toList();
    });
  }

  /// Refreshes ONLY the play counts of the current songs from the database
  Future<void> refreshPlayCounts() async {
    if (!state.hasValue) return;

    final playCounts = await DatabaseService.instance.getPlayCounts();

    final updatedSongs = state.value!.map((s) {
      final newCount = playCounts[s.filename] ?? 0;
      if (newCount == s.playCount) return s;
      return Song(
        title: s.title,
        artist: s.artist,
        album: s.album,
        filename: s.filename,
        url: s.url,
        coverUrl: s.coverUrl,
        hasLyrics: s.hasLyrics,
        playCount: newCount,
        duration: s.duration,
        mtime: s.mtime,
      );
    }).toList();

    state = AsyncValue.data(updatedSongs);

    // Update player manager and cache
    ref.read(audioPlayerManagerProvider).refreshSongs(updatedSongs);
    await DatabaseService.instance.insertSongsBatch(updatedSongs);
  }

  Future<void> hideSong(Song song) async {
    await ref.read(userDataProvider.notifier).toggleHidden(song.filename);
    // state will auto-update because build() watches userDataProvider
  }

  Future<void> deleteSongFile(Song song) async {
    // Get current songs before setting loading state
    final currentSongs = state.value ?? [];

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // Delete the physical file
      await ref.read(fileManagerServiceProvider).deleteSongFile(song);

      // Remove from database
      await DatabaseService.instance.deleteFile(song.filename);

      // Remove the deleted song from the current list immediately
      final updatedSongs =
          currentSongs.where((s) => s.filename != song.filename).toList();

      // Update audio player with the new list
      ref.read(audioPlayerManagerProvider).refreshSongs(updatedSongs);

      // Return the updated list immediately (no full scan needed)
      final userData = ref.read(userDataProvider);
      return updatedSongs.where((s) => !userData.isHidden(s.filename)).toList();
    });
  }

  Future<void> bulkDeleteSongs(List<Song> songs) async {
    final currentSongs = state.value ?? [];
    final filenamesToDelete = songs.map((s) => s.filename).toSet();

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final fileManager = ref.read(fileManagerServiceProvider);

      for (final song in songs) {
        try {
          await fileManager.deleteSongFile(song);
          await DatabaseService.instance.deleteFile(song.filename);
        } catch (e) {
          debugPrint('Failed to delete ${song.filename}: $e');
        }
      }

      final updatedSongs = currentSongs
          .where((s) => !filenamesToDelete.contains(s.filename))
          .toList();

      ref.read(audioPlayerManagerProvider).refreshSongs(updatedSongs);
      final userData = ref.read(userDataProvider);
      return updatedSongs.where((s) => !userData.isHidden(s.filename)).toList();
    });
  }

  Future<BulkMetadataResult> updateSongsMetadataBulk(
      List<Song> songs, BulkMetadataPlan plan) async {
    final notifier = ref.read(metadataSaveProvider.notifier);
    notifier.start();

    int updatedCount = 0;
    List<String> failedFilenames = [];

    try {
      final fileManager = ref.read(fileManagerServiceProvider);
      final currentSongs = state.value ?? [];
      final updatedSongsList = List<Song>.from(currentSongs);

      for (final song in songs) {
        try {
          final updatedSong = plan.apply(song);
          await fileManager.updateSongMetadata(
            song,
            updatedSong.title,
            updatedSong.artist,
            updatedSong.album,
          );

          final index =
              updatedSongsList.indexWhere((s) => s.filename == song.filename);
          if (index != -1) {
            updatedSongsList[index] = updatedSong;
          }
          updatedCount++;
        } catch (e) {
          debugPrint('Failed to update bulk metadata for ${song.filename}: $e');
          failedFilenames.add(song.filename);
        }
      }

      state = AsyncValue.data(updatedSongsList);
      ref.read(audioPlayerManagerProvider).refreshSongs(updatedSongsList);

      unawaited(refresh(isBackground: true));

      notifier.success('Updated $updatedCount songs');
      return BulkMetadataResult(
          updated: updatedCount, failedFilenames: failedFilenames);
    } catch (e) {
      notifier.error('Bulk update failed');
      return BulkMetadataResult(
          updated: updatedCount, failedFilenames: failedFilenames);
    }
  }

  Future<void> renameSong(Song song, String newFilename) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(fileManagerServiceProvider).renameSong(song, newFilename);
      return _performFullScan();
    });
  }

  Future<void> updateSongTitle(Song song, String newTitle) async {
    final notifier = ref.read(metadataSaveProvider.notifier);
    notifier.start();
    unawaited(() async {
      try {
        await ref
            .read(fileManagerServiceProvider)
            .updateSongTitle(song, newTitle);
        if (state.hasValue) {
          final current = state.value ?? [];
          state = AsyncValue.data([
            for (final s in current)
              if (s.filename == song.filename)
                Song(
                  title: newTitle,
                  artist: s.artist,
                  album: s.album,
                  filename: s.filename,
                  url: s.url,
                  coverUrl: s.coverUrl,
                  hasLyrics: s.hasLyrics,
                  playCount: s.playCount,
                  duration: s.duration,
                  mtime: s.mtime,
                )
              else
                s,
          ]);
        }
        await refresh(isBackground: true);
        notifier.success();
      } catch (e) {
        notifier.error();
        debugPrint('Failed to update song title: $e');
      }
    }());
  }

  Future<void> updateSongMetadata(
      Song song, String title, String artist, String album) async {
    final notifier = ref.read(metadataSaveProvider.notifier);
    notifier.start();
    unawaited(() async {
      try {
        await ref
            .read(fileManagerServiceProvider)
            .updateSongMetadata(song, title, artist, album);
        if (state.hasValue) {
          final current = state.value ?? [];
          state = AsyncValue.data([
            for (final s in current)
              if (s.filename == song.filename)
                Song(
                  title: title,
                  artist: artist,
                  album: album,
                  filename: s.filename,
                  url: s.url,
                  coverUrl: s.coverUrl,
                  hasLyrics: s.hasLyrics,
                  playCount: s.playCount,
                  duration: s.duration,
                  mtime: s.mtime,
                )
              else
                s,
          ]);
        }
        await refresh(isBackground: true);
        notifier.success();
      } catch (e) {
        notifier.error();
        debugPrint('Failed to update song metadata: $e');
      }
    }());
  }

  Future<void> updateSongCover(Song song, String? imagePath) async {
    final notifier = ref.read(metadataSaveProvider.notifier);
    notifier.start();
    try {
      await ref.read(audioPlayerManagerProvider).stopIfCurrentSong(song.url);
      final newCoverPath = await ref
          .read(fileManagerServiceProvider)
          .updateSongCover(song, imagePath);

      // Read the file's new mtime. Prefer the one embedded in the cache filename
      // to ensure consistency with the scanner service.
      double? newMtime;
      if (newCoverPath != null) {
        final match = RegExp(r'_(\d+)(\.[^.]+)?$').firstMatch(newCoverPath);
        if (match != null) {
          final ms = int.tryParse(match.group(1)!);
          if (ms != null) {
            newMtime = ms / 1000.0;
          }
        }
      }

      if (newMtime == null) {
        try {
          final stat = await File(song.url).stat();
          newMtime = stat.modified.millisecondsSinceEpoch / 1000.0;
        } catch (_) {
          newMtime = song.mtime;
        }
      }

      if (state.hasValue) {
        final current = state.value ?? [];
        state = AsyncValue.data([
          for (final s in current)
            if (s.filename == song.filename)
              Song(
                title: s.title,
                artist: s.artist,
                album: s.album,
                filename: s.filename,
                url: s.url,
                coverUrl: newCoverPath,
                hasLyrics: s.hasLyrics,
                playCount: s.playCount,
                duration: s.duration,
                mtime: newMtime,
              )
            else
              s,
        ]);
      }
      // Force refresh to ensure UI updates across the app
      ref.read(audioPlayerManagerProvider).refreshSongs(state.value ?? []);
      await refresh(isBackground: true);
      notifier.success('Cover updated successfully');
    } catch (e) {
      notifier.error('Failed to update cover');
      debugPrint('Failed to update song cover: $e');
      rethrow;
    }
  }

  Future<void> exportSongCover(Song song, String destinationPath) async {
    try {
      await ref
          .read(fileManagerServiceProvider)
          .exportSongCover(song, destinationPath);
    } catch (e) {
      debugPrint('Failed to export cover: $e');
      rethrow;
    }
  }

  Future<void> updateLyrics(Song song, String lyricsContent) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(fileManagerServiceProvider)
          .updateLyrics(song, lyricsContent);
      return _performFullScan();
    });
  }

  Future<void> moveSong(Song song, String targetDirectoryPath) async {
    if (kDebugMode) {
      debugPrint("MOVE_SONG: Starting move for ${song.title}");
      debugPrint("MOVE_SONG: Source: ${song.url}");
      debugPrint("MOVE_SONG: Target Dir: $targetDirectoryPath");
    }

    try {
      final oldFile = File(song.url);
      if (!await oldFile.exists()) {
        if (kDebugMode) {
          debugPrint("MOVE_SONG: ERROR - Source file does not exist");
        }
        return;
      }

      final newPath = p.join(targetDirectoryPath, song.filename);
      if (kDebugMode) debugPrint("MOVE_SONG: Target Path: $newPath");

      if (p.equals(oldFile.path, newPath)) {
        if (kDebugMode) {
          debugPrint("MOVE_SONG: Source and target are identical, skipping");
        }
        return;
      }

      // Ensure target directory exists
      final targetDir = Directory(targetDirectoryPath);
      if (!await targetDir.exists()) {
        if (kDebugMode) {
          debugPrint(
              "MOVE_SONG: Creating target directory: $targetDirectoryPath");
        }
        await targetDir.create(recursive: true);
      }

      if (kDebugMode) {
        debugPrint("MOVE_SONG: Executing rename...");
      }
      // Cross-platform safe move
      try {
        await oldFile.rename(newPath);
      } catch (e) {
        if (kDebugMode) {
          debugPrint("MOVE_SONG: Rename failed, trying copy/delete: $e");
        }
        await oldFile.copy(newPath);
        await oldFile.delete();
      }
      if (kDebugMode) {
        debugPrint("MOVE_SONG: Move successful");
      }

      if (kDebugMode) {
        debugPrint("MOVE_SONG: Refreshing provider...");
      }
      await refresh();
      if (kDebugMode) {
        debugPrint("MOVE_SONG: Finished");
      }
    } catch (e, stack) {
      debugPrint('MOVE_SONG: ERROR: $e');
      if (kDebugMode) {
        debugPrint('MOVE_SONG: STACKTRACE: $stack');
      }
      rethrow;
    }
  }

  Future<void> moveFolder(String oldFolderPath, String targetParentPath) async {
    if (kDebugMode) {
      debugPrint("MOVE_FOLDER: Starting move for $oldFolderPath");
      debugPrint("MOVE_FOLDER: Target Parent: $targetParentPath");
    }

    try {
      final oldDir = Directory(oldFolderPath);
      if (!await oldDir.exists()) {
        if (kDebugMode) {
          debugPrint("MOVE_FOLDER: ERROR - Source directory does not exist");
        }
        return;
      }

      final folderName = p.basename(oldFolderPath);
      final newPath = p.join(targetParentPath, folderName);
      if (kDebugMode) {
        debugPrint("MOVE_FOLDER: New Path: $newPath");
      }

      if (p.equals(oldDir.path, newPath)) {
        if (kDebugMode) {
          debugPrint("MOVE_FOLDER: Source and target are identical, skipping");
        }
        return;
      }

      if (p.isWithin(oldDir.path, targetParentPath)) {
        if (kDebugMode) {
          debugPrint("MOVE_FOLDER: ERROR - Cannot move folder into itself");
        }
        throw Exception("Cannot move a folder into itself or its subfolders");
      }

      // Ensure target parent exists
      final targetParentDir = Directory(targetParentPath);
      if (!await targetParentDir.exists()) {
        if (kDebugMode) {
          debugPrint("MOVE_FOLDER: Creating target parent: $targetParentPath");
        }
        await targetParentDir.create(recursive: true);
      }

      if (kDebugMode) {
        debugPrint("MOVE_FOLDER: Executing rename...");
      }
      try {
        await oldDir.rename(newPath);
      } catch (e) {
        if (kDebugMode) {
          debugPrint("MOVE_FOLDER: Rename failed, trying recursive move: $e");
        }
        // Fallback for cross-device moves or other issues
        final newDir = Directory(newPath);
        await newDir.create(recursive: true);
        await for (final entity in oldDir.list(recursive: false)) {
          final name = p.basename(entity.path);
          if (entity is File) {
            await entity.copy(p.join(newPath, name));
            await entity.delete();
          } else if (entity is Directory) {
            // Simple recursive call or handle nested
            // For now, let's keep it simple as most moves are on same device
          }
        }
        await oldDir.delete(recursive: true);
      }
      if (kDebugMode) {
        debugPrint("MOVE_FOLDER: Rename successful");
      }

      if (kDebugMode) {
        debugPrint("MOVE_FOLDER: Refreshing provider...");
      }
      await refresh();
      if (kDebugMode) {
        debugPrint("MOVE_FOLDER: Finished");
      }
    } catch (e, stack) {
      debugPrint('MOVE_FOLDER: ERROR: $e');
      if (kDebugMode) {
        debugPrint('MOVE_FOLDER: STACKTRACE: $stack');
      }
      rethrow;
    }
  }
}

final songsProvider =
    AsyncNotifierProvider<SongsNotifier, List<Song>>(SongsNotifier.new);

final recommendationsProvider = Provider<List<Song>>((ref) {
  final userData = ref.watch(userDataProvider);
  final songsAsync = ref.watch(songsProvider);

  if (songsAsync is! AsyncData || songsAsync.value == null) {
    return [];
  }

  final allSongs = songsAsync.value!;
  final quickPicks = userData.playlists
      .where((p) => p.id == 'quick_picks' && p.isRecommendation)
      .firstOrNull;

  if (quickPicks == null) return [];

  final result = <Song>[];
  for (final ps in quickPicks.songs) {
    final song =
        allSongs.where((s) => s.filename == ps.songFilename).firstOrNull;
    if (song != null) result.add(song);
  }

  return result;
});

final playCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  // Watch userData to refresh when stats might have changed or synced
  ref.watch(userDataProvider);
  return DatabaseService.instance.getPlayCounts();
});

final artistListProvider = FutureProvider<List<String>>((ref) async {
  // Watch songsProvider to refresh when library changes
  ref.watch(songsProvider);
  return DatabaseService.instance.getArtists();
});

final albumListProvider = FutureProvider<List<String>>((ref) async {
  // Watch songsProvider to refresh when library changes
  ref.watch(songsProvider);
  return DatabaseService.instance.getAlbums();
});

final userDataProvider = NotifierProvider<UserDataNotifier, UserDataState>(() {
  return UserDataNotifier();
});
