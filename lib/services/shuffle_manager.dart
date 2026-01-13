import 'dart:math';
import '../models/song.dart';
import '../models/queue_item.dart';
import '../models/shuffle_config.dart';

class ShuffleManager {
  static double calculateSongWeight(
    Song song, 
    Song? lastSong, 
    ShuffleConfig config, 
    List<String> history
  ) {
    double weight = 1.0;

    // 1. Anti-repeat weighting
    if (config.antiRepeatEnabled && history.isNotEmpty) {
      int index = history.lastIndexOf(song.filename);
      if (index != -1) {
        int distance = history.length - 1 - index;
        if (distance < config.antiRepeatWindow) {
          double penalty = (1.0 - (distance / config.antiRepeatWindow));
          weight *= (1.0 - penalty * 0.9);
        }
      }
    }

    // 2. Streak breaker (Artist/Album)
    if (config.streakBreakerEnabled && lastSong != null) {
      if (song.artist != null && lastSong.artist != null && song.artist == lastSong.artist) {
        weight *= config.artistWeight;
      }
      if (song.album != null && lastSong.album != null && song.album == lastSong.album) {
        weight *= config.albumWeight;
      }
    }

    return max(weight, 0.01);
  }

  static List<QueueItem> applyShuffle({
    required List<QueueItem> effectiveQueue,
    required int currentIndex,
    required ShuffleConfig config,
    required List<String> history,
  }) {
    if (effectiveQueue.isEmpty) return effectiveQueue;
    
    final currentItem = effectiveQueue[currentIndex];
    final lastSong = currentItem.song;
    
    final otherItems = <QueueItem>[];
    for (int i = 0; i < effectiveQueue.length; i++) {
      if (i == currentIndex) continue;
      otherItems.add(effectiveQueue[i]);
    }
    
    final priorityItems = otherItems.where((item) => item.isPriority).toList();
    final normalItems = otherItems.where((item) => !item.isPriority).toList();
    
    final shuffledNormal = <QueueItem>[];
    final pool = List<QueueItem>.from(normalItems);
    final random = Random();

    while (pool.isNotEmpty) {
      final weights = pool.map((item) => calculateSongWeight(item.song, lastSong, config, history)).toList();
      double totalWeight = weights.reduce((a, b) => a + b);
      
      double target = random.nextDouble() * totalWeight;
      double cumulative = 0;
      int selectedIdx = 0;
      
      for (int i = 0; i < weights.length; i++) {
        cumulative += weights[i];
        if (cumulative >= target) {
          selectedIdx = i;
          break;
        }
      }
      
      shuffledNormal.add(pool.removeAt(selectedIdx));
    }
    
    return [
      currentItem,
      ...priorityItems,
      ...shuffledNormal,
    ];
  }
}
