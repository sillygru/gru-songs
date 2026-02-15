import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'providers.dart';
import 'session_history_provider.dart';
import '../services/database_service.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../domain/models/play_session.dart';

class UserDataState {
  final List<String> favorites;
  final List<String> suggestLess;
  final List<String> hidden;
  final List<Playlist> playlists;
  final Map<String, List<String>> mergedGroups;
  final Map<String, String?> mergedGroupPriorities;
  final Map<String, ({String? customTitle, bool isPinned})>
      recommendationPreferences;
  final List<String> removedRecommendations;
  final bool isLoading;

  UserDataState({
    this.favorites = const [],
    this.suggestLess = const [],
    this.hidden = const [],
    this.playlists = const [],
    this.mergedGroups = const {},
    this.mergedGroupPriorities = const {},
    this.recommendationPreferences = const {},
    this.removedRecommendations = const [],
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
    Map<String, ({String? customTitle, bool isPinned})>?
        recommendationPreferences,
    List<String>? removedRecommendations,
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
      recommendationPreferences:
          recommendationPreferences ?? this.recommendationPreferences,
      removedRecommendations:
          removedRecommendations ?? this.removedRecommendations,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// UserDataNotifier implements local-only data management:
class UserDataNotifier extends Notifier<UserDataState> {
  bool _initialized = false;

  @override
  UserDataState build() {
    // Listen to songsProvider to trigger recommendation updates when songs are ready.
    // This ensures that even if updateRecommendationPlaylists was called too early during init,
    // it will run as soon as we have songs to generate from.
    ref.listen(songsProvider, (previous, next) {
      if (next is AsyncData && next.value != null && next.value!.isNotEmpty) {
        updateRecommendationPlaylists();
      }
    });

    if (!_initialized) {
      _initialized = true;
      Future.microtask(() => _initLocal());
      return UserDataState(isLoading: true);
    }
    return state;
  }

  Future<void> _initLocal() async {
    // Initialize local database (single user mode)
    await DatabaseService.instance.init();

    // Load from local database
    try {
      final localFavs = await DatabaseService.instance.getFavorites();
      final localSL = await DatabaseService.instance.getSuggestLess();
      final localHidden = await DatabaseService.instance.getHidden();
      final localPlaylists = await DatabaseService.instance.getPlaylists();
      final localMergedGroups =
          await DatabaseService.instance.getMergedSongGroups();
      final localRecommendationPrefs =
          await DatabaseService.instance.getRecommendationPreferences();
      final localRemovedRecommendations =
          await DatabaseService.instance.getRemovedRecommendations();

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
        recommendationPreferences: localRecommendationPrefs,
        removedRecommendations: localRemovedRecommendations,
        isLoading: false,
      );
      _updateManager();

      // Try to update recommendations if they are old or missing
      await updateRecommendationPlaylists();
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
        );
  }

  /// Manual refresh - just reload from local database
  Future<void> refresh({bool force = true}) async {
    if (force) {
      state = state.copyWith(isLoading: true);
    }

    await _initLocal();
    await updateRecommendationPlaylists(force: force);
  }

  /// Toggle favorite (local-only)
  Future<void> toggleFavorite(String songFilename, {bool sync = false}) async {
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

  Future<void> bulkToggleFavorite(List<String> filenames, bool favorite) async {
    final newFavs = List<String>.from(state.favorites);
    final newSL = List<String>.from(state.suggestLess);

    for (final filename in filenames) {
      final isCurrentlyFav = state.isFavorite(filename);

      if (favorite && !isCurrentlyFav) {
        newFavs.add(filename);
        await DatabaseService.instance.addFavorite(filename);

        // Remove from suggestLess if present
        if (state.isSuggestLess(filename)) {
          final actualSLMatch = state.suggestLess.firstWhere(
            (sl) =>
                sl.toLowerCase() == filename.toLowerCase() ||
                p.basename(sl).toLowerCase() ==
                    p.basename(filename).toLowerCase(),
            orElse: () => filename,
          );
          newSL.remove(actualSLMatch);
          await DatabaseService.instance.removeSuggestLess(actualSLMatch);
        }
      } else if (!favorite && isCurrentlyFav) {
        final actualFilename = state.favorites.firstWhere(
          (f) =>
              f.toLowerCase() == filename.toLowerCase() ||
              p.basename(f).toLowerCase() == p.basename(filename).toLowerCase(),
          orElse: () => filename,
        );
        newFavs.remove(actualFilename);
        await DatabaseService.instance.removeFavorite(actualFilename);
      }
    }

    state = state.copyWith(favorites: newFavs, suggestLess: newSL);
    _updateManager();
  }

  Future<void> bulkHide(List<String> filenames, bool hide) async {
    final newHidden = List<String>.from(state.hidden);

    for (final filename in filenames) {
      final isCurrentlyHidden = state.isHidden(filename);

      if (hide && !isCurrentlyHidden) {
        newHidden.add(filename);
        await DatabaseService.instance.addHidden(filename);
      } else if (!hide && isCurrentlyHidden) {
        final actualFilename = state.hidden.firstWhere(
          (h) =>
              h.toLowerCase() == filename.toLowerCase() ||
              p.basename(h).toLowerCase() == p.basename(filename).toLowerCase(),
          orElse: () => filename,
        );
        newHidden.remove(actualFilename);
        await DatabaseService.instance.removeHidden(actualFilename);
      }
    }

    state = state.copyWith(hidden: newHidden);
    _updateManager();
  }

  // --- Playlist Management ---

  Future<void> createPlaylist(String name, [String? firstSong]) async {
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

  Future<void> bulkAddSongsToPlaylist(
      String playlistId, List<String> filenames) async {
    await DatabaseService.instance
        .bulkAddSongsToPlaylist(playlistId, filenames);

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final newPlaylists = state.playlists.map((pl) {
      if (pl.id == playlistId) {
        final updatedSongs = List<PlaylistSong>.from(pl.songs);
        for (final filename in filenames) {
          if (!updatedSongs.any((s) => s.songFilename == filename)) {
            updatedSongs
                .add(PlaylistSong(songFilename: filename, addedAt: now));
          }
        }
        return pl.copyWith(songs: updatedSongs, updatedAt: now);
      }
      return pl;
    }).toList();

    state = state.copyWith(playlists: newPlaylists);
  }

  Future<void> bulkRemoveSongsFromPlaylist(
      String playlistId, List<String> filenames) async {
    await DatabaseService.instance
        .bulkRemoveSongsFromPlaylist(playlistId, filenames);

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final newPlaylists = state.playlists.map((pl) {
      if (pl.id == playlistId) {
        final updatedSongs =
            pl.songs.where((s) => !filenames.contains(s.songFilename)).toList();
        return pl.copyWith(songs: updatedSongs, updatedAt: now);
      }
      return pl;
    }).toList();

    state = state.copyWith(playlists: newPlaylists);
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songFilename,
      {bool sync = false}) async {
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
    // Update local database
    await DatabaseService.instance.deletePlaylist(playlistId);
    final newPlaylists =
        state.playlists.where((p) => p.id != playlistId).toList();
    state = state.copyWith(playlists: newPlaylists);
  }

  Future<void> updatePlaylistName(String playlistId, String newName) async {
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

  // --- Recommendation Management ---

  Future<void> pinRecommendation(String id, bool pinned,
      {List<Song>? songs, String? title, String? description}) async {
    await DatabaseService.instance
        .saveRecommendationPreference(id, isPinned: pinned);

    if (pinned && songs != null) {
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final playlist = Playlist(
        id: id,
        name: title ?? id,
        description: description,
        isRecommendation: true,
        createdAt: now,
        updatedAt: now,
        songs: songs
            .map((s) => PlaylistSong(songFilename: s.filename, addedAt: now))
            .toList(),
      );
      await DatabaseService.instance.savePlaylist(playlist);

      // Add to local state
      final newPlaylists = List<Playlist>.from(state.playlists)
        ..removeWhere((p) => p.id == id)
        ..add(playlist);
      state = state.copyWith(playlists: newPlaylists);
    } else if (!pinned) {
      await DatabaseService.instance.deletePlaylist(id);

      // Remove from local state
      final newPlaylists = state.playlists.where((p) => p.id != id).toList();
      state = state.copyWith(playlists: newPlaylists);
    }

    final newPrefs = Map<String, ({String? customTitle, bool isPinned})>.from(
        state.recommendationPreferences);
    final current =
        newPrefs[id] ?? (customTitle: null as String?, isPinned: false);
    newPrefs[id] = (customTitle: current.customTitle, isPinned: pinned);

    state = state.copyWith(recommendationPreferences: newPrefs);
  }

  Future<void> renameRecommendation(String id, String newName,
      {List<Song>? songs, String? description}) async {
    // If recommendation is renamed it automatically becomes pinned
    await DatabaseService.instance
        .saveRecommendationPreference(id, customTitle: newName, isPinned: true);

    if (songs != null) {
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final playlist = Playlist(
        id: id,
        name: newName,
        description: description,
        isRecommendation: true,
        createdAt: now,
        updatedAt: now,
        songs: songs
            .map((s) => PlaylistSong(songFilename: s.filename, addedAt: now))
            .toList(),
      );
      await DatabaseService.instance.savePlaylist(playlist);

      // Add to local state
      final newPlaylists = List<Playlist>.from(state.playlists)
        ..removeWhere((p) => p.id == id)
        ..add(playlist);
      state = state.copyWith(playlists: newPlaylists);
    } else {
      // Update name of existing frozen playlist if it exists
      final existingIndex = state.playlists.indexWhere((p) => p.id == id);
      if (existingIndex != -1) {
        final updated = state.playlists[existingIndex].copyWith(name: newName);
        await DatabaseService.instance.savePlaylist(updated);

        final newPlaylists = List<Playlist>.from(state.playlists);
        newPlaylists[existingIndex] = updated;
        state = state.copyWith(playlists: newPlaylists);
      }
    }

    final newPrefs = Map<String, ({String? customTitle, bool isPinned})>.from(
        state.recommendationPreferences);
    newPrefs[id] = (customTitle: newName, isPinned: true);

    state = state.copyWith(recommendationPreferences: newPrefs);
  }

  Future<void> removeRecommendation(String id) async {
    await DatabaseService.instance.addRecommendationRemoval(id);

    final newRemoved = List<String>.from(state.removedRecommendations)..add(id);
    state = state.copyWith(removedRecommendations: newRemoved);
  }

  Future<void> restoreRecommendation(String id) async {
    await DatabaseService.instance.removeRecommendationRemoval(id);

    final newRemoved = List<String>.from(state.removedRecommendations)
      ..remove(id);
    state = state.copyWith(removedRecommendations: newRemoved);
  }

  // --- Recommendation Playlist Logic ---

  List<Song> _generateSongsForRecommendation(
    String id,
    List<Song> allSongs,
    Map<String, int> playCounts,
    List<PlaySession> sessions,
  ) {
    if (allSongs.isEmpty) return [];
    final random = Random();

    switch (id) {
      case 'quick_picks':
        final recommendations = List<Song>.from(allSongs);
        recommendations.sort((a, b) {
          double score(Song s) {
            double val = log((playCounts[s.filename] ?? 0) + 1.5) * 2.0;
            if (state.isFavorite(s.filename)) val += 5.0;
            if (state.isSuggestLess(s.filename)) val -= 10.0;
            val += random.nextDouble() * 4.0;
            return val;
          }

          return score(b).compareTo(score(a));
        });
        return recommendations.take(10).toList();

      case 'top_hits':
        final list = List<Song>.from(allSongs);
        list.sort((a, b) => (playCounts[b.filename] ?? 0)
            .compareTo(playCounts[a.filename] ?? 0));
        return list.take(20).toList();

      case 'fresh_finds':
        final list = List<Song>.from(allSongs);
        list.sort((a, b) => (b.mtime ?? 0).compareTo(a.mtime ?? 0));
        return list.take(20).toList();

      case 'forgotten_favorites':
        final recentFilenames = sessions
            .take(5)
            .expand((s) => s.events ?? [])
            .map((e) => e.songFilename)
            .toSet();
        final forgotten = allSongs.where((s) {
          final isFav = state.isFavorite(s.filename);
          final count = playCounts[s.filename] ?? 0;
          return (isFav || count > 10) && !recentFilenames.contains(s.filename);
        }).toList();
        if (forgotten.isEmpty) return [];
        return (forgotten..shuffle()).take(20).toList();

      case 'quick_refresh':
        final unplayed =
            allSongs.where((s) => (playCounts[s.filename] ?? 0) < 3).toList();
        if (unplayed.isEmpty) return [];
        return (unplayed..shuffle()).take(20).toList();

      case 'artist_mix':
        if (sessions.isEmpty) return [];
        final artistCounts = <String, int>{};
        for (final session in sessions.take(10)) {
          for (final event in session.events ?? []) {
            if (event.song != null) {
              artistCounts[event.song!.artist] =
                  (artistCounts[event.song!.artist] ?? 0) + 1;
            }
          }
        }
        if (artistCounts.isEmpty) return [];
        final topArtist = artistCounts.entries
            .reduce((a, b) => a.value > b.value ? a : b)
            .key;
        final artistSongs =
            allSongs.where((s) => s.artist == topArtist).toList();
        if (artistSongs.length < 3) return [];
        return (artistSongs..shuffle()).take(20).toList();

      default:
        return [];
    }
  }

  Future<void> updateRecommendationPlaylists({bool force = false}) async {
    final songsAsync = ref.read(songsProvider);

    if (songsAsync is! AsyncData || songsAsync.value == null) return;
    final allSongs = songsAsync.value!;

    // Await stats to ensure good recommendations
    final playCounts = await ref.read(playCountsProvider.future);
    final sessions = await ref.read(sessionHistoryProvider.future);

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final audioManager = ref.read(audioPlayerManagerProvider);
    final currentPlaylistId = audioManager.currentPlaylistId;

    final recommendationTypes = [
      (
        id: 'quick_picks',
        title: 'Quick Picks',
        desc: 'Personalized for you right now.'
      ),
      (id: 'top_hits', title: 'Top Hits', desc: 'Your all-time favorites.'),
      (
        id: 'fresh_finds',
        title: 'Fresh Finds',
        desc: 'Newly added to your library.'
      ),
      (
        id: 'forgotten_favorites',
        title: 'Forgotten Favorites',
        desc: 'Songs you haven\'t heard in a while.'
      ),
      (
        id: 'quick_refresh',
        title: 'Quick Refresh',
        desc: 'Give these tracks another spin.'
      ),
      (
        id: 'artist_mix',
        title: 'Artist Mix',
        desc: 'A collection of tracks from your favorite artist.'
      ),
    ];

    final updatedPlaylists = List<Playlist>.from(state.playlists);
    bool changed = false;

    for (final type in recommendationTypes) {
      if (state.removedRecommendations.contains(type.id)) continue;

      final existing =
          updatedPlaylists.where((p) => p.id == type.id).firstOrNull;
      final pref = state.recommendationPreferences[type.id];
      final isPinned = pref?.isPinned ?? false;

      // DO NOT update if it's currently playing OR if it's pinned (pinned ones are kept)
      if (type.id == currentPlaylistId || isPinned) continue;

      bool shouldUpdate = force || existing == null;
      if (!shouldUpdate) {
        // Update if older than 24 hours
        if (now - existing.updatedAt > 86400) {
          shouldUpdate = true;
        }
      }

      if (shouldUpdate) {
        final songs = _generateSongsForRecommendation(
            type.id, allSongs, playCounts, sessions);
        if (songs.isNotEmpty) {
          final playlist = Playlist(
            id: type.id,
            name: pref?.customTitle ?? (existing?.name ?? type.title),
            description: existing?.description ?? type.desc,
            isRecommendation: true,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            songs: songs
                .map(
                    (s) => PlaylistSong(songFilename: s.filename, addedAt: now))
                .toList(),
          );

          await DatabaseService.instance.savePlaylist(playlist);
          updatedPlaylists.removeWhere((p) => p.id == type.id);
          updatedPlaylists.add(playlist);
          changed = true;
        }
      }
    }

    if (changed) {
      state = state.copyWith(playlists: updatedPlaylists);
    }
  }
}
