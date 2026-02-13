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

  @override
  Widget build(BuildContext context) {
    final audioManager = ref.watch(audioPlayerManagerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Shuffle Settings'),
        actions: [
          TextButton.icon(
            onPressed: () {
              final currentConfig =
                  audioManager.shuffleStateNotifier.value.config;
              audioManager.updateShuffleConfig(
                currentConfig.copyWith(
                  avoidRepeatingSongs: true,
                  avoidRepeatingArtists: true,
                  avoidRepeatingAlbums: true,
                  leastPlayedWeight: 0,
                  mostPlayedWeight: 0,
                  favoritesWeight: 0,
                  suggestLessWeight: 0,
                  playlistSongsWeight: 0,
                ),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Settings reset to defaults')),
              );
            },
            icon: const Icon(Icons.refresh, size: 20),
            label: const Text('Reset'),
          ),
        ],
      ),
      body: ValueListenableBuilder<ShuffleState>(
        valueListenable: audioManager.shuffleStateNotifier,
        builder: (context, shuffleState, child) {
          final config = shuffleState.config;

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Simple Settings Section
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
                        audioManager.updateShuffleConfig(
                          config.copyWith(avoidRepeatingSongs: value),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Avoid Repeating Artists'),
                      subtitle: const Text(
                          'Reduce chance of playing same artist consecutively'),
                      value: config.avoidRepeatingArtists,
                      onChanged: (value) {
                        audioManager.updateShuffleConfig(
                          config.copyWith(avoidRepeatingArtists: value),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Avoid Repeating Albums'),
                      subtitle: const Text(
                          'Reduce chance of playing same album consecutively'),
                      value: config.avoidRepeatingAlbums,
                      onChanged: (value) {
                        audioManager.updateShuffleConfig(
                          config.copyWith(avoidRepeatingAlbums: value),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Advanced Settings Toggle
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

              // Advanced Settings Section
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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildAdvancedSlider(
                          label: 'Least Played Songs',
                          value: config.leastPlayedWeight,
                          onChanged: (value) {
                            audioManager.updateShuffleConfig(
                              config.copyWith(leastPlayedWeight: value),
                            );
                          },
                        ),
                        _buildAdvancedSlider(
                          label: 'Most Played Songs',
                          value: config.mostPlayedWeight,
                          onChanged: (value) {
                            audioManager.updateShuffleConfig(
                              config.copyWith(mostPlayedWeight: value),
                            );
                          },
                        ),
                        _buildAdvancedSlider(
                          label: 'Favorites',
                          value: config.favoritesWeight,
                          onChanged: (value) {
                            audioManager.updateShuffleConfig(
                              config.copyWith(favoritesWeight: value),
                            );
                          },
                        ),
                        _buildAdvancedSlider(
                          label: 'Suggest Less Songs',
                          value: config.suggestLessWeight,
                          onChanged: (value) {
                            audioManager.updateShuffleConfig(
                              config.copyWith(suggestLessWeight: value),
                            );
                          },
                        ),
                        _buildAdvancedSlider(
                          label: 'Songs in Playlists',
                          value: config.playlistSongsWeight,
                          onChanged: (value) {
                            audioManager.updateShuffleConfig(
                              config.copyWith(playlistSongsWeight: value),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 32),
            ],
          );
        },
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
