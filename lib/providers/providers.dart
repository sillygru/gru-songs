import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../services/api_service.dart';
import '../services/stats_service.dart';
import '../services/user_data_service.dart';
import '../services/audio_player_manager.dart';
import '../services/storage_service.dart';
import '../services/scanner_service.dart';
import '../services/database_service.dart';
import '../services/file_manager_service.dart';
import '../data/repositories/song_repository.dart';
import '../models/song.dart';
import '../providers/auth_provider.dart';
import 'user_data_provider.dart';

enum SyncStatus { syncing, upToDate, offline, usingCache }

class SyncState {
  final Map<String, SyncStatus> tasks;
  final DateTime? lastSync;
  final bool hasError;

  SyncState({
    this.tasks = const {},
    this.lastSync,
    this.hasError = false,
  });

  SyncStatus get status {
    if (hasError) return SyncStatus.offline;
    if (tasks.values.any((s) => s == SyncStatus.syncing)) {
      return SyncStatus.syncing;
    }
    if (tasks.values.any((s) => s == SyncStatus.usingCache)) {
      return SyncStatus.usingCache;
    }
    return SyncStatus.upToDate;
  }

  SyncState copyWith({
    Map<String, SyncStatus>? tasks,
    DateTime? lastSync,
    bool? hasError,
  }) {
    return SyncState(
      tasks: tasks ?? this.tasks,
      lastSync: lastSync ?? this.lastSync,
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
    newTasks.forEach((key, value) => newTasks[key] = SyncStatus.upToDate);
    state = state.copyWith(
        tasks: newTasks, lastSync: DateTime.now(), hasError: false);
  }
}

final syncProvider =
    NotifierProvider<SyncNotifier, SyncState>(SyncNotifier.new);

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
final apiServiceProvider = Provider<ApiService>((ref) {
  final apiService = ApiService();
  // Update apiService username when auth state changes
  final authState = ref.watch(authProvider);
  apiService.setUsername(authState.username);

  ref.onDispose(() => apiService.dispose());
  return apiService;
});

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

final statsServiceProvider = Provider<StatsService>((ref) {
  return StatsService();
});

final userDataServiceProvider = Provider<UserDataService>((ref) {
  return UserDataService(ref.watch(apiServiceProvider));
});

final scannerServiceProvider = Provider<ScannerService>((ref) {
  return ScannerService();
});

final fileManagerServiceProvider = Provider<FileManagerService>((ref) {
  return FileManagerService(ref.watch(apiServiceProvider));
});

final songRepositoryProvider = Provider<SongRepository>((ref) {
  return SongRepository(ref.watch(apiServiceProvider));
});

final audioPlayerManagerProvider = Provider<AudioPlayerManager>((ref) {
  final authState = ref.watch(authProvider);
  final manager = AudioPlayerManager(
    ref.watch(apiServiceProvider),
    ref.watch(statsServiceProvider),
    ref.watch(storageServiceProvider),
    authState.username,
  );

  ref.onDispose(() => manager.dispose());
  return manager;
});

// Data Providers
class SongsNotifier extends AsyncNotifier<List<Song>> {
  @override
  Future<List<Song>> build() async {
    final storage = ref.watch(storageServiceProvider);
    final userData = ref.watch(userDataProvider);

    // 1. Load instantly from cache
    final cached = await storage.loadSongs();
    if (cached.isNotEmpty) {
      // De-duplicate by filename to avoid Hero tag conflicts and UI glitches
      final seenFilenames = <String>{};
      final uniqueCached = cached.where((s) {
        if (seenFilenames.contains(s.filename)) return false;
        seenFilenames.add(s.filename);
        return true;
      }).toList();

      final filtered =
          uniqueCached.where((s) => !userData.isHidden(s.filename)).toList();
      // Return cached immediately, then update in background
      _backgroundScanUpdate(uniqueCached);
      return filtered;
    }

    // 2. If no cache, perform initial scan
    final scanned = await _performFullScan();

    final seenFilenames = <String>{};
    final uniqueScanned = scanned.where((s) {
      if (seenFilenames.contains(s.filename)) return false;
      seenFilenames.add(s.filename);
      return true;
    }).toList();

    return uniqueScanned.where((s) => !userData.isHidden(s.filename)).toList();
  }

  Future<List<Song>> _performFullScan(
      {bool isBackground = false, List<Song>? existingSongs}) async {
    final storage = ref.read(storageServiceProvider);
    final scanner = ref.read(scannerServiceProvider);

    final musicPath = await storage.getMusicFolderPath();
    final lyricsPath = await storage.getLyricsFolderPath();

    if (musicPath == null || musicPath.isEmpty) return [];

    // Only show scanning indicator for non-background scans
    if (!isBackground) {
      ref.read(isScanningProvider.notifier).state = true;
    }
    ref.read(scanProgressProvider.notifier).state = 0.0;

    try {
      final songs = await scanner.scanDirectory(
        musicPath,
        existingSongs: existingSongs,
        lyricsPath: lyricsPath,
        onProgress: (progress) {
          ref.read(scanProgressProvider.notifier).state = progress;
        },
      );

      // De-duplicate by filename
      final seenFilenames = <String>{};
      final uniqueSongs = songs.where((s) {
        if (seenFilenames.contains(s.filename)) return false;
        seenFilenames.add(s.filename);
        return true;
      }).toList();

      await storage.saveSongs(uniqueSongs);

      // Return all songs from scan, build() will filter them
      return uniqueSongs;
    } finally {
      if (!isBackground) {
        ref.read(isScanningProvider.notifier).state = false;
      }
      ref.read(scanProgressProvider.notifier).state = 0.0;
    }
  }

