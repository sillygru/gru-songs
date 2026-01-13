import 'package:equatable/equatable.dart';

class ShuffleConfig extends Equatable {
  final bool antiRepeatEnabled;
  final int antiRepeatWindow;
  final bool streakBreakerEnabled;
  final double artistWeight;
  final double albumWeight;

  const ShuffleConfig({
    this.antiRepeatEnabled = true,
    this.antiRepeatWindow = 10,
    this.streakBreakerEnabled = true,
    this.artistWeight = 0.5,
    this.albumWeight = 0.5,
  });

  factory ShuffleConfig.fromJson(Map<String, dynamic> json) {
    return ShuffleConfig(
      antiRepeatEnabled: json['anti_repeat_enabled'] ?? true,
      antiRepeatWindow: json['anti_repeat_window'] ?? 10,
      streakBreakerEnabled: json['streak_breaker_enabled'] ?? true,
      artistWeight: (json['artist_weight'] ?? 0.5).toDouble(),
      albumWeight: (json['album_weight'] ?? 0.5).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'anti_repeat_enabled': antiRepeatEnabled,
      'anti_repeat_window': antiRepeatWindow,
      'streak_breaker_enabled': streakBreakerEnabled,
      'artist_weight': artistWeight,
      'album_weight': albumWeight,
    };
  }

  @override
  List<Object?> get props => [
    antiRepeatEnabled,
    antiRepeatWindow,
    streakBreakerEnabled,
    artistWeight,
    albumWeight,
  ];
}
