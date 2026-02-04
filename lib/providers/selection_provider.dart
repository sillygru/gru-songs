import 'package:flutter_riverpod/flutter_riverpod.dart';

class SelectionState {
  final bool isSelectionMode;
  final Set<String> selectedFilenames;

  SelectionState({
    this.isSelectionMode = false,
    this.selectedFilenames = const {},
  });

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
    state = state.copyWith(
      isSelectionMode: !state.isSelectionMode,
      selectedFilenames: {},
    );
  }

  void enterSelectionMode(String initialFilename) {
    state = state.copyWith(
      isSelectionMode: true,
      selectedFilenames: {initialFilename},
    );
  }

  void exitSelectionMode() {
    state = SelectionState();
  }

  void toggleSelection(String filename) {
    final current = Set<String>.from(state.selectedFilenames);
    if (current.contains(filename)) {
      current.remove(filename);
      if (current.isEmpty) {
        state = SelectionState(); // Exit if none left
        return;
      }
    } else {
      current.add(filename);
    }
    state = state.copyWith(selectedFilenames: current);
  }

  void selectAll(List<String> filenames) {
    state = state.copyWith(selectedFilenames: Set.from(filenames));
  }
}

final selectionProvider =
    NotifierProvider<SelectionNotifier, SelectionState>(() {
  return SelectionNotifier();
});
