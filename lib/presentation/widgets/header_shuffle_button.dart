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
///
/// A long press opens a small menu anchored to the button with deferred
/// variants of the same shuffle — after the current song, or after the
/// current queue. Tap always shuffles immediately.
class HeaderShuffleButton extends ConsumerStatefulWidget {
  final VoidCallback? onShufflePressed;
  final VoidCallback? onShuffleAfterSong;
  final VoidCallback? onShuffleAfterQueue;
  final String tooltip;
  final Color? color;

  const HeaderShuffleButton({
    super.key,
    this.onShufflePressed,
    this.onShuffleAfterSong,
    this.onShuffleAfterQueue,
    this.tooltip = 'Shuffle all',
    this.color,
  });

  @override
  ConsumerState<HeaderShuffleButton> createState() =>
      _HeaderShuffleButtonState();
}

class _HeaderShuffleButtonState extends ConsumerState<HeaderShuffleButton> {
  final MenuController _menuController = MenuController();

  void _openHoldMenu() {
    if (_menuController.isOpen) return;
    _menuController.open();
  }

  @override
  Widget build(BuildContext context) {
    final isScanning = ref.watch(isScanningProvider);
    final scanProgress = ref.watch(scanProgressProvider);
    final accent = AppTokens.accentOf(context, ref);
    final effectiveColor = widget.color ?? accent;

    final hasHoldActions =
        widget.onShuffleAfterSong != null || widget.onShuffleAfterQueue != null;

    Widget button = IconButton(
      key: const ValueKey('header_shuffle_button'),
      tooltip: widget.tooltip,
      icon: AppIcon(AppIcons.shuffle, color: effectiveColor),
      onPressed: widget.onShufflePressed,
      onLongPress: hasHoldActions ? _openHoldMenu : null,
    );

    if (hasHoldActions) {
      button = MenuAnchor(
        controller: _menuController,
        alignmentOffset: const Offset(0, AppTokens.s2),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppTokens.surface(2)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppTokens.brMd),
          ),
        ),
        menuChildren: [
          if (widget.onShuffleAfterSong != null)
            MenuItemButton(
              leadingIcon: const AppIcon(AppIcons.skipNext),
              onPressed: widget.onShuffleAfterSong,
              child: Text(
                'Shuffle after current song',
                style: AppTokens.rowTitle(context),
              ),
            ),
          if (widget.onShuffleAfterQueue != null)
            MenuItemButton(
              leadingIcon: const AppIcon(AppIcons.queue),
              onPressed: widget.onShuffleAfterQueue,
              child: Text(
                'Shuffle after current queue',
                style: AppTokens.rowTitle(context),
              ),
            ),
        ],
        builder: (context, controller, child) => child!,
        child: button,
      );
    }

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
          : button,
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
