import 'dart:collection';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SelectionState {
  final bool isSelectionMode;
  final LinkedHashSet<String> selectedFilenames;

  SelectionState({
    this.isSelectionMode = false,
    LinkedHashSet<String>? selectedFilenames,
  }) : selectedFilenames = selectedFilenames ?? LinkedHashSet<String>();

  SelectionState copyWith({
    bool? isSelectionMode,
    LinkedHashSet<String>? selectedFilenames,
  }) {
    return SelectionState(
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      selectedFilenames: selectedFilenames ?? this.selectedFilenames,
    );
  }
}

class SelectionNotifier extends Notifier<SelectionState> {
  @override
  SelectionState build() {
    return SelectionState();
  }

  void toggleSelectionMode() {
    state = SelectionState(
      isSelectionMode: !state.isSelectionMode,
      selectedFilenames: LinkedHashSet<String>(),
    );
  }

  void enterSelectionMode(String initialFilename) {
    final newSet = LinkedHashSet<String>();
    newSet.add(initialFilename);
    state = SelectionState(
      isSelectionMode: true,
      selectedFilenames: newSet,
    );
  }

  void exitSelectionMode() {
    state = SelectionState();
  }

  void toggleSelection(String filename) {
    final current = LinkedHashSet<String>.from(state.selectedFilenames);
    if (current.contains(filename)) {
      current.remove(filename);
      if (current.isEmpty) {
        state = SelectionState();
        return;
      }
    } else {
      current.add(filename);
    }
    state = state.copyWith(selectedFilenames: current);
  }

  void selectAll(List<String> filenames) {
    state = state.copyWith(selectedFilenames: LinkedHashSet.from(filenames));
  }

  List<String> getOrderedSelection() {
    return state.selectedFilenames.toList();
  }
}

final selectionProvider =
    NotifierProvider<SelectionNotifier, SelectionState>(() {
  return SelectionNotifier();
});
