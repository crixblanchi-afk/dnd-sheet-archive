import 'package:dnd_sheet_archive/data/local_archive_sync_store.dart';
import 'package:dnd_sheet_archive/data/sembast_character_repository.dart';
import 'package:dnd_sheet_archive/models/archive_sync_data.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:dnd_sheet_archive/models/character_version.dart';
import 'package:dnd_sheet_archive/models/snapshot_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('merge keeps the newest character and unions append-only versions', () {
    final localCharacter = _character(
      id: 'shared',
      name: 'Local old',
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final remoteCharacter = _character(
      id: 'shared',
      name: 'Remote new',
      updatedAt: DateTime.utc(2026, 1, 2),
    );
    final localOnly = _character(
      id: 'local-only',
      name: 'Local only',
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final merged = ArchiveSyncData.merge(
      ArchiveSyncData(
        generatedAt: DateTime.utc(2026),
        characters: [localCharacter, localOnly],
        versions: [_version(localCharacter, 'local-version')],
      ),
      ArchiveSyncData(
        generatedAt: DateTime.utc(2026),
        characters: [remoteCharacter],
        versions: [_version(remoteCharacter, 'remote-version')],
      ),
      generatedAt: DateTime.utc(2026, 1, 3),
    );

    expect(merged.characters, hasLength(2));
    expect(
      merged.characters.singleWhere((item) => item.id == 'shared').name,
      'Remote new',
    );
    expect(
      merged.versions.map((version) => version.id),
      containsAll(['local-version', 'remote-version']),
    );
  });

  test('a later deletion prevents an old device from resurrecting data', () {
    final character = _character(
      id: 'deleted',
      name: 'Deleted',
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final merged = ArchiveSyncData.merge(
      ArchiveSyncData(
        generatedAt: DateTime.utc(2026),
        characters: [character],
        versions: [_version(character, 'version')],
      ),
      ArchiveSyncData(
        generatedAt: DateTime.utc(2026),
        deletions: {'deleted': DateTime.utc(2026, 1, 2)},
      ),
    );

    expect(merged.characters, isEmpty);
    expect(merged.versions, isEmpty);
    expect(merged.deletions, contains('deleted'));
  });

  test('an edit made after a concurrent deletion wins', () {
    final edited = _character(
      id: 'shared',
      name: 'Edited later',
      updatedAt: DateTime.utc(2026, 1, 3),
    );
    final merged = ArchiveSyncData.merge(
      ArchiveSyncData(generatedAt: DateTime.utc(2026), characters: [edited]),
      ArchiveSyncData(
        generatedAt: DateTime.utc(2026),
        deletions: {'shared': DateTime.utc(2026, 1, 2)},
      ),
    );

    expect(merged.characters.single.name, 'Edited later');
    expect(merged.deletions, isEmpty);
  });

  test('repository deletion is exported as a sync tombstone', () async {
    final database = await databaseFactoryMemory.openDatabase('sync-test.db');
    final repository = SembastCharacterRepository(database);
    final store = LocalArchiveSyncStore(database);
    final character = await repository.createCharacter('Deleted hero');

    await repository.deleteCharacter(character.id);
    final archive = await store.read();

    expect(archive.characters, isEmpty);
    expect(archive.deletions, contains(character.id));
    await database.close();
  });

  test('sync payload rejects unsupported schema versions', () {
    expect(
      () => ArchiveSyncData.fromJson({
        'schemaVersion': 99,
        'generatedAt': DateTime.utc(2026).toIso8601String(),
        'characters': <Object?>[],
        'versions': <Object?>[],
        'deletions': <String, Object?>{},
      }),
      throwsFormatException,
    );
  });

  test('merge keeps only the newest snapshots for each character', () {
    final character = _character(
      id: 'limited',
      name: 'Limited history',
      updatedAt: DateTime.utc(2026, 1, 20),
    );
    final versions = [
      for (var day = 0; day < maxSnapshotsPerCharacter + 2; day++)
        _version(
          character,
          'version-$day',
          createdAt: DateTime.utc(2026, 1, 1 + day),
        ),
    ];

    final merged = ArchiveSyncData.merge(
      ArchiveSyncData(
        generatedAt: DateTime.utc(2026),
        characters: [character],
        versions: versions.take(6),
      ),
      ArchiveSyncData(
        generatedAt: DateTime.utc(2026),
        characters: [character],
        versions: versions.skip(6),
      ),
    );

    expect(merged.versions, hasLength(maxSnapshotsPerCharacter));
    expect(
      merged.versions.map((version) => version.id),
      isNot(containsAll(['version-0', 'version-1'])),
    );
    expect(
      merged.versions.map((version) => version.id),
      contains('version-11'),
    );
  });

  test('merge prefers the newest content of a coalesced snapshot', () {
    final character = _character(
      id: 'coalesced',
      name: 'Current',
      updatedAt: DateTime.utc(2026, 1, 3),
    );
    final oldVersion = _version(
      character,
      'same-version',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    character.fields['AC'] = '20';
    final newVersion = _version(
      character,
      'same-version',
      createdAt: DateTime.utc(2026, 1, 2),
    );

    final merged = ArchiveSyncData.merge(
      ArchiveSyncData(
        generatedAt: DateTime.utc(2026),
        characters: [character],
        versions: [oldVersion],
      ),
      ArchiveSyncData(
        generatedAt: DateTime.utc(2026),
        characters: [character],
        versions: [newVersion],
      ),
    );

    expect(merged.versions.single.fields['AC'], '20');
    expect(merged.versions.single.createdAt, DateTime.utc(2026, 1, 2));
  });
}

Character _character({
  required String id,
  required String name,
  required DateTime updatedAt,
}) => Character(
  id: id,
  name: name,
  createdAt: DateTime.utc(2025),
  updatedAt: updatedAt,
  locked: false,
  fields: {'CharacterName': name},
);

CharacterVersion _version(
  Character character,
  String id, {
  DateTime? createdAt,
}) => CharacterVersion.fromCharacter(
  character,
  id: id,
  reason: 'session',
  createdAt: createdAt ?? DateTime.utc(2026),
);
