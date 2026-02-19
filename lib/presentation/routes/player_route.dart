import 'package:flutter/material.dart';
import '../screens/player_screen.dart';

class PlayerPageRoute extends PageRoute<void> {
  PlayerPageRoute({required this.songId});

  final String songId;

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => true;

  @override
  Color get barrierColor => Colors.transparent;

  @override
  String get barrierLabel => 'Dismiss player';

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return const PlayerScreen();
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final primary = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutQuart,
      reverseCurve: Curves.easeInCubic,
    );
    final backdrop = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      reverseCurve: const Interval(0.0, 0.75, curve: Curves.easeIn),
    );
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(primary);
    final scale = Tween<double>(begin: 0.992, end: 1.0).animate(primary);

    return Stack(
      children: [
        FadeTransition(
          opacity: backdrop,
          child: Container(
            color: Colors.black.withValues(alpha: 0.46),
          ),
        ),
        FadeTransition(
          opacity: primary,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(
              scale: scale,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget buildModalBarrier() {
    return const SizedBox.shrink();
  }
}
