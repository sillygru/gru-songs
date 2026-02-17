import 'dart:convert';

enum QuickAction {
  playNext,
  goToAlbum,
  goToArtist,
  moveToFolder,
  addToPlaylist,
  share,
  addToNewPlaylist,
  editMetadata,
  toggleFavorite,
  toggleSuggestLess,
  delete,
  hide,
}

class QuickActionConfig {
  final List<QuickAction> enabledActions;
  final List<QuickAction> actionOrder;

  const QuickActionConfig({
    required this.enabledActions,
    required this.actionOrder,
  });

  static const List<QuickAction> defaultOrder = [
    QuickAction.toggleFavorite,
    QuickAction.playNext,
    QuickAction.addToPlaylist,
    QuickAction.share,
    QuickAction.delete,
    QuickAction.hide,
    QuickAction.goToAlbum,
    QuickAction.goToArtist,
    QuickAction.moveToFolder,
    QuickAction.addToNewPlaylist,
    QuickAction.editMetadata,
    QuickAction.toggleSuggestLess,
  ];

  static const List<QuickAction> defaultEnabled = [
    QuickAction.toggleFavorite,
    QuickAction.playNext,
    QuickAction.addToPlaylist,
    QuickAction.share,
    QuickAction.delete,
  ];

  static QuickActionConfig get defaults => const QuickActionConfig(
        enabledActions: defaultEnabled,
        actionOrder: defaultOrder,
      );

  QuickActionConfig copyWith({
    List<QuickAction>? enabledActions,
    List<QuickAction>? actionOrder,
  }) {
    return QuickActionConfig(
      enabledActions: enabledActions ?? this.enabledActions,
      actionOrder: actionOrder ?? this.actionOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabledActions': enabledActions.map((e) => e.index).toList(),
        'actionOrder': actionOrder.map((e) => e.index).toList(),
      };

  factory QuickActionConfig.fromJson(Map<String, dynamic> json) {
    return QuickActionConfig(
      enabledActions: (json['enabledActions'] as List<dynamic>?)
              ?.map((e) => QuickAction.values[e as int])
              .toList() ??
          defaultEnabled,
      actionOrder: (json['actionOrder'] as List<dynamic>?)
              ?.map((e) => QuickAction.values[e as int])
              .toList() ??
          defaultOrder,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory QuickActionConfig.fromJsonString(String jsonString) {
    try {
      return QuickActionConfig.fromJson(jsonDecode(jsonString));
    } catch (_) {
      return defaults;
    }
  }
}
