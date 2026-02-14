import 'package:equatable/equatable.dart';

/// Stored in SQLite for fast full-text search
class SearchIndexEntry extends Equatable {
  final String filename;
  final String title;
  final String artist;
  final String album;
  final String? lyricsContent;
  final int titleLength;
  final int artistLength;
  final int albumLength;
  final int? lyricsLength;
  final int lastModified;

  const SearchIndexEntry({
    required this.filename,
    required this.title,
    required this.artist,
    required this.album,
    this.lyricsContent,
    required this.titleLength,
    required this.artistLength,
    required this.albumLength,
    this.lyricsLength,
    required this.lastModified,
  });

  factory SearchIndexEntry.fromMap(Map<String, dynamic> map) {
    return SearchIndexEntry(
      filename: map['filename'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String,
      album: map['album'] as String,
      lyricsContent: map['lyrics_content'] as String?,
      titleLength: map['title_length'] as int,
      artistLength: map['artist_length'] as int,
      albumLength: map['album_length'] as int,
      lyricsLength: map['lyrics_length'] as int?,
      lastModified: map['last_modified'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'filename': filename,
      'title': title,
      'artist': artist,
      'album': album,
      'lyrics_content': lyricsContent,
      'title_length': titleLength,
      'artist_length': artistLength,
      'album_length': albumLength,
      'lyrics_length': lyricsLength,
      'last_modified': lastModified,
    };
  }

  @override
  List<Object?> get props => [
        filename,
        title,
        artist,
        album,
        lyricsContent,
        titleLength,
        artistLength,
        albumLength,
        lyricsLength,
        lastModified,
      ];
}

/// Index metadata for monitoring and optimization
class SearchIndexStats extends Equatable {
  final int totalEntries;
  final int entriesWithLyrics;
  final int totalLyricsChars;
  final DateTime? lastUpdated;

  const SearchIndexStats({
    required this.totalEntries,
    required this.entriesWithLyrics,
    required this.totalLyricsChars,
    this.lastUpdated,
  });

  factory SearchIndexStats.empty() {
    return const SearchIndexStats(
      totalEntries: 0,
      entriesWithLyrics: 0,
      totalLyricsChars: 0,
      lastUpdated: null,
    );
  }

  @override
  List<Object?> get props => [
        totalEntries,
        entriesWithLyrics,
        totalLyricsChars,
        lastUpdated,
      ];
}
