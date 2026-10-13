import 'dart:convert';

import 'package:collection/collection.dart';

import 'character.dart';
import 'character_merge.dart';
import 'character_version.dart';
import 'image_payload.dart';
import 'snapshot_policy.dart';

class ArchiveSyncData {
  ArchiveSyncData({
    required this.generatedAt,
    Iterable<Character> characters = const [],
    Iterable<CharacterVersion> versions = const [],
    Map<String, DateTime> deletions = const {},
    Map<String, String> blobs = const {},
  }) : characters = List.of(characters),
       versions = List.of(versions),
       deletions = Map.of(deletions),
       blobs = Map.of(blobs);

  /// Versione 2: le immagini stanno in `blobs`, indirizzate per contenuto, e i
  /// campi ne tengono il riferimento. Nella 1 ogni campo portava la propria
  /// copia in base64, anche quando dieci versioni mostravano la stessa foto.
  static const schemaVersion = 2;

  /// Formati che questa versione dell'app sa ancora leggere da Drive.
  static const supportedSchemaVersions = {1, 2};

  /// Per quanto una cancellazione resta nel backup come lapide.
  ///
  /// Serve a impedire che un dispositivo rimasto indietro faccia ricomparire
  /// un personaggio eliminato altrove, quindi la finestra deve essere ben più
  /// larga del tempo che un dispositivo può passare offline; senza un limite,
  /// però, l'elenco crescerebbe per sempre.
  static const deletionRetention = Duration(days: 90);

  final DateTime generatedAt;
  final List<Character> characters;
  final List<CharacterVersion> versions;
  final Map<String, DateTime> deletions;

  /// Riferimento dell'immagine -> payload base64.
  final Map<String, String> blobs;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'characters': characters.map((character) => character.toJson()).toList(),
    'versions': versions.map((version) => version.toJson()).toList(),
    'deletions': {
      for (final entry in deletions.entries)
        entry.key: entry.value.toUtc().toIso8601String(),
    },
    'blobs': blobs,
  };

  factory ArchiveSyncData.fromJson(Map<String, Object?> json) {
    if (!supportedSchemaVersions.contains(json['schemaVersion'])) {
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
    // Un backup nel formato 1 non ha `blobs`: le immagini sono ancora dentro
    // i campi e vengono spostate dal merge.
    final blobsValue = json['blobs'] ?? const <String, Object?>{};
    if (blobsValue is! Map) {
      throw const FormatException('Immagini del backup Drive non valide.');
    }
    final blobs = <String, String>{};
    for (final entry in blobsValue.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('Immagine nel backup non valida.');
      }
      blobs[entry.key as String] = entry.value as String;
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
      blobs: blobs,
    );
  }

  static ArchiveSyncData merge(
    ArchiveSyncData local,
    ArchiveSyncData remote, {
    DateTime? generatedAt,
  }) {
    final mergedAt = (generatedAt ?? DateTime.now()).toUtc();
    final deletions = Map<String, DateTime>.of(local.deletions);
    for (final entry in remote.deletions.entries) {
      final current = deletions[entry.key];
      if (current == null || entry.value.isAfter(current)) {
        deletions[entry.key] = entry.value;
      }
    }

    // Le copie della stessa scheda si uniscono campo per campo: vince la
    // modifica più recente di ogni elemento, non l'ultima scheda salvata.
    final characters = <String, Character>{};
    for (final character in [...local.characters, ...remote.characters]) {
      final current = characters[character.id];
      characters[character.id] = current == null
          ? character.copy()
          : mergeCharacters(current, character);
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

    // Le lapidi hanno già fatto il loro lavoro su ogni dispositivo che si è
    // sincronizzato nella finestra di conservazione: tenerle oltre gonfierebbe
    // il backup senza limite.
    final oldestKeptDeletion = mergedAt.subtract(deletionRetention);
    deletions.removeWhere(
      (_, deletedAt) => deletedAt.toUtc().isBefore(oldestKeptDeletion),
    );

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

    final blobs = <String, String>{...local.blobs, ...remote.blobs};
    // Un backup nel formato 1, o una scheda salvata prima della migrazione,
    // porta ancora l'immagine dentro il campo: qui prende la forma comune.
    for (final character in sortedCharacters) {
      extractInlineImages(character.fields, blobs);
    }
    for (final version in sortedVersions) {
      extractInlineImages(version.fields, blobs);
    }
    // Le immagini delle schede eliminate e delle versioni potate non hanno
    // più nessuno che le citi: tenerle gonfierebbe il backup per sempre.
    final referenced = <String>{
      for (final character in sortedCharacters)
        ...blobReferencesIn(character.fields),
      for (final version in sortedVersions) ...blobReferencesIn(version.fields),
    };
    blobs.removeWhere((reference, _) => !referenced.contains(reference));

    return ArchiveSyncData(
      generatedAt: mergedAt,
      characters: sortedCharacters,
      versions: sortedVersions,
      deletions: deletions,
      blobs: blobs,
    );
  }

  static bool _preferVersion(
    CharacterVersion candidate,
    CharacterVersion current,
  ) {
    // Due dispositivi che aggiornano lo stesso snapshot dentro la stessa
    // finestra di 24 ore ne condividono il `createdAt`: a discriminare è
    // l'ultima modifica, non l'apertura.
    final updateOrder = candidate.updatedAt.compareTo(current.updatedAt);
    if (updateOrder != 0) return updateOrder > 0;
    final timestampOrder = candidate.createdAt.compareTo(current.createdAt);
    if (timestampOrder != 0) return timestampOrder > 0;
    return _stableJson(
          candidate.toJson(),
        ).compareTo(_stableJson(current.toJson())) >
        0;
  }

  /// Vero se i due archivi contengono gli stessi dati, a prescindere da
  /// quando sono stati generati e dall'ordine dei record.
  ///
  /// Dice al sync se il merge ha portato qualcosa di nuovo rispetto al backup
  /// su Drive: in caso contrario non serve ricaricarlo.
  static bool sameContent(ArchiveSyncData a, ArchiveSyncData b) {
    const equality = DeepCollectionEquality();
    Map<String, Object?> byId(Iterable<Map<String, Object?>> records) => {
      for (final record in records) record['id']! as String: record,
    };
    String iso(DateTime date) => date.toUtc().toIso8601String();
    return equality.equals(
          byId(a.characters.map((character) => character.toJson())),
          byId(b.characters.map((character) => character.toJson())),
        ) &&
        equality.equals(
          byId(a.versions.map((version) => version.toJson())),
          byId(b.versions.map((version) => version.toJson())),
        ) &&
        equality.equals(
          a.deletions.map((id, date) => MapEntry(id, iso(date))),
          b.deletions.map((id, date) => MapEntry(id, iso(date))),
        ) &&
        equality.equals(a.blobs, b.blobs);
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
