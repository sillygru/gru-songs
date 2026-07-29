import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../components/app_feedback.dart';
import '../components/app_icon.dart';
import '../tokens/app_icons.dart';
import '../tokens/app_tokens.dart';

/// App bar action button that displays a shuffle icon by default, but replaces
/// it with a circular progress indicator following the app theme whenever library
/// scanning / analyzing is in progress.
class HeaderShuffleButton extends ConsumerWidget {
  final VoidCallback? onShufflePressed;
  final String tooltip;
  final Color? color;

  const HeaderShuffleButton({
    super.key,
    this.onShufflePressed,
    this.tooltip = 'Shuffle all',
    this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isScanning = ref.watch(isScanningProvider);
    final scanProgress = ref.watch(scanProgressProvider);
    final accent = AppTokens.accentOf(context, ref);
    final effectiveColor = color ?? accent;

    return AnimatedSwitcher(
      duration: AppTokens.dBase,
      switchInCurve: AppTokens.cEmphasized,
      switchOutCurve: AppTokens.cEmphasized,
      child: isScanning
          ? _HeaderScanProgressCircle(
              key: const ValueKey('header_scan_progress'),
              progress: scanProgress,
              color: effectiveColor,
            )
          : IconButton(
              key: const ValueKey('header_shuffle_button'),
              tooltip: tooltip,
              icon: AppIcon(AppIcons.shuffle, color: effectiveColor),
              onPressed: onShufflePressed,
            ),
    );
  }
}

class _HeaderScanProgressCircle extends StatelessWidget {
  final double progress;
  final Color color;

  const _HeaderScanProgressCircle({
    super.key,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final clampedProgress = progress.clamp(0.0, 1.0);
    final percentage = (clampedProgress * 100).toInt();

    return Tooltip(
      message: 'Scanning library ($percentage%)',
      child: Semantics(
        label: 'Scanning library $percentage percent complete',
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.rPill),
          onTap: () {
            appSnack(
              context,
              'Scanning library: $percentage%',
              tone: AppTone.info,
            );
          },
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  value: clampedProgress > 0 ? clampedProgress : null,
                  strokeWidth: 2.5,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.2),
                  strokeCap: StrokeCap.round,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
