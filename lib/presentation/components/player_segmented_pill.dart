import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/player_tokens.dart';

/// Pane switcher: plain labels sitting directly on the backdrop with a sliding
/// underline. No container, no border — the labels are there so the panes are
/// discoverable, not to be a piece of furniture in their own right.
///
/// The underline is driven by a *fractional* position so it tracks a swipe
/// continuously instead of jumping once the page settles.
class PlayerSegmentedPill extends StatelessWidget {
  final List<String> labels;

  /// Continuous position in segment units — 0.0 is the first label, 1.0 the
  /// second, 0.5 exactly between them.
  final ValueListenable<double> position;
  final ValueChanged<int> onSelected;
  final Color accent;
  final bool compact;

  const PlayerSegmentedPill({
    super.key,
    required this.labels,
    required this.position,
    required this.onSelected,
    required this.accent,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = compact ? 11.5 : 13.0;
    final height = compact ? 26.0 : 30.0;

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / labels.length;

          return ValueListenableBuilder<double>(
            valueListenable: position,
            builder: (context, value, _) {
              final clamped = value.clamp(0.0, (labels.length - 1).toDouble());

              return Stack(
                children: [
                  Row(
                    children: List.generate(labels.length, (index) {
                      // Full strength when the underline is centred here,
                      // fading as it slides away.
                      final emphasis =
                          1.0 - (clamped - index).abs().clamp(0.0, 1.0);

                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onSelected(index);
                          },
                          child: Center(
                            child: Text(
                              labels[index],
                              style: TextStyle(
                                fontSize: fontSize,
                                letterSpacing: 0.3,
                                fontWeight: FontWeight.lerp(
                                  FontWeight.w500,
                                  FontWeight.w800,
                                  emphasis,
                                ),
                                color: Color.lerp(
                                  Colors.white.withValues(
                                      alpha: PlayerTokens.aTertiary),
                                  accent,
                                  emphasis,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  Positioned(
                    left: clamped * segmentWidth + segmentWidth / 2 - 9,
                    bottom: 0,
                    child: Container(
                      width: 18,
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: PlayerTokens.brPill,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
