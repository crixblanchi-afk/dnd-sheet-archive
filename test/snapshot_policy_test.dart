import 'package:dnd_sheet_archive/models/character_version.dart';
import 'package:dnd_sheet_archive/models/snapshot_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gli snapshot automatici sono solo sessione e blocco', () {
    expect(isAutomaticSnapshot('session'), isTrue);
    expect(isAutomaticSnapshot('lock'), isTrue);
    expect(isAutomaticSnapshot('pre-restore'), isFalse);
  });

  test('di ogni personaggio restano le versioni più recenti', () {
    final versions = [
      for (var day = 1; day <= maxSnapshotsPerCharacter + 3; day++)
        _version('giorno-$day', 'hero', DateTime.utc(2026, 1, day)),
    ];

    final retained = retainRecentSnapshots(versions);

    expect(retained, hasLength(maxSnapshotsPerCharacter));
    expect(
      retained.map((version) => version.id),
      contains('giorno-${maxSnapshotsPerCharacter + 3}'),
    );
    expect(retained.map((version) => version.id), isNot(contains('giorno-1')));
  });

  test('il limite si applica a ogni personaggio separatamente', () {
    final versions = [
      for (final characterId in ['hero', 'villain'])
        for (var day = 1; day <= maxSnapshotsPerCharacter + 2; day++)
          _version(
            '$characterId-$day',
            characterId,
            DateTime.utc(2026, 1, day),
          ),
    ];

    final retained = retainRecentSnapshots(versions);

    expect(retained, hasLength(maxSnapshotsPerCharacter * 2));
    for (final characterId in ['hero', 'villain']) {
      expect(
        retained.where((version) => version.characterId == characterId),
        hasLength(maxSnapshotsPerCharacter),
      );
    }
  });

  test('le versioni di personaggi non attivi vengono scartate', () {
    final versions = [
      _version('viva', 'hero', DateTime.utc(2026)),
      _version('orfana', 'deleted', DateTime.utc(2026)),
    ];

    final retained = retainRecentSnapshots(
      versions,
      activeCharacterIds: {'hero'},
    );

    expect(retained.single.id, 'viva');
  });

  test('senza elenco di personaggi attivi nessuna versione viene filtrata', () {
    final versions = [
      _version('viva', 'hero', DateTime.utc(2026)),
      _version('orfana', 'deleted', DateTime.utc(2026)),
    ];

    expect(retainRecentSnapshots(versions), hasLength(2));
  });

  test('a parità di data il taglio è deterministico', () {
    final versions = [
      for (var day = 2; day <= maxSnapshotsPerCharacter; day++)
        _version('giorno-$day', 'hero', DateTime.utc(2026, 1, day)),
      _version('aa', 'hero', DateTime.utc(2026, 1, 1)),
      _version('zz', 'hero', DateTime.utc(2026, 1, 1)),
    ];

    final retained = retainRecentSnapshots(versions);
    final retainedIds = retained.map((version) => version.id);

    expect(retained, hasLength(maxSnapshotsPerCharacter));
    expect(retainedIds, contains('zz'));
    expect(retainedIds, isNot(contains('aa')));
  });
}

CharacterVersion _version(String id, String characterId, DateTime createdAt) =>
    CharacterVersion(
      id: id,
      characterId: characterId,
      createdAt: createdAt,
      reason: 'session',
      name: 'Hero',
      locked: false,
      fields: const {},
      comments: const {},
    );
