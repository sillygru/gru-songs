import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/providers/providers.dart';

/// The dock is deliberately lopsided: easy to bring back, harder to dismiss.
/// Symmetric travel meant a flick down hid it and half a screen of upward drag
/// was needed to see it again.
void main() {
  late ProviderContainer container;

  BottomDockVisibilityNotifier notifier() =>
      container.read(bottomDockVisibilityProvider.notifier);

  double visibility() =>
      container.read(bottomDockVisibilityProvider).visibility;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('starts fully visible', () {
    expect(visibility(), 1.0);
  });

  test('a short upward drag from hidden settles the dock back in', () {
    notifier().updateFromDrag(scrollDelta: 400); // scroll down, hide
    notifier().settle();
    expect(visibility(), 0.0);

    notifier().updateFromDrag(scrollDelta: -18);
    notifier().settle();
    expect(visibility(), 1.0);
  });

  test('a nudge downward springs back rather than hiding', () {
    notifier().updateFromDrag(scrollDelta: 18);
    notifier().settle();
    expect(visibility(), 1.0);
  });

  test('sustained downward travel does hide it', () {
    notifier().updateFromDrag(
      scrollDelta: BottomDockVisibilityNotifier.hideDragDistance,
    );
    notifier().settle();
    expect(visibility(), 0.0);
  });

  test('revealing takes far less travel than hiding', () {
    expect(
      BottomDockVisibilityNotifier.revealDragDistance,
      lessThan(BottomDockVisibilityNotifier.hideDragDistance),
    );
  });

  test('show() overrides a half-finished hide', () {
    notifier().updateFromDrag(scrollDelta: 60);
    expect(visibility(), lessThan(1.0));

    notifier().show();
    expect(visibility(), 1.0);
    expect(container.read(bottomDockVisibilityProvider).isDragging, isFalse);
  });

  test('visibility never leaves 0..1', () {
    notifier().updateFromDrag(scrollDelta: 5000);
    expect(visibility(), 0.0);
    notifier().updateFromDrag(scrollDelta: -5000);
    expect(visibility(), 1.0);
  });
}
