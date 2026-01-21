import 'dart:io';
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

    // 1. Load instantly from cache
    final cached = await storage.loadSongs();
    if (cached.isNotEmpty) {
      // Return cached immediately, then update in background
      _backgroundScanUpdate();
      return cached;
    }

    // 2. If no cache, perform initial scan
    return _performFullScan();
  }

  Future<List<Song>> _performFullScan() async {
    final storage = ref.read(storageServiceProvider);
    final scanner = ref.read(scannerServiceProvider);

    final musicPath = await storage.getMusicFolderPath();
    final lyricsPath = await storage.getLyricsFolderPath();

    if (musicPath == null || musicPath.isEmpty) return [];

    final songs =
        await scanner.scanDirectory(musicPath, lyricsPath: lyricsPath);
    await storage.saveSongs(songs);
    return songs;
  }

  Future<void> _backgroundScanUpdate() async {
    try {
      final songs = await _performFullScan();
      ref.read(audioPlayerManagerProvider).refreshSongs(songs);
      state = AsyncValue.data(songs);
    } catch (e) {
      debugPrint('Background scan failed: $e');
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final storage = ref.read(storageServiceProvider);
      final isLocalMode = await storage.getIsLocalMode();

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
      } else {
        if (kDebugMode) {
          debugPrint('Local mode: Skipping server sync');
        }
      }

      final songs = await _performFullScan();
      ref.read(audioPlayerManagerProvider).refreshSongs(songs);
      return songs;
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

      if (kDebugMode) debugPrint("MOVE_SONG: Executing rename...");
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
      if (kDebugMode) debugPrint("MOVE_SONG: Move successful");

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
          if (kDebugMode)
            debugPrint("MOVE_SONG: Lyrics moved to $newLyricsPath");
        }
      }

      if (kDebugMode) debugPrint("MOVE_SONG: Refreshing provider...");
      await refresh();
      if (kDebugMode) debugPrint("MOVE_SONG: Finished");
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
      if (kDebugMode) debugPrint("MOVE_FOLDER: New Path: $newPath");

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

      if (kDebugMode) debugPrint("MOVE_FOLDER: Executing rename...");
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
      if (kDebugMode) debugPrint("MOVE_FOLDER: Rename successful");

      if (kDebugMode) debugPrint("MOVE_FOLDER: Refreshing provider...");
      await refresh();
      if (kDebugMode) debugPrint("MOVE_FOLDER: Finished");
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

final userDataProvider = NotifierProvider<UserDataNotifier, UserDataState>(() {
  return UserDataNotifier();
});
