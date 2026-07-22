import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/services/cover_warm_order.dart';

void main() {
  group('orderForWarming', () {
    test('starts with the entry after the current one', () {
      final result = orderForWarming([0, 1, 2, 3, 4], 1);
      expect(result.first, 2);
    });

    test('walks forward, wraps to the start, and ends on the current entry',
        () {
      expect(orderForWarming([0, 1, 2, 3, 4], 2), [3, 4, 0, 1, 2]);
    });

    test('wraps immediately when the current entry is last', () {
      expect(orderForWarming([0, 1, 2, 3], 3), [0, 1, 2, 3]);
    });

    test('covers every element exactly once', () {
      final items = List<int>.generate(298, (i) => i);
      final result = orderForWarming(items, 42);

      expect(result, hasLength(items.length));
      expect(result.toSet(), items.toSet());
    });

    test('falls back to natural order for an out-of-range index', () {
      expect(orderForWarming([0, 1, 2], 9), [0, 1, 2]);
      expect(orderForWarming([0, 1, 2], -1), [0, 1, 2]);
    });

    test('handles empty and single-item lists', () {
      expect(orderForWarming(<int>[], 0), isEmpty);
      expect(orderForWarming([7], 0), [7]);
    });

    test('does not alias the input list', () {
      final items = [0, 1, 2];
      final result = orderForWarming(items, 0);
      result.add(99);
      expect(items, [0, 1, 2]);
    });
  });
}
