import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/playlist.dart';
import '../services/user_data_service.dart';
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
  late final UserDataService _service;
  String? _username;

  @override
  UserDataState build() {
    // Listen to auth changes
    final authState = ref.watch(authProvider);
    _username = authState.username;
    
    return UserDataState(isLoading: true);
  }
  
  void setService(UserDataService service) {
    _service = service;
    if (_username != null) {
      refresh();
    }
  }

  Future<void> refresh() async {
    if (_username == null) return;
    
    state = state.copyWith(isLoading: true);
    try {
      final favs = await _service.getFavorites(_username!);
      final sl = await _service.getSuggestLess(_username!);
      final playlists = await _service.getPlaylists(_username!);
      state = state.copyWith(favorites: favs, suggestLess: sl, playlists: playlists, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false);
      // Handle error appropriately
    }
  }

  Future<void> toggleSuggestLess(String songFilename) async {
    if (_username == null) return;

    final isSL = state.suggestLess.contains(songFilename);
    final newSL = List<String>.from(state.suggestLess);

    if (isSL) {
      newSL.remove(songFilename);
    } else {
      newSL.add(songFilename);
    }
    state = state.copyWith(suggestLess: newSL);

    try {
      if (isSL) {
        await _service.removeSuggestLess(_username!, songFilename);
      } else {
        await _service.addSuggestLess(_username!, songFilename);
      }
    } catch (e) {
      state = state.copyWith(suggestLess: state.suggestLess);
    }
  }

  Future<void> toggleFavorite(String songFilename) async {
    if (_username == null) return;
    
    final isFav = state.favorites.contains(songFilename);
    final newFavs = List<String>.from(state.favorites);
    
    // Optimistic update
    if (isFav) {
      newFavs.remove(songFilename);
    } else {
      newFavs.add(songFilename);
    }
    state = state.copyWith(favorites: newFavs);
    
    try {
      if (isFav) {
        await _service.removeFavorite(_username!, songFilename);
      } else {
        final statsService = ref.read(statsServiceProvider);
        await _service.addFavorite(_username!, songFilename, statsService.sessionId);
      }
    } catch (e) {
      // Revert on error
      state = state.copyWith(favorites: state.favorites);
    }
  }

  Future<Playlist?> createPlaylist(String name) async {
    if (_username == null) return null;
    try {
      final playlist = await _service.createPlaylist(_username!, name);
      state = state.copyWith(playlists: [...state.playlists, playlist]);
      return playlist;
    } catch (e) {
      return null;
    }
  }

  Future<void> deletePlaylist(String id) async {
    if (_username == null) return;
    
    final oldPlaylists = state.playlists;
    state = state.copyWith(playlists: state.playlists.where((p) => p.id != id).toList());
    
    try {
      await _service.deletePlaylist(_username!, id);
    } catch (e) {
      state = state.copyWith(playlists: oldPlaylists);
    }
  }

  Future<void> addSongToPlaylist(String playlistId, String songFilename) async {
    if (_username == null) return;
    
    // Optimistic? No, let's just wait, simpler for nested lists.
    await _service.addSongToPlaylist(_username!, playlistId, songFilename);
    await refresh(); // Refresh to get updated list
  }
  
  Future<void> removeSongFromPlaylist(String playlistId, String songFilename) async {
    if (_username == null) return;
    await _service.removeSongFromPlaylist(_username!, playlistId, songFilename);
    await refresh();
  }
}
