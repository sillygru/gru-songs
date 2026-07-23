import 'package:equatable/equatable.dart';

/// One lyrics record from LRCLIB.
///
/// Mirrors the API payload exactly — `duration` arrives as a float count of
/// *seconds*, not milliseconds, and both lyric fields are independently
/// nullable: a record can carry synced lyrics, plain lyrics, both, or (for an
/// instrumental) neither.
class LrclibResult extends Equatable {
  final int id;
  final String trackName;
  final String artistName;
  final String albumName;
  final Duration? duration;
  final bool instrumental;
  final String? plainLyrics;
  final String? syncedLyrics;

  const LrclibResult({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    this.duration,
    this.instrumental = false,
    this.plainLyrics,
    this.syncedLyrics,
  });

  factory LrclibResult.fromJson(Map<String, dynamic> json) {
    final seconds = (json['duration'] as num?)?.toDouble();
    return LrclibResult(
      id: (json['id'] as num?)?.toInt() ?? 0,
      trackName: (json['trackName'] ?? json['name'] ?? '').toString(),
      artistName: (json['artistName'] ?? '').toString(),
      albumName: (json['albumName'] ?? '').toString(),
      duration: (seconds == null || seconds <= 0)
          ? null
          : Duration(milliseconds: (seconds * 1000).round()),
      instrumental: json['instrumental'] == true,
      plainLyrics: _nonEmpty(json['plainLyrics']),
      syncedLyrics: _nonEmpty(json['syncedLyrics']),
    );
  }

  static String? _nonEmpty(Object? value) {
    if (value is! String) return null;
    return value.trim().isEmpty ? null : value;
  }

  bool get hasSynced => syncedLyrics != null;
  bool get hasPlain => plainLyrics != null;

  /// Whether this record can supply anything at all. An instrumental counts:
  /// applying it deliberately writes empty lyrics, which is a real answer to
  /// "why does this track have no words".
  bool get isUsable => instrumental || hasSynced || hasPlain;

  /// The text to embed. Synced is preferred when present unless [preferPlain]
  /// is set; an instrumental resolves to an empty string either way.
  String? lyricsFor({bool preferPlain = false}) {
    if (instrumental) return '';
    if (preferPlain) return plainLyrics ?? syncedLyrics;
    return syncedLyrics ?? plainLyrics;
  }

  @override
  List<Object?> get props => [
        id,
        trackName,
        artistName,
        albumName,
        duration,
        instrumental,
        plainLyrics,
        syncedLyrics,
      ];
}
