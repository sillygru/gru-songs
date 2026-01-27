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
  final Duration? duration;
  final double? mtime;

  const Song({
    required this.title,
    required this.artist,
    required this.album,
    required this.filename,
    required this.url,
    this.lyricsUrl,
    this.coverUrl,
    this.playCount = 0,
    this.duration,
    this.mtime,
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
      duration: (json['duration'] != null && json['duration'] > 0)
          ? Duration(milliseconds: (json['duration'] * 1000).round())
          : null,
      mtime: json['mtime']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'artist': artist,
      'album': album,
      'filename': filename,
      'url': url,
      'lyrics_url': lyricsUrl,
      'cover_url': coverUrl,
      'play_count': playCount,
      if (duration != null) 'duration': duration!.inMilliseconds / 1000.0,
      if (mtime != null) 'mtime': mtime,
    };
  }

  @override
  List<Object?> get props => [
        title,
        artist,
        album,
        filename,
        url,
        lyricsUrl,
        coverUrl,
        playCount,
        duration,
        mtime
      ];
}

class LyricLine extends Equatable {
  final Duration time;
  final String text;

  const LyricLine({required this.time, required this.text});

  static List<LyricLine> parse(String content) {
    final List<LyricLine> lyrics = [];
    final RegExp timeExp = RegExp(r'[[0-9]+:[0-9]+.?\[d*]');

    for (var line in content.split('\n')) {
      line = line.trim();
      if (line.isEmpty) continue;

      final List<RegExpMatch> matches = timeExp.allMatches(line).toList();
      if (matches.isEmpty) {
        final bool isMetadata = RegExp(r'^[a-z]+:.*]$').hasMatch(line);
        if (!isMetadata) {
          lyrics.add(LyricLine(time: Duration.zero, text: line));
        }
        continue;
      }

      for (int i = 0; i < matches.length; i++) {
        final match = matches[i];
        final int minutes = int.parse(match.group(1)!);
        final double seconds = double.parse(match.group(2)!);
        final duration = Duration(
          milliseconds: (minutes * 60 * 1000 + seconds * 1000).toInt(),
        );

        // Text for this timestamp is everything until the next timestamp
        int nextStart =
            (i + 1 < matches.length) ? matches[i + 1].start : line.length;
        String text = line.substring(match.end, nextStart).trim();

        // If text is empty, it might be multiple tags for the same text at the end
        if (text.isEmpty) {
          // Look forward for the first non-empty text in this line
          for (int j = i + 1; j < matches.length; j++) {
            int jNextStart =
                (j + 1 < matches.length) ? matches[j + 1].start : line.length;
            String jText = line.substring(matches[j].end, jNextStart).trim();
            if (jText.isNotEmpty) {
              text = jText;
              break;
            }
          }
          // If still empty, it might be that the text is before the tags (unlikely but handle it)
          if (text.isEmpty) {
            text = line.replaceAll(timeExp, '').trim();
          }
        }

        if (text.isNotEmpty) {
          lyrics.add(LyricLine(time: duration, text: text));
        }
      }
    }

    lyrics.sort((a, b) => a.time.compareTo(b.time));
    return lyrics;
  }

  @override
  List<Object?> get props => [time, text];
}
