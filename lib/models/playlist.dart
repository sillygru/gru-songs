class Playlist {
  final String id;
  final String name;
  final double createdAt;
  final double updatedAt;
  final List<PlaylistSong> songs;

  Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.songs,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: (json['created_at'] as num).toDouble(),
      updatedAt: (json['updated_at'] as num).toDouble(),
      songs: (json['songs'] as List<dynamic>?)
              ?.map((e) => PlaylistSong.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'songs': songs.map((e) => e.toJson()).toList(),
    };
  }
}

class PlaylistSong {
  final String songFilename;
  final double addedAt;

  PlaylistSong({
    required this.songFilename,
    required this.addedAt,
  });

  factory PlaylistSong.fromJson(Map<String, dynamic> json) {
    return PlaylistSong(
      songFilename: json['song_filename'] as String,
      addedAt: (json['added_at'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'song_filename': songFilename,
      'added_at': addedAt,
    };
  }
}
