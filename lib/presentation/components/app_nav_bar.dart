import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tokens/app_tokens.dart';
import 'pressable.dart';

/// One destination in [AppNavBar].
class AppNavItem {
  final IconData icon;
  final IconData selectedIcon;
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
/// The selected destination sits on an accent-tinted pill (a tonal wash, never
/// an outline — the same active treatment as a list row), the icon springs
/// under the finger via [Pressable], and switching taps a selection haptic.
/// There is no ink ripple and no glass: the motion is the feedback.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppTokens.accentOf(context, ref);

    return SizedBox(
      height: 64,
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
            child: Icon(
              selected ? item.selectedIcon : item.icon,
              key: ValueKey(selected),
              size: 24,
              color: iconColor,
            ),
          ),
        ),
        const SizedBox(height: AppTokens.s1),
        AnimatedDefaultTextStyle(
          duration: AppTokens.dFast,
          curve: AppTokens.cStandard,
          style: AppTokens.meta(context).copyWith(
            color: labelColor,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          child: Text(item.label),
        ),
      ],
    );
  }
}
