import 'package:flutter/material.dart';
import '../components/ambient_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/quick_action_config.dart';
import '../../providers/settings_provider.dart';
import '../components/app_surface.dart';
import '../components/app_feedback.dart';
import '../components/app_icon.dart';
import '../tokens/app_icons.dart';

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
      case QuickAction.share:
        return 'Share';
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
    return AppIcon(_getIconData(action), color: color);
  }

  AppIconData _getIconData(QuickAction action) {
    switch (action) {
      case QuickAction.playNext:
        return AppIcons.queue;
      case QuickAction.goToAlbum:
        return AppIcons.album;
      case QuickAction.goToArtist:
        return AppIcons.person;
      case QuickAction.moveToFolder:
        return AppIcons.folderMove;
      case QuickAction.addToPlaylist:
        return AppIcons.playlistAdd;
      case QuickAction.share:
        return AppIcons.share;
      case QuickAction.addToNewPlaylist:
        return AppIcons.playlistAdd;
      case QuickAction.editMetadata:
        return AppIcons.edit;
      case QuickAction.toggleFavorite:
        return AppIcons.favorite;
      case QuickAction.toggleSuggestLess:
        return AppIcons.heartBroken;
      case QuickAction.delete:
        return AppIcons.delete;
      case QuickAction.hide:
        return AppIcons.visibilityOff;
    }
  }

  void _resetToDefaults() {
    setState(() {
      _orderedActions = List.from(QuickActionConfig.defaultOrder);
      _enabledActions = Set.from(QuickActionConfig.defaultEnabled);
    });
    _saveConfig();
    appSnack(context, 'Reset to defaults');
  }

  @override
  Widget build(BuildContext context) {
    final enabledActions = _orderedActions
        .where((action) => _enabledActions.contains(action))
        .toList();
    final disabledActions = _orderedActions
        .where((action) => !_enabledActions.contains(action))
        .toList();

    return AmbientScaffold(
      appBar: AppBar(
        title: const Text("Quick Actions"),
        actions: [
          TextButton(
            onPressed: _resetToDefaults,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          if (enabledActions.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    AppIcon(
                      AppIcons.checkCircle,
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
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverReorderableList(
                itemCount: enabledActions.length,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final item = enabledActions.removeAt(oldIndex);
                    enabledActions.insert(newIndex, item);
                    _orderedActions = [
                      ...enabledActions,
                      ...disabledActions,
                    ];
                  });
                  _saveConfig();
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    AppIcon(
                      AppIcons.close,
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
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final action = disabledActions[index];
                    return _buildActionTile(
                      key: ValueKey(action),
                      action: action,
                      enabled: false,
                      index: index,
                    );
                  },
                  childCount: disabledActions.length,
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(
            child: SizedBox(height: 100),
          ),
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
    return AppSurface(
      padding: EdgeInsets.zero,
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
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
                child: const AppIcon(AppIcons.dragHandle),
              ),
          ],
        ),
      ),
    );
  }
}
