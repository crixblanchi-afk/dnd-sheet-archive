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
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;
  final String characterId;

  /// Apertura dello snapshot, e quindi ancora della finestra di 24 ore entro
  /// la quale i salvataggi automatici successivi lo aggiornano invece di
  /// crearne uno nuovo. Resta fissa per tutta la vita dello snapshot.
  final DateTime createdAt;

  /// Ultima volta che il contenuto è stato aggiornato.
  ///
  /// Due dispositivi che aggiornano lo stesso snapshot dentro la stessa
  /// finestra ne condividono il `createdAt`: senza questo timestamp il merge
  /// non potrebbe dire quale dei due corpi è il più recente e ripiegherebbe
  /// su un ordinamento arbitrario.
  final DateTime updatedAt;

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
    DateTime? updatedAt,
  }) => CharacterVersion(
    id: id,
    characterId: character.id,
    createdAt: createdAt ?? DateTime.now().toUtc(),
    updatedAt: updatedAt,
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
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'reason': reason,
    'name': name,
    'locked': locked,
    'fields': fields,
    'comments': comments,
  };

  factory CharacterVersion.fromJson(Map<String, Object?> json) {
    final createdAt = DateTime.parse(json['createdAt']! as String);
    final updatedAtValue = json['updatedAt'];
    return CharacterVersion(
      id: json['id']! as String,
      characterId: json['characterId']! as String,
      createdAt: createdAt,
      // Gli snapshot salvati prima che il campo esistesse non lo hanno: il
      // momento di apertura è la migliore approssimazione disponibile.
      updatedAt: updatedAtValue is String
          ? DateTime.tryParse(updatedAtValue) ?? createdAt
          : createdAt,
      reason: json['reason']! as String,
      name: json['name']! as String,
      locked: json['locked'] as bool? ?? false,
      fields: objectMapFromJson(json['fields']),
      comments: stringMapFromJson(json['comments']),
    );
  }
}
