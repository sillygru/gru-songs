import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'auth_provider.dart';
import 'providers.dart';
import '../services/database_service.dart';
import '../models/playlist.dart';

class UserDataState {
  final List<String> favorites;
  final List<String> suggestLess;
  final List<String> hidden;
  final List<Playlist> playlists;
  final Map<String, List<String>> mergedGroups;
  final Map<String, String?> mergedGroupPriorities;
  final bool isLoading;

  UserDataState({
    this.favorites = const [],
    this.suggestLess = const [],
    this.hidden = const [],
    this.playlists = const [],
    this.mergedGroups = const {},
    this.mergedGroupPriorities = const {},
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

  bool isHidden(String filename) {
    final searchBasename = p.basename(filename).toLowerCase();
    for (final h in hidden) {
      if (h.toLowerCase() == filename.toLowerCase()) return true;
      if (p.basename(h).toLowerCase() == searchBasename) return true;
    }
    return false;
  }

  /// Checks if a song is part of a merged group
  bool isMerged(String filename) {
    for (final group in mergedGroups.values) {
      if (group.contains(filename)) return true;
    }
    return false;
  }

  /// Gets the merge group ID for a song
  String? getMergedGroupId(String filename) {
    for (final entry in mergedGroups.entries) {
      if (entry.value.contains(filename)) return entry.key;
    }
    return null;
  }

  /// Gets all songs in the same merge group as the given song
  List<String> getMergedSiblings(String filename) {
    for (final group in mergedGroups.values) {
      if (group.contains(filename)) {
        return group.where((f) => f != filename).toList();
      }
    }
    return [];
  }

  /// Gets the priority filename for a merge group
  String? getMergedGroupPriority(String groupId) {
    return mergedGroupPriorities[groupId];
  }

  /// Checks if a song is the priority song in its merge group
  bool isPriorityInMergeGroup(String filename) {
    final groupId = getMergedGroupId(filename);
    if (groupId == null) return false;
    final priority = mergedGroupPriorities[groupId];
    return priority == filename;
  }

  UserDataState copyWith({
    List<String>? favorites,
    List<String>? suggestLess,
    List<String>? hidden,
    List<Playlist>? playlists,
    Map<String, List<String>>? mergedGroups,
    Map<String, String?>? mergedGroupPriorities,
    bool? isLoading,
  }) {
    return UserDataState(
      favorites: favorites ?? this.favorites,
      suggestLess: suggestLess ?? this.suggestLess,
      hidden: hidden ?? this.hidden,
      playlists: playlists ?? this.playlists,
      mergedGroups: mergedGroups ?? this.mergedGroups,
      mergedGroupPriorities:
          mergedGroupPriorities ?? this.mergedGroupPriorities,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// UserDataNotifier implements local-only data management:
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
        Future.microtask(() => _initLocal());
        return UserDataState(isLoading: true);
      }
      return state;
    } else {
      _username = null;
      _initialized = false;
      return UserDataState();
    }
  }

  Future<void> _initLocal() async {
    if (_username == null) return;

    // Initialize local database
    await DatabaseService.instance.initForUser(_username!);

    // Load from local database
    try {
      final localFavs = await DatabaseService.instance.getFavorites();
      final localSL = await DatabaseService.instance.getSuggestLess();
      final localHidden = await DatabaseService.instance.getHidden();
      final localPlaylists = await DatabaseService.instance.getPlaylists();
      final localMergedGroups =
          await DatabaseService.instance.getMergedSongGroups();

      // Extract groups and priorities from the new format
      final groups = <String, List<String>>{};
      final priorities = <String, String?>{};
      for (final entry in localMergedGroups.entries) {
        groups[entry.key] = entry.value.filenames;
        priorities[entry.key] = entry.value.priorityFilename;
      }

      state = state.copyWith(
        favorites: localFavs,
        suggestLess: localSL,
        hidden: localHidden,
        playlists: localPlaylists,
        mergedGroups: groups,
        mergedGroupPriorities: priorities,
        isLoading: false,
      );
      _updateManager();
    } catch (e) {
      debugPrint('Error loading local user data: $e');
    }
  }

  void _updateManager() {
    ref.read(audioPlayerManagerProvider).setUserData(
          favorites: state.favorites,
          suggestLess: state.suggestLess,
          hidden: state.hidden,
          mergedGroups: state.mergedGroups,
          mergedGroupPriorities: state.mergedGroupPriorities,
        );
  }

  /// Manual refresh - just reload from local database
  Future<void> refresh({bool force = true}) async {
    if (_username == null) return;

    if (force) {
      state = state.copyWith(isLoading: true);
    }

    await _initLocal();
  }

  /// Toggle favorite (local-only)
  Future<void> toggleFavorite(String songFilename, {bool sync = false}) async {
    if (_username == null) return;

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

    // Update local database
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
  }

  /// Toggle suggestLess (local-only)
  Future<void> toggleSuggestLess(String songFilename) async {
    if (_username == null) return;

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

    // Update local database
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
  }

  /// Toggle hidden (local-only)
  Future<void> toggleHidden(String songFilename) async {
    if (_username == null) return;

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

    // Update local database
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
  }

  // --- Playlist Management ---

  Future<void> createPlaylist(String name, [String? firstSong]) async {
    if (_username == null) return;

    final id = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final playlist = Playlist(
      id: id,
      name: name,
      createdAt: now,
      updatedAt: now,
      songs: firstSong != null
          ? [PlaylistSong(songFilename: firstSong, addedAt: now)]
          : [],
    );

    // Update local database
    await DatabaseService.instance.savePlaylist(playlist);
    final newPlaylists = List<Playlist>.from(state.playlists)
      ..insert(0, playlist);
    state = state.copyWith(playlists: newPlaylists);
  }

  Future<void> addSongToPlaylist(String playlistId, String songFilename,
      {bool sync = false}) async {
    if (_username == null) return;

    // Update local database
    await DatabaseService.instance.addSongToPlaylist(playlistId, songFilename);

    // Update state
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final newPlaylists = state.playlists.map((pl) {
      if (pl.id == playlistId) {
        // Only add if not already present
        if (!pl.songs.any((s) => s.songFilename == songFilename)) {
          final updatedSongs = List<PlaylistSong>.from(pl.songs)
            ..add(PlaylistSong(songFilename: songFilename, addedAt: now));
          return pl.copyWith(songs: updatedSongs, updatedAt: now);
        }
      }
      return pl;
    }).toList();

    state = state.copyWith(playlists: newPlaylists);
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songFilename,
      {bool sync = false}) async {
    if (_username == null) return;

    // Update local database
    await DatabaseService.instance
        .removeSongFromPlaylist(playlistId, songFilename);

    // Update state
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final newPlaylists = state.playlists.map((pl) {
      if (pl.id == playlistId) {
        final updatedSongs =
            pl.songs.where((s) => s.songFilename != songFilename).toList();
        return pl.copyWith(songs: updatedSongs, updatedAt: now);
      }
      return pl;
    }).toList();

    state = state.copyWith(playlists: newPlaylists);
  }

  Future<void> deletePlaylist(String playlistId) async {
    if (_username == null) return;

    // Update local database
    await DatabaseService.instance.deletePlaylist(playlistId);
    final newPlaylists =
        state.playlists.where((p) => p.id != playlistId).toList();
    state = state.copyWith(playlists: newPlaylists);
  }

  Future<void> updatePlaylistName(String playlistId, String newName) async {
    if (_username == null) return;

    // Update local database
    await DatabaseService.instance.updatePlaylistName(playlistId, newName);

    // Update state
    final newPlaylists = state.playlists.map((pl) {
      if (pl.id == playlistId) {
        return pl.copyWith(name: newName);
      }
      return pl;
    }).toList();

    state = state.copyWith(playlists: newPlaylists);
  }

  // --- Merged Songs Management ---

  /// Creates a new merge group with the given song filenames
  /// [priorityFilename] is the song to prioritize during shuffle
  Future<String> createMergedGroup(List<String> filenames,
      {String? priorityFilename}) async {
    if (_username == null) throw Exception('Not logged in');
    if (filenames.length < 2) {
      throw Exception('Need at least 2 songs to merge');
    }

    // Create in database
    final groupId = await DatabaseService.instance
        .createMergedGroup(filenames, priorityFilename: priorityFilename);

    // Update state
    final newGroups = Map<String, List<String>>.from(state.mergedGroups);
    final newPriorities =
        Map<String, String?>.from(state.mergedGroupPriorities);
    newGroups[groupId] = filenames;
    newPriorities[groupId] = priorityFilename;
    state = state.copyWith(
        mergedGroups: newGroups, mergedGroupPriorities: newPriorities);
    _updateManager();

    return groupId;
  }

  /// Sets the priority song for a merge group
  Future<void> setMergedGroupPriority(
      String groupId, String? priorityFilename) async {
    if (_username == null) return;

    await DatabaseService.instance
        .setMergedGroupPriority(groupId, priorityFilename);

    // Update state
    final newPriorities =
        Map<String, String?>.from(state.mergedGroupPriorities);
    newPriorities[groupId] = priorityFilename;
    state = state.copyWith(mergedGroupPriorities: newPriorities);
    _updateManager();
  }

  /// Adds songs to an existing merge group
  Future<void> addSongsToMergedGroup(
      String groupId, List<String> filenames) async {
    if (_username == null) return;

    await DatabaseService.instance.addSongsToMergedGroup(groupId, filenames);

    // Update state
    final newGroups = Map<String, List<String>>.from(state.mergedGroups);
    final existing = newGroups[groupId] ?? [];
    newGroups[groupId] = [...existing, ...filenames];
    state = state.copyWith(mergedGroups: newGroups);
    _updateManager();
  }

  /// Removes a song from its merge group
  Future<void> unmergeSong(String filename) async {
    if (_username == null) return;

    // Find the group and check if we're removing the priority song
    for (final entry in state.mergedGroups.entries) {
      if (entry.value.contains(filename)) {
        break;
      }
    }

    await DatabaseService.instance.removeSongFromMergedGroup(filename);

    // Update state
    final newGroups = Map<String, List<String>>.from(state.mergedGroups);
    final newPriorities =
        Map<String, String?>.from(state.mergedGroupPriorities);
    String? groupToRemove;
    for (final entry in newGroups.entries) {
      if (entry.value.contains(filename)) {
        final updatedList = entry.value.where((f) => f != filename).toList();
        if (updatedList.length < 2) {
          groupToRemove = entry.key;
        } else {
          newGroups[entry.key] = updatedList;
          // If we removed the priority song, clear the priority
          if (newPriorities[entry.key] == filename) {
            newPriorities[entry.key] = null;
          }
        }
        break;
      }
    }
    if (groupToRemove != null) {
      newGroups.remove(groupToRemove);
      newPriorities.remove(groupToRemove);
    }
    state = state.copyWith(
        mergedGroups: newGroups, mergedGroupPriorities: newPriorities);
    _updateManager();
  }

  /// Deletes an entire merge group
  Future<void> deleteMergedGroup(String groupId) async {
    if (_username == null) return;

    await DatabaseService.instance.deleteMergedGroup(groupId);

    // Update state
    final newGroups = Map<String, List<String>>.from(state.mergedGroups);
    final newPriorities =
        Map<String, String?>.from(state.mergedGroupPriorities);
    newGroups.remove(groupId);
    newPriorities.remove(groupId);
    state = state.copyWith(
        mergedGroups: newGroups, mergedGroupPriorities: newPriorities);
    _updateManager();
  }
}
