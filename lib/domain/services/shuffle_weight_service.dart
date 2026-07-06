import '../../models/queue_item.dart';
import '../../models/shuffle_config.dart';

double calculateWeight({
  required QueueItem item,
  QueueItem? prev,
  required ShuffleConfig config,
  required bool isFavorite,
  required bool isSuggestLess,
  required int playCount,
  required int maxPlayCount,
  int? historyIndex,
  double? playRatioInHistory,
  int? skipCount,
  double? skipAvgRatio,
}) {
  double weight = 1.0;

  final bool isConsistentMode =
      config.personality == ShufflePersonality.consistent;
  final bool isCustomMode = config.personality == ShufflePersonality.custom;
  final bool shouldAvoidRepeatingSongs =
      config.antiRepeatEnabled && (!isCustomMode || config.avoidRepeatingSongs);

  if (shouldAvoidRepeatingSongs && historyIndex != null) {
    if (historyIndex < config.historyLimit) {
      double basePenaltyPercent;

      if (isConsistentMode) {
        if (historyIndex < 10) {
          basePenaltyPercent = 60.0;
        } else if (historyIndex < 20) {
          basePenaltyPercent = 50.0;
        } else if (historyIndex < 30) {
          basePenaltyPercent = 40.0;
        } else if (historyIndex < 40) {
          basePenaltyPercent = 30.0;
        } else if (historyIndex < 50) {
          basePenaltyPercent = 20.0;
        } else if (historyIndex < 60) {
          basePenaltyPercent = 15.0;
        } else if (historyIndex < 80) {
          basePenaltyPercent = 10.0;
        } else if (historyIndex < 100) {
          basePenaltyPercent = 5.0;
        } else {
          basePenaltyPercent = 0.0;
        }
      } else {
        if (historyIndex < 10) {
          basePenaltyPercent = 95.0;
        } else if (historyIndex < 20) {
          basePenaltyPercent = 90.0;
        } else if (historyIndex < 30) {
          basePenaltyPercent = 80.0;
        } else if (historyIndex < 40) {
          basePenaltyPercent = 70.0;
        } else if (historyIndex < 50) {
          basePenaltyPercent = 60.0;
        } else if (historyIndex < 60) {
          basePenaltyPercent = 50.0;
        } else if (historyIndex < 80) {
          basePenaltyPercent = 40.0;
        } else if (historyIndex < 100) {
          basePenaltyPercent = 30.0;
        } else if (historyIndex < 120) {
          basePenaltyPercent = 20.0;
        } else if (historyIndex < 150) {
          basePenaltyPercent = 10.0;
        } else {
          basePenaltyPercent = 5.0;
        }
      }

      double penaltyMultiplier = basePenaltyPercent / 100.0;
      if ((playRatioInHistory ?? 0.0) >= 0.9) {
        penaltyMultiplier *= 1.2;
      }

      weight *= (1.0 - penaltyMultiplier.clamp(0.0, 0.95));
    }
  }

  if (config.streakBreakerEnabled && prev != null) {
    final prevArtist = prev.song.artist.toLowerCase().trim();
    final currentArtist = item.song.artist.toLowerCase().trim();

    if (prevArtist.isNotEmpty &&
        currentArtist.isNotEmpty &&
        prevArtist == currentArtist) {
      weight *= 0.1;
    }

    final prevAlbum = prev.song.album.toLowerCase().trim();
    final currentAlbum = item.song.album.toLowerCase().trim();

    if (prevAlbum.isNotEmpty &&
        currentAlbum.isNotEmpty &&
        prevAlbum == currentAlbum) {
      weight *= 0.3;
    }
  }

  if (isCustomMode) {
    final favoriteBoost = config.favoritesWeight / 100.0;
    final suggestLessPenalty = -config.suggestLessWeight / 100.0;

    if (isFavorite && favoriteBoost != 0) {
      weight *= (1.0 + favoriteBoost);
    }
    if (isSuggestLess && suggestLessPenalty != 0) {
      weight *= (1.0 + suggestLessPenalty);
    }

    if (skipCount != null && skipCount > 0 && skipAvgRatio != null) {
      if (skipAvgRatio > 0.7) {
        weight *= 0.5;
      } else if (skipAvgRatio < 0.3) {
        weight *= 1.2;
      }
    }
  }

  if (!isConsistentMode) {
    if (maxPlayCount > 0 && playCount > 0) {
      final playCountRatio = playCount / maxPlayCount;
      final playCountPenalty = playCountRatio * 0.3;
      weight *= (1.0 - playCountPenalty);
    }
  }

  return weight.clamp(0.01, double.infinity);
}
