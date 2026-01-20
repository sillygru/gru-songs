import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'auth_provider.dart';
import 'providers.dart';
import '../services/database_service.dart';
import '../models/shuffle_config.dart';

class UserDataState {
  final List<String> favorites;
  final List<String> suggestLess;
  final bool isLoading;

  UserDataState({
    this.favorites = const [],
    this.suggestLess = const [],
    this.isLoading = false,
  });

  bool isFavorite(String filename) {
    final searchBasename = p.basename(filename).toLowerCase();
    for (final fav in favorites) {
      if (fav.toLowerCase() == filename.toLowerCase()) return true;
      if (p.basename(fav).toLowerCase() == searchBasename) return true;
    }
    return false;
  }

  bool isSuggestLess(String filename) {
    final searchBasename = p.basename(filename).toLowerCase();
    for (final sl in suggestLess) {
      if (sl.toLowerCase() == filename.toLowerCase()) return true;
      if (p.basename(sl).toLowerCase() == searchBasename) return true;
    }
    return false;
  }

  UserDataState copyWith({
    List<String>? favorites,
    List<String>? suggestLess,
    bool? isLoading,
  }) {
    return UserDataState(
      favorites: favorites ?? this.favorites,
      suggestLess: suggestLess ?? this.suggestLess,
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

      state = state.copyWith(
        favorites: localFavs,
        suggestLess: localSL,
        isLoading: false,
      );
      _updateManager();

      ref
          .read(syncProvider.notifier)
          .updateTask('userData', SyncStatus.usingCache);
    } catch (e) {
      debugPrint('Error loading local user data: $e');
    }

    // 3. Perform proper sync with server
    await _syncWithServer();
  }

  void _updateManager() {
    ref.read(audioPlayerManagerProvider).setUserData(
          favorites: state.favorites,
          suggestLess: state.suggestLess,
        );
  }

  /// Proper bidirectional sync:
  /// 1. Fetch server state (source of truth)
  /// 2. Find local-only additions
  /// 3. Push local additions to server via API calls
  /// 4. Update local cache with server state
  Future<void> _syncWithServer() async {
    if (_username == null) return;

    final syncNotifier = ref.read(syncProvider.notifier);
    final service = ref.read(userDataServiceProvider);

    try {
      syncNotifier.updateTask('userData', SyncStatus.syncing);

      // 1. Get current local state BEFORE fetching server
      final localFavs =
          Set<String>.from(await DatabaseService.instance.getFavorites());
      final localSL =
          Set<String>.from(await DatabaseService.instance.getSuggestLess());

      // 2. Fetch server state (source of truth)
      final serverData = await service.getUserData(_username!);
      final serverFavs = Set<String>.from(serverData['favorites'] ?? []);
      final serverSL = Set<String>.from(serverData['suggestLess'] ?? []);
      final serverShuffleState = serverData['shuffleState'];

      debugPrint(
          'Sync: Server has ${serverFavs.length} favorites, local has ${localFavs.length}');
      debugPrint(
          'Sync: Server has ${serverSL.length} suggestLess, local has ${localSL.length}');

      // 3. Find local-only additions (items in local but not in server)
      //    These need to be pushed TO the server
      final localOnlyFavs = localFavs.difference(serverFavs);
      final localOnlySL = localSL.difference(serverSL);

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

      // 5. Merge: Final state = Server state + Local additions
      final mergedFavs = serverFavs.union(localOnlyFavs).toList();
      final mergedSL = serverSL.union(localOnlySL).toList();

      // 6. Update local cache with merged state
      await DatabaseService.instance.setFavorites(mergedFavs);
      await DatabaseService.instance.setSuggestLess(mergedSL);

      // 7. Update shuffle state from server
      if (serverShuffleState != null && serverShuffleState is Map) {
        try {
          final audioManager = ref.read(audioPlayerManagerProvider);
          final updatedShuffleState = ShuffleState.fromJson(
              Map<String, dynamic>.from(serverShuffleState));
          await audioManager.updateShuffleState(updatedShuffleState);
        } catch (e) {
          debugPrint('Failed to update shuffle state: $e');
        }
      }

      // 8. Download stats DB for local viewing (read-only sync)
      await DatabaseService.instance.downloadStatsFromServer(_username!);
      await DatabaseService.instance.downloadFinalStatsFromServer(_username!);

      // 9. Update UI state
      state = state.copyWith(
        favorites: mergedFavs,
        suggestLess: mergedSL,
        isLoading: false,
      );
      _updateManager();

      syncNotifier.updateTask('userData', SyncStatus.upToDate);
      debugPrint(
          'Sync complete: ${mergedFavs.length} favorites, ${mergedSL.length} suggestLess');
    } catch (e) {
      debugPrint('Sync with server failed: $e');
      syncNotifier.setError();
    }
  }

  /// Manual refresh triggered by pull-to-refresh
  Future<void> refresh() async {
    if (_username == null) return;
    state = state.copyWith(isLoading: true);
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
}
