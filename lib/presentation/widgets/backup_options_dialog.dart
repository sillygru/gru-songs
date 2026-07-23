import 'package:flutter/material.dart';
import '../../services/backup_service.dart';
import '../tokens/app_tokens.dart';

class BackupOptionsDialog extends StatefulWidget {
  final Set<BackupContentType> initialTypes;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final IconData buttonIcon;

  const BackupOptionsDialog({
    super.key,
    required this.initialTypes,
    this.title = 'Create Backup',
    this.subtitle = 'Select content to backup',
    this.buttonLabel = 'Create',
    this.buttonIcon = Icons.backup_rounded,
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

  IconData _getContentTypeIcon(BackupContentType type) {
    switch (type) {
      case BackupContentType.userStats:
        return Icons.analytics_outlined;
      case BackupContentType.userData:
        return Icons.person_outline;
      case BackupContentType.userSettings:
        return Icons.settings_outlined;
      case BackupContentType.coverCache:
        return Icons.album_outlined;
      case BackupContentType.libraryCache:
        return Icons.library_music_outlined;
      case BackupContentType.searchIndex:
        return Icons.search_outlined;
      case BackupContentType.waveformCache:
        return Icons.waves_outlined;
      case BackupContentType.colorCache:
        return Icons.palette_outlined;
      case BackupContentType.lyricsCache:
        return Icons.lyrics_outlined;
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
            child: Icon(widget.buttonIcon,
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
                        child: Icon(
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
                      Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
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
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: AppTokens.brSm,
                    ),
                    side: BorderSide(color: theme.colorScheme.outline),
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
                  icon: Icon(widget.buttonIcon, size: 18),
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
