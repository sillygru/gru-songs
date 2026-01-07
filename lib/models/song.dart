class Song {
  final String title;
  final String artist;
  final String filename;
  final String url;
  final String? lyricsUrl;
  final String? coverUrl;

  Song({
    required this.title,
    required this.artist,
    required this.filename,
    required this.url,
    this.lyricsUrl,
    this.coverUrl,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      title: json['title'] ?? 'Unknown Title',
      artist: json['artist'] ?? 'Unknown Artist',
      filename: json['filename'] ?? '',
      url: json['url'] ?? '',
      lyricsUrl: json['lyrics_url'],
      coverUrl: json['cover_url'],
    );
  }
}
