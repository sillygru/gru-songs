import 'package:flutter_riverpod/flutter_riverpod.dart';

class SelectionState {
  final bool isSelectionMode;
  final Set<String> selectedFilenames;

  SelectionState({
    this.isSelectionMode = false,
    Set<String>? selectedFilenames,
  }) : selectedFilenames = selectedFilenames ?? {};

  SelectionState copyWith({
    bool? isSelectionMode,
    Set<String>? selectedFilenames,
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
      selectedFilenames: {},
    );
  }

  void enterSelectionMode(String initialFilename) {
    final newSet = <String>{};
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
    final current = <String>{...state.selectedFilenames};
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
    state = state.copyWith(selectedFilenames: <String>{...filenames});
  }

  List<String> getOrderedSelection() {
    return state.selectedFilenames.toList();
  }
}

final selectionProvider =
    NotifierProvider<SelectionNotifier, SelectionState>(() {
  return SelectionNotifier();
});
