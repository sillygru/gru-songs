import 'package:flutter/material.dart';
import '../components/ambient_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../services/library_logic.dart';
import '../widgets/folder_grid_image.dart';
import '../widgets/duration_display.dart';
import '../components/app_feedback.dart';
import '../components/app_media_card.dart';
import '../components/app_sheet.dart';
import '../routes/app_page_route.dart';
import '../tokens/app_tokens.dart';
import 'song_list_screen.dart';

/// Parses a multi-artist string and returns individual artist names.
/// Handles formats like:
/// - "Artist1, Artist2 & Artist3"
/// - "Artist1 & Artist2"
/// - "Artist1 and Artist2"
List<String> _parseArtists(String artistField) {
  if (artistField.isEmpty) return [];

  // Split by common separators: comma, &, and the word " and " (case insensitive)
  final parts = artistField
      .split(RegExp(r',\s*|\s*&\s*|\s+and\s+', caseSensitive: false))
      .map((part) => part.trim().toLowerCase())
      .where((part) => part.isNotEmpty)
      .toList();

  return parts;
}

/// Returns true if [songArtist] matches [targetArtist] accounting for multi-artist strings.
bool _artistMatches(String songArtist, String targetArtist) {
  if (songArtist.isEmpty && targetArtist.isEmpty) return true;
  if (songArtist.isEmpty || targetArtist.isEmpty) return false;

  final parsedSongArtists = _parseArtists(songArtist);
  if (parsedSongArtists.isEmpty) return false;

  final lowerTarget = targetArtist.toLowerCase();

  // Check if any of the song's artists contain the target artist
  return parsedSongArtists.any((artist) => artist.contains(lowerTarget));
}

class ArtistsScreen extends ConsumerStatefulWidget {
  const ArtistsScreen({super.key});

  @override
  ConsumerState<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends ConsumerState<ArtistsScreen> {
  String _sortBy = 'name'; // 'name', 'songs', 'recent'
  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(songsProvider);

    return AmbientScaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search artists...',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : const Text('Artists'),
        leading: _isSearching
            ? IconButton(
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
            icon: Icon(_isSearching ? Icons.close : Icons.search),
          ),
          IconButton(
            onPressed: () => _showSortOptions(context),
            icon: const Icon(Icons.sort),
          ),
        ],
      ),
      body: songsAsync.when(
        data: (songs) {
          var artistMap = LibraryLogic.groupByArtist(songs);

          if (_searchQuery.isNotEmpty) {
            artistMap = Map.fromEntries(
              artistMap.entries.where((entry) =>
                  entry.key.toLowerCase().contains(_searchQuery.toLowerCase())),
            );
          }

          final sortedArtists = _sortArtists(artistMap);

          if (sortedArtists.isEmpty) {
            return const AppEmptyState(
              icon: Icons.person_rounded,
              title: 'No artists found',
              message: 'Add music to your library to see artists.',
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.s4,
              AppTokens.s4,
              AppTokens.s4,
              AppTokens.scrollBottomInset,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.78,
              crossAxisSpacing: AppTokens.s4,
              mainAxisSpacing: AppTokens.s4,
            ),
            itemCount: sortedArtists.length,
            itemBuilder: (context, index) {
              final artist = sortedArtists[index];
              final artistSongs = artistMap[artist]!;

              return _buildArtistCard(
                context,
                artist: artist,
                songs: artistSongs,
              );
            },
          );
        },
        loading: () => const AppLoading(),
        error: (e, _) => AppEmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load artists',
          message: '$e',
          tone: AppTone.danger,
        ),
      ),
    );
  }

  Widget _buildArtistCard(
    BuildContext context, {
    required String artist,
    required List<Song> songs,
  }) {
    return AppMediaCard(
      expand: true,
      title: artist,
      subtitle: collectionSummary(songs),
      artwork: FolderGridImage(songs: songs, isGridItem: true),
      onTap: () {
        final allSongs = ref.read(songsProvider).value ?? [];
        final artistSongs = allSongs.where((s) {
          final songArtist = s.artist.isEmpty ? 'Unknown Artist' : s.artist;
          return _artistMatches(songArtist, artist);
        }).toList();
        context.pushApp(SongListScreen(title: artist, songs: artistSongs));
      },
    );
  }

  List<String> _sortArtists(Map<String, List<Song>> artistMap) {
    final artists = artistMap.keys.toList();

    switch (_sortBy) {
      case 'songs':
        artists.sort((a, b) {
          final countCompare =
              artistMap[b]!.length.compareTo(artistMap[a]!.length);
          if (countCompare != 0) return countCompare;
          return a.toLowerCase().compareTo(b.toLowerCase());
        });
        break;
      case 'name':
      default:
        artists.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        break;
    }

    return artists;
  }

  void _showSortOptions(BuildContext context) {
    showAppSheet(
      context,
      title: 'Sort artists',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sortAction(
              sheetContext, 'name', Icons.sort_by_alpha_rounded, 'Name (A-Z)'),
          _sortAction(
              sheetContext, 'songs', Icons.music_note_rounded, 'Most Songs'),
        ],
      ),
    );
  }

  Widget _sortAction(
    BuildContext sheetContext,
    String value,
    IconData icon,
    String label,
  ) {
    final selected = _sortBy == value;
    return AppSheetAction(
      icon: icon,
      label: label,
      trailing: selected
          ? Icon(Icons.check_rounded, color: AppTokens.accentOf(context, ref))
          : null,
      onTap: () {
        setState(() => _sortBy = value);
        Navigator.pop(sheetContext);
      },
    );
  }
}
