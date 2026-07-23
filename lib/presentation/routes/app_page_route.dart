import 'package:flutter/material.dart';

/// The one sub-screen transition for the whole app.
///
/// Every pushed screen — settings pages, detail views, pickers — used the stock
/// [MaterialPageRoute] slide, which is the platform default and reads as
/// "generic app." This is the counterpart to the player's [PlayerPageRoute]: the
/// incoming screen *rises into place* (fade + a short lift + a hair of scale)
/// and the screen it covers recedes a touch, so navigation feels like one
/// continuous surface rather than cards sliding over each other.
///
/// Push with `context.pushApp(SomeScreen())`.
class AppPageRoute<T> extends PageRoute<T> {
  AppPageRoute({
    required this.builder,
    super.settings,
    super.fullscreenDialog,
  });

  final WidgetBuilder builder;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  bool get opaque => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 240);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final incoming = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutQuart,
      reverseCurve: Curves.easeInCubic,
    );
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).animate(incoming);
    final scale = Tween<double>(begin: 0.98, end: 1.0).animate(incoming);

    // The screen underneath eases back and dims slightly as this one arrives,
    // then comes forward again on pop — the sense of depth between screens.
    final receding = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final underScale = Tween<double>(begin: 1.0, end: 0.985).animate(receding);
    final underFade = Tween<double>(begin: 1.0, end: 0.55).animate(receding);

    return FadeTransition(
      opacity: underFade,
      child: ScaleTransition(
        scale: underScale,
        child: FadeTransition(
          opacity: incoming,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(scale: scale, child: child),
          ),
        ),
      ),
    );
  }
}

/// Push [page] with the app's shared [AppPageRoute] transition.
extension AppNavigation on BuildContext {
  Future<T?> pushApp<T>(Widget page, {bool fullscreenDialog = false}) {
    return Navigator.of(this).push<T>(
      AppPageRoute<T>(
        builder: (_) => page,
        fullscreenDialog: fullscreenDialog,
      ),
    );
  }
}
