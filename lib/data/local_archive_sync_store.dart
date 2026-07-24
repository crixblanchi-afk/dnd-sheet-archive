import 'package:sembast/sembast.dart';

import '../models/archive_sync_data.dart';
import '../models/character.dart';
import '../models/character_version.dart';

class LocalArchiveSyncStore {
  LocalArchiveSyncStore(this.database);

  final Database database;
  final _characters = stringMapStoreFactory.store('characters');
  final _versions = stringMapStoreFactory.store('versions');
  final _tombstones = stringMapStoreFactory.store('sync_tombstones');

  Future<ArchiveSyncData> read() => _read(database);

  Future<ArchiveSyncData> mergeAndReplace(ArchiveSyncData remote) async {
    late ArchiveSyncData merged;
    await database.transaction((transaction) async {
      final local = await _read(transaction);
      merged = ArchiveSyncData.merge(local, remote);
      await _characters.delete(transaction);
      await _versions.delete(transaction);
      await _tombstones.delete(transaction);
      for (final character in merged.characters) {
        await _characters
            .record(character.id)
            .put(transaction, character.toJson());
      }
      for (final version in merged.versions) {
        await _versions.record(version.id).put(transaction, version.toJson());
      }
      for (final entry in merged.deletions.entries) {
        await _tombstones.record(entry.key).put(transaction, {
          'deletedAt': entry.value.toUtc().toIso8601String(),
        });
      }
    });
    return merged;
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
    return ArchiveSyncData(
      generatedAt: DateTime.now().toUtc(),
      characters: characterRecords.map(
        (record) => Character.fromJson(record.value),
      ),
      versions: versionRecords.map(
        (record) => CharacterVersion.fromJson(record.value),
      ),
      deletions: deletions,
    );
  }
}
