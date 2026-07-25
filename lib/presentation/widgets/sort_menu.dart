import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/settings_provider.dart';
import '../components/app_icon.dart';
import '../tokens/app_icons.dart';

class SortMenu extends ConsumerWidget {
  const SortMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sortOrder = ref.watch(settingsProvider).sortOrder;

    return PopupMenuButton<SongSortOrder>(
      icon: const AppIcon(AppIcons.sort, size: 20),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      tooltip: 'Sort by',
      onSelected: (order) {
        ref.read(settingsProvider.notifier).setSortOrder(order);
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: SongSortOrder.title,
          checked: sortOrder == SongSortOrder.title,
          child: const Text('Title (A-Z)'),
        ),
        CheckedPopupMenuItem(
          value: SongSortOrder.artist,
          checked: sortOrder == SongSortOrder.artist,
          child: const Text('Artist'),
        ),
        CheckedPopupMenuItem(
          value: SongSortOrder.album,
          checked: sortOrder == SongSortOrder.album,
          child: const Text('Album'),
        ),
        CheckedPopupMenuItem(
          value: SongSortOrder.dateAdded,
          checked: sortOrder == SongSortOrder.dateAdded,
          child: const Text('Date Added'),
        ),
        CheckedPopupMenuItem(
          value: SongSortOrder.songDate,
          checked: sortOrder == SongSortOrder.songDate,
          child: const Text('Song Date'),
        ),
        CheckedPopupMenuItem(
          value: SongSortOrder.playCount,
          checked: sortOrder == SongSortOrder.playCount,
          child: const Text('Most Played'),
        ),
        CheckedPopupMenuItem(
          value: SongSortOrder.recentlyPlayed,
          checked: sortOrder == SongSortOrder.recentlyPlayed,
          child: const Text('Recently Played'),
        ),
        CheckedPopupMenuItem(
          value: SongSortOrder.recommended,
          checked: sortOrder == SongSortOrder.recommended,
          child: const Text('Recommended'),
        ),
      ],
    );
  }
}
