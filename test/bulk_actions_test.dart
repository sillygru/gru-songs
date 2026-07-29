import 'dart:collection';
import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/providers/selection_provider.dart';

void main() {
  group('SelectionState Tests', () {
    test('initial state is empty', () {
      final state = SelectionState();
      expect(state.isSelectionMode, false);
      expect(state.selectedFilenames, isEmpty);
    });

    test('copyWith updates values correctly', () {
      final state = SelectionState();
      final updated = state.copyWith(
        isSelectionMode: true,
        selectedFilenames: LinkedHashSet<String>.from({'song1.mp3'}),
      );
      expect(updated.isSelectionMode, true);
      expect(updated.selectedFilenames, {'song1.mp3'});
    });
  });
}
