import 'character.dart';

class VersionMeta {
  const VersionMeta({
    required this.id,
    required this.createdAt,
    required this.reason,
  });

  final String id;
  final DateTime createdAt;
  final String reason;
}

class CharacterVersion {
  CharacterVersion({
    required this.id,
    required this.characterId,
    required this.createdAt,
    required this.reason,
    required this.name,
    required this.locked,
    required this.fields,
    required this.comments,
  });

  final String id;
  final String characterId;
  final DateTime createdAt;
  final String reason;
  final String name;
  final bool locked;
  final Map<String, Object?> fields;
  final Map<String, String> comments;

  factory CharacterVersion.fromCharacter(
    Character character, {
    required String id,
    required String reason,
    DateTime? createdAt,
  }) => CharacterVersion(
    id: id,
    characterId: character.id,
    createdAt: createdAt ?? DateTime.now().toUtc(),
    reason: reason,
    name: character.name,
    locked: character.locked,
    fields: Map.of(character.fields),
    comments: Map.of(character.comments),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'characterId': characterId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'reason': reason,
    'name': name,
    'locked': locked,
    'fields': fields,
    'comments': comments,
  };

  factory CharacterVersion.fromJson(Map<String, Object?> json) =>
      CharacterVersion(
        id: json['id']! as String,
        characterId: json['characterId']! as String,
        createdAt: DateTime.parse(json['createdAt']! as String),
        reason: json['reason']! as String,
        name: json['name']! as String,
        locked: json['locked'] as bool? ?? false,
        fields: objectMapFromJson(json['fields']),
        comments: stringMapFromJson(json['comments']),
      );
}
