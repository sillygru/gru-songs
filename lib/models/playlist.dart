import 'package:equatable/equatable.dart';

class PlaylistSong extends Equatable {
  final String filename;
  final DateTime addedAt;

  const PlaylistSong({
    required this.filename,
    required this.addedAt,
  });

  factory PlaylistSong.fromJson(Map<String, dynamic> json) {
    return PlaylistSong(
      filename: json['filename'] ?? '',
      addedAt: (json['added_at'] is num)
          ? DateTime.fromMillisecondsSinceEpoch(
              ((json['added_at'] as num) * 1000).toInt())
          : DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [filename, addedAt];
}

class Playlist extends Equatable {
  final String id;
  final String name;
  final List<PlaylistSong> songs;

  const Playlist({
    required this.id,
    required this.name,
    required this.songs,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Untitled',
      songs: (json['songs'] as List?)
              ?.map((e) => PlaylistSong.fromJson(e))
              .toList() ??
          [],
    );
  }

  @override
  List<Object?> get props => [id, name, songs];
}
