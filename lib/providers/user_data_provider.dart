import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/playlist.dart';
import 'auth_provider.dart';
import 'providers.dart';

class UserDataState {
  final List<String> favorites;
  final List<String> suggestLess;
  final List<Playlist> playlists;
  final bool isLoading;

  UserDataState({
    this.favorites = const [],
    this.suggestLess = const [],
    this.playlists = const [],
    this.isLoading = false,
  });

  UserDataState copyWith({
    List<String>? favorites,
    List<String>? suggestLess,
    List<Playlist>? playlists,
    bool? isLoading,
  }) {
    return UserDataState(
      favorites: favorites ?? this.favorites,
      suggestLess: suggestLess ?? this.suggestLess,
      playlists: playlists ?? this.playlists,
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
    
    // If username changed and is now logged in, trigger refresh (with cache)
    if (newUsername != null && newUsername != _username) {
      _username = newUsername;
      Future.microtask(() => _loadCacheAndRefresh());
    } else if (newUsername == null) {
      _username = null;
      return UserDataState();
    }
    
    _username = newUsername;
    // Initial state is loading if we are just starting, 
    // but if we have previous state (from param change) we might want to keep it?
    // For now, default to loading until cache hits.
    return UserDataState(isLoading: true);
  }

  Future<void> _loadCacheAndRefresh() async {
    if (_username == null) return;
    
    // 1. Load Cache
    final storage = ref.read(storageServiceProvider);
    try {
      final cached = await storage.loadUserData(_username!);
      if (cached != null) {
        state = state.copyWith(
          favorites: List<String>.from(cached['favorites'] ?? []),
          suggestLess: List<String>.from(cached['suggest_less'] ?? []),
          playlists: (cached['playlists'] as List?)
              ?.map((p) => Playlist.fromJson(p))
              .toList() ?? [],
          isLoading: false,
        );
      }
    } catch (e) {
      debugPrint('Error loading user cache: $e');
    }

    // 2. Fetch from Network
    await refresh();
  }

  Future<void> _saveCache() async {
    if (_username == null) return;
    final storage = ref.read(storageServiceProvider);
    final data = {
      'favorites': state.favorites,
      'suggest_less': state.suggestLess,
      'playlists': state.playlists.map((p) => p.toJson()).toList(),
    };
    await storage.saveUserData(_username!, data);
  }

  Future<void> refresh() async {
    if (_username == null) return;
    
    final service = ref.read(userDataServiceProvider);
    // Don't set isLoading to true if we already have data (from cache)
    // state = state.copyWith(isLoading: true); 
    
    try {
      final favs = await service.getFavorites(_username!);
      final sl = await service.getSuggestLess(_username!);
      final playlists = await service.getPlaylists(_username!);
      state = state.copyWith(favorites: favs, suggestLess: sl, playlists: playlists, isLoading: false);
      _saveCache();
    } catch (e) {
      // Only set loading to false if we were loading
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
    } else {
      newSL.add(songFilename);
    }
    state = state.copyWith(suggestLess: newSL);
    _saveCache();

    try {
      if (isSL) {
        await service.removeSuggestLess(_username!, songFilename);
      } else {
        await service.addSuggestLess(_username!, songFilename);
      }
    } catch (e) {
      // Revert on error?
      // state = state.copyWith(suggestLess: state.suggestLess);
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
    } else {
      newFavs.add(songFilename);
      if (isSL) {
        newSL.remove(songFilename);
      }
    }
    
    state = state.copyWith(favorites: newFavs, suggestLess: newSL);
    _saveCache();
    
    try {
      if (isFav) {
        await service.removeFavorite(_username!, songFilename);
      } else {
        final statsService = ref.read(statsServiceProvider);
        await service.addFavorite(_username!, songFilename, statsService.sessionId);
        if (isSL) {
          await service.removeSuggestLess(_username!, songFilename);
        }
      }
    } catch (e) {
      // Revert?
    }
  }

  Future<Playlist?> createPlaylist(String name) async {
    if (_username == null) return null;
    final service = ref.read(userDataServiceProvider);
    try {
      final playlist = await service.createPlaylist(_username!, name);
      state = state.copyWith(playlists: [...state.playlists, playlist]);
      _saveCache();
      return playlist;
    } catch (e) {
      return null;
    }
  }

  Future<void> deletePlaylist(String id) async {
    if (_username == null) return;
    final service = ref.read(userDataServiceProvider);
    
    final oldPlaylists = state.playlists;
    state = state.copyWith(playlists: state.playlists.where((p) => p.id != id).toList());
    _saveCache();
    
    try {
      await service.deletePlaylist(_username!, id);
    } catch (e) {
      state = state.copyWith(playlists: oldPlaylists);
    }
  }

  Future<void> addSongToPlaylist(String playlistId, String songFilename) async {
    if (_username == null) return;
    final service = ref.read(userDataServiceProvider);
    // Optimistic update would be better, but for now just refresh
    await service.addSongToPlaylist(_username!, playlistId, songFilename);
    await refresh();
  }
  
  Future<void> removeSongFromPlaylist(String playlistId, String songFilename) async {
    if (_username == null) return;
    final service = ref.read(userDataServiceProvider);
    await service.removeSongFromPlaylist(_username!, playlistId, songFilename);
    await refresh();
  }
}
