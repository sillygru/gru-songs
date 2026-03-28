import 'package:flutter/material.dart';
import '../../services/import_options.dart';

class ImportOptionsDialog extends StatefulWidget {
  final Set<ImportDataCategory> availableCategories;
  final bool defaultAdditive;
  final bool defaultRestoreDatabases;

  const ImportOptionsDialog({
    super.key,
    this.availableCategories = const {},
    this.defaultAdditive = false,
    this.defaultRestoreDatabases = true,
  });

  @override
  State<ImportOptionsDialog> createState() => _ImportOptionsDialogState();
}

class _ImportOptionsDialogState extends State<ImportOptionsDialog> {
  late Set<ImportDataCategory> _selectedCategories;
  late bool _additive;
  late bool _restoreDatabases;

  @override
  void initState() {
    super.initState();
    _selectedCategories = Set.from(widget.availableCategories);
    _additive = widget.defaultAdditive;
    _restoreDatabases = widget.defaultRestoreDatabases;
  }

  void _toggleCategory(ImportDataCategory category) {
    setState(() {
      if (_selectedCategories.contains(category)) {
        _selectedCategories.remove(category);
      } else {
        _selectedCategories.add(category);
      }
    });
  }

  void _selectAll(Set<ImportDataCategory> categories) {
    setState(() {
      _selectedCategories.addAll(categories);
    });
  }

  void _deselectAll(Set<ImportDataCategory> categories) {
    setState(() {
      _selectedCategories.removeAll(categories);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final databaseCategories = {
      ImportDataCategory.favorites,
      ImportDataCategory.suggestless,
      ImportDataCategory.hidden,
      ImportDataCategory.playlists,
      ImportDataCategory.mergedGroups,
      ImportDataCategory.recommendations,
      ImportDataCategory.moods,
      ImportDataCategory.userdata,
      ImportDataCategory.playHistory,
    };
    final databaseCategoriesAvailable =
        databaseCategories.intersection(widget.availableCategories);
    final databaseCategoriesDisabled =
        databaseCategories.difference(widget.availableCategories);

    final storageCategories = {
      ImportDataCategory.songs,
      ImportDataCategory.finalStats,
      ImportDataCategory.queueHistory,
      ImportDataCategory.shuffleState,
      ImportDataCategory.playbackState,
    };
    final storageCategoriesAvailable =
        storageCategories.intersection(widget.availableCategories);
    final storageCategoriesDisabled =
        storageCategories.difference(widget.availableCategories);

    final settingsCategories = {
      ImportDataCategory.themeSettings,
      ImportDataCategory.scannerSettings,
      ImportDataCategory.playbackSettings,
      ImportDataCategory.uiSettings,
      ImportDataCategory.backupSettings,
    };
    final settingsCategoriesAvailable =
        settingsCategories.intersection(widget.availableCategories);
    final settingsCategoriesDisabled =
        settingsCategories.difference(widget.availableCategories);

    return AlertDialog(
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          const Icon(Icons.restore),
          const SizedBox(width: 8),
          const Expanded(child: Text('Select Data to Restore')),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(null),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (databaseCategories.isNotEmpty)
                _buildCategorySection(
                  context,
                  'Database',
                  databaseCategoriesAvailable,
                  databaseCategoriesDisabled,
                  Icons.storage_outlined,
                  databaseCategories,
                ),
              if (storageCategories.isNotEmpty)
                _buildCategorySection(
                  context,
                  'Storage',
                  storageCategoriesAvailable,
                  storageCategoriesDisabled,
                  Icons.folder_outlined,
                  storageCategories,
                ),
              if (settingsCategories.isNotEmpty)
                _buildCategorySection(
                  context,
                  'Settings',
                  settingsCategoriesAvailable,
                  settingsCategoriesDisabled,
                  Icons.settings_outlined,
                  settingsCategories,
                ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Restore Options',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      title: const Text('Replace Databases'),
                      subtitle:
                          const Text('Clear existing data before restoring'),
                      value: _restoreDatabases,
                      onChanged: (value) {
                        setState(() {
                          _restoreDatabases = value ?? true;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const Divider(),
                    Text(
                      'Import Mode',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    RadioGroup<bool>(
                      groupValue: _additive,
                      onChanged: (value) {
                        setState(() {
                          _additive = value ?? false;
                        });
                      },
                      child: Column(
                        children: [
                          RadioListTile<bool>(
                            title: const Text('Replace'),
                            subtitle: const Text('Overwrite existing data'),
                            value: false,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                          RadioListTile<bool>(
                            title: const Text('Merge'),
                            subtitle: const Text(
                                'Add to existing data (skip duplicates)'),
                            value: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedCategories.isEmpty
              ? null
              : () {
                  final options = ImportOptions(
                    categories: _selectedCategories,
                    additive: _additive,
                    restoreDatabases: _restoreDatabases,
                  );
                  Navigator.of(context).pop(options);
                },
          child: const Text('Restore'),
        ),
      ],
    );
  }

  Widget _buildCategorySection(
    BuildContext context,
    String title,
    Set<ImportDataCategory> availableCategories,
    Set<ImportDataCategory> disabledCategories,
    IconData icon,
    Set<ImportDataCategory> allCategories,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _selectAll(availableCategories),
                child: const Text('All'),
              ),
              TextButton(
                onPressed: () => _deselectAll(availableCategories),
                child: const Text('None'),
              ),
            ],
          ),
        ),
        ...allCategories.map((category) {
          final isDisabled = disabledCategories.contains(category);
          return CheckboxListTile(
            title: Text(
              category.displayName,
              style: TextStyle(
                color: isDisabled ? theme.disabledColor : null,
              ),
            ),
            subtitle: Text(
              category.description,
              style: TextStyle(
                color: isDisabled ? theme.disabledColor.withAlpha(150) : null,
              ),
            ),
            value: _selectedCategories.contains(category),
            onChanged: isDisabled ? null : (_) => _toggleCategory(category),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            controlAffinity: ListTileControlAffinity.leading,
          );
        }),
        const Divider(),
      ],
    );
  }
}
