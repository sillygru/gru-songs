import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/search_filter.dart';
import '../../providers/search_provider.dart';
import '../components/app_chip.dart';
import '../tokens/app_tokens.dart';

/// Widget displaying filter chips for search filtering
class SearchFilterChips extends ConsumerWidget {
  const SearchFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(searchFilterProvider);
    final notifier = ref.read(searchFilterProvider.notifier);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
      child: Row(
        children: [
          AppChip(
            label: 'All',
            selected: filterState.all,
            onTap: () => notifier.selectFilter(SearchFilterType.all),
          ),
          const SizedBox(width: AppTokens.s2),
          AppChip(
            label: 'Songs',
            selected: filterState.songs,
            onTap: () => notifier.toggleFilter(SearchFilterType.songs),
          ),
          const SizedBox(width: AppTokens.s2),
          AppChip(
            label: 'Artists',
            selected: filterState.artists,
            onTap: () => notifier.toggleFilter(SearchFilterType.artists),
          ),
          const SizedBox(width: AppTokens.s2),
          AppChip(
            label: 'Albums',
            selected: filterState.albums,
            onTap: () => notifier.toggleFilter(SearchFilterType.albums),
          ),
        ],
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
    final notifier = ref.read(searchFilterProvider.notifier);

    return Wrap(
      spacing: AppTokens.s2,
      runSpacing: AppTokens.s2,
      children: [
        AppChip(
          label: 'All',
          selected: filterState.all,
          onTap: () => notifier.selectFilter(SearchFilterType.all),
        ),
        AppChip(
          label: 'Songs',
          selected: filterState.songs,
          onTap: () => notifier.toggleFilter(SearchFilterType.songs),
        ),
        AppChip(
          label: 'Artists',
          selected: filterState.artists,
          onTap: () => notifier.toggleFilter(SearchFilterType.artists),
        ),
        AppChip(
          label: 'Albums',
          selected: filterState.albums,
          onTap: () => notifier.toggleFilter(SearchFilterType.albums),
        ),
      ],
    );
  }
}
