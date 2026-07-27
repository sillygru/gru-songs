class OnlineSearchResult {
  final String title;
  final String artist;
  final String album;
  final String? coverUrl;
  final String source; // 'deezer' or 'itunes'
  final Duration? duration;

  const OnlineSearchResult({
    required this.title,
    required this.artist,
    required this.album,
    this.coverUrl,
    required this.source,
    this.duration,
  });

  @override
  String toString() {
    return 'OnlineSearchResult(title: $title, artist: $artist, album: $album, source: $source)';
  }
}
