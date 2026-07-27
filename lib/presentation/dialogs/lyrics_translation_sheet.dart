import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import '../components/app_icon.dart';
import '../components/app_sheet.dart';
import '../tokens/app_icons.dart';
import '../tokens/app_tokens.dart';

class LyricsTranslationConfig {
  final String targetLanguage;
  final String displayMode;
  final bool autoTranslate;
  final bool translateNow;
  final bool clearCache;

  const LyricsTranslationConfig({
    required this.targetLanguage,
    required this.displayMode,
    required this.autoTranslate,
    this.translateNow = false,
    this.clearCache = false,
  });
}

const Map<String, String> kSupportedTranslationLanguages = {
  'es': 'Spanish',
  'en': 'English',
  'fr': 'French',
  'de': 'German',
  'it': 'Italian',
  'ja': 'Japanese',
  'zh': 'Chinese',
  'ko': 'Korean',
  'pt': 'Portuguese',
  'ru': 'Russian',
  'hi': 'Hindi',
  'ar': 'Arabic',
  'nl': 'Dutch',
  'pl': 'Polish',
  'tr': 'Turkish',
  'vi': 'Vietnamese',
  'uk': 'Ukrainian',
  'sv': 'Swedish',
  'id': 'Indonesian',
  'th': 'Thai',
  'cs': 'Czech',
  'el': 'Greek',
  'hu': 'Hungarian',
  'ro': 'Romanian',
  'da': 'Danish',
  'fi': 'Finnish',
  'no': 'Norwegian',
};

Future<LyricsTranslationConfig?> showLyricsTranslationSheet(
  BuildContext context, {
  required String currentSongTitle,
  required bool hasCachedTranslation,
}) {
  return showAppSheet<LyricsTranslationConfig>(
    context,
    title: 'Translate lyrics',
    builder: (context) => _LyricsTranslationSheet(
      hasCachedTranslation: hasCachedTranslation,
    ),
  );
}

class _LyricsTranslationSheet extends ConsumerStatefulWidget {
  final bool hasCachedTranslation;

  const _LyricsTranslationSheet({
    required this.hasCachedTranslation,
  });

  @override
  ConsumerState<_LyricsTranslationSheet> createState() =>
      _LyricsTranslationSheetState();
}

class _LyricsTranslationSheetState
    extends ConsumerState<_LyricsTranslationSheet> {
  final TextEditingController _searchController = TextEditingController();
  late String _selectedLanguage;
  late String _displayMode;
  late bool _autoTranslate;
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _selectedLanguage = settings.lyricsTargetLanguage;
    _displayMode = settings.lyricsTranslationMode;
    _autoTranslate = settings.lyricsAutoTranslate;

    _searchController.addListener(() {
      setState(() {
        _filterQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _saveAndClose({bool translateNow = true, bool clearCache = false}) {
    final notifier = ref.read(settingsProvider.notifier);
    notifier.setLyricsTargetLanguage(_selectedLanguage);
    notifier.setLyricsTranslationMode(_displayMode);
    notifier.setLyricsAutoTranslate(_autoTranslate);

    Navigator.of(context).pop(
      LyricsTranslationConfig(
        targetLanguage: _selectedLanguage,
        displayMode: _displayMode,
        autoTranslate: _autoTranslate,
        translateNow: translateNow,
        clearCache: clearCache,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredLangs = kSupportedTranslationLanguages.entries.where((entry) {
      if (_filterQuery.isEmpty) return true;
      return entry.value.toLowerCase().contains(_filterQuery) ||
          entry.key.toLowerCase().contains(_filterQuery);
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Display Mode Selector
          Text(
            'Display mode',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: AppTokens.s2),
          Row(
            children: [
              Expanded(
                child: _buildModeTile(
                  title: 'Subtext below',
                  subtitle: 'Show translation under lyrics',
                  value: 'subtext',
                  icon: AppIcons.subtitles,
                ),
              ),
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: _buildModeTile(
                  title: 'Replace base',
                  subtitle: 'Replace original lyrics entirely',
                  value: 'replace',
                  icon: AppIcons.swapHoriz,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s4),

          // Auto-translate toggle
          SwitchListTile(
            value: _autoTranslate,
            onChanged: (val) {
              setState(() {
                _autoTranslate = val;
              });
            },
            title: const Text(
              'Auto-translate all songs',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              'Automatically translate lyrics using selected language',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: AppTokens.s3),

          // Target Language Picker Section
          Text(
            'Target language',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: AppTokens.s2),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search language...',
              prefixIcon: const Padding(
                padding: EdgeInsets.all(12.0),
                child: AppIcon(AppIcons.search, size: 20),
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppTokens.s3,
                vertical: AppTokens.s2,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: AppTokens.s2),
          SizedBox(
            height: 180,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: Colors.white.withValues(alpha: 0.04),
                child: ListView.builder(
                  itemCount: filteredLangs.length,
                  itemBuilder: (context, index) {
                    final entry = filteredLangs[index];
                    final isSelected = entry.key == _selectedLanguage;

                    return ListTile(
                      dense: true,
                      selected: isSelected,
                      title: Text(
                        entry.value,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w400,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      subtitle: Text(
                        entry.key.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      trailing: isSelected
                          ? AppIcon(
                              AppIcons.checkCircle,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            )
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedLanguage = entry.key;
                        });
                      },
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.s4),

          // Action Buttons
          Row(
            children: [
              if (widget.hasCachedTranslation) ...[
                OutlinedButton.icon(
                  onPressed: () =>
                      _saveAndClose(translateNow: false, clearCache: true),
                  icon: const AppIcon(AppIcons.delete, size: 18),
                  label: const Text('Clear cache'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: BorderSide.none,
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.12),
                  ),
                ),
                const SizedBox(width: AppTokens.s3),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _saveAndClose(translateNow: true),
                  icon: const AppIcon(AppIcons.translate, size: 18),
                  label: const Text('Translate now'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s4),
        ],
      ),
    );
  }

  Widget _buildModeTile({
    required String title,
    required String subtitle,
    required String value,
    required AppIconData icon,
  }) {
    final isSelected = _displayMode == value;
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: () {
        setState(() {
          _displayMode = value;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppTokens.s3),
        decoration: BoxDecoration(
          color: isSelected
              ? primary.withValues(alpha: 0.20)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppIcon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? primary
                      : Colors.white.withValues(alpha: 0.7),
                ),
                const SizedBox(width: AppTokens.s2),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s1),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
