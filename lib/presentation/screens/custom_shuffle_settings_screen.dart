import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/shuffle_config.dart';
import '../../providers/providers.dart';

class CustomShuffleSettingsScreen extends ConsumerStatefulWidget {
  const CustomShuffleSettingsScreen({super.key});

  @override
  ConsumerState<CustomShuffleSettingsScreen> createState() =>
      _CustomShuffleSettingsScreenState();
}

class _CustomShuffleSettingsScreenState
    extends ConsumerState<CustomShuffleSettingsScreen> {
  bool _showAdvanced = false;
  late ShuffleConfig _localConfig;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    final audioManager = ref.read(audioPlayerManagerProvider);
    _localConfig = audioManager.shuffleStateNotifier.value.config;
  }

  void _updateConfig(ShuffleConfig newConfig) {
    setState(() {
      _localConfig = newConfig;
      _hasChanges = true;
    });
  }

  void _resetToDefaults() {
    setState(() {
      _localConfig = _localConfig.copyWith(
        avoidRepeatingSongs: true,
        avoidRepeatingArtists: true,
        avoidRepeatingAlbums: true,
        leastPlayedWeight: 0,
        mostPlayedWeight: 0,
        favoritesWeight: 0,
        suggestLessWeight: 0,
        playlistSongsWeight: 0,
      );
      _hasChanges = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings reset to defaults')),
    );
  }

  void _saveSettings() {
    final audioManager = ref.read(audioPlayerManagerProvider);
    audioManager.updateShuffleConfig(
      _localConfig,
      applyToCurrentQueue: false,
    );
    setState(() {
      _hasChanges = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('Do you want to save your changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true) {
      _saveSettings();
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final config = _localConfig;

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Custom Shuffle Settings'),
          actions: [
            TextButton.icon(
              onPressed: _resetToDefaults,
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('Reset'),
            ),
            if (_hasChanges)
              TextButton.icon(
                onPressed: _saveSettings,
                icon: const Icon(Icons.save, size: 20),
                label: const Text('Save'),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            if (_hasChanges)
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Changes will apply to next queue',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_hasChanges) const SizedBox(height: 16),
            _buildSectionTitle('Basic Settings'),
            Card(
              elevation: 0,
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.3),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Avoid Repeating Songs'),
                    subtitle: const Text(
                        'Reduce chance of playing recently played songs'),
                    value: config.avoidRepeatingSongs,
                    onChanged: (value) {
                      _updateConfig(
                          config.copyWith(avoidRepeatingSongs: value));
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Avoid Repeating Artists'),
                    subtitle: const Text(
                        'Reduce chance of playing same artist consecutively'),
                    value: config.avoidRepeatingArtists,
                    onChanged: (value) {
                      _updateConfig(
                          config.copyWith(avoidRepeatingArtists: value));
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Avoid Repeating Albums'),
                    subtitle: const Text(
                        'Reduce chance of playing same album consecutively'),
                    value: config.avoidRepeatingAlbums,
                    onChanged: (value) {
                      _updateConfig(
                          config.copyWith(avoidRepeatingAlbums: value));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              title: const Text(
                'Advanced Settings',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Fine-tune individual weight values'),
              trailing: Icon(
                _showAdvanced
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
              ),
              onTap: () {
                setState(() {
                  _showAdvanced = !_showAdvanced;
                });
              },
            ),
            if (_showAdvanced) ...[
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.3),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Weight Values (-99 to +99)',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '0 = neutral, negative = penalty, positive = boost',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildAdvancedSlider(
                        label: 'Least Played Songs',
                        value: config.leastPlayedWeight,
                        onChanged: (value) {
                          _updateConfig(
                              config.copyWith(leastPlayedWeight: value));
                        },
                      ),
                      _buildAdvancedSlider(
                        label: 'Most Played Songs',
                        value: config.mostPlayedWeight,
                        onChanged: (value) {
                          _updateConfig(
                              config.copyWith(mostPlayedWeight: value));
                        },
                      ),
                      _buildAdvancedSlider(
                        label: 'Favorites',
                        value: config.favoritesWeight,
                        onChanged: (value) {
                          _updateConfig(
                              config.copyWith(favoritesWeight: value));
                        },
                      ),
                      _buildAdvancedSlider(
                        label: 'Suggest Less Songs',
                        value: config.suggestLessWeight,
                        onChanged: (value) {
                          _updateConfig(
                              config.copyWith(suggestLessWeight: value));
                        },
                      ),
                      _buildAdvancedSlider(
                        label: 'Songs in Playlists',
                        value: config.playlistSongsWeight,
                        onChanged: (value) {
                          _updateConfig(
                              config.copyWith(playlistSongsWeight: value));
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildAdvancedSlider({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 14)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: value == 0
                    ? Colors.grey.withValues(alpha: 0.2)
                    : value > 0
                        ? Colors.green.withValues(alpha: 0.2)
                        : Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                value > 0 ? '+$value' : '$value',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: value == 0
                      ? Colors.grey
                      : value > 0
                          ? Colors.green
                          : Colors.red,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: -99,
          max: 99,
          divisions: 198,
          onChanged: (newValue) {
            onChanged(newValue.round());
          },
          activeColor: value == 0
              ? Colors.grey
              : value > 0
                  ? Colors.green
                  : Colors.red,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
