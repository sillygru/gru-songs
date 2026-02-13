import 'package:equatable/equatable.dart';

enum ShufflePersonality { defaultMode, explorer, consistent, custom }

class ShuffleConfig extends Equatable {
  final bool enabled;
  final bool antiRepeatEnabled;
  final bool streakBreakerEnabled;
  final double favoriteMultiplier;
  final double suggestLessMultiplier;
  final int historyLimit;
  final ShufflePersonality personality;

  // Custom mode - Simple Settings
  final bool avoidRepeatingSongs;
  final bool avoidRepeatingArtists;
  final bool avoidRepeatingAlbums;
  final bool
      favorLeastPlayed; // true = favor least played, false = favor most played

  // Custom mode - Advanced Settings (-99 to +99, 0 = neutral)
  final int leastPlayedWeight;
  final int mostPlayedWeight;
  final int favoritesWeight;
  final int suggestLessWeight;
  final int playlistSongsWeight;

  const ShuffleConfig({
    this.enabled = false,
    this.antiRepeatEnabled = true,
    this.streakBreakerEnabled = true,
    this.favoriteMultiplier = 1.2,
    this.suggestLessMultiplier = 0.2,
    this.historyLimit = 200,
    this.personality = ShufflePersonality.defaultMode,
    // Custom mode - Simple (defaults)
    this.avoidRepeatingSongs = true,
    this.avoidRepeatingArtists = true,
    this.avoidRepeatingAlbums = true,
    this.favorLeastPlayed = true,
    // Custom mode - Advanced (0 = neutral)
    this.leastPlayedWeight = 0,
    this.mostPlayedWeight = 0,
    this.favoritesWeight = 0,
    this.suggestLessWeight = 0,
    this.playlistSongsWeight = 0,
  });

