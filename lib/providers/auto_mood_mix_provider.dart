import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../models/mood_tag.dart';
import 'providers.dart';
import 'user_data_provider.dart';
import 'session_history_provider.dart';

/// Minimum number of songs with mood tags required to generate auto mood mix
const _minSongsWithMoods = 20;

/// Auto-generated mood mix provider
/// 
/// Automatically generates a "Feeling [Mood]?" mix based on:
/// - Time of day
/// - Recent listening history
/// - Available mood-tagged songs
/// 
/// Only generates if there are enough songs with mood tags (>= 20)
final autoMoodMixProvider = Provider<AutoMoodMixState>((ref) {
  final userData = ref.watch(userDataProvider);
  final songsAsync = ref.watch(songsProvider);
  final sessionHistory = ref.watch(sessionHistoryProvider).value ?? [];

  if (songsAsync is! AsyncData || songsAsync.value == null) {
    return const AutoMoodMixState(
      isLoading: true,
      hasEnoughData: false,
    );
  }

  final allSongs = songsAsync.value!;

  // Check if we have enough songs with mood tags
  final songsWithMoods = allSongs.where((song) {
    final moods = userData.moodsForSong(song.filename);
    return moods.isNotEmpty;
  }).toList();

  if (songsWithMoods.length < _minSongsWithMoods) {
    return AutoMoodMixState(
      isLoading: false,
      hasEnoughData: false,
      songsWithMoodsCount: songsWithMoods.length,
    );
  }

  // Select mood based on time and history
  final selectedMood = _selectMood(userData.moodTags, sessionHistory);
  
  if (selectedMood == null) {
    return AutoMoodMixState(
      isLoading: false,
      hasEnoughData: false,
      songsWithMoodsCount: songsWithMoods.length,
    );
  }

  // Generate the mix
  final mixSongs = _generateMoodMix(
    allSongs,
    userData,
    selectedMood.id,
    length: 25,
  );

  return AutoMoodMixState(
    isLoading: false,
    hasEnoughData: true,
    songsWithMoodsCount: songsWithMoods.length,
    selectedMood: selectedMood,
    songs: mixSongs,
  );
});

class AutoMoodMixState {
  final bool isLoading;
  final bool hasEnoughData;
  final int songsWithMoodsCount;
  final MoodTag? selectedMood;
  final List<Song> songs;

  const AutoMoodMixState({
    this.isLoading = false,
    this.hasEnoughData = false,
    this.songsWithMoodsCount = 0,
    this.selectedMood,
    this.songs = const [],
  });

  String get displayName {
    if (selectedMood == null) return '';
    return 'Feeling ${selectedMood!.name}?';
  }

  String get description {
    if (selectedMood == null) return '';
    return 'Auto-generated mix based on your ${selectedMood!.name.toLowerCase()} vibes';
  }
}

