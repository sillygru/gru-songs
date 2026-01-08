import 'package:equatable/equatable.dart';

class Playlist extends Equatable {
  final String id;
  final String name;
  final List<String> songFilenames;

  const Playlist({
    required this.id,
    required this.name,
    required this.songFilenames,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'],
      name: json['name'],
      songFilenames: List<String>.from(json['songs']),
    );
  }

  @override
  List<Object?> get props => [id, name, songFilenames];
}
