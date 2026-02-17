import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/quick_action_config.dart';
import '../../providers/settings_provider.dart';

class QuickActionsSettingsScreen extends ConsumerStatefulWidget {
  const QuickActionsSettingsScreen({super.key});

  @override
  ConsumerState<QuickActionsSettingsScreen> createState() =>
      _QuickActionsSettingsScreenState();
}

class _QuickActionsSettingsScreenState
    extends ConsumerState<QuickActionsSettingsScreen> {
  late List<QuickAction> _orderedActions;
  late Set<QuickAction> _enabledActions;

  @override
  void initState() {
    super.initState();
    final config = ref.read(settingsProvider).quickActionConfig;
    _orderedActions = List.from(config.actionOrder);
    _enabledActions = Set.from(config.enabledActions);
  }

  void _saveConfig() {
    final enabledOrder = _orderedActions
        .where((action) => _enabledActions.contains(action))
        .toList();
    final config = QuickActionConfig(
      enabledActions: enabledOrder,
      actionOrder: _orderedActions,
    );
    ref.read(settingsProvider.notifier).setQuickActionConfig(config);
  }

  String _getActionLabel(QuickAction action) {
    switch (action) {
      case QuickAction.playNext:
        return 'Play Next';
      case QuickAction.goToAlbum:
        return 'Go to Album';
      case QuickAction.goToArtist:
        return 'Go to Artist';
      case QuickAction.moveToFolder:
        return 'Move to Folder';
      case QuickAction.addToPlaylist:
        return 'Add to Playlist';
      case QuickAction.addToNewPlaylist:
        return 'Add to New Playlist';
      case QuickAction.editMetadata:
        return 'Edit Metadata';
      case QuickAction.toggleFavorite:
        return 'Favorite';
      case QuickAction.toggleSuggestLess:
        return 'Suggest Less';
      case QuickAction.delete:
        return 'Delete';
      case QuickAction.hide:
        return 'Hide';
    }
  }

  Widget _getActionIcon(QuickAction action, bool enabled) {
    final color = enabled
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outline;
    return Icon(_getIconData(action), color: color);
  }

  IconData _getIconData(QuickAction action) {
    switch (action) {
      case QuickAction.playNext:
        return Icons.queue;
      case QuickAction.goToAlbum:
        return Icons.album;
      case QuickAction.goToArtist:
        return Icons.person;
      case QuickAction.moveToFolder:
        return Icons.drive_file_move_outlined;
      case QuickAction.addToPlaylist:
        return Icons.playlist_add;
      case QuickAction.addToNewPlaylist:
        return Icons.playlist_add_circle_outlined;
      case QuickAction.editMetadata:
        return Icons.edit_outlined;
      case QuickAction.toggleFavorite:
        return Icons.favorite;
      case QuickAction.toggleSuggestLess:
        return Icons.heart_broken;
      case QuickAction.delete:
        return Icons.delete_outline;
      case QuickAction.hide:
        return Icons.visibility_off;
    }
  }

  void _resetToDefaults() {
    setState(() {
      _orderedActions = List.from(QuickActionConfig.defaultOrder);
      _enabledActions = Set.from(QuickActionConfig.defaultEnabled);
    });
    _saveConfig();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reset to defaults')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabledActions = _orderedActions
        .where((action) => _enabledActions.contains(action))
        .toList();
    final disabledActions = _orderedActions
        .where((action) => !_enabledActions.contains(action))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Quick Actions"),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _resetToDefaults,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (enabledActions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ENABLED (${enabledActions.length})',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: enabledActions.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final item = enabledActions.removeAt(oldIndex);
                    enabledActions.insert(newIndex, item);
                    _orderedActions = [
                      ...enabledActions,
                      ...disabledActions,
                    ];
                  });
                },
                itemBuilder: (context, index) {
                  final action = enabledActions[index];
                  return _buildActionTile(
                    key: ValueKey(action),
                    action: action,
                    enabled: true,
                    index: index,
                  );
                },
              ),
            ),
          ],
          if (disabledActions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.disabled_by_default,
                    size: 16,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'DISABLED (${disabledActions.length})',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.outline,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: disabledActions.length,
                itemBuilder: (context, index) {
                  final action = disabledActions[index];
                  return _buildActionTile(
                    key: ValueKey(action),
                    action: action,
                    enabled: false,
                    index: index,
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required Key key,
    required QuickAction action,
    required bool enabled,
    required int index,
  }) {
    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.3),
      child: ListTile(
        leading: _getActionIcon(action, enabled),
        title: Text(
          _getActionLabel(action),
          style: TextStyle(
            color: enabled
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.outline,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: enabled,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _enabledActions.add(action);
                  } else {
                    _enabledActions.remove(action);
                  }
                });
                _saveConfig();
              },
            ),
            if (enabled)
              ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle),
              ),
          ],
        ),
      ),
    );
  }
}
