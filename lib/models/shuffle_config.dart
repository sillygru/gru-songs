import 'package:equatable/equatable.dart';

class ShuffleConfig extends Equatable {
  final bool enabled;
  final bool antiRepeatEnabled;
  final bool streakBreakerEnabled;
  final double favoriteMultiplier;
  final double suggestLessMultiplier;
  final int historyLimit;

  const ShuffleConfig({
    this.enabled = false,
    this.antiRepeatEnabled = true,
    this.streakBreakerEnabled = true,
    this.favoriteMultiplier = 1.15,
    this.suggestLessMultiplier = 0.2,
    this.historyLimit = 50,
  });

  factory ShuffleConfig.fromJson(Map<String, dynamic> json) {
    return ShuffleConfig(
      enabled: json['enabled'] ?? false,
      antiRepeatEnabled: json['anti_repeat_enabled'] ?? true,
      streakBreakerEnabled: json['streak_breaker_enabled'] ?? true,
      favoriteMultiplier: (json['favorite_multiplier'] ?? 1.15).toDouble(),
      suggestLessMultiplier: (json['suggest_less_multiplier'] ?? 0.2).toDouble(),
      historyLimit: json['history_limit'] ?? 50,
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
    };
  }

  ShuffleConfig copyWith({
    bool? enabled,
    bool? antiRepeatEnabled,
    bool? streakBreakerEnabled,
    double? favoriteMultiplier,
    double? suggestLessMultiplier,
    int? historyLimit,
  }) {
    return ShuffleConfig(
      enabled: enabled ?? this.enabled,
      antiRepeatEnabled: antiRepeatEnabled ?? this.antiRepeatEnabled,
      streakBreakerEnabled: streakBreakerEnabled ?? this.streakBreakerEnabled,
      favoriteMultiplier: favoriteMultiplier ?? this.favoriteMultiplier,
      suggestLessMultiplier: suggestLessMultiplier ?? this.suggestLessMultiplier,
      historyLimit: historyLimit ?? this.historyLimit,
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
      ];
}

class ShuffleState extends Equatable {
  final ShuffleConfig config;
  final List<String> history;

  const ShuffleState({
    this.config = const ShuffleConfig(),
    this.history = const [],
  });

  factory ShuffleState.fromJson(Map<String, dynamic> json) {
    return ShuffleState(
      config: json['config'] != null 
          ? ShuffleConfig.fromJson(json['config']) 
          : const ShuffleConfig(),
      history: List<String>.from(json['history'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'config': config.toJson(),
      'history': history,
    };
  }

  ShuffleState copyWith({
    ShuffleConfig? config,
    List<String>? history,
  }) {
    return ShuffleState(
      config: config ?? this.config,
      history: history ?? this.history,
    );
  }

  @override
  List<Object?> get props => [config, history];
}
