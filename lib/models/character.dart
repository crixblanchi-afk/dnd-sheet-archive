import 'game_system.dart';

/// I due campi che mostrano il nome del personaggio, uno per pagina (D&D 5e).
const characterNameFields = ['CharacterName', 'CharacterName 2'];

class Character {
  Character({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.locked,
    this.system = GameSystem.dnd5e,
    DaggerheartClass? daggerheartClass,
    Map<String, Object?>? fields,
    Map<String, String>? comments,
    Map<String, DateTime>? clocks,
    DateTime? clockFloor,
  }) : daggerheartClass = system == GameSystem.daggerheart
           ? (daggerheartClass ?? DaggerheartClass.blank)
           : null,
       fields = fields ?? <String, Object?>{},
       comments = comments ?? <String, String>{},
       clocks = clocks ?? <String, DateTime>{},
       clockFloor = clockFloor ?? updatedAt;

  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;
  bool locked;
  final GameSystem system;
  final DaggerheartClass? daggerheartClass;
  final Map<String, Object?> fields;
  final Map<String, String> comments;

  /// I campi del foglio che rispecchiano il nome del personaggio.
  List<String> get nameFields => system == GameSystem.dnd5e
      ? characterNameFields
      : const ['CharacterName'];

  /// Quando è cambiato per l'ultima volta ogni elemento della scheda.
  ///
  /// Le chiavi sono quelle di `characterClockKeys`. Servono al merge con Drive
  /// per decidere campo per campo invece che sull'intera scheda: due
  /// dispositivi che modificano campi diversi conservano entrambe le modifiche.
  /// Una chiave assente vale `clockFloor`.
  final Map<String, DateTime> clocks;

  /// L'orologio di ogni elemento senza una voce in `clocks`.
  ///
  /// Le schede salvate prima degli orologi per campo non hanno né l'uno né
  /// l'altro: per loro vale `updatedAt`, che riproduce il vecchio merge
  /// sull'intera scheda.
  DateTime clockFloor;

  Character copy() => Character.fromJson(toJson());

  void rename(String value) {
    name = value;
    for (final field in nameFields) {
      if (value.isEmpty) {
        fields.remove(field);
      } else {
        fields[field] = value;
      }
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'locked': locked,
    if (system != GameSystem.dnd5e) 'system': system.id,
    if (daggerheartClass != null) 'daggerheartClass': daggerheartClass!.id,
    'fields': fields,
    'comments': comments,
    'clocks': {
      for (final entry in clocks.entries)
        entry.key: entry.value.toUtc().toIso8601String(),
    },
    'clockFloor': clockFloor.toUtc().toIso8601String(),
  };

  factory Character.fromJson(Map<String, Object?> json) {
    final clockFloor = json['clockFloor'];
    final system = GameSystem.fromJson(json['system']);
    return Character(
      id: json['id']! as String,
      name: json['name']! as String,
      createdAt: DateTime.parse(json['createdAt']! as String),
      updatedAt: DateTime.parse(json['updatedAt']! as String),
      locked: json['locked'] as bool? ?? false,
      system: system,
      daggerheartClass: system == GameSystem.daggerheart
          ? DaggerheartClass.fromJson(json['daggerheartClass'])
          : null,
      fields: objectMapFromJson(json['fields']),
      comments: stringMapFromJson(json['comments']),
      clocks: _dateMapFromJson(json['clocks']),
      clockFloor: clockFloor is String ? DateTime.tryParse(clockFloor) : null,
    );
  }

  /// La scheda, o `null` se il record è danneggiato.
  ///
  /// Un solo record illeggibile non deve rendere inutilizzabili l'elenco o il
  /// sync di tutti gli altri.
  static Character? tryFromJson(Map<String, Object?> json) {
    try {
      return Character.fromJson(json);
    } on Object {
      return null;
    }
  }
}

Map<String, DateTime> _dateMapFromJson(Object? value) {
  if (value is! Map) return <String, DateTime>{};
  return {
    for (final entry in value.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: ?DateTime.tryParse(entry.value as String),
  };
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
    this.system = GameSystem.dnd5e,
    this.daggerheartClass,
  });

  final String id;
  final String name;
  final DateTime updatedAt;
  final bool locked;
  final GameSystem system;
  final DaggerheartClass? daggerheartClass;

  String get systemSubtitle => switch (system) {
    GameSystem.dnd5e => 'D&D 5e',
    GameSystem.daggerheart =>
      daggerheartClass == null || daggerheartClass == DaggerheartClass.blank
          ? 'Daggerheart'
          : 'Daggerheart · ${daggerheartClass!.label}',
  };

  factory CharacterSummary.fromJson(Map<String, Object?> json) {
    final system = GameSystem.fromJson(json['system']);
    return CharacterSummary(
      id: json['id']! as String,
      name: json['name']! as String,
      updatedAt: DateTime.parse(json['updatedAt']! as String),
      locked: json['locked'] as bool? ?? false,
      system: system,
      daggerheartClass: system == GameSystem.daggerheart
          ? (DaggerheartClass.fromJson(json['daggerheartClass']) ??
                DaggerheartClass.blank)
          : null,
    );
  }

  static CharacterSummary? tryFromJson(Map<String, Object?> json) {
    try {
      return CharacterSummary.fromJson(json);
    } on Object {
      return null;
    }
  }
}
