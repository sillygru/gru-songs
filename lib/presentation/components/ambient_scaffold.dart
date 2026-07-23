import 'package:flutter/material.dart';

import '../widgets/immersive_background.dart';

/// A [Scaffold] that sits over the app-wide [AmbientLayer].
///
/// This is what carries the immersive, cover-tinted backdrop into every pushed
/// sub-screen (settings, detail views, pickers) — where a bare
/// `Scaffold(appBar: AppBar(...))` would otherwise drop back onto a flat,
/// generic surface. The ambient fills the whole screen; a fully transparent
/// [Scaffold] lays its app bar and body over it, so there is no card, no glass
/// and no outline between chrome and backdrop.
///
/// It is a drop-in for [Scaffold]: the app bar and body lay out exactly as they
/// would normally (no content hides behind the bar), only the background
/// changes.
class AmbientScaffold extends StatelessWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final Widget? bottomSheet;

  /// Force a specific ambient tint instead of the live cover colour.
  final Color? colorOverride;

  final bool resizeToAvoidBottomInset;

  const AmbientScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.bottomSheet,
    this.colorOverride,
    this.resizeToAvoidBottomInset = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: AmbientLayer(colorOverride: colorOverride)),
        Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          appBar: appBar,
          floatingActionButton: floatingActionButton,
          floatingActionButtonLocation: floatingActionButtonLocation,
          bottomNavigationBar: bottomNavigationBar,
          bottomSheet: bottomSheet,
          body: body,
        ),
      ],
    );
  }
}
