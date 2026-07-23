import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tokens/app_tokens.dart';
import 'press_highlight.dart';

/// Opens the app's one bottom sheet.
///
/// Every `showModalBottomSheet` in the app routes through here so the grab
/// handle, corner radius, fill and safe-area handling are decided once.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool isScrollControlled = true,
  bool showHandle = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => AppSheet(
      title: title,
      showHandle: showHandle,
      child: Builder(builder: builder),
    ),
  );
}

/// The sheet shell: grab handle, optional title, flat fill, large top corners.
class AppSheet extends ConsumerWidget {
  final Widget child;
  final String? title;
  final bool showHandle;

  /// Trailing action in the title row — a "Done", a clear button.
  final Widget? action;

  const AppSheet({
    super.key,
    required this.child,
    this.title,
    this.showHandle = true,
    this.action,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accent = AppTokens.accentOf(context, ref);

    return Container(
      decoration: BoxDecoration(
        // Flat, no glass — a near-scaffold fill lifted by a hint of the current
        // cover colour so the sheet reads as part of the immersive surface.
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.10),
          Color.alphaBlend(
            AppTokens.surface(1),
            theme.scaffoldBackgroundColor,
          ),
        ),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.rLg),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHandle)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppTokens.s3,
                  bottom: AppTokens.s2,
                ),
                child: Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTokens.fg(0.28),
                      borderRadius: AppTokens.brPill,
                    ),
                  ),
                ),
              ),
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s5,
                  AppTokens.s2,
                  AppTokens.s3,
                  AppTokens.s3,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTokens.paneTitle(context),
                      ),
                    ),
                    if (action != null) action!,
                  ],
                ),
              ),
            Flexible(child: child),
            const SizedBox(height: AppTokens.s2),
          ],
        ),
      ),
    );
  }
}

/// A single tappable action inside a sheet. Replaces the `ListTile`s that
/// option sheets currently hand-build, each with its own icon tint.
class AppSheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? description;
  final VoidCallback? onTap;

  /// Destructive actions — delete, remove, reset.
  final bool isDanger;

  /// Trailing slot for a switch or a check mark.
  final Widget? trailing;

  const AppSheetAction({
    super.key,
    required this.icon,
    required this.label,
    this.description,
    this.onTap,
    this.isDanger = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDanger ? AppTokens.danger : Colors.white;

    return PressHighlight(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s5,
          vertical: AppTokens.s3,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: AppTokens.s4),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTokens.rowTitle(context).copyWith(
                      color: color,
                      fontSize: 15,
                    ),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 2),
                    Text(description!, style: AppTokens.meta(context)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppTokens.s2),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
