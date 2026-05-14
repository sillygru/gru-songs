import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import 'song.dart';

class QueueItem extends Equatable {
  final String queueId;
  final Song song;

  QueueItem({
    required this.song,
    String? queueId,
  }) : queueId = queueId ?? const Uuid().v4();

  QueueItem copyWith({
    Song? song,
    String? queueId,
  }) {
    return QueueItem(
      song: song ?? this.song,
      queueId: queueId ?? this.queueId,
    );
  }

  factory QueueItem.fromJson(Map<String, dynamic> json) {
    return QueueItem(
      song: Song.fromJson(json['song']),
      queueId: json['queueId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'song': song.toJson(),
      'queueId': queueId,
    };
  }

  @override
  List<Object?> get props => [queueId, song];
}