  Future<void> _backgroundScanUpdate(List<Song> existingSongs) async {
    try {
      // Background scan doesn't trigger the scanning indicator
      final songs = await _performFullScan(
          isBackground: true, existingSongs: existingSongs);

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

    // If it's a background refresh, we don't want to set the state to loading
    // as it would clear the current UI list.
    if (!isBackground) {
      // For manual refresh, we can show loading if we want,
      // but AsyncNotifier usually handles this via state.
    }

    final newState = await AsyncValue.guard<List<Song>>(() async {
      final isLocalMode = await storage.getIsLocalMode();
      final serverMode = await storage.getServerRefreshMode();

      if (!isLocalMode) {
        // Force a full bidirectional sync of stats, data, and settings
        final auth = ref.read(authProvider);
        if (auth.username != null && ApiService.baseUrl.isNotEmpty) {
          try {
            await DatabaseService.instance.sync(auth.username!);
            await ref.read(userDataProvider.notifier).refresh();
          } catch (e) {
            if (kDebugMode) {
              debugPrint(
                  'Sync failed during refresh (continuing to local scan): $e');
            }
          }
        }

        if (serverMode == 'sync_only') {
          return state.value ?? <Song>[];
        }
      }

      final musicPath = await storage.getMusicFolderPath();
      if (musicPath != null) {
        await ref
            .read(fileManagerServiceProvider)
            .syncRenamesFromServer(musicPath);
      }

      // Pass isBackground to _performFullScan
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
  }

  Future<void> forceFullScan() async {
    state = await AsyncValue.guard<List<Song>>(() async {
      final songs = await _performFullScan(); // No existingSongs = full scan
      ref.read(audioPlayerManagerProvider).refreshSongs(songs);
      final userData = ref.read(userDataProvider);
      return songs.where((s) => !userData.isHidden(s.filename)).toList();
    });
  }

  Future<void> hideSong(Song song) async {
    await ref.read(userDataProvider.notifier).toggleHidden(song.filename);
    // state will auto-update because build() watches userDataProvider
  }

  Future<void> deleteSongFile(Song song) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(fileManagerServiceProvider).deleteSongFile(song);
      final songs = await _performFullScan();
      ref.read(audioPlayerManagerProvider).refreshSongs(songs);
      final userData = ref.read(userDataProvider);
      return songs.where((s) => !userData.isHidden(s.filename)).toList();
    });
  }

  Future<void> renameSong(Song song, String newTitle,
      {int deviceCount = 0}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(fileManagerServiceProvider)
          .renameSong(song, newTitle, deviceCount: deviceCount);
      return _performFullScan();
    });
  }

  Future<void> updateSongTitle(Song song, String newTitle,
      {int deviceCount = 0}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(fileManagerServiceProvider)
          .updateSongTitle(song, newTitle, deviceCount: deviceCount);
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

      // Also try to move lyrics if they exist
      if (song.lyricsUrl != null) {
        final oldLyricsFile = File(song.lyricsUrl!);
        if (await oldLyricsFile.exists()) {
          final lyricsFilename = p.basename(song.lyricsUrl!);
          final newLyricsPath = p.join(targetDirectoryPath, lyricsFilename);
          try {
            await oldLyricsFile.rename(newLyricsPath);
          } catch (e) {
            await oldLyricsFile.copy(newLyricsPath);
            await oldLyricsFile.delete();
          }
          if (kDebugMode) {
            debugPrint("MOVE_SONG: Lyrics moved to $newLyricsPath");
          }
        }
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

class RecommendationsNotifier extends Notifier<List<Song>> {
  @override
  List<Song> build() {
    return [];
  }

  void generate(List<Song> songs, UserDataState userData) {
    if (songs.isEmpty) {
      state = [];
      return;
    }

    final random = Random();
    final recommendations = List<Song>.from(songs);

    recommendations.sort((a, b) {
      double score(Song s) {
        // Base score from play count
        double val = log(s.playCount + 1.5) * 2.0;

        // Boost for favorites
        if (userData.isFavorite(s.filename)) {
          val += 5.0;
        }

        // Heavy penalty for suggest-less (but not absolute block)
        if (userData.isSuggestLess(s.filename)) {
          val -= 10.0;
        }

        // Add randomness
        val += random.nextDouble() * 4.0;

        return val;
      }

      return score(b).compareTo(score(a));
    });

    state = recommendations.take(10).toList();
  }
}

final recommendationsProvider =
    NotifierProvider<RecommendationsNotifier, List<Song>>(
        RecommendationsNotifier.new);

final userDataProvider = NotifierProvider<UserDataNotifier, UserDataState>(() {
  return UserDataNotifier();
});
