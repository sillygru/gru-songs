import 'dart:math' as math;
import '../../models/song.dart';

class ExpertConfig {
  final String styleName;
  final double linguisticTempoScale;

  const ExpertConfig({
    required this.styleName,
    required this.linguisticTempoScale,
  });
}

class LyricsStyleRouter {
  static const ExpertConfig popElectronic = ExpertConfig(
    styleName: 'POP_ELECTRONIC',
    linguisticTempoScale: 1.0,
  );
  static const ExpertConfig rapHipHop = ExpertConfig(
    styleName: 'RAP_HIPHOP',
    linguisticTempoScale: 1.15,
  );
  static const ExpertConfig rockDistorted = ExpertConfig(
    styleName: 'ROCK_DISTORTED',
    linguisticTempoScale: 0.95,
  );
  static const ExpertConfig slowBallad = ExpertConfig(
    styleName: 'SLOW_BALLAD',
    linguisticTempoScale: 0.90,
  );

  static (String, ExpertConfig) detectStyle(
    List<LyricLine> lines, {
    Song? song,
  }) {
    if (lines.isEmpty) return ('POP_ELECTRONIC', popElectronic);

    final cpsList = <double>[];
    final durList = <double>[];
    var totalWords = 0;

    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (!l.isSynced) continue;
      // find next timed line for dur
      Duration? nextTime;
      for (var j = i + 1; j < lines.length; j++) {
        if (lines[j].isSynced) {
          nextTime = lines[j].time;
          break;
        }
      }
      final tokens =
          l.text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      final chars = tokens.fold<int>(0, (s, t) => s + t.length);
      double durS;
      if (nextTime != null) {
        durS = math.max(0.1, (nextTime - l.time).inMicroseconds / 1000000.0);
      } else if (song?.duration != null) {
        durS = math.max(
            0.1, (song!.duration! - l.time).inMicroseconds / 1000000.0);
      } else {
        durS = 3.0;
      }
      // Filter similar to python? python uses unfiltered for song_tempo, but for style we use all lines.
      cpsList.add(chars / durS);
      durList.add(durS);
      totalWords += tokens.length;
    }

    if (cpsList.isEmpty) return ('POP_ELECTRONIC', popElectronic);

    // 75th percentile like ultra_fast
    final sorted = List<double>.from(cpsList)..sort();
    final idx =
        ((sorted.length - 1) * 0.75).round().clamp(0, sorted.length - 1);
    final tempoCps = sorted[idx];
    final meanDur = durList.isEmpty
        ? 3.0
        : durList.reduce((a, b) => a + b) / durList.length;

    double totDurS = 1.0;
    final firstSynced = lines.where((l) => l.isSynced).toList();
    if (firstSynced.isNotEmpty) {
      final last = firstSynced.last;
      final first = firstSynced.first;
      Duration end = last.time + const Duration(seconds: 3);
      if (song != null && song.duration != null && song.duration! > last.time) {
        end = song.duration!;
      }
      // if last has next timed? approximate with nextTime above else song duration
      totDurS = math.max(1.0, (end - first.time).inMicroseconds / 1000000.0);
    }
    final wps = totalWords / totDurS;

    final haystack = [
      song?.title.toLowerCase() ?? '',
      song?.artist.toLowerCase() ?? '',
      song?.album.toLowerCase() ?? '',
      song?.filename.toLowerCase() ?? '',
    ].join(' ');

    // 1. RAP / FAST HIP-HOP
    if (tempoCps > 14.5 || wps > 2.75) {
      return ('RAP_HIPHOP', rapHipHop);
    }

    // 2. ROCK / DISTORTED
    const rockKeywords = [
      'deftones',
      'bleachers',
      'die for you',
      'one more hour',
      'katseye',
      'rock',
      'metal'
    ];
    for (final kw in rockKeywords) {
      if (haystack.contains(kw)) {
        return ('ROCK_DISTORTED', rockDistorted);
      }
    }

    // 3. SLOW BALLAD
    if (tempoCps < 9.8 && meanDur > 3.0) {
      return ('SLOW_BALLAD', slowBallad);
    }

    return ('POP_ELECTRONIC', popElectronic);
  }
}
