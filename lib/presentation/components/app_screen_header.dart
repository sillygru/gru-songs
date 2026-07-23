import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tokens/app_tokens.dart';

/// The scrolling header for the top-level screens.
///
/// Home and Library each grew their own `SliverAppBar` with slightly different
/// backgrounds, blur handling and title weights. This is the one of them.
/// Honours the existing `showProgressiveBlurHeaders` setting.
class AppSliverHeader extends ConsumerWidget {
  final String title;

  /// Whether the content beneath has scrolled — drives the background.
  final bool isScrolled;

  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  final bool pinned;
  final bool floating;
  final bool snap;

  /// Renders [title] in the large screen-title style rather than the compact
  /// one. Used by the root screens.
  final bool large;

  const AppSliverHeader({
    super.key,
    required this.title,
    this.isScrolled = false,
    this.actions = const [],
    this.bottom,
    this.pinned = true,
    this.floating = false,
    this.snap = false,
    this.large = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;

    // No glass: when the content scrolls under the header, a solid, ambient-
    // matching scrim eases in so the title stays legible. It fades from clear
    // at the top to the scaffold colour at the bottom — depth from a gradient,
    // never a blur panel.
    final Widget? scrim = isScrolled
        ? IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scaffoldBg.withValues(alpha: 0.0),
                    scaffoldBg.withValues(alpha: 0.92),
                  ],
                ),
              ),
            ),
          )
        : null;

    return SliverAppBar(
      pinned: pinned,
      floating: floating,
      snap: snap,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleSpacing: AppTokens.s5,
      flexibleSpace: scrim,
      title: Text(
        title,
        style: large
            ? AppTokens.screenTitle(context)
            : AppTokens.paneTitle(context),
      ),
      actions: [
        ...actions,
        const SizedBox(width: AppTokens.s2),
      ],
      bottom: bottom,
    );
  }
}

/// The header for pushed sub-screens — settings pages, detail views, pickers.
/// Replaces every bare `AppBar(title: Text(...))`, so they all share one back
/// affordance, one title weight and one action spacing.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final Widget? leading;
  final bool centerTitle;

  const AppTopBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.bottom,
    this.leading,
    this.centerTitle = false,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: leading,
      centerTitle: centerTitle,
      titleSpacing: leading == null && !centerTitle ? 0 : null,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      title: Text(title, style: AppTokens.paneTitle(context)),
      actions: [
        ...actions,
        const SizedBox(width: AppTokens.s2),
      ],
      bottom: bottom,
    );
  }
}
