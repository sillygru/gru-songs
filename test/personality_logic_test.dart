import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/domain/services/shuffle_selector.dart';
import 'package:wispie/domain/services/song_affinity_service.dart';
import 'package:wispie/models/shuffle_config.dart';

ShuffleCandidate<String> _candidate(
  String name, {
  double affinity = 0.5,
  int playCount = 5,
  bool isFavorite = false,
  bool isSuggestLess = false,
  bool isInPlaylist = false,
  String artist = 'Artist',
  String album = 'Album',
}) =>
    ShuffleCandidate<String>(
      payload: name,
      artist: artist,
      album: album,
      affinity: SongAffinity(
        affinity: affinity,
        recentSaturation: 0.0,
        completionRate: 1.0,
        skipRate: 0.0,
        playCount: playCount,
        lastPlayedAt: null,
      ),
      isFavorite: isFavorite,
      isSuggestLess: isSuggestLess,
      isInPlaylist: isInPlaylist,
    );

/// Ratio of a well-loved song's score to a lukewarm one's. Higher means the
/// personality leans harder into established taste.
double _tasteRatio(ShuffleWeights weights) {
  final loved = scoreCandidate(
      _candidate('loved', affinity: 1.0, playCount: 80), weights);
  final lukewarm =
      scoreCandidate(_candidate('meh', affinity: 0.15, playCount: 6), weights);
  return loved / lukewarm;
}

ShuffleWeights _weights(ShufflePersonality personality) =>
    ShuffleWeights.forPersonality(ShuffleConfig(personality: personality));

