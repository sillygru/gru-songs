import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/search_filter.dart';
import '../../providers/search_provider.dart';

/// Widget displaying filter chips for search filtering
class SearchFilterChips extends ConsumerWidget {
  const SearchFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(searchFilterProvider);

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
    );
  }
}

/// Compact filter selector for smaller spaces
class CompactSearchFilterChips extends ConsumerWidget {
  const CompactSearchFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(searchFilterProvider);

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
      ],
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
