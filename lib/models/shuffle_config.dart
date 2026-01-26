import 'package:equatable/equatable.dart';

enum ShufflePersonality { defaultMode, explorer, consistent }

class ShuffleConfig extends Equatable {
  final bool enabled;
  final bool antiRepeatEnabled;
  final bool streakBreakerEnabled;
  final double favoriteMultiplier;
  final double suggestLessMultiplier;
  final int historyLimit;
  final ShufflePersonality personality;

  const ShuffleConfig({
    this.enabled = false,
    this.antiRepeatEnabled = true,
    this.streakBreakerEnabled = true,
    this.favoriteMultiplier = 1.2,
    this.suggestLessMultiplier = 0.2,
    this.historyLimit = 100,
    this.personality = ShufflePersonality.defaultMode,
  });

  factory ShuffleConfig.fromJson(Map<String, dynamic> json) {
    return ShuffleConfig(
      enabled: json['enabled'] ?? false,
      antiRepeatEnabled: json['anti_repeat_enabled'] ?? true,
      streakBreakerEnabled: json['streak_breaker_enabled'] ?? true,
      favoriteMultiplier: (json['favorite_multiplier'] ?? 1.2).toDouble(),
      suggestLessMultiplier:
          (json['suggest_less_multiplier'] ?? 0.2).toDouble(),
      historyLimit: json['history_limit'] ?? 100,
      personality: _parsePersonality(json['personality']),
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
    };
  }

  static ShufflePersonality _parsePersonality(String? val) {
    switch (val) {
      case 'explorer':
        return ShufflePersonality.explorer;
      case 'consistent':
        return ShufflePersonality.consistent;
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
  final List<HistoryEntry> history;

  const ShuffleState({
    this.config = const ShuffleConfig(),
    this.history = const [],
  });

  factory ShuffleState.fromJson(Map<String, dynamic> json) {
    final historyJson = json['history'] as List? ?? [];
    return ShuffleState(
      config: json['config'] != null
          ? ShuffleConfig.fromJson(json['config'])
          : const ShuffleConfig(),
      history: historyJson.map((e) => HistoryEntry.fromJson(e)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'config': config.toJson(),
      'history': history.map((e) => e.toJson()).toList(),
    };
  }

  ShuffleState copyWith({
    ShuffleConfig? config,
    List<HistoryEntry>? history,
  }) {
    return ShuffleState(
      config: config ?? this.config,
      history: history ?? this.history,
    );
  }

  @override
  List<Object?> get props => [config, history];
}
