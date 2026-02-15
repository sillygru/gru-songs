import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import 'providers.dart';

final mixedPlaylistsProvider = Provider<List<Playlist>>((ref) {
  final userData = ref.watch(userDataProvider);
  final songsAsync = ref.watch(songsProvider);

  if (songsAsync is! AsyncData ||
      songsAsync.value == null ||
      songsAsync.value!.isEmpty) {
    return [];
  }

  final allSongs = songsAsync.value!;

  // Get all recommendation playlists except quick_picks
  final recommendationPlaylists = userData.playlists
      .where((p) => p.isRecommendation && p.id != 'quick_picks')
      .toList();

  final result = <Playlist>[];

  for (final pl in recommendationPlaylists) {
    if (userData.removedRecommendations.contains(pl.id)) continue;

    final playlistSongs = <Song>[];
    for (final ps in pl.songs) {
      final song =
          allSongs.where((s) => s.filename == ps.songFilename).firstOrNull;
      if (song != null) playlistSongs.add(song);
    }

    if (playlistSongs.isNotEmpty) {
      // We need to return the playlist with resolved songs if we want to use it in UI easily,
      // but Playlist model stores PlaylistSong (filenames).
      // For the UI to work as before, we might need a wrapper or just use Playlist and resolve songs in UI.
      // However, AutoPlaylist was already a wrapper.
      // Let's just return the Playlist objects and handle song resolution in the UI or here.
      result.add(pl);
    }
  }

  // Final sorting: Pinned ones first
  result.sort((a, b) {
    final aPinned = userData.recommendationPreferences[a.id]?.isPinned ?? false;
    final bPinned = userData.recommendationPreferences[b.id]?.isPinned ?? false;
    if (aPinned && !bPinned) return -1;
    if (!aPinned && bPinned) return 1;
    return 0;
  });

  return result;
});
