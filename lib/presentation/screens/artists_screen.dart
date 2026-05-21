import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../services/library_logic.dart';
import '../widgets/folder_grid_image.dart';
import '../widgets/duration_display.dart';
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
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
        centerTitle: true,
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
            return _buildEmptyState(context, colorScheme);
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.85,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: sortedArtists.length,
            itemBuilder: (context, index) {
              final artist = sortedArtists[index];
              final artistSongs = artistMap[artist]!;

              return _buildArtistCard(
                context,
                artist: artist,
                songs: artistSongs,
                colorScheme: colorScheme,
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildArtistCard(
    BuildContext context, {
    required String artist,
    required List<Song> songs,
    required ColorScheme colorScheme,
  }) {
    return GestureDetector(
      onTap: () {
        final allSongs = ref.read(songsProvider).value ?? [];
        final artistSongs = allSongs.where((s) {
          final songArtist = s.artist.isEmpty ? 'Unknown Artist' : s.artist;
          return _artistMatches(songArtist, artist);
        }).toList();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SongListScreen(
              title: artist,
              songs: artistSongs,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: FolderGridImage(
                songs: songs,
                isGridItem: true,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              artist,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          CollectionDurationDisplay(
            songs: songs,
            showSongCount: true,
            compact: true,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_outline,
            size: 100,
            color: colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'No artists found',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add music to your library to see artists',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sort_by_alpha),
              title: const Text('Name (A-Z)'),
              trailing: _sortBy == 'name' ? const Icon(Icons.check) : null,
              onTap: () {
                setState(() => _sortBy = 'name');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.music_note),
              title: const Text('Most Songs'),
              trailing: _sortBy == 'songs' ? const Icon(Icons.check) : null,
              onTap: () {
                setState(() => _sortBy = 'songs');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
