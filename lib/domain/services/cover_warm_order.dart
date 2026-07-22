/// Ordering for passive, background work that walks a playback queue.
///
/// Pure and I/O-free so it can be tested directly.
library;

/// [items] reordered so the ones that will be needed soonest come first:
/// the entry after [currentIndex], then forward to the end of the queue, then
/// wrapping round to the start and back up to [currentIndex] itself.
///
/// [currentIndex] may be out of range (nothing playing yet, or a queue that has
/// since shrunk), in which case the list is returned in its natural order.
/// Every element appears exactly once.
List<T> orderForWarming<T>(List<T> items, int currentIndex) {
  if (items.length <= 1) return List<T>.from(items);
  if (currentIndex < 0 || currentIndex >= items.length) {
    return List<T>.from(items);
  }

  final ordered = <T>[];
  for (int offset = 1; offset <= items.length; offset++) {
    ordered.add(items[(currentIndex + offset) % items.length]);
  }
  return ordered;
}
