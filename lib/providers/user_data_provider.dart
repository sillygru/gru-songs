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
        // Load initial data from DB and trigger background sync
        Future.microtask(() => _initAndRefresh());
        return UserDataState(isLoading: true);
      }
      // If same user, Riverpod preserves the state automatically 
      // when build() returns the same object or if we manage it.
      // But in build() we MUST return the state.
      return state; 
    } else {
      _username = null;
      _initialized = false;
      return UserDataState();
    }
  }

  Future<void> _initAndRefresh() async {
    if (_username == null) return;

    // 1. Ensure DB is initialized for user (this mirrors from server if missing)
    await DatabaseService.instance.initForUser(_username!);

    // 2. Load initial data from mirrored DB
    try {
      final favs = await DatabaseService.instance.getFavorites();
      final sl = await DatabaseService.instance.getSuggestLess();
      
      state = state.copyWith(
        favorites: favs,
        suggestLess: sl,
        isLoading: false,
      );
      _updateManager();
      
      ref.read(syncProvider.notifier).updateTask('userData', SyncStatus.usingCache);
    } catch (e) {
      debugPrint('Error loading initial user data from DB: $e');
    }

    // 3. Perform background sync (Upload local -> Merge -> Download)
    await _backgroundSync();
  }

  void _updateManager() {
    ref.read(audioPlayerManagerProvider).setUserData(
          favorites: state.favorites,
          suggestLess: state.suggestLess,
        );
  }

  Future<void> _backgroundSync() async {
    if (_username == null) return;

    final syncNotifier = ref.read(syncProvider.notifier);

    try {
      syncNotifier.updateTask('userData', SyncStatus.syncing);

      // Perform comprehensive bidirectional sync of all user data
      await syncAllUserData();

      syncNotifier.updateTask('userData', SyncStatus.upToDate);
    } catch (e) {
      debugPrint('User data background sync failed: $e');
      syncNotifier.setError();
    }
  }

  Future<void> refresh() async {
    if (_username == null) return;

    try {
      // 1. Perform full bidirectional DB sync
      await DatabaseService.instance.sync(_username!);

      // 2. Reload favorites and suggest-less from the newly synced local DB
      final favs = await DatabaseService.instance.getFavorites();
      final sl = await DatabaseService.instance.getSuggestLess();

      state = state.copyWith(
          favorites: favs,
          suggestLess: sl,
          isLoading: false);

      // 3. Sync shuffle personality/history from the updated local final_stats
      await ref.read(audioPlayerManagerProvider).syncShuffleState();

      _updateManager();
    } catch (e) {
      debugPrint('Refresh failed: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  // Comprehensive sync of all user data
  Future<void> syncAllUserData() async {
    if (_username == null) return;

    try {
      final service = ref.read(userDataServiceProvider);
      final audioManager = ref.read(audioPlayerManagerProvider);

      // 1. Get updated data from server FIRST
      final serverData = await service.getUserData(_username!);
      final serverFavs = List<String>.from(serverData['favorites'] ?? []);
      final serverSuggestLess = List<String>.from(serverData['suggestLess'] ?? []);
      final serverShuffleState = serverData['shuffleState'];

      debugPrint('Sync: Received ${serverFavs.length} favorites from server: $serverFavs');

      // 2. Update local database with server data
      await _updateLocalData(serverFavs, serverSuggestLess);

      // 4. Update shuffle state from server if available
      if (serverShuffleState != null) {
        final updatedShuffleState = ShuffleState.fromJson(serverShuffleState);
        await audioManager.updateShuffleState(updatedShuffleState);
      }

      // 5. Push local data (which now includes server data) back to server to be safe
      // This ensures any local additions that weren't on server are now there.
      final mergedFavs = await DatabaseService.instance.getFavorites();
      final mergedSL = await DatabaseService.instance.getSuggestLess();
      
      await service.updateUserData(_username!, {
        'favorites': mergedFavs,
        'suggestLess': mergedSL,
        'shuffleState': audioManager.shuffleStateNotifier.value.toJson(),
      });

      // 6. Update state
      state = state.copyWith(
        favorites: mergedFavs,
        suggestLess: mergedSL,
        isLoading: false,
      );

      _updateManager();
    } catch (e) {
      debugPrint('Comprehensive user data sync failed: $e');
    }
  }

  Future<void> _updateLocalData(List<String> favorites, List<String> suggestLess) async {
    // Clear current local data
    final currentFavs = await DatabaseService.instance.getFavorites();
    final currentSuggestLess = await DatabaseService.instance.getSuggestLess();

    // Helper for robust check
    bool existsRobust(List<String> list, String filename) {
      final lowerFile = filename.toLowerCase();
      if (list.any((item) => item.toLowerCase() == lowerFile)) return true;
      final base = p.basename(filename).toLowerCase();
      return list.any((item) => p.basename(item).toLowerCase() == base);
    }

    // Remove items that are no longer in the lists
    for (final filename in currentFavs) {
      if (!existsRobust(favorites, filename)) {
        await DatabaseService.instance.removeFavorite(filename);
      }
    }

    for (final filename in currentSuggestLess) {
      if (!existsRobust(suggestLess, filename)) {
        await DatabaseService.instance.removeSuggestLess(filename);
      }
    }

    // Add new items
    for (final filename in favorites) {
      if (!existsRobust(currentFavs, filename)) {
        await DatabaseService.instance.addFavorite(filename);
      }
    }

    for (final filename in suggestLess) {
      if (!existsRobust(currentSuggestLess, filename)) {
        await DatabaseService.instance.addSuggestLess(filename);
      }
    }
  }

  Future<void> toggleSuggestLess(String songFilename) async {
    if (_username == null) return;

    final isSL = state.isSuggestLess(songFilename);
    final newSL = List<String>.from(state.suggestLess);

    if (isSL) {
      // Find the actual string that matched (could be different path or case)
      final actualMatch = state.suggestLess.firstWhere(
        (sl) => sl.toLowerCase() == songFilename.toLowerCase() || 
                p.basename(sl).toLowerCase() == p.basename(songFilename).toLowerCase(),
        orElse: () => songFilename,
      );
      newSL.remove(actualMatch);
      await DatabaseService.instance.removeSuggestLess(actualMatch);
    } else {
      newSL.add(songFilename);
      await DatabaseService.instance.addSuggestLess(songFilename);
    }
    state = state.copyWith(suggestLess: newSL);
    _updateManager();

    try {
      // Trigger comprehensive sync to ensure all data is consistent
      await syncAllUserData();
    } catch (e) {
      debugPrint('Sync suggest-less toggle failed (offline?): $e');
    }
  }

  Future<void> toggleFavorite(String songFilename) async {
    if (_username == null) return;

    final isFav = state.isFavorite(songFilename);
    final isSL = state.isSuggestLess(songFilename);

    final newFavs = List<String>.from(state.favorites);
    final newSL = List<String>.from(state.suggestLess);

    if (isFav) {
      // Find the actual string that matched (could be different path or case)
      final actualMatch = state.favorites.firstWhere(
        (f) => f.toLowerCase() == songFilename.toLowerCase() || 
               p.basename(f).toLowerCase() == p.basename(songFilename).toLowerCase(),
        orElse: () => songFilename,
      );
      newFavs.remove(actualMatch);
      await DatabaseService.instance.removeFavorite(actualMatch);
    } else {
      newFavs.add(songFilename);
      await DatabaseService.instance.addFavorite(songFilename);
      if (isSL) {
        final actualSLMatch = state.suggestLess.firstWhere(
          (sl) => sl.toLowerCase() == songFilename.toLowerCase() || 
                  p.basename(sl).toLowerCase() == p.basename(songFilename).toLowerCase(),
          orElse: () => songFilename,
        );
        newSL.remove(actualSLMatch);
        await DatabaseService.instance.removeSuggestLess(actualSLMatch);
      }
    }

    state = state.copyWith(favorites: newFavs, suggestLess: newSL);
    _updateManager();

    try {
      // Trigger comprehensive sync to ensure all data is consistent
      await syncAllUserData();
    } catch (e) {
      debugPrint('Sync favorite toggle failed (offline?): $e');
    }
  }
}