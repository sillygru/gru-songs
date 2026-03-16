import 'package:uuid/uuid.dart';

class QueueSnapshot {
  final String id;
  final String name;
  final double createdAt;
  final List<String> songFilenames;
  final String source;

  const QueueSnapshot({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.songFilenames,
    required this.source,
  });

  factory QueueSnapshot.create({
    required String name,
    required List<String> songFilenames,
    required String source,
  }) {
    return QueueSnapshot(
      id: const Uuid().v4(),
      name: name,
      createdAt: DateTime.now().millisecondsSinceEpoch / 1000.0,
      songFilenames: songFilenames,
      source: source,
    );
  }

  DateTime get createdDateTime =>
      DateTime.fromMillisecondsSinceEpoch((createdAt * 1000).toInt());

  String get displayDate {
    final dt = createdDateTime;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final snapshotDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(snapshotDay).inDays;

    final timeStr =
        '${dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour)}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';

    if (diff == 0) return 'Today at $timeStr';
    if (diff == 1) return 'Yesterday at $timeStr';

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day} at $timeStr';
  }

  QueueSnapshot copyWith({
    String? id,
    String? name,
    double? createdAt,
    List<String>? songFilenames,
    String? source,
  }) {
    return QueueSnapshot(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      songFilenames: songFilenames ?? this.songFilenames,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created_at': createdAt,
        'song_filenames': songFilenames,
        'source': source,
      };

  factory QueueSnapshot.fromJson(Map<String, dynamic> json) {
    return QueueSnapshot(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: (json['created_at'] as num).toDouble(),
      songFilenames: List<String>.from(json['song_filenames'] as List),
      source: json['source'] as String? ?? 'unknown',
    );
  }
}
