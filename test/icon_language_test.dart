import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source scan guarding the app's icon language.
///
/// The app runs on one icon set (Hugeicons stroke-rounded, reached through
/// [AppIcons]/[AppIcon]) with one documented exemption: the unified player
/// subtree, which still draws Material [Icons]. Both halves of that rule are
/// easy to break silently — a stray `Icons.foo` compiles fine and just looks
/// wrong — so they are pinned here rather than left to review.
void main() {
  /// The player keeps Material icons on purpose. Everything else must not.
  const playerExemptions = {
    'lib/presentation/screens/player/',
    'lib/presentation/screens/unified_player_screen.dart',
    'lib/presentation/components/player_track_row.dart',
    'lib/presentation/components/player_section_header.dart',
    'lib/presentation/components/player_segmented_pill.dart',
    'lib/presentation/components/player_glass_surface.dart',
    'lib/presentation/components/queue_cover_mosaic.dart',
  };

  /// `Icons.x` but not `AppIcons.x` / `HugeIcons.x`.
  final materialIcon = RegExp(r'(^|[^A-Za-z])Icons\.[a-zA-Z0-9_]+');

  List<File> dartSources() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  bool isExempt(String path) =>
      playerExemptions.any((prefix) => path.startsWith(prefix));

  test('Material Icons are confined to the player subtree', () {
    final offenders = <String>[];

    for (final file in dartSources()) {
      if (isExempt(file.path)) continue;

      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains('AppIcons.') || line.contains('HugeIcons.')) continue;
        if (materialIcon.hasMatch(line)) {
          offenders.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Outside the player, icons come from AppIcons via AppIcon. '
          'Add a semantic name to lib/presentation/tokens/app_icons.dart '
          'instead of reaching for Material Icons:\n${offenders.join('\n')}',
    );
  });

  test('only app_icon.dart and app_icons.dart import hugeicons', () {
    const allowed = {
      'lib/presentation/components/app_icon.dart',
      'lib/presentation/tokens/app_icons.dart',
    };

    final offenders = dartSources()
        .where((f) => !allowed.contains(f.path))
        .where((f) => f.readAsStringSync().contains("package:hugeicons/"))
        .map((f) => f.path)
        .toList();

    expect(
      offenders,
      isEmpty,
      reason: 'The icon package is an implementation detail of AppIcon. '
          'Call sites use AppIcons.<name> so the set can be swapped in one '
          'file:\n${offenders.join('\n')}',
    );
  });
}