MoodTag? _selectMood(List<MoodTag> moodTags, List<dynamic> sessionHistory) {
  if (moodTags.isEmpty) return null;

  final random = Random();
  final hour = DateTime.now().hour;

  // Time-based mood suggestions
  List<String> timeAppropriateMoods;
  if (hour >= 5 && hour < 9) {
    // Morning: calm, focus, uplifting
    timeAppropriateMoods = ['calm', 'focus', 'uplifting'];
  } else if (hour >= 9 && hour < 12) {
    // Late morning: focus, energetic, uplifting
    timeAppropriateMoods = ['focus', 'energetic', 'uplifting'];
  } else if (hour >= 12 && hour < 14) {
    // Lunch: energetic, party, happy
    timeAppropriateMoods = ['energetic', 'party', 'happy'];
  } else if (hour >= 14 && hour < 17) {
    // Afternoon: focus, energetic
    timeAppropriateMoods = ['focus', 'energetic'];
  } else if (hour >= 17 && hour < 20) {
    // Evening: party, energetic, happy
    timeAppropriateMoods = ['party', 'energetic', 'happy'];
  } else if (hour >= 20 && hour < 23) {
    // Night: calm, romantic, nostalgic
    timeAppropriateMoods = ['calm', 'romantic', 'nostalgic'];
  } else {
    // Late night: calm, dark, nostalgic
    timeAppropriateMoods = ['calm', 'dark', 'nostalgic'];
  }

  // Find moods that match time-appropriate suggestions
  final timeMatchedMoods = moodTags.where((mood) {
    return timeAppropriateMoods.any((tm) => 
      mood.normalizedName.contains(tm) || tm.contains(mood.normalizedName)
    );
  }).toList();

  // If we have time-matched moods, prefer them
  if (timeMatchedMoods.isNotEmpty) {
    return timeMatchedMoods[random.nextInt(timeMatchedMoods.length)];
  }

  // Fallback to recent history analysis
  if (sessionHistory.isNotEmpty) {
    final recentSessionIds = sessionHistory.take(10).toList();
    final moodFrequency = <String, int>{};
    
    for (final session in recentSessionIds) {
      // Extract mood information from session if available
      // For now, we'll just use random selection
    }
    
    if (moodFrequency.isNotEmpty) {
      final topMood = moodFrequency.entries.reduce((a, b) => 
        a.value > b.value ? a : b
      ).key;
      final matchingMood = moodTags.firstWhere(
        (m) => m.id == topMood,
        orElse: () => moodTags[random.nextInt(moodTags.length)],
      );
      return matchingMood;
    }
  }

  // Final fallback: random mood
  return moodTags[random.nextInt(moodTags.length)];
}

List<Song> _generateMoodMix(
  List<Song> allSongs,
  UserDataState userData,
  String moodId, {
  int length = 25,
}) {
  final playCounts = {}; // Could be fetched from DB if needed
  final random = Random();
  
  final candidates = allSongs.where((song) {
    if (userData.isHidden(song.filename)) return false;
    final songMoodIds = userData.moodsForSong(song.filename);
    return songMoodIds.any((id) => id == moodId);
  }).toList();

  if (candidates.isEmpty) return [];

  final scored = candidates.map((song) {
    final songMoodIds = userData.moodsForSong(song.filename).toSet();
    final overlapScore = songMoodIds.contains(moodId) ? 1.0 : 0.0;
    final plays = playCounts[song.filename] ?? 0;
    final noveltyScore = 1.0 / (1.0 + (plays > 0 ? (plays).toDouble().log() : 0));
    var score = overlapScore * 5.5 + noveltyScore * 1.5;
    if (userData.isFavorite(song.filename)) score += 1.1;
    if (userData.isSuggestLess(song.filename)) score -= 1.4;
    score += random.nextDouble() * 0.45;
    return (song: song, score: score);
  }).toList()
    ..sort((a, b) => b.score.compareTo(a.score));

  final picked = <Song>[];
  final artistHits = <String, int>{};
  final albumHits = <String, int>{};
  final diversity = 0.65;
  
  for (final entry in scored) {
    if (picked.length >= length) break;
    final artistPenalty = (artistHits[entry.song.artist] ?? 0) * diversity;
    final albumPenalty = (albumHits[entry.song.album] ?? 0) * (diversity * 0.7);
    final effective = entry.score - artistPenalty - albumPenalty;
    if (effective > 0.15 || picked.length < 4) {
      picked.add(entry.song);
      artistHits[entry.song.artist] = (artistHits[entry.song.artist] ?? 0) + 1;
      albumHits[entry.song.album] = (albumHits[entry.song.album] ?? 0) + 1;
    }
  }

  // Fill remaining slots if needed
  if (picked.length < length) {
    for (final entry in scored) {
      if (picked.length >= length) break;
      if (!picked.contains(entry.song)) picked.add(entry.song);
    }
  }
  
  return picked.take(length).toList();
}
