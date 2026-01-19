import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  UserDataState build() {
    final authState = ref.watch(authProvider);
    final newUsername = authState.username;

    if (newUsername != null && newUsername != _username) {
      _username = newUsername;
      Future.microtask(() => _initAndRefresh());
    } else if (newUsername == null) {
      _username = null;
      return UserDataState();
    }

    _username = newUsername;
    return UserDataState(isLoading: true);
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

      // Get current local data
      final localFavs = await DatabaseService.instance.getFavorites();
      final localSuggestLess = await DatabaseService.instance.getSuggestLess();

      // Get current shuffle state
      final audioManager = ref.read(audioPlayerManagerProvider);
      final currentShuffleState = audioManager.shuffleStateNotifier.value;

      // Send local data to server
      await service.updateUserData(_username!, {
        'favorites': localFavs,
        'suggestLess': localSuggestLess,
        'shuffleState': currentShuffleState.toJson(),
      });

      // Get updated data from server
      final serverData = await service.getUserData(_username!);
      final serverFavs = List<String>.from(serverData['favorites'] ?? []);
      final serverSuggestLess = List<String>.from(serverData['suggestLess'] ?? []);
      final serverShuffleState = serverData['shuffleState'];

      // Update local database with server data
      await _updateLocalData(serverFavs, serverSuggestLess);

      // Update shuffle state from server if available
      if (serverShuffleState != null) {
        final updatedShuffleState = ShuffleState.fromJson(serverShuffleState);
        await audioManager.updateShuffleState(updatedShuffleState);
      }

      // Update state
      state = state.copyWith(
        favorites: serverFavs,
        suggestLess: serverSuggestLess,
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

    // Remove items that are no longer in the lists
    for (final filename in currentFavs) {
      if (!favorites.contains(filename)) {
        await DatabaseService.instance.removeFavorite(filename);
      }
    }

    for (final filename in currentSuggestLess) {
      if (!suggestLess.contains(filename)) {
        await DatabaseService.instance.removeSuggestLess(filename);
      }
    }

    // Add new items
    for (final filename in favorites) {
      if (!currentFavs.contains(filename)) {
        await DatabaseService.instance.addFavorite(filename);
      }
    }

    for (final filename in suggestLess) {
      if (!currentSuggestLess.contains(filename)) {
        await DatabaseService.instance.addSuggestLess(filename);
      }
    }
  }

  Future<void> toggleSuggestLess(String songFilename) async {
    if (_username == null) return;

    final isSL = state.suggestLess.contains(songFilename);
    final newSL = List<String>.from(state.suggestLess);

    if (isSL) {
      newSL.remove(songFilename);
      await DatabaseService.instance.removeSuggestLess(songFilename);
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

    final isFav = state.favorites.contains(songFilename);
    final isSL = state.suggestLess.contains(songFilename);

    final newFavs = List<String>.from(state.favorites);
    final newSL = List<String>.from(state.suggestLess);

    if (isFav) {
      newFavs.remove(songFilename);
      await DatabaseService.instance.removeFavorite(songFilename);
    } else {
      newFavs.add(songFilename);
      await DatabaseService.instance.addFavorite(songFilename);
      if (isSL) {
        newSL.remove(songFilename);
        await DatabaseService.instance.removeSuggestLess(songFilename);
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