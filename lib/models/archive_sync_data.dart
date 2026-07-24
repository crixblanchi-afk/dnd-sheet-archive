import 'dart:convert';

import 'character.dart';
import 'character_version.dart';
import 'snapshot_policy.dart';

class ArchiveSyncData {
  ArchiveSyncData({
    required this.generatedAt,
    Iterable<Character> characters = const [],
    Iterable<CharacterVersion> versions = const [],
    Map<String, DateTime> deletions = const {},
  }) : characters = List.of(characters),
       versions = List.of(versions),
       deletions = Map.of(deletions);

  static const schemaVersion = 1;

  final DateTime generatedAt;
  final List<Character> characters;
  final List<CharacterVersion> versions;
  final Map<String, DateTime> deletions;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'characters': characters.map((character) => character.toJson()).toList(),
    'versions': versions.map((version) => version.toJson()).toList(),
    'deletions': {
      for (final entry in deletions.entries)
        entry.key: entry.value.toUtc().toIso8601String(),
    },
  };

  factory ArchiveSyncData.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Versione del backup Drive non supportata.');
    }
    final generatedAtValue = json['generatedAt'];
    final generatedAt = generatedAtValue is String
        ? DateTime.tryParse(generatedAtValue)
        : null;
    if (generatedAt == null) {
      throw const FormatException('Data del backup Drive non valida.');
    }

    final charactersValue = json['characters'];
    final versionsValue = json['versions'];
    final deletionsValue = json['deletions'];
    if (charactersValue is! List ||
        versionsValue is! List ||
        deletionsValue is! Map) {
      throw const FormatException('Contenuto del backup Drive non valido.');
    }

    final characters = <Character>[];
    for (final value in charactersValue) {
      characters.add(Character.fromJson(_stringKeyedMap(value)));
    }
    final versions = <CharacterVersion>[];
    for (final value in versionsValue) {
      versions.add(CharacterVersion.fromJson(_stringKeyedMap(value)));
    }
    final deletions = <String, DateTime>{};
    for (final entry in deletionsValue.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('Cancellazione nel backup non valida.');
      }
      final deletedAt = DateTime.tryParse(entry.value as String);
      if (deletedAt == null) {
        throw const FormatException('Data di cancellazione non valida.');
      }
      deletions[entry.key as String] = deletedAt;
    }

    return ArchiveSyncData(
      generatedAt: generatedAt,
      characters: characters,
      versions: versions,
      deletions: deletions,
    );
  }

  static ArchiveSyncData merge(
    ArchiveSyncData local,
    ArchiveSyncData remote, {
    DateTime? generatedAt,
  }) {
    final deletions = Map<String, DateTime>.of(local.deletions);
    for (final entry in remote.deletions.entries) {
      final current = deletions[entry.key];
      if (current == null || entry.value.isAfter(current)) {
        deletions[entry.key] = entry.value;
      }
    }

    final characters = <String, Character>{};
    for (final character in [...local.characters, ...remote.characters]) {
      final current = characters[character.id];
      if (current == null || _preferCharacter(character, current)) {
        characters[character.id] = character.copy();
      }
    }

    for (final entry in Map<String, DateTime>.of(deletions).entries) {
      final character = characters[entry.key];
      if (character == null || !character.updatedAt.isAfter(entry.value)) {
        characters.remove(entry.key);
      } else {
        // A later edit is an intentional resurrection and supersedes deletion.
        deletions.remove(entry.key);
      }
    }

    final versions = <String, CharacterVersion>{};
    for (final version in [...local.versions, ...remote.versions]) {
      if (!characters.containsKey(version.characterId)) continue;
      final current = versions[version.id];
      if (current == null || _preferVersion(version, current)) {
        versions[version.id] = CharacterVersion.fromJson(version.toJson());
      }
    }

    final retainedVersions = retainRecentSnapshots(
      versions.values,
      activeCharacterIds: characters.keys.toSet(),
    );

    final sortedCharacters = characters.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final sortedVersions = retainedVersions
      ..sort((a, b) => a.id.compareTo(b.id));
    return ArchiveSyncData(
      generatedAt: (generatedAt ?? DateTime.now()).toUtc(),
      characters: sortedCharacters,
      versions: sortedVersions,
      deletions: deletions,
    );
  }

  static bool _preferCharacter(Character candidate, Character current) {
    final timestampOrder = candidate.updatedAt.compareTo(current.updatedAt);
    if (timestampOrder != 0) return timestampOrder > 0;
    return _stableJson(
          candidate.toJson(),
        ).compareTo(_stableJson(current.toJson())) >
        0;
  }

  static bool _preferVersion(
    CharacterVersion candidate,
    CharacterVersion current,
  ) {
    final timestampOrder = candidate.createdAt.compareTo(current.createdAt);
    if (timestampOrder != 0) return timestampOrder > 0;
    return _stableJson(
          candidate.toJson(),
        ).compareTo(_stableJson(current.toJson())) >
        0;
  }

  static String _stableJson(Map<String, Object?> value) {
    Object? normalize(Object? item) {
      if (item is Map) {
        final entries = item.entries.toList()
          ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
        return {
          for (final entry in entries)
            entry.key.toString(): normalize(entry.value),
        };
      }
      if (item is List) return item.map(normalize).toList();
      return item;
    }

    return jsonEncode(normalize(value));
  }
}

Map<String, Object?> _stringKeyedMap(Object? value) {
  if (value is! Map) throw const FormatException('Documento non valido.');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('Chiave del documento non valida.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}
