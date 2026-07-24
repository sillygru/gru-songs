import 'package:flutter/material.dart';
import '../../services/backup_service.dart';
import '../tokens/app_tokens.dart';
import '../components/app_icon.dart';
import '../tokens/app_icons.dart';

class BackupOptionsDialog extends StatefulWidget {
  final Set<BackupContentType> initialTypes;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final AppIconData buttonIcon;

  const BackupOptionsDialog({
    super.key,
    required this.initialTypes,
    this.title = 'Create Backup',
    this.subtitle = 'Select content to backup',
    this.buttonLabel = 'Create',
    this.buttonIcon = AppIcons.cloudUpload,
  });

  @override
  State<BackupOptionsDialog> createState() => _BackupOptionsDialogState();
}

class _BackupOptionsDialogState extends State<BackupOptionsDialog> {
  late final Set<BackupContentType> _selectedTypes =
      Set.of(widget.initialTypes);

  String _getContentTypeName(BackupContentType type) {
    switch (type) {
      case BackupContentType.userStats:
        return 'User Stats';
      case BackupContentType.userData:
        return 'User Data';
      case BackupContentType.userSettings:
        return 'User Settings';
      case BackupContentType.coverCache:
        return 'Cover Cache';
      case BackupContentType.libraryCache:
        return 'Library Cache';
      case BackupContentType.searchIndex:
        return 'Search Index';
      case BackupContentType.waveformCache:
        return 'Waveform Cache';
      case BackupContentType.colorCache:
        return 'Color Cache';
      case BackupContentType.lyricsCache:
        return 'Lyrics Cache';
    }
  }

  String _getContentTypeDescription(BackupContentType type) {
    switch (type) {
      case BackupContentType.userStats:
        return 'Play history, stats, merged groups';
      case BackupContentType.userData:
        return 'Favorites, playlists, preferences';
      case BackupContentType.userSettings:
        return 'Theme, sort order, app preferences';
      case BackupContentType.coverCache:
        return 'Cached album artwork';
      case BackupContentType.libraryCache:
        return 'Cached metadata';
      case BackupContentType.searchIndex:
        return 'Search database';
      case BackupContentType.waveformCache:
        return 'Waveform data';
      case BackupContentType.colorCache:
        return 'Color palettes';
      case BackupContentType.lyricsCache:
        return 'Cached lyrics';
    }
  }

  AppIconData _getContentTypeIcon(BackupContentType type) {
    switch (type) {
      case BackupContentType.userStats:
        return AppIcons.analytics;
      case BackupContentType.userData:
        return AppIcons.person;
      case BackupContentType.userSettings:
        return AppIcons.settings;
      case BackupContentType.coverCache:
        return AppIcons.album;
      case BackupContentType.libraryCache:
        return AppIcons.library;
      case BackupContentType.searchIndex:
        return AppIcons.search;
      case BackupContentType.waveformCache:
        return AppIcons.waves;
      case BackupContentType.colorCache:
        return AppIcons.palette;
      case BackupContentType.lyricsCache:
        return AppIcons.lyrics;
    }
  }

  void _toggleType(BackupContentType type) {
    setState(() {
      if (_selectedTypes.contains(type)) {
        _selectedTypes.remove(type);
      } else {
        _selectedTypes.add(type);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: AppTokens.brSm,
            ),
            child: AppIcon(widget.buttonIcon,
                color: theme.colorScheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: AppTokens.brMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: BackupContentType.values.map((type) {
            final isSelected = _selectedTypes.contains(type);
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _toggleType(type),
                borderRadius: AppTokens.brSm,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.colorScheme.primary
                                  .withValues(alpha: 0.12)
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: AppTokens.brSm,
                        ),
                        child: AppIcon(
                          _getContentTypeIcon(type),
                          size: 17,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getContentTypeName(type),
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: isSelected
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              _getContentTypeDescription(type),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      AppIcon(
                        isSelected ? AppIcons.checkCircle : AppIcons.circle,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.4),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTokens.surface(2),
                    foregroundColor: AppTokens.fgPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppTokens.brSm,
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 40,
                child: FilledButton.icon(
                  onPressed: _selectedTypes.isEmpty
                      ? null
                      : () {
                          Navigator.pop(
                            context,
                            BackupOptions(contentTypes: _selectedTypes),
                          );
                        },
                  icon: AppIcon(widget.buttonIcon, size: 18),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: AppTokens.brSm,
                    ),
                  ),
                  label: Text(widget.buttonLabel),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
