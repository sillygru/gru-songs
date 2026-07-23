import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/app_tokens.dart';

/// The app's segmented control — the counterpart to the player's underline
/// pill, in the app's own language: a tonal track with an accent-washed thumb
/// that slides between segments (the same active treatment as a list row, never
/// an outline). iOS-style, and deliberately *not* a Material [TabBar].
///
/// It drives off a [TabController], so the thumb tracks a [TabBarView] swipe
/// *continuously* — reading `controller.animation` rather than the settled
/// index — and existing `DefaultTabController` layouts drop it in unchanged.
class AppSegmentedTabs extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<String> labels;
  final Color? accent;

  const AppSegmentedTabs({
    super.key,
    required this.controller,
    required this.labels,
    this.accent,
  });

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final acc = accent ?? Theme.of(context).colorScheme.primary;
    final anim = controller.animation ?? kAlwaysCompleteAnimation;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s5,
        0,
        AppTokens.s5,
        AppTokens.s2,
      ),
      child: SizedBox(
        height: 40,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTokens.surface(1),
            borderRadius: AppTokens.brPill,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final segmentWidth = constraints.maxWidth / labels.length;

              return AnimatedBuilder(
                animation: anim,
                builder: (context, _) {
                  final pos = controller.animation?.value ??
                      controller.index.toDouble();
                  final clamped =
                      pos.clamp(0.0, (labels.length - 1).toDouble());

                  return Stack(
                    children: [
                      // The sliding thumb — an accent wash, matching the
                      // active-row treatment elsewhere in the app.
                      Positioned(
                        left: clamped * segmentWidth + 3,
                        top: 3,
                        bottom: 3,
                        width: segmentWidth - 6,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: acc.withValues(
                              alpha: AppTokens.accentWashAlpha,
                            ),
                            borderRadius: AppTokens.brPill,
                          ),
                        ),
                      ),
                      Row(
                        children: List.generate(labels.length, (index) {
                          final emphasis =
                              1.0 - (clamped - index).abs().clamp(0.0, 1.0);

                          return Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (controller.index == index) return;
                                HapticFeedback.selectionClick();
                                controller.animateTo(index);
                              },
                              child: Center(
                                child: Text(
                                  labels[index],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    letterSpacing: -0.1,
                                    fontWeight: FontWeight.lerp(
                                      FontWeight.w500,
                                      FontWeight.w800,
                                      emphasis,
                                    ),
                                    color: Color.lerp(
                                      AppTokens.fg(AppTokens.aSecondary),
                                      acc,
                                      emphasis,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
