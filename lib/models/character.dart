class Character {
  Character({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.locked,
    Map<String, Object?>? fields,
    Map<String, String>? comments,
  }) : fields = fields ?? <String, Object?>{},
       comments = comments ?? <String, String>{};

  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;
  bool locked;
  final Map<String, Object?> fields;
  final Map<String, String> comments;

  Character copy() => Character.fromJson(toJson());

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'locked': locked,
    'fields': fields,
    'comments': comments,
  };

  factory Character.fromJson(Map<String, Object?> json) => Character(
    id: json['id']! as String,
    name: json['name']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    locked: json['locked'] as bool? ?? false,
    fields: objectMapFromJson(json['fields']),
    comments: stringMapFromJson(json['comments']),
  );
}

Map<String, Object?> objectMapFromJson(Object? value) {
  if (value is! Map) return <String, Object?>{};
  return {
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

Map<String, String> stringMapFromJson(Object? value) {
  if (value is! Map) return <String, String>{};
  return {
    for (final entry in value.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: entry.value as String,
  };
}

class CharacterSummary {
  const CharacterSummary({
    required this.id,
    required this.name,
    required this.updatedAt,
    required this.locked,
  });

  final String id;
  final String name;
  final DateTime updatedAt;
  final bool locked;

  factory CharacterSummary.fromJson(Map<String, Object?> json) =>
      CharacterSummary(
        id: json['id']! as String,
        name: json['name']! as String,
        updatedAt: DateTime.parse(json['updatedAt']! as String),
        locked: json['locked'] as bool? ?? false,
      );
}
