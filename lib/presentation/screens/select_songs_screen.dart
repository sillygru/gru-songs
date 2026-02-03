import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/library_logic.dart';
import '../widgets/album_art_image.dart';

class SelectSongsScreen extends ConsumerStatefulWidget {
  final List<Song> songs;
  final List<String>? preselectedFilenames;
  final String? title;
  final bool isMerging;
  final String? actionLabel;
  final int minSelection;

  const SelectSongsScreen({
    super.key,
    required this.songs,
    this.preselectedFilenames,
    this.title,
    this.isMerging = true,
    this.actionLabel,
    this.minSelection = 2,
  });

  @override
  ConsumerState<SelectSongsScreen> createState() => _SelectSongsScreenState();
}

class _SelectSongsScreenState extends ConsumerState<SelectSongsScreen> {
  final Set<String> _selectedFilenames = {};
  String? _priorityFilename;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.preselectedFilenames != null) {
      _selectedFilenames.addAll(widget.preselectedFilenames!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortOrder = ref.watch(settingsProvider).sortOrder;
    final userData = ref.watch(userDataProvider);

    final sortedSongs = LibraryLogic.sortSongs(
      widget.songs,
      sortOrder,
      userData: userData,
    );

    final filteredSongs = _searchQuery.isEmpty
        ? sortedSongs
        : sortedSongs
            .where((s) =>
                s.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                s.artist.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Select Songs'),
        actions: [
          if (_selectedFilenames.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedFilenames.clear();
                });
              },
              child: const Text('Clear'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Info card explaining merge functionality (only if merging)
          if (widget.isMerging)
            Container(
              margin: const EdgeInsets.all(16.0),
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'What is merging?',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Merged songs are different versions of the same song:',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  _buildInfoBullet(context,
                      'Like remixes, live versions, or different quality versions'),
                  _buildInfoBullet(context,
                      'Favorites and "suggest less" are independent per song'),
                  _buildInfoBullet(
                      context, 'Your play counts and stats remain unchanged'),
                  _buildInfoBullet(context,
                      'Select a priority song (⭐) to prioritize it during shuffle'),
                ],
              ),
            ),
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search songs...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          // Selection info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_selectedFilenames.length} selected',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const Spacer(),
                if (widget.isMerging && _selectedFilenames.length >= 2)
                  Text(
                    'Ready to merge',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
              ],
            ),
          ),
          // Song list
          Expanded(
            child: filteredSongs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off,
                            size: 48, color: Colors.grey[600]),
                        const SizedBox(height: 16),
                        Text('No songs found',
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredSongs.length,
                    itemBuilder: (context, index) {
                      final song = filteredSongs[index];
                      final isSelected =
                          _selectedFilenames.contains(song.filename);
                      final isPriority = _priorityFilename == song.filename;

                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedFilenames.add(song.filename);
                              // Auto-set first selected as priority if none set
                              if (widget.isMerging) {
                                _priorityFilename ??= song.filename;
                              }
                            } else {
                              _selectedFilenames.remove(song.filename);
                              // Clear priority if priority song is deselected
                              if (_priorityFilename == song.filename) {
                                _priorityFilename = null;
                              }
                            }
                          });
                        },
                        secondary: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Priority star button (only show if selected AND merging)
                            if (isSelected && widget.isMerging)
                              IconButton(
                                icon: Icon(
                                  isPriority ? Icons.star : Icons.star_border,
                                  color: isPriority
                                      ? Colors.amber
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.4),
                                ),
                                tooltip: isPriority
                                    ? 'Priority song'
                                    : 'Set as priority',
                                onPressed: () {
                                  setState(() {
                                    _priorityFilename =
                                        isPriority ? null : song.filename;
                                  });
                                },
                              ),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: AlbumArtImage(
                                url: song.coverUrl ?? '',
                                filename: song.filename,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ],
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isPriority && widget.isMerging)
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'PRIORITY',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_selectedFilenames.length < widget.minSelection)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    'Select at least ${widget.minSelection} song${widget.minSelection > 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
                ),
              FilledButton(
                onPressed: _selectedFilenames.length >= widget.minSelection
                    ? () {
                        Navigator.pop(
                          context,
                          {
                            'filenames': _selectedFilenames.toList(),
                            'priority': _priorityFilename,
                          },
                        );
                      }
                    : null,
                child: Text(widget.actionLabel ??
                    (widget.isMerging
                        ? 'Merge ${_selectedFilenames.length} Songs'
                        : 'Select ${_selectedFilenames.length} Songs')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBullet(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, top: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '•',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
