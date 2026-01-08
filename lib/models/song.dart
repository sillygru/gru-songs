import 'package:equatable/equatable.dart';

class Song extends Equatable {
  final String title;
  final String artist;
  final String album;
  final String filename;
  final String url;
  final String? lyricsUrl;
  final String? coverUrl;
  final int playCount;

  const Song({
    required this.title,
    required this.artist,
    required this.album,
    required this.filename,
    required this.url,
    this.lyricsUrl,
    this.coverUrl,
    this.playCount = 0,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      title: json['title'] ?? 'Unknown Title',
      artist: json['artist'] ?? 'Unknown Artist',
      album: json['album'] ?? 'Unknown Album',
      filename: json['filename'] ?? '',
      url: json['url'] ?? '',
      lyricsUrl: json['lyrics_url'],
      coverUrl: json['cover_url'],
      playCount: json['play_count'] ?? 0,
    );
  }

  @override
  List<Object?> get props => [title, artist, album, filename, url, lyricsUrl, coverUrl, playCount];
}

class LyricLine extends Equatable {
  final Duration time;
  final String text;

  const LyricLine({required this.time, required this.text});

  static List<LyricLine> parse(String content) {
    final List<LyricLine> lyrics = [];
    final RegExp regExp = RegExp(r'^\[(\d+):(\d+\.?\d*)\](.*)$');
    
    for (var line in content.split('\n')) {
      final match = regExp.firstMatch(line.trim());
      if (match != null) {
        final int minutes = int.parse(match.group(1)!);
        final double seconds = double.parse(match.group(2)!);
        final String text = match.group(3)!.trim();
        
        lyrics.add(LyricLine(
          time: Duration(milliseconds: (minutes * 60 * 1000 + seconds * 1000).toInt()),
          text: text,
        ));
      } else if (line.trim().isNotEmpty) {
        // Fallback for non-timed lyrics
        lyrics.add(LyricLine(time: Duration.zero, text: line.trim()));
      }
    }
    return lyrics;
  }

  @override
  List<Object?> get props => [time, text];
}