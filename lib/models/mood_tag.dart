import 'package:equatable/equatable.dart';

class MoodTag extends Equatable {
  final String id;
  final String name;
  final String normalizedName;
  final bool isPreset;
  final double createdAt;

  const MoodTag({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.isPreset,
    required this.createdAt,
  });

  factory MoodTag.fromJson(Map<String, dynamic> json) {
    return MoodTag(
      id: json['id'] as String,
      name: json['name'] as String,
      normalizedName: json['normalized_name'] as String,
      isPreset: (json['is_preset'] as int? ?? 0) == 1,
      createdAt: (json['created_at'] as num?)?.toDouble() ??
          DateTime.now().millisecondsSinceEpoch / 1000.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'normalized_name': normalizedName,
      'is_preset': isPreset ? 1 : 0,
      'created_at': createdAt,
    };
  }

  MoodTag copyWith({
    String? id,
    String? name,
    String? normalizedName,
    bool? isPreset,
    double? createdAt,
  }) {
    return MoodTag(
      id: id ?? this.id,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      isPreset: isPreset ?? this.isPreset,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [id, name, normalizedName, isPreset, createdAt];
}
