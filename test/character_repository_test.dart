import 'package:dnd_sheet_archive/data/sembast_character_repository.dart';
import 'package:dnd_sheet_archive/models/snapshot_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  late SembastCharacterRepository repository;

  setUp(() async {
    final database = await databaseFactoryMemory.openDatabase('test.db');
    repository = SembastCharacterRepository(database);
  });

  test('create and save character', () async {
    final character = await repository.createCharacter('Minsc');
    expect(character.fields['CharacterName'], 'Minsc');
    character.fields['STR'] = '18';
    await repository.saveCharacter(character);
    expect((await repository.getCharacter(character.id))!.fields['STR'], '18');
  });

  test('snapshot and restore preserve the current state', () async {
    final character = await repository.createCharacter('Jaheira');
    character.fields['AC'] = '16';
    character.comments['AC'] = 'Leather armor';
    await repository.saveCharacter(character);
    await repository.createSnapshot(character, 'session');
    final originalVersion = (await repository.listVersions(
      character.id,
    )).single;

    character.fields['AC'] = '20';
    character.comments.clear();
    await repository.saveCharacter(character);
    await repository.restoreVersion(character.id, originalVersion.id);

    final restored = await repository.getCharacter(character.id);
    expect(restored!.fields['AC'], '16');
    expect(restored.comments['AC'], 'Leather armor');
    final versions = await repository.listVersions(character.id);
    expect(versions, hasLength(2));
    expect(versions.any((version) => version.reason == 'pre-restore'), isTrue);
  });

  test('delete removes character and its versions', () async {
    final character = await repository.createCharacter('Boo');
    await repository.createSnapshot(character, 'session');
    await repository.deleteCharacter(character.id);
    expect(await repository.getCharacter(character.id), isNull);
    expect(await repository.listVersions(character.id), isEmpty);
  });

  test('automatic snapshots are coalesced daily and capped', () async {
    var now = DateTime.utc(2026, 1, 1, 8);
    final database = await databaseFactoryMemory.openDatabase(
      'snapshot-policy.db',
    );
    final repository = SembastCharacterRepository(database, now: () => now);
    final character = await repository.createCharacter('Viconia');

    character.fields['WIS'] = '16';
    await repository.createSnapshot(character, 'session');
    final first = (await repository.listVersions(character.id)).single;

    now = now.add(const Duration(hours: 2));
    character.fields['WIS'] = '18';
    await repository.createSnapshot(character, 'lock');

    final coalesced = await repository.listVersions(character.id);
    expect(coalesced, hasLength(1));
    expect(coalesced.single.id, first.id);
    expect((await repository.getVersion(first.id))!.fields['WIS'], '18');

    for (var day = 1; day <= maxSnapshotsPerCharacter + 2; day++) {
      now = DateTime.utc(2026, 1, 1 + day, 10);
      character.fields['WIS'] = '${18 + day}';
      await repository.createSnapshot(character, 'session');
    }

    final retained = await repository.listVersions(character.id);
    expect(retained, hasLength(maxSnapshotsPerCharacter));
    expect(retained.any((version) => version.id == first.id), isFalse);
    expect(
      (await repository.getVersion(retained.first.id))!.fields['WIS'],
      '${18 + maxSnapshotsPerCharacter + 2}',
    );
    await database.close();
  });
}
