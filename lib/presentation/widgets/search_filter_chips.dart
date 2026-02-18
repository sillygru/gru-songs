import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/search_filter.dart';
import '../../models/mood_tag.dart';
import '../../providers/providers.dart';
import '../../providers/search_provider.dart';

/// Widget displaying filter chips for search filtering
class SearchFilterChips extends ConsumerWidget {
  const SearchFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(searchFilterProvider);
    final userData = ref.watch(userDataProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            isSelected: filterState.all,
            onSelected: (selected) {
              if (selected) {
                ref
                    .read(searchFilterProvider.notifier)
                    .selectFilter(SearchFilterType.all);
              }
            },
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Songs',
            isSelected: filterState.songs,
            onSelected: (selected) {
              ref
                  .read(searchFilterProvider.notifier)
                  .toggleFilter(SearchFilterType.songs);
            },
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Artists',
            isSelected: filterState.artists,
            onSelected: (selected) {
              ref
                  .read(searchFilterProvider.notifier)
                  .toggleFilter(SearchFilterType.artists);
            },
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Albums',
            isSelected: filterState.albums,
            onSelected: (selected) {
              ref
                  .read(searchFilterProvider.notifier)
                  .toggleFilter(SearchFilterType.albums);
            },
          ),
          const SizedBox(width: 8),
          _MoodDropdownChip(
            moodTags: userData.moodTags,
            selectedMoodIds: filterState.selectedMoodIds,
            onToggleMood: (moodId) =>
                ref.read(searchFilterProvider.notifier).toggleMood(moodId),
            onClear: () => ref.read(searchFilterProvider.notifier).clearMoods(),
          ),
        ],
      ),
    );
  }
}

/// Individual filter chip widget
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final ValueChanged<bool> onSelected;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: onSelected,
      showCheckmark: false,
      selectedColor: theme.colorScheme.primaryContainer,
      labelStyle: TextStyle(
        color: isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      side: isSelected
          ? BorderSide(color: theme.colorScheme.primary)
          : BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary)
            : BorderSide.none,
      ),
    );
  }
}

/// Compact filter selector for smaller spaces
class CompactSearchFilterChips extends ConsumerWidget {
  const CompactSearchFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(searchFilterProvider);
    final userData = ref.watch(userDataProvider);

    return Wrap(
      spacing: 8,
      children: [
        _CompactChip(
          label: 'All',
          isSelected: filterState.all,
          onTap: () => ref
              .read(searchFilterProvider.notifier)
              .selectFilter(SearchFilterType.all),
        ),
        _CompactChip(
          label: 'Songs',
          isSelected: filterState.songs,
          onTap: () => ref
              .read(searchFilterProvider.notifier)
              .toggleFilter(SearchFilterType.songs),
        ),
        _CompactChip(
          label: 'Artists',
          isSelected: filterState.artists,
          onTap: () => ref
              .read(searchFilterProvider.notifier)
              .toggleFilter(SearchFilterType.artists),
        ),
        _CompactChip(
          label: 'Albums',
          isSelected: filterState.albums,
          onTap: () => ref
              .read(searchFilterProvider.notifier)
              .toggleFilter(SearchFilterType.albums),
        ),
        _MoodDropdownChip(
          moodTags: userData.moodTags,
          selectedMoodIds: filterState.selectedMoodIds,
          onToggleMood: (moodId) =>
              ref.read(searchFilterProvider.notifier).toggleMood(moodId),
          onClear: () => ref.read(searchFilterProvider.notifier).clearMoods(),
          compact: true,
        ),
      ],
    );
  }
}

class _MoodDropdownChip extends StatelessWidget {
  final List<MoodTag> moodTags;
  final List<String> selectedMoodIds;
  final ValueChanged<String> onToggleMood;
  final VoidCallback onClear;
  final bool compact;

  const _MoodDropdownChip({
    required this.moodTags,
    required this.selectedMoodIds,
    required this.onToggleMood,
    required this.onClear,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final selected = selectedMoodIds.toSet();
    final label = selected.isEmpty ? 'moods' : 'moods (${selected.length})';
    final theme = Theme.of(context);

    return PopupMenuButton<String>(
      tooltip: 'Moods',
      offset: const Offset(0, 40),
      color: theme.colorScheme.surface,
      surfaceTintColor: theme.colorScheme.surfaceTint,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      onSelected: (value) {
        if (value == '__clear__') {
          onClear();
          return;
        }
        onToggleMood(value);
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            enabled: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              'Select moods',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const PopupMenuDivider(height: 1),
        ];
        for (final mood in moodTags) {
          final moodId = mood.id;
          items.add(
            PopupMenuItem<String>(
              value: moodId,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    selected.contains(moodId)
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: selected.contains(moodId)
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    mood.name,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight:
                          selected.contains(moodId) ? FontWeight.w600 : null,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (selected.isNotEmpty) {
          items.add(const PopupMenuDivider(height: 1));
          items.add(
            PopupMenuItem<String>(
              value: '__clear__',
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.clear_all_rounded,
                    color: theme.colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Clear all',
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (moodTags.isEmpty) {
          items.add(
            PopupMenuItem<String>(
              enabled: false,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'No moods available',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }
        return items;
      },
      child: Material(
        color: selected.isEmpty
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 6 : 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_list_rounded,
                  size: compact ? 16 : 18,
                  color: selected.isEmpty
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onPrimaryContainer),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected.isEmpty
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onPrimaryContainer,
                  fontWeight:
                      selected.isEmpty ? FontWeight.normal : FontWeight.w600,
                  fontSize: compact ? 13 : 14,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded,
                  size: compact ? 14 : 16,
                  color: selected.isEmpty
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact chip for wrap layouts
class _CompactChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CompactChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isSelected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurface,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
