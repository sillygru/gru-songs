import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/song_merge_finder.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../providers/user_data_provider.dart';
import '../components/ambient_scaffold.dart';
import '../components/app_feedback.dart';
import '../components/app_icon.dart';
import '../components/app_screen_header.dart';
import '../components/app_segmented_tabs.dart';
import '../components/app_surface.dart';
import '../routes/app_page_route.dart';
import '../tokens/app_icons.dart';
import '../tokens/app_tokens.dart';
import '../widgets/album_art_image.dart';
import 'select_songs_screen.dart';

class MergedSongsScreen extends ConsumerStatefulWidget {
  const MergedSongsScreen({super.key});

  @override
  ConsumerState<MergedSongsScreen> createState() => _MergedSongsScreenState();
}

class _MergedSongsScreenState extends ConsumerState<MergedSongsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userData = ref.watch(userDataProvider);
    final songsAsync = ref.watch(songsProvider);

    return AmbientScaffold(
      body: songsAsync.when(
        data: (allSongs) => _buildContent(context, userData, allSongs),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    UserDataState userData,
    List<Song> allSongs,
  ) {
    final candidateGroups = SongMergeFinder.findCandidates(
      allSongs,
      userData.mergedGroups,
    );

    final mergedCount = userData.mergedGroups.length;
    final candidateCount = candidateGroups.length;

    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverToBoxAdapter(
            child: AppTopBar(
              title: 'Merged Songs',
              actions: [
                IconButton(
                  icon: const AppIcon(AppIcons.add),
                  tooltip: 'Create merge group',
                  onPressed: () => _openSelectSongsScreen(context, allSongs),
                ),
              ],
              bottom: AppSegmentedTabs(
                controller: _tabController,
                labels: [
                  'Groups ($mergedCount)',
                  'Auto-Find ($candidateCount)',
                ],
              ),
            ),
          ),
        ];
      },
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildActiveGroupsTab(context, userData, allSongs),
          _buildAutoFindTab(context, userData, candidateGroups),
        ],
      ),
    );
  }

  Future<void> _openSelectSongsScreen(
      BuildContext context, List<Song> allSongs) async {
    final result = await context.pushApp<Map<String, dynamic>>(
      SelectSongsScreen(
        songs: allSongs,
        title: 'Select Songs to Merge',
      ),
    );
    if (result != null && context.mounted) {
      final selected = result['filenames'] as List<String>;
      final priority = result['priority'] as String?;
      if (selected.length >= 2) {
        try {
          await ref.read(userDataProvider.notifier).createMergedGroup(
                selected,
                priorityFilename: priority,
              );
          if (context.mounted) {
            appSnack(
              context,
              'Merged ${selected.length} songs',
              tone: AppTone.success,
            );
          }
        } catch (e) {
          if (context.mounted) {
            appSnack(context, '$e', tone: AppTone.danger);
          }
        }
      }
    }
  }

  // --- Tab 1: Active Groups ---
  Widget _buildActiveGroupsTab(
    BuildContext context,
    UserDataState userData,
    List<Song> allSongs,
  ) {
    if (userData.mergedGroups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(
                AppIcons.merge,
                size: 56,
                color: AppTokens.fg(AppTokens.aTertiary),
              ),
              const SizedBox(height: AppTokens.s4),
              Text(
                'No merged songs yet',
                style: AppTokens.paneTitle(context),
              ),
              const SizedBox(height: AppTokens.s2),
              Text(
                'Group different versions of the same song (remixes, live versions, acoustics) so they share one spot during shuffle.',
                textAlign: TextAlign.center,
                style: AppTokens.rowSubtitle(context),
              ),
              const SizedBox(height: AppTokens.s5),
              FilledButton.icon(
                onPressed: () => _openSelectSongsScreen(context, allSongs),
                icon: const AppIcon(AppIcons.add, size: 18),
                label: const Text('Create Merge Group'),
              ),
            ],
          ),
        ),
      );
    }

    final songMap = {for (var s in allSongs) s.filename: s};

    return ListView.builder(
      padding: const EdgeInsets.all(AppTokens.s4),
      itemCount: userData.mergedGroups.length,
      itemBuilder: (context, index) {
        final entry = userData.mergedGroups.entries.elementAt(index);
        final groupId = entry.key;
        final filenames = entry.value;
        final groupSongs =
            filenames.map((f) => songMap[f]).whereType<Song>().toList();

        if (groupSongs.length < 2) return const SizedBox.shrink();

        final priorityFilename = userData.getMergedGroupPriority(groupId);

        return _MergeGroupCard(
          groupId: groupId,
          songs: groupSongs,
          priorityFilename: priorityFilename,
          onSetPriority: (filename) async {
            final newPriority = priorityFilename == filename ? null : filename;
            await ref
                .read(userDataProvider.notifier)
                .setMergedGroupPriority(groupId, newPriority);
            if (context.mounted) {
              final songTitle =
                  groupSongs.firstWhere((s) => s.filename == filename).title;
              appSnack(
                context,
                newPriority != null
                    ? '"$songTitle" set as priority song'
                    : 'Priority cleared',
                tone: AppTone.info,
              );
            }
          },
          onUnmergeSong: (song) => _showUnmergeDialog(context, song),
          onDeleteGroup: () => _showDeleteGroupDialog(context, groupId),
        );
      },
    );
  }

  // --- Tab 2: Auto-Find Suggestions ---
  Widget _buildAutoFindTab(
    BuildContext context,
    UserDataState userData,
    List<MergeCandidateGroup> candidateGroups,
  ) {
    if (candidateGroups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(
                AppIcons.autoAwesome,
                size: 56,
                color: AppTokens.fg(AppTokens.aTertiary),
              ),
              const SizedBox(height: AppTokens.s4),
              Text(
                'No candidate songs found',
                style: AppTokens.paneTitle(context),
              ),
              const SizedBox(height: AppTokens.s2),
              Text(
                'No unmerged song variants (remixes, live versions, acoustics) were detected in your library.',
                textAlign: TextAlign.center,
                style: AppTokens.rowSubtitle(context),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.s4,
            AppTokens.s2,
            AppTokens.s4,
            AppTokens.s2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Found ${candidateGroups.length} potential group${candidateGroups.length != 1 ? 's' : ''} to merge',
                  style: AppTokens.rowSubtitle(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _mergeAllCandidates(context, candidateGroups),
                icon: const AppIcon(AppIcons.merge, size: 16),
                label: const Text('Merge All'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
            itemCount: candidateGroups.length,
            itemBuilder: (context, index) {
              final candidate = candidateGroups[index];
              return _CandidateGroupCard(
                candidate: candidate,
                onMerge: (selectedFilenames) async {
                  if (selectedFilenames.length < 2) return;
                  await ref
                      .read(userDataProvider.notifier)
                      .createMergedGroup(selectedFilenames);
                  if (context.mounted) {
                    appSnack(
                      context,
                      'Merged ${selectedFilenames.length} songs',
                      tone: AppTone.success,
                    );
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _mergeAllCandidates(
    BuildContext context,
    List<MergeCandidateGroup> candidateGroups,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge All Suggestions'),
        content: Text(
            'Create ${candidateGroups.length} merge group${candidateGroups.length != 1 ? 's' : ''} for detected song variants?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Merge All'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      int count = 0;
      for (final candidate in candidateGroups) {
        final filenames = candidate.songs.map((s) => s.filename).toList();
        if (filenames.length >= 2) {
          await ref
              .read(userDataProvider.notifier)
              .createMergedGroup(filenames);
          count++;
        }
      }
      if (context.mounted) {
        appSnack(
          context,
          'Created $count merge group${count != 1 ? 's' : ''}',
          tone: AppTone.success,
        );
      }
    }
  }

  Future<void> _showUnmergeDialog(BuildContext context, Song song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unmerge Song'),
        content: Text('Remove "${song.title}" from this merge group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unmerge'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(userDataProvider.notifier).unmergeSong(song.filename);
      if (context.mounted) {
        appSnack(context, '"${song.title}" unmerged', tone: AppTone.info);
      }
    }
  }

  Future<void> _showDeleteGroupDialog(
      BuildContext context, String groupId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Merge Group'),
        content: const Text('Unmerge all songs in this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unmerge All'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(userDataProvider.notifier).deleteMergedGroup(groupId);
      if (context.mounted) {
        appSnack(context, 'Merge group deleted', tone: AppTone.info);
      }
    }
  }
}

class _MergeGroupCard extends ConsumerWidget {
  final String groupId;
  final List<Song> songs;
  final String? priorityFilename;
  final ValueChanged<String> onSetPriority;
  final Function(Song) onUnmergeSong;
  final VoidCallback onDeleteGroup;

  const _MergeGroupCard({
    required this.groupId,
    required this.songs,
    required this.priorityFilename,
    required this.onSetPriority,
    required this.onUnmergeSong,
    required this.onDeleteGroup,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppTokens.accentOf(context, ref);

    return AppSurface(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(bottom: AppTokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s4,
              vertical: AppTokens.s3,
            ),
            decoration: BoxDecoration(
              color: AppTokens.surface(2),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTokens.rMd),
              ),
            ),
            child: Row(
              children: [
                AppIcon(AppIcons.merge, size: 20, color: accent),
                const SizedBox(width: AppTokens.s2),
                Expanded(
                  child: Text(
                    'Merge Group',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
                Text(
                  '${songs.length} versions',
                  style: AppTokens.rowSubtitle(context),
                ),
                const SizedBox(width: AppTokens.s2),
                IconButton(
                  icon: const AppIcon(AppIcons.delete, size: 18),
                  onPressed: onDeleteGroup,
                  tooltip: 'Unmerge all',
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: songs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 1),
            itemBuilder: (context, index) {
              final song = songs[index];
              final isPriority = song.filename == priorityFilename;

              return ListTile(
                leading: ClipRRect(
                  borderRadius: AppTokens.brSm,
                  child: AlbumArtImage(
                    url: song.coverUrl ?? '',
                    filename: song.filename,
                    width: 40,
                    height: 40,
                    memCacheWidth: 80,
                    memCacheHeight: 80,
                  ),
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
                    if (isPriority) ...[
                      const SizedBox(width: AppTokens.s1),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.s2,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(
                            alpha: AppTokens.accentWashAlpha,
                          ),
                          borderRadius: AppTokens.brPill,
                        ),
                        child: Text(
                          'Priority',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTokens.rowSubtitle(context),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: AppIcon(
                        AppIcons.star,
                        size: 18,
                        color: isPriority
                            ? accent
                            : AppTokens.fg(AppTokens.aTertiary),
                      ),
                      onPressed: () => onSetPriority(song.filename),
                      tooltip: isPriority
                          ? 'Priority song for shuffle'
                          : 'Set as priority song',
                    ),
                    IconButton(
                      icon: const AppIcon(AppIcons.linkOff, size: 18),
                      onPressed: () => onUnmergeSong(song),
                      tooltip: 'Unmerge song',
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CandidateGroupCard extends StatefulWidget {
  final MergeCandidateGroup candidate;
  final ValueChanged<List<String>> onMerge;

  const _CandidateGroupCard({
    required this.candidate,
    required this.onMerge,
  });

  @override
  State<_CandidateGroupCard> createState() => _CandidateGroupCardState();
}

class _CandidateGroupCardState extends State<_CandidateGroupCard> {
  late Set<String> _selectedFilenames;

  @override
  void initState() {
    super.initState();
    _selectedFilenames = widget.candidate.songs.map((s) => s.filename).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final songs = widget.candidate.songs;
    final canMerge = _selectedFilenames.length >= 2;

    return AppSurface(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(bottom: AppTokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s4,
              vertical: AppTokens.s3,
            ),
            decoration: BoxDecoration(
              color: AppTokens.surface(2),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTokens.rMd),
              ),
            ),
            child: Row(
              children: [
                const AppIcon(AppIcons.autoAwesome, size: 20),
                const SizedBox(width: AppTokens.s2),
                Expanded(
                  child: Text(
                    widget.candidate.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${_selectedFilenames.length}/${songs.length} selected',
                  style: AppTokens.rowSubtitle(context),
                ),
                const SizedBox(width: AppTokens.s3),
                FilledButton(
                  onPressed: canMerge
                      ? () => widget.onMerge(_selectedFilenames.toList())
                      : null,
                  child: const Text('Merge'),
                ),
              ],
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              final isChecked = _selectedFilenames.contains(song.filename);

              return CheckboxListTile(
                value: isChecked,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedFilenames.add(song.filename);
                    } else {
                      _selectedFilenames.remove(song.filename);
                    }
                  });
                },
                secondary: ClipRRect(
                  borderRadius: AppTokens.brSm,
                  child: AlbumArtImage(
                    url: song.coverUrl ?? '',
                    filename: song.filename,
                    width: 36,
                    height: 36,
                    memCacheWidth: 72,
                    memCacheHeight: 72,
                  ),
                ),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTokens.rowSubtitle(context),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
