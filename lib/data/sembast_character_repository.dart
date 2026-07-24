import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../models/character.dart';
import '../models/character_version.dart';
import '../models/snapshot_policy.dart';
import '../sync/archive_sync_tracker.dart';
import 'character_repository.dart';

class SembastCharacterRepository implements CharacterRepository {
  SembastCharacterRepository(
    this.database, {
    Uuid? uuid,
    ArchiveSyncTracker? syncTracker,
    DateTime Function()? now,
  }) : _uuid = uuid ?? const Uuid(),
       syncTracker = syncTracker ?? ArchiveSyncTracker.inMemory(),
       _now = now ?? DateTime.now;

  final Database database;
  final Uuid _uuid;
  final DateTime Function() _now;
  final ArchiveSyncTracker syncTracker;
  final _characters = stringMapStoreFactory.store('characters');
  final _versions = stringMapStoreFactory.store('versions');
  final _tombstones = stringMapStoreFactory.store('sync_tombstones');

  @override
  Stream<List<CharacterSummary>> watchCharacters() => _characters
      .query(finder: Finder(sortOrders: [SortOrder('updatedAt', false)]))
      .onSnapshots(database)
      .map(
        (records) => records
            .map((record) => CharacterSummary.fromJson(record.value))
            .toList(growable: false),
      );

  @override
  Future<Character?> getCharacter(String id) async {
    final value = await _characters.record(id).get(database);
    return value == null ? null : Character.fromJson(value);
  }

  @override
  Future<Character> createCharacter(String name) async {
    final now = _now().toUtc();
    final character = Character(
      id: _uuid.v4(),
      name: name.trim(),
      createdAt: now,
      updatedAt: now,
      locked: false,
      fields: {'CharacterName': name.trim()},
    );
    await database.transaction((transaction) async {
      await _characters
          .record(character.id)
          .put(transaction, character.toJson());
      await _tombstones.record(character.id).delete(transaction);
    });
    await syncTracker.markChanged();
    return character;
  }

  @override
  Future<void> saveCharacter(Character character) async {
    character.updatedAt = _now().toUtc();
    await database.transaction((transaction) async {
      await _characters
          .record(character.id)
          .put(transaction, character.toJson());
      await _tombstones.record(character.id).delete(transaction);
    });
    await syncTracker.markChanged();
  }

  @override
  Future<void> renameCharacter(String id, String newName) async {
    final character = await getCharacter(id);
    if (character == null) return;
    character.name = newName.trim();
    await saveCharacter(character);
  }

  @override
  Future<void> deleteCharacter(String id) async {
    await database.transaction((transaction) async {
      await _characters.record(id).delete(transaction);
      await _versions.delete(
        transaction,
        finder: Finder(filter: Filter.equals('characterId', id)),
      );
      await _tombstones.record(id).put(transaction, {
        'deletedAt': _now().toUtc().toIso8601String(),
      });
    });
    await syncTracker.markChanged();
  }

  @override
  Future<List<VersionMeta>> listVersions(String characterId) async {
    final records = await _versions.find(
      database,
      finder: Finder(
        filter: Filter.equals('characterId', characterId),
        sortOrders: [SortOrder('createdAt', false)],
      ),
    );
    final versions = <VersionMeta>[];
    for (final record in records) {
      final createdAtValue = record.value['createdAt'];
      final reason = record.value['reason'];
      final createdAt = createdAtValue is String
          ? DateTime.tryParse(createdAtValue)
          : null;
      if (createdAt == null || reason is! String) continue;
      versions.add(
        VersionMeta(id: record.key, createdAt: createdAt, reason: reason),
      );
    }
    return versions;
  }

  @override
  Future<CharacterVersion?> getVersion(String versionId) async {
    final value = await _versions.record(versionId).get(database);
    return value == null ? null : CharacterVersion.fromJson(value);
  }

  @override
  Future<void> createSnapshot(Character character, String reason) async {
    final now = _now().toUtc();
    await database.transaction((transaction) async {
      var versionId = _uuid.v4();
      if (isAutomaticSnapshot(reason)) {
        final records = await _versions.find(
          transaction,
          finder: Finder(
            filter: Filter.equals('characterId', character.id),
            sortOrders: [SortOrder('createdAt', false)],
          ),
        );
        for (final record in records) {
          final previous = CharacterVersion.fromJson(record.value);
          if (!isAutomaticSnapshot(previous.reason)) continue;
          final age = now.difference(previous.createdAt);
          if (!age.isNegative && age < automaticSnapshotWindow) {
            versionId = previous.id;
          }
          break;
        }
      }
      final version = CharacterVersion.fromCharacter(
        character,
        id: versionId,
        reason: reason,
        createdAt: now,
      );
      await _versions.record(version.id).put(transaction, version.toJson());
      await _pruneSnapshots(transaction, character.id);
    });
    await syncTracker.markChanged();
  }

  Future<void> _pruneSnapshots(
    DatabaseClient client,
    String characterId,
  ) async {
    final records = await _versions.find(
      client,
      finder: Finder(
        filter: Filter.equals('characterId', characterId),
        sortOrders: [SortOrder('createdAt', false)],
      ),
    );
    for (final record in records.skip(maxSnapshotsPerCharacter)) {
      await _versions.record(record.key).delete(client);
    }
  }

  @override
  Future<void> restoreVersion(String characterId, String versionId) async {
    await database.transaction((transaction) async {
      final liveJson = await _characters.record(characterId).get(transaction);
      final versionJson = await _versions.record(versionId).get(transaction);
      if (liveJson == null || versionJson == null) {
        throw StateError('Character or version not found');
      }
      final live = Character.fromJson(liveJson);
      final version = CharacterVersion.fromJson(versionJson);
      if (version.characterId != characterId) {
        throw StateError('Version belongs to another character');
      }
      final backup = CharacterVersion.fromCharacter(
        live,
        id: _uuid.v4(),
        reason: 'pre-restore',
        createdAt: _now().toUtc(),
      );
      await _versions.record(backup.id).put(transaction, backup.toJson());
      final restored = Character(
        id: live.id,
        name: version.name,
        createdAt: live.createdAt,
        updatedAt: _now().toUtc(),
        locked: version.locked,
        fields: Map.of(version.fields),
        comments: Map.of(version.comments),
      );
      await _characters.record(characterId).put(transaction, restored.toJson());
      await _pruneSnapshots(transaction, characterId);
    });
    await syncTracker.markChanged();
  }
}
