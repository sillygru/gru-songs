import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
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
    final blurEnabled =
        ref.watch(settingsProvider.select((s) => s.showProgressiveBlurHeaders));
    final useBlur = blurEnabled && isScrolled;

    return SliverAppBar(
      pinned: pinned,
      floating: floating,
      snap: snap,
      backgroundColor: isScrolled && !blurEnabled
          ? Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.95)
          : Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleSpacing: AppTokens.s5,
      flexibleSpace: useBlur
          ? RepaintBoundary(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Container(color: Colors.transparent),
                ),
              ),
            )
          : null,
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
