import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import 'providers.dart';
import '../services/database_service.dart';

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

      // Perform full bidirectional sync
      await refresh();
      
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

  Future<void> toggleSuggestLess(String songFilename) async {
    if (_username == null) return;
    final service = ref.read(userDataServiceProvider);

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
      if (isSL) {
        await service.removeSuggestLess(_username!, songFilename);
      } else {
        await service.addSuggestLess(_username!, songFilename);
      }
    } catch (e) {
      debugPrint('Sync suggest-less toggle failed (offline?): $e');
    }
  }

  Future<void> toggleFavorite(String songFilename) async {
    if (_username == null) return;
    final service = ref.read(userDataServiceProvider);

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
      if (isFav) {
        await service.removeFavorite(_username!, songFilename);
      } else {
        final statsService = ref.read(statsServiceProvider);
        await service.addFavorite(
            _username!, songFilename, statsService.sessionId);
        if (isSL) {
          await service.removeSuggestLess(_username!, songFilename);
        }
      }
    } catch (e) {
      debugPrint('Sync favorite toggle failed (offline?): $e');
    }
  }
}