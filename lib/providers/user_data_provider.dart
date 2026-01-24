import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'auth_provider.dart';
import 'providers.dart';
import 'theme_provider.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/storage_service.dart';

class UserDataState {
  final List<String> favorites;
  final List<String> suggestLess;
  final List<String> hidden;
  final bool isLoading;

  // Optimized lookup sets
  final Set<String> _favSet;
  final Set<String> _favBasenameSet;
  final Set<String> _slSet;
  final Set<String> _slBasenameSet;
  final Set<String> _hiddenSet;
  final Set<String> _hiddenBasenameSet;

  UserDataState({
    this.favorites = const [],
    this.suggestLess = const [],
    this.hidden = const [],
    this.isLoading = false,
  })  : _favSet = favorites.map((e) => e.toLowerCase()).toSet(),
        _favBasenameSet =
            favorites.map((e) => p.basename(e).toLowerCase()).toSet(),
        _slSet = suggestLess.map((e) => e.toLowerCase()).toSet(),
        _slBasenameSet =
            suggestLess.map((e) => p.basename(e).toLowerCase()).toSet(),
        _hiddenSet = hidden.map((e) => e.toLowerCase()).toSet(),
        _hiddenBasenameSet =
            hidden.map((e) => p.basename(e).toLowerCase()).toSet();

  bool isFavorite(String filename) {
    final lowerFilename = filename.toLowerCase();
    if (_favSet.contains(lowerFilename)) return true;
    final searchBasename = p.basename(lowerFilename);
    return _favBasenameSet.contains(searchBasename);
  }

  bool isSuggestLess(String filename) {
    final lowerFilename = filename.toLowerCase();
    if (_slSet.contains(lowerFilename)) return true;
    final searchBasename = p.basename(lowerFilename);
    return _slBasenameSet.contains(searchBasename);
  }

  bool isHidden(String filename) {
    final lowerFilename = filename.toLowerCase();
    if (_hiddenSet.contains(lowerFilename)) return true;
    final searchBasename = p.basename(lowerFilename);
    return _hiddenBasenameSet.contains(searchBasename);
  }

