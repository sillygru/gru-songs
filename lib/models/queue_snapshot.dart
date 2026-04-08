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
    String? name,
    required List<String> songFilenames,
    required String source,
  }) {
    final now = DateTime.now();
    final createdAt =
        now.microsecondsSinceEpoch / Duration.microsecondsPerSecond;
    return QueueSnapshot(
      id: now.microsecondsSinceEpoch.toString(),
      name: (name != null && name.trim().isNotEmpty)
          ? name.trim()
          : defaultNameForTimestamp(createdAt),
      createdAt: createdAt,
      songFilenames: songFilenames,
      source: source,
    );
  }

  static String timestampMarkerFromEpochSeconds(double createdAt) =>
      (createdAt * Duration.microsecondsPerSecond).round().toString();

  static String defaultNameForTimestamp(double createdAt) =>
      'Queue @ ${timestampLabelFromEpochSeconds(createdAt)}';

  static String timestampLabelFromEpochSeconds(double createdAt) {
    final date = DateTime.fromMicrosecondsSinceEpoch(
      (createdAt * Duration.microsecondsPerSecond).round(),
    );
    return _formatTimestamp(date);
  }

  static String _formatTimestamp(DateTime dateTime) {
    final local = dateTime.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute:$second';
  }

  DateTime get createdDateTime => DateTime.fromMicrosecondsSinceEpoch(
        (createdAt * Duration.microsecondsPerSecond).round(),
      );

  String get timestampLabel => _formatTimestamp(createdDateTime);

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
    final createdAtRaw = json['created_at'];
    final createdAt = createdAtRaw is num
        ? createdAtRaw.toDouble()
        : double.tryParse(createdAtRaw?.toString() ?? '') ??
            DateTime.now().millisecondsSinceEpoch / 1000.0;
    final idRaw = json['id']?.toString();
    final resolvedId = (idRaw != null && idRaw.isNotEmpty)
        ? idRaw
        : timestampMarkerFromEpochSeconds(createdAt);
    final nameRaw = json['name']?.toString();
    final resolvedName = (nameRaw != null && nameRaw.trim().isNotEmpty)
        ? nameRaw.trim()
        : defaultNameForTimestamp(createdAt);
    final songsRaw = json['song_filenames'] as List?;

    return QueueSnapshot(
      id: resolvedId,
      name: resolvedName,
      createdAt: createdAt,
      songFilenames: songsRaw?.map((song) => song.toString()).toList() ?? [],
      source: json['source'] as String? ?? 'unknown',
    );
  }
}