  factory ShuffleConfig.fromJson(Map<String, dynamic> json) {
    return ShuffleConfig(
      enabled: json['enabled'] ?? false,
      antiRepeatEnabled: json['anti_repeat_enabled'] ?? true,
      streakBreakerEnabled: json['streak_breaker_enabled'] ?? true,
      favoriteMultiplier: (json['favorite_multiplier'] ?? 1.2).toDouble(),
      suggestLessMultiplier:
          (json['suggest_less_multiplier'] ?? 0.2).toDouble(),
      historyLimit: json['history_limit'] ?? 200,
      personality: _parsePersonality(json['personality']),
      // Custom mode - Simple
      avoidRepeatingSongs: json['avoid_repeating_songs'] ?? true,
      avoidRepeatingArtists: json['avoid_repeating_artists'] ?? true,
      avoidRepeatingAlbums: json['avoid_repeating_albums'] ?? true,
      favorLeastPlayed: json['favor_least_played'] ?? true,
      // Custom mode - Advanced
      leastPlayedWeight: json['least_played_weight'] ?? 0,
      mostPlayedWeight: json['most_played_weight'] ?? 0,
      favoritesWeight: json['favorites_weight'] ?? 0,
      suggestLessWeight: json['suggest_less_weight'] ?? 0,
      playlistSongsWeight: json['playlist_songs_weight'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'anti_repeat_enabled': antiRepeatEnabled,
      'streak_breaker_enabled': streakBreakerEnabled,
      'favorite_multiplier': favoriteMultiplier,
      'suggest_less_multiplier': suggestLessMultiplier,
      'history_limit': historyLimit,
      'personality': _personalityToString(personality),
      // Custom mode - Simple
      'avoid_repeating_songs': avoidRepeatingSongs,
      'avoid_repeating_artists': avoidRepeatingArtists,
      'avoid_repeating_albums': avoidRepeatingAlbums,
      'favor_least_played': favorLeastPlayed,
      // Custom mode - Advanced
      'least_played_weight': leastPlayedWeight,
      'most_played_weight': mostPlayedWeight,
      'favorites_weight': favoritesWeight,
      'suggest_less_weight': suggestLessWeight,
      'playlist_songs_weight': playlistSongsWeight,
    };
  }

  static ShufflePersonality _parsePersonality(String? val) {
    switch (val) {
      case 'explorer':
        return ShufflePersonality.explorer;
      case 'consistent':
        return ShufflePersonality.consistent;
      case 'custom':
        return ShufflePersonality.custom;
      default:
        return ShufflePersonality.defaultMode;
    }
  }

  static String _personalityToString(ShufflePersonality p) {
    switch (p) {
      case ShufflePersonality.explorer:
        return 'explorer';
      case ShufflePersonality.consistent:
        return 'consistent';
      case ShufflePersonality.custom:
        return 'custom';
      default:
        return 'default';
    }
  }

  ShuffleConfig copyWith({
    bool? enabled,
    bool? antiRepeatEnabled,
    bool? streakBreakerEnabled,
    double? favoriteMultiplier,
    double? suggestLessMultiplier,
    int? historyLimit,
    ShufflePersonality? personality,
    // Custom mode - Simple
    bool? avoidRepeatingSongs,
    bool? avoidRepeatingArtists,
    bool? avoidRepeatingAlbums,
    bool? favorLeastPlayed,
    // Custom mode - Advanced
    int? leastPlayedWeight,
    int? mostPlayedWeight,
    int? favoritesWeight,
    int? suggestLessWeight,
    int? playlistSongsWeight,
  }) {
    return ShuffleConfig(
      enabled: enabled ?? this.enabled,
      antiRepeatEnabled: antiRepeatEnabled ?? this.antiRepeatEnabled,
      streakBreakerEnabled: streakBreakerEnabled ?? this.streakBreakerEnabled,
      favoriteMultiplier: favoriteMultiplier ?? this.favoriteMultiplier,
      suggestLessMultiplier:
          suggestLessMultiplier ?? this.suggestLessMultiplier,
      historyLimit: historyLimit ?? this.historyLimit,
      personality: personality ?? this.personality,
      // Custom mode - Simple
      avoidRepeatingSongs: avoidRepeatingSongs ?? this.avoidRepeatingSongs,
      avoidRepeatingArtists:
          avoidRepeatingArtists ?? this.avoidRepeatingArtists,
      avoidRepeatingAlbums: avoidRepeatingAlbums ?? this.avoidRepeatingAlbums,
      favorLeastPlayed: favorLeastPlayed ?? this.favorLeastPlayed,
      // Custom mode - Advanced
      leastPlayedWeight: leastPlayedWeight ?? this.leastPlayedWeight,
      mostPlayedWeight: mostPlayedWeight ?? this.mostPlayedWeight,
      favoritesWeight: favoritesWeight ?? this.favoritesWeight,
      suggestLessWeight: suggestLessWeight ?? this.suggestLessWeight,
      playlistSongsWeight: playlistSongsWeight ?? this.playlistSongsWeight,
    );
  }

  @override
  List<Object?> get props => [
        enabled,
        antiRepeatEnabled,
        streakBreakerEnabled,
        favoriteMultiplier,
        suggestLessMultiplier,
        historyLimit,
        personality,
        // Custom mode - Simple
        avoidRepeatingSongs,
        avoidRepeatingArtists,
        avoidRepeatingAlbums,
        favorLeastPlayed,
        // Custom mode - Advanced
        leastPlayedWeight,
        mostPlayedWeight,
        favoritesWeight,
        suggestLessWeight,
        playlistSongsWeight,
      ];
}

class HistoryEntry extends Equatable {
  final String filename;
  final double timestamp;

  const HistoryEntry({required this.filename, required this.timestamp});

  factory HistoryEntry.fromJson(dynamic json) {
    if (json is String) {
      // Backwards compatibility for legacy string-only history
      return HistoryEntry(filename: json, timestamp: 0);
    }
    return HistoryEntry(
      filename: json['filename'],
      timestamp: (json['timestamp'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filename': filename,
      'timestamp': timestamp,
    };
  }

  @override
  List<Object?> get props => [filename, timestamp];
}

class ShuffleState extends Equatable {
  final ShuffleConfig config;

  const ShuffleState({
    this.config = const ShuffleConfig(),
  });

  factory ShuffleState.fromJson(Map<String, dynamic> json) {
    return ShuffleState(
      config: json['config'] != null
          ? ShuffleConfig.fromJson(json['config'])
          : const ShuffleConfig(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'config': config.toJson(),
    };
  }

  ShuffleState copyWith({
    ShuffleConfig? config,
  }) {
    return ShuffleState(
      config: config ?? this.config,
    );
  }

  @override
  List<Object?> get props => [config];
}