  UserDataState copyWith({
    List<String>? favorites,
    List<String>? suggestLess,
    List<String>? hidden,
    bool? isLoading,
  }) {
    return UserDataState(
      favorites: favorites ?? this.favorites,
      suggestLess: suggestLess ?? this.suggestLess,
      hidden: hidden ?? this.hidden,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// UserDataNotifier implements proper bidirectional sync:
///
/// SYNC PHILOSOPHY:
/// 1. Server is SOURCE OF TRUTH for favorites/suggestLess
/// 2. On startup: Fetch server data -> Merge with local -> Update server with any local additions
/// 3. On add/remove: Update local immediately -> Call server API -> Refresh from server
/// 4. Never blindly overwrite server data
class UserDataNotifier extends Notifier<UserDataState> {
  String? _username;
  bool _initialized = false;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;

  @override
  UserDataState build() {
    final authState = ref.watch(authProvider);
    final newUsername = authState.username;

    if (newUsername != null) {
      if (!_initialized || newUsername != _username) {
        _username = newUsername;
        _initialized = true;
        Future.microtask(() => _initAndSync());
        return UserDataState(isLoading: true);
      }
      return state;
    } else {
      _username = null;
      _initialized = false;
      return UserDataState();
    }
  }

  Future<void> _initAndSync() async {
    if (_username == null) return;

    // 1. Initialize local database
    await DatabaseService.instance.initForUser(_username!);

    // 2. Load from local cache first (instant UI)
    try {
      final localFavs = await DatabaseService.instance.getFavorites();
      final localSL = await DatabaseService.instance.getSuggestLess();
      final localHidden = await DatabaseService.instance.getHidden();

      state = state.copyWith(
        favorites: localFavs,
        suggestLess: localSL,
        hidden: localHidden,
        isLoading: false,
      );
      _updateManager();

      final isLocalMode = await StorageService().getIsLocalMode();
      if (!isLocalMode) {
        ref
            .read(syncProvider.notifier)
            .updateTask('userData', SyncStatus.usingCache);
      }
    } catch (e) {
      debugPrint('Error loading local user data: $e');
    }

    // 3. Perform proper sync with server (DEFERRED to allow instant startup)
    Future.delayed(const Duration(seconds: 2), () => _syncWithServer());
  }

  void _updateManager() {
    ref.read(audioPlayerManagerProvider).setUserData(
          favorites: state.favorites,
          suggestLess: state.suggestLess,
          hidden: state.hidden,
        );
  }

  /// Proper bidirectional sync:
  /// 1. Fetch server state (source of truth)
  /// 2. Find local-only additions
  /// 3. Push local additions to server via API calls
  /// 4. Update local cache with server state
  Future<void> _syncWithServer() async {
    if (_username == null) return;
    if (await StorageService().getIsLocalMode()) {
      debugPrint('UserData: Local mode enabled, skipping server sync');
      return;
    }

    if (_isSyncing) {
      debugPrint('UserData sync already in progress, skipping');
      return;
    }

    final syncNotifier = ref.read(syncProvider.notifier);
    final service = ref.read(userDataServiceProvider);

    try {
      _isSyncing = true;
      syncNotifier.updateTask('userData', SyncStatus.syncing);
      _lastSyncTime = DateTime.now();

      // 1. Get current local state BEFORE fetching server
      final localFavs =
          Set<String>.from(await DatabaseService.instance.getFavorites());
      final localSL =
          Set<String>.from(await DatabaseService.instance.getSuggestLess());
      final localHidden =
          Set<String>.from(await DatabaseService.instance.getHidden());

      // 2. Fetch server state (source of truth)
      final serverData = await service.getUserData(_username!);
      final serverFavs = Set<String>.from(serverData['favorites'] ?? []);
      final serverSL = Set<String>.from(serverData['suggestLess'] ?? []);
      final serverHidden = Set<String>.from(serverData['hidden'] ?? []);

      // Theme Sync Logic
      final localThemeState = ref.read(themeProvider);
      final serverThemeModeStr = serverData['themeMode'] as String?;
      final serverSyncTheme = serverData['syncTheme'] as bool? ?? false;

      if (localThemeState.syncTheme) {
        // Local wants to sync.
        if (serverSyncTheme) {
          // Both want to sync. Check if local is newer or server is newer.
          // For simplicity, we'll assume the server is the truth for Pull,
          // but we push if we have a change that wasn't synced.
          if (serverThemeModeStr != null &&
              serverThemeModeStr != localThemeState.mode.toString()) {
            final remoteMode = GruThemeMode.values.firstWhere(
              (e) => e.toString() == serverThemeModeStr,
              orElse: () => GruThemeMode.classic,
            );
            ref.read(themeProvider.notifier).updateFromSync(remoteMode, true);
            debugPrint('Sync: Updated local theme from server: $remoteMode');
          }
        } else {
          // Server doesn't have sync enabled yet. Push local settings.
          await service.updateUserData(_username!, {
            'themeMode': localThemeState.mode.toString(),
            'syncTheme': true,
          });
          debugPrint('Sync: Pushed local theme settings to server');
        }
      } else if (serverSyncTheme) {
        // Server has sync enabled, but local doesn't.
        // This usually means a new device or user just enabled it elsewhere.
        // We follow the server.
        final remoteMode = GruThemeMode.values.firstWhere(
          (e) => e.toString() == serverThemeModeStr,
          orElse: () => GruThemeMode.classic,
        );
        ref.read(themeProvider.notifier).updateFromSync(remoteMode, true);
        debugPrint('Sync: Enabled theme sync from server: $remoteMode');
      }

      debugPrint(
          'Sync: Server has ${serverFavs.length} favorites, local has ${localFavs.length}');
      debugPrint(
          'Sync: Server has ${serverSL.length} suggestLess, local has ${localSL.length}');
      debugPrint(
          'Sync: Server has ${serverHidden.length} hidden, local has ${localHidden.length}');

      // 3. Find local-only additions (items in local but not in server)
      //    These need to be pushed TO the server
      final localOnlyFavs = localFavs.difference(serverFavs);
      final localOnlySL = localSL.difference(serverSL);
      final localOnlyHidden = localHidden.difference(serverHidden);

      // 4. Push local additions to server via individual API calls
      for (final filename in localOnlyFavs) {
        try {
          await service.addFavorite(_username!, filename, 'sync');
          debugPrint('Sync: Pushed local favorite to server: $filename');
        } catch (e) {
          debugPrint('Sync: Failed to push favorite $filename: $e');
        }
      }

      for (final filename in localOnlySL) {
        try {
          await service.addSuggestLess(_username!, filename);
          debugPrint('Sync: Pushed local suggestLess to server: $filename');
        } catch (e) {
          debugPrint('Sync: Failed to push suggestLess $filename: $e');
        }
      }

      for (final filename in localOnlyHidden) {
        try {
          await service.addHidden(_username!, filename);
          debugPrint('Sync: Pushed local hidden to server: $filename');
        } catch (e) {
          debugPrint('Sync: Failed to push hidden $filename: $e');
        }
      }

      // 5. Merge: Final state = Server state + Local additions
      final mergedFavs = serverFavs.union(localOnlyFavs).toList();
      final mergedSL = serverSL.union(localOnlySL).toList();
      final mergedHidden = serverHidden.union(localOnlyHidden).toList();

      // 6. Update local cache with merged state
      await DatabaseService.instance.setFavorites(mergedFavs);
      await DatabaseService.instance.setSuggestLess(mergedSL);
      await DatabaseService.instance.setHidden(mergedHidden);

      // 7. Download stats DB for local viewing (read-only sync)
      await DatabaseService.instance.downloadStatsFromServer(_username!);
      await DatabaseService.instance.downloadFinalStatsFromServer(_username!);

      // 8. Update UI state
      state = state.copyWith(
        favorites: mergedFavs,
        suggestLess: mergedSL,
        hidden: mergedHidden,
        isLoading: false,
      );
      _updateManager();

      syncNotifier.updateTask('userData', SyncStatus.upToDate);
      debugPrint(
          'Sync complete: ${mergedFavs.length} favorites, ${mergedSL.length} suggestLess, ${mergedHidden.length} hidden');
    } catch (e) {
      debugPrint('Sync with server failed: $e');
      syncNotifier.setError();
    } finally {
      _isSyncing = false;
    }
  }

  /// Manual refresh triggered by pull-to-refresh or background events
  Future<void> refresh({bool force = true}) async {
    if (_username == null) return;

    if (!force && _lastSyncTime != null) {
      final diff = DateTime.now().difference(_lastSyncTime!);
      if (diff.inSeconds < 60) {
        debugPrint(
            'UserData sync throttled (last sync ${diff.inSeconds}s ago)');
        return;
      }
    }

    if (force) {
      state = state.copyWith(isLoading: true);
    }
    await _syncWithServer();
  }

  /// Toggle favorite with proper sync:
  /// 1. Update local immediately (optimistic)
  /// 2. Call server API
  /// 3. On failure, rollback local change
  Future<void> toggleFavorite(String songFilename) async {
    if (_username == null) return;

    final service = ref.read(userDataServiceProvider);
    final isFav = state.isFavorite(songFilename);
    final isSL = state.isSuggestLess(songFilename);

    // Find actual match in list (for case-insensitive scenarios)
    String actualFilename = songFilename;
    if (isFav) {
      actualFilename = state.favorites.firstWhere(
        (f) =>
            f.toLowerCase() == songFilename.toLowerCase() ||
            p.basename(f).toLowerCase() ==
                p.basename(songFilename).toLowerCase(),
        orElse: () => songFilename,
      );
    }

    // 1. Optimistic local update
    final newFavs = List<String>.from(state.favorites);
    final newSL = List<String>.from(state.suggestLess);

    if (isFav) {
      newFavs.remove(actualFilename);
      await DatabaseService.instance.removeFavorite(actualFilename);
    } else {
      newFavs.add(songFilename);
      await DatabaseService.instance.addFavorite(songFilename);

      // Remove from suggestLess if present
      if (isSL) {
        final actualSLMatch = state.suggestLess.firstWhere(
          (sl) =>
              sl.toLowerCase() == songFilename.toLowerCase() ||
              p.basename(sl).toLowerCase() ==
                  p.basename(songFilename).toLowerCase(),
          orElse: () => songFilename,
        );
        newSL.remove(actualSLMatch);
        await DatabaseService.instance.removeSuggestLess(actualSLMatch);
      }
    }

    state = state.copyWith(favorites: newFavs, suggestLess: newSL);
    _updateManager();

    // 2. Call server API
    if (await StorageService().getIsLocalMode()) return;
    try {
      if (isFav) {
        await service.removeFavorite(_username!, actualFilename);
        debugPrint('Removed favorite from server: $actualFilename');
      } else {
        await service.addFavorite(_username!, songFilename, 'user_action');
        debugPrint('Added favorite to server: $songFilename');

        if (isSL) {
          final actualSLMatch = state.suggestLess.firstWhere(
            (sl) =>
                sl.toLowerCase() == songFilename.toLowerCase() ||
                p.basename(sl).toLowerCase() ==
                    p.basename(songFilename).toLowerCase(),
            orElse: () => songFilename,
          );
          await service.removeSuggestLess(_username!, actualSLMatch);
        }
      }
    } catch (e) {
      debugPrint('Server API call failed (offline?): $e');
      // Local change is kept - will sync on next startup
    }
  }

  /// Toggle suggestLess with proper sync
  Future<void> toggleSuggestLess(String songFilename) async {
    if (_username == null) return;

    final service = ref.read(userDataServiceProvider);
    final isSL = state.isSuggestLess(songFilename);

    // Find actual match
    String actualFilename = songFilename;
    if (isSL) {
      actualFilename = state.suggestLess.firstWhere(
        (sl) =>
            sl.toLowerCase() == songFilename.toLowerCase() ||
            p.basename(sl).toLowerCase() ==
                p.basename(songFilename).toLowerCase(),
        orElse: () => songFilename,
      );
    }

    // 1. Optimistic local update
    final newSL = List<String>.from(state.suggestLess);

    if (isSL) {
      newSL.remove(actualFilename);
      await DatabaseService.instance.removeSuggestLess(actualFilename);
    } else {
      newSL.add(songFilename);
      await DatabaseService.instance.addSuggestLess(songFilename);
    }

    state = state.copyWith(suggestLess: newSL);
    _updateManager();

    // 2. Call server API
    if (await StorageService().getIsLocalMode()) return;
    try {
      if (isSL) {
        await service.removeSuggestLess(_username!, actualFilename);
        debugPrint('Removed suggestLess from server: $actualFilename');
      } else {
        await service.addSuggestLess(_username!, songFilename);
        debugPrint('Added suggestLess to server: $songFilename');
      }
    } catch (e) {
      debugPrint('Server API call failed (offline?): $e');
    }
  }

  /// Toggle hidden with proper sync
  Future<void> toggleHidden(String songFilename) async {
    if (_username == null) return;

    final service = ref.read(userDataServiceProvider);
    final isHidden = state.isHidden(songFilename);

    // Find actual match
    String actualFilename = songFilename;
    if (isHidden) {
      actualFilename = state.hidden.firstWhere(
        (h) =>
            h.toLowerCase() == songFilename.toLowerCase() ||
            p.basename(h).toLowerCase() ==
                p.basename(songFilename).toLowerCase(),
        orElse: () => songFilename,
      );
    }

    // 1. Optimistic local update
    final newHidden = List<String>.from(state.hidden);

    if (isHidden) {
      newHidden.remove(actualFilename);
      await DatabaseService.instance.removeHidden(actualFilename);
    } else {
      newHidden.add(songFilename);
      await DatabaseService.instance.addHidden(songFilename);
    }

    state = state.copyWith(hidden: newHidden);
    _updateManager();

    // 2. Call server API
    if (await StorageService().getIsLocalMode()) return;
    try {
      if (isHidden) {
        await service.removeHidden(_username!, actualFilename);
        debugPrint('Removed hidden from server: $actualFilename');
      } else {
        await service.addHidden(_username!, songFilename);
        debugPrint('Added hidden to server: $songFilename');
      }
    } catch (e) {
      debugPrint('Server API call failed (offline?): $e');
    }
  }
}
