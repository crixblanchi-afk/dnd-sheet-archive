import 'package:collection/collection.dart';
import 'package:sembast/sembast.dart';

import '../models/archive_sync_data.dart';
import '../models/character.dart';
import '../models/character_version.dart';
import '../models/image_payload.dart';
import 'blob_store.dart';

const _deepEquals = DeepCollectionEquality();

class LocalArchiveSyncStore {
  LocalArchiveSyncStore(this.database);

  final Database database;
  final _characters = stringMapStoreFactory.store('characters');
  final _versions = stringMapStoreFactory.store('versions');
  final _tombstones = stringMapStoreFactory.store('sync_tombstones');
  late final BlobStore _blobs = BlobStore(database);

  Future<ArchiveSyncData> read() => _read(database);

  Future<ArchiveSyncData> mergeAndReplace(
    ArchiveSyncData remote, {
    void Function()? beforeReplace,
  }) async {
    late ArchiveSyncData merged;
    await database.transaction((transaction) async {
      final local = await _read(transaction);
      merged = ArchiveSyncData.merge(local, remote);
      beforeReplace?.call();
      await _applyDifferences(transaction, local, merged);
    });
    return merged;
  }

  /// Scrive soltanto i record che il merge ha cambiato.
  ///
  /// Prima i tre store venivano svuotati e riscritti da capo. Il log di sembast
  /// è però un append di una riga per record senza marcatore di commit: un
  /// processo ucciso a metà scrittura poteva lasciare sul disco le
  /// cancellazioni senza le riscritture, e quindi un archivio locale vuoto.
  /// Toccare le sole differenze rende quella finestra proporzionale a quanto è
  /// davvero cambiato, e nel caso più comune — nessuna novità da Drive — non
  /// scrive niente.
  Future<void> _applyDifferences(
    DatabaseClient client,
    ArchiveSyncData local,
    ArchiveSyncData merged,
  ) async {
    await _syncRecords(
      client,
      _characters,
      {
        for (final character in local.characters)
          character.id: character.toJson(),
      },
      {
        for (final character in merged.characters)
          character.id: character.toJson(),
      },
    );
    await _syncRecords(
      client,
      _versions,
      {for (final version in local.versions) version.id: version.toJson()},
      {for (final version in merged.versions) version.id: version.toJson()},
    );
    await _syncRecords(
      client,
      _tombstones,
      {
        for (final entry in local.deletions.entries)
          entry.key: {'deletedAt': entry.value.toUtc().toIso8601String()},
      },
      {
        for (final entry in merged.deletions.entries)
          entry.key: {'deletedAt': entry.value.toUtc().toIso8601String()},
      },
    );
    await _blobs.writePayloads(client, merged.blobs);
    await _blobs.collectGarbage(client);
  }

  Future<void> _syncRecords(
    DatabaseClient client,
    StoreRef<String, Map<String, Object?>> store,
    Map<String, Map<String, Object?>> before,
    Map<String, Map<String, Object?>> after,
  ) async {
    for (final entry in after.entries) {
      if (_deepEquals.equals(before[entry.key], entry.value)) continue;
      await store.record(entry.key).put(client, entry.value);
    }
    for (final key in before.keys) {
      if (after.containsKey(key)) continue;
      await store.record(key).delete(client);
    }
  }

  Future<ArchiveSyncData> _read(DatabaseClient client) async {
    final characterRecords = await _characters.find(client);
    final versionRecords = await _versions.find(client);
    final tombstoneRecords = await _tombstones.find(client);
    final deletions = <String, DateTime>{};
    for (final record in tombstoneRecords) {
      final value = record.value['deletedAt'];
      final deletedAt = value is String ? DateTime.tryParse(value) : null;
      if (deletedAt != null) deletions[record.key] = deletedAt;
    }
    final characters = characterRecords
        .map((record) => Character.fromJson(record.value))
        .toList(growable: false);
    final versions = versionRecords
        .map((record) => CharacterVersion.fromJson(record.value))
        .toList(growable: false);
    return ArchiveSyncData(
      generatedAt: DateTime.now().toUtc(),
      characters: characters,
      versions: versions,
      deletions: deletions,
      // Il backup è un file unico: le immagini citate dalle schede e dalle
      // versioni viaggiano con esso, una sola volta per contenuto.
      blobs: await _blobs.readPayloads(client, [
        for (final character in characters)
          ...blobReferencesIn(character.fields),
        for (final version in versions) ...blobReferencesIn(version.fields),
      ]),
    );
  }
}
