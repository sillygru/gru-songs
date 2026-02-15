class Playlist {
  final String id;
  final String name;
  final String? description;
  final bool isRecommendation;
  final double createdAt;
  final double updatedAt;
  final List<PlaylistSong> songs;

  Playlist({
    required this.id,
    required this.name,
    this.description,
    this.isRecommendation = false,
    required this.createdAt,
    required this.updatedAt,
    required this.songs,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      isRecommendation: (json['is_recommendation'] as int? ?? 0) == 1,
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
      'description': description,
      'is_recommendation': isRecommendation ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'songs': songs.map((e) => e.toJson()).toList(),
    };
  }

  Playlist copyWith({
    String? id,
    String? name,
    String? description,
    bool? isRecommendation,
    double? createdAt,
    double? updatedAt,
    List<PlaylistSong>? songs,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isRecommendation: isRecommendation ?? this.isRecommendation,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      songs: songs ?? this.songs,
    );
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
