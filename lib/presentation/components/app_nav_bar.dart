import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tokens/app_tokens.dart';
import 'pressable.dart';
import '../tokens/app_icons.dart';
import 'app_icon.dart';

/// One destination in [AppNavBar].
class AppNavItem {
  final AppIconData icon;
  final AppIconData selectedIcon;
  final String label;

  const AppNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// The app's bottom navigation — a bespoke bar rather than Material's
/// [NavigationBar], so the tap feel matches the rest of the revamp.
///
/// It spans the full width and sits flush against the bottom edge, painting the
/// safe-area strip in its own fill so it runs under the gesture bar rather than
/// hovering above it. The selected destination sits on an accent-tinted pill (a
/// tonal wash, never an outline — the same active treatment as a list row), the
/// icon springs under the finger via [Pressable], and switching taps a
/// selection haptic. There is no ink ripple and no glass: the motion is the
/// feedback.
class AppNavBar extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<AppNavItem> items;

  const AppNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  /// Height of the destination row, above whatever safe-area strip the bar
  /// paints beneath it.
  static const double _rowHeight = 64;

  /// [AppTokens.shadowFloating], cast upward. A bar flush to the bottom edge
  /// has nothing below it, so the token's downward offset would fall off-screen
  /// and leave the bar sitting on the content with no separation at all.
  static const List<BoxShadow> _liftShadow = [
    BoxShadow(
      color: Color(0x40000000),
      blurRadius: 24,
      offset: Offset(0, -12),
      spreadRadius: -8,
    ),
    BoxShadow(
      color: Color(0x26000000),
      blurRadius: 8,
      offset: Offset(0, -3),
      spreadRadius: -3,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppTokens.accentOf(context, ref);
    // Opaque, never translucent: a glass dock would show the list scrolling
    // through it. The fill is the canvas lifted one notch, so the bar reads as
    // a solid slab over the page — the shadow does the lifting.
    final dockColor = Color.alphaBlend(
      AppTokens.floatingFill,
      Theme.of(context).colorScheme.surface,
    );

    return DecoratedBox(
      decoration: const BoxDecoration(boxShadow: _liftShadow),
      child: ColoredBox(
        color: dockColor,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: _rowHeight,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: Pressable(
                      haptic: PressHaptic.selection,
                      spring: AppTokens.springSnappy,
                      onTap: () => onSelected(i),
                      child: _NavDestination(
                        item: items[i],
                        selected: i == selectedIndex,
                        accent: accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavDestination extends StatelessWidget {
  final AppNavItem item;
  final bool selected;
  final Color accent;

  const _NavDestination({
    required this.item,
    required this.selected,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = selected ? accent : AppTokens.fg(AppTokens.aTertiary);
    final labelColor = selected ? accent : AppTokens.fg(AppTokens.aTertiary);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: AppTokens.dFast,
          curve: AppTokens.cStandard,
          width: 60,
          height: 32,
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: AppTokens.accentWashAlpha)
                : Colors.transparent,
            borderRadius: AppTokens.brPill,
          ),
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: AppTokens.dFast,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: AppIcon(
              selected ? item.selectedIcon : item.icon,
              key: ValueKey(selected),
              size: AppTokens.iconMd,
              color: iconColor,
              // Icon weight echoes the depth ladder: the active glyph draws a
              // heavier stroke, the way a raised surface reads heavier.
              strokeWidth: selected
                  ? AppTokens.iconStrokeEmphasis
                  : AppTokens.iconStroke,
            ),
          ),
        ),
        const SizedBox(height: AppTokens.s1),
        AnimatedDefaultTextStyle(
          duration: AppTokens.dFast,
          curve: AppTokens.cStandard,
          style: AppTokens.meta(context).copyWith(
            color: labelColor,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
          child: Text(item.label),
        ),
      ],
    );
  }
}