void main() {
  group('personalities are meaningfully different', () {
    test('familiarity increases from explorer to default to consistent', () {
      final explorer = _tasteRatio(_weights(ShufflePersonality.explorer));
      final normal = _tasteRatio(_weights(ShufflePersonality.defaultMode));
      final consistent = _tasteRatio(_weights(ShufflePersonality.consistent));

      expect(explorer, lessThan(normal));
      expect(normal, lessThan(consistent));
    });

    test('explorer lifts unheard songs far more than consistent does', () {
      final fresh = _candidate('fresh', affinity: 0.0, playCount: 0);
      final familiar = _candidate('familiar', affinity: 0.8, playCount: 50);

      double freshShare(ShufflePersonality personality) {
        final w = _weights(personality);
        final a = scoreCandidate(fresh, w);
        final b = scoreCandidate(familiar, w);
        return a / (a + b);
      }

      expect(freshShare(ShufflePersonality.explorer),
          greaterThan(freshShare(ShufflePersonality.consistent)));
    });

    test('explorer avoids recent repeats more aggressively', () {
      expect(_weights(ShufflePersonality.explorer).repeatAversion,
          greaterThan(_weights(ShufflePersonality.consistent).repeatAversion));
    });

    test('explorer spaces artists further apart', () {
      expect(_weights(ShufflePersonality.explorer).artistSpacing,
          greaterThan(_weights(ShufflePersonality.consistent).artistSpacing));
    });

    test('no two personalities resolve to the same taste ratio', () {
      final ratios = [
        for (final p in ShufflePersonality.values) _tasteRatio(_weights(p)),
      ];
      expect(ratios.toSet().length, ratios.length);
    });
  });

  group('shared settings apply in every personality', () {
    test('favoriteMultiplier is honored everywhere', () {
      // This setting was written by the settings UI and read by nothing.
      for (final personality in ShufflePersonality.values) {
        final low = ShuffleWeights.forPersonality(ShuffleConfig(
          personality: personality,
          favoriteMultiplier: 1.05,
        ));
        final high = ShuffleWeights.forPersonality(ShuffleConfig(
          personality: personality,
          favoriteMultiplier: 1.9,
        ));

        final favorite = _candidate('f', isFavorite: true);
        expect(scoreCandidate(favorite, high),
            greaterThan(scoreCandidate(favorite, low)),
            reason: '$personality');
      }
    });

    test('suggestLessMultiplier is honored everywhere', () {
      for (final personality in ShufflePersonality.values) {
        final gentle = ShuffleWeights.forPersonality(ShuffleConfig(
          personality: personality,
          suggestLessMultiplier: 0.8,
        ));
        final harsh = ShuffleWeights.forPersonality(ShuffleConfig(
          personality: personality,
          suggestLessMultiplier: 0.05,
        ));

        final suppressed = _candidate('s', isSuggestLess: true);
        expect(scoreCandidate(suppressed, harsh),
            lessThan(scoreCandidate(suppressed, gentle)),
            reason: '$personality');
      }
    });

    test('historyLimit reaches the anti-repeat curve everywhere', () {
      for (final personality in ShufflePersonality.values) {
        final weights = ShuffleWeights.forPersonality(ShuffleConfig(
          personality: personality,
          historyLimit: 321,
        ));
        expect(weights.historyLimit, 321, reason: '$personality');
      }
    });
  });

  group('custom mode settings all have an effect', () {
    ShuffleWeights custom(ShuffleConfig Function(ShuffleConfig) build) =>
        ShuffleWeights.forPersonality(
          build(const ShuffleConfig(personality: ShufflePersonality.custom)),
        );

    test('favorLeastPlayed flips the familiarity tilt', () {
      final leastPlayed = custom((c) => c.copyWith(favorLeastPlayed: true));
      final mostPlayed = custom((c) => c.copyWith(favorLeastPlayed: false));

      expect(_tasteRatio(mostPlayed), greaterThan(_tasteRatio(leastPlayed)));
    });

    test('mostPlayedWeight sharpens toward established taste', () {
      final neutral = custom((c) => c);
      final leaning = custom((c) => c.copyWith(mostPlayedWeight: 90));
      expect(_tasteRatio(leaning), greaterThan(_tasteRatio(neutral)));
    });

    test('leastPlayedWeight flattens toward discovery', () {
      final neutral = custom((c) => c);
      final leaning = custom((c) => c.copyWith(leastPlayedWeight: 90));
      expect(_tasteRatio(leaning), lessThan(_tasteRatio(neutral)));
    });

    test('favoritesWeight strengthens the favorite boost', () {
      final favorite = _candidate('f', isFavorite: true);
      final neutral = custom((c) => c);
      final boosted = custom((c) => c.copyWith(favoritesWeight: 80));

      expect(scoreCandidate(favorite, boosted),
          greaterThan(scoreCandidate(favorite, neutral)));
    });

    test('a favoritesWeight of 0 still respects favorites', () {
      // "Neutral" must not mean "ignore what the listener explicitly marked".
      final weights = custom((c) => c);
      expect(scoreCandidate(_candidate('f', isFavorite: true), weights),
          greaterThan(scoreCandidate(_candidate('p'), weights)));
    });

    test('suggestLessWeight deepens the penalty', () {
      final suppressed = _candidate('s', isSuggestLess: true);
      final neutral = custom((c) => c);
      final harsh = custom((c) => c.copyWith(suggestLessWeight: 90));

      expect(scoreCandidate(suppressed, harsh),
          lessThan(scoreCandidate(suppressed, neutral)));
    });

    test('playlistSongsWeight boosts songs the listener playlisted', () {
      final weights = custom((c) => c.copyWith(playlistSongsWeight: 70));
      expect(scoreCandidate(_candidate('p', isInPlaylist: true), weights),
          greaterThan(scoreCandidate(_candidate('q'), weights)));
    });

    test('playlistSongsWeight is neutral at 0', () {
      final weights = custom((c) => c);
      expect(scoreCandidate(_candidate('p', isInPlaylist: true), weights),
          scoreCandidate(_candidate('q'), weights));
    });

    test('avoidRepeatingSongs toggles anti-repeat', () {
      expect(
          custom((c) => c.copyWith(avoidRepeatingSongs: true)).repeatAversion,
          greaterThan(0.0));
      expect(
          custom((c) => c.copyWith(avoidRepeatingSongs: false)).repeatAversion,
          0.0);
    });

    test('avoidRepeatingArtists toggles artist spacing', () {
      expect(
          custom((c) => c.copyWith(avoidRepeatingArtists: true)).artistSpacing,
          greaterThan(0));
      expect(
          custom((c) => c.copyWith(avoidRepeatingArtists: false)).artistSpacing,
          0);
    });

    test('avoidRepeatingAlbums toggles album spacing', () {
      expect(custom((c) => c.copyWith(avoidRepeatingAlbums: true)).albumSpacing,
          greaterThan(0));
      expect(
          custom((c) => c.copyWith(avoidRepeatingAlbums: false)).albumSpacing,
          0);
    });
  });
}
