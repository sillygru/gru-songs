import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import 'song.dart';

class QueueItem extends Equatable {
  final String queueId;
  final Song song;
  final bool isPriority;

  QueueItem({
    required this.song,
    String? queueId,
    this.isPriority = false,
  }) : queueId = queueId ?? const Uuid().v4();

  QueueItem copyWith({
    Song? song,
    String? queueId,
    bool? isPriority,
  }) {
    return QueueItem(
      song: song ?? this.song,
      queueId: queueId ?? this.queueId,
      isPriority: isPriority ?? this.isPriority,
    );
  }

  @override
  List<Object?> get props => [queueId, song, isPriority];
}
