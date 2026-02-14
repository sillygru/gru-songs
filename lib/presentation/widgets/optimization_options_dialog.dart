import 'package:flutter/material.dart';
import '../../services/database_optimizer_service.dart';

class OptimizationOptionsDialog extends StatefulWidget {
  const OptimizationOptionsDialog({super.key});

  @override
  State<OptimizationOptionsDialog> createState() =>
      _OptimizationOptionsDialogState();
}

class _OptimizationOptionsDialogState extends State<OptimizationOptionsDialog> {
  bool _automaticMode = true;
  final Set<OptimizationType> _selectedTypes = {
    OptimizationType.shuffleState,
    OptimizationType.statsDatabase,
    OptimizationType.userDataDatabase,
    OptimizationType.coverCache,
    OptimizationType.searchIndex,
  };

  static const Map<OptimizationType, _OptimizationItem> _items = {
    OptimizationType.shuffleState: _OptimizationItem(
      icon: Icons.casino,
      title: 'Clean up shuffle state',
      description: 'Removes obsolete history data from shuffle state',
    ),
    OptimizationType.statsDatabase: _OptimizationItem(
      icon: Icons.insert_chart,
      title: 'Optimize stats database',
      description: 'Fixes event categorizations and vacuum',
    ),
    OptimizationType.userDataDatabase: _OptimizationItem(
      icon: Icons.person,
      title: 'Optimize user data database',
      description: 'Fixes schema, orphans, and duplicates',
    ),
    OptimizationType.coverCache: _OptimizationItem(
      icon: Icons.image,
      title: 'Rebuild cover caches',
      description: 'Rebuilds embedded album art cache',
    ),
    OptimizationType.searchIndex: _OptimizationItem(
      icon: Icons.search,
      title: 'Optimize search index',
      description: 'Rebuilds search index for faster lookups',
    ),
  };

  void _onAutomaticModeChanged(bool value) {
    setState(() {
      _automaticMode = value;
    });
  }

  void _onTypeChanged(OptimizationType type, bool value) {
    if (_automaticMode) return;
    setState(() {
      if (value) {
        _selectedTypes.add(type);
      } else {
        _selectedTypes.remove(type);
      }
    });
  }

  void _onProceed() {
    Navigator.pop(
      context,
      OptimizationOptions(
        automaticMode: _automaticMode,
        selectedTypes: _selectedTypes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('Optimize Database'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Automatic mode checkbox
            CheckboxListTile(
              title: const Text(
                'Automatic (Recommended)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Run all optimizations',
                style: TextStyle(fontSize: 12),
              ),
              value: _automaticMode,
              onChanged: (value) => _onAutomaticModeChanged(value ?? true),
              secondary: Icon(
                Icons.auto_mode,
                color: _automaticMode
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              activeColor: colorScheme.primary,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const Divider(height: 24),
            // Individual options
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                'OR select specific optimizations:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: OptimizationType.values.length,
                itemBuilder: (context, index) {
                  final type = OptimizationType.values[index];
                  final item = _items[type]!;
                  final isEnabled = !_automaticMode;
                  final isSelected = _selectedTypes.contains(type);

                  return Opacity(
                    opacity: isEnabled ? 1.0 : 0.5,
                    child: CheckboxListTile(
                      title: Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isSelected ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        item.description,
                        style: const TextStyle(fontSize: 11),
                      ),
                      value: isSelected,
                      onChanged: isEnabled
                          ? (value) => _onTypeChanged(type, value ?? false)
                          : null,
                      secondary: Icon(
                        item.icon,
                        size: 20,
                        color: isSelected && isEnabled
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      activeColor: colorScheme.primary,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            // Warning text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'It is recommended to backup your data before proceeding.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _onProceed,
          child: const Text('Proceed'),
        ),
      ],
    );
  }
}

class _OptimizationItem {
  final IconData icon;
  final String title;
  final String description;

  const _OptimizationItem({
    required this.icon,
    required this.title,
    required this.description,
  });
}
