import 'package:dnd_sheet_archive/data/local_archive_sync_store.dart';
import 'package:dnd_sheet_archive/data/sembast_character_repository.dart';
import 'package:dnd_sheet_archive/models/archive_sync_data.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:dnd_sheet_archive/models/character_merge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  var databaseIndex = 0;

  /// Un dispositivo: archivio proprio, orologio proprio.
  Future<(SembastCharacterRepository, void Function(DateTime))> device() async {
    var now = DateTime.utc(2026, 3, 1, 12);
    final database = await databaseFactoryMemory.openDatabase(
      'character-merge-${databaseIndex++}.db',
    );
    addTearDown(database.close);
    return (
      SembastCharacterRepository(database, now: () => now),
      (DateTime value) => now = value,
    );
  }

  /// Porta su [to] la scheda di [from], come farebbe un sync.
  Future<void> syncInto(
    SembastCharacterRepository from,
    SembastCharacterRepository to,
  ) async {
    final remote = await LocalArchiveSyncStore(from.database).read();
    await LocalArchiveSyncStore(to.database).mergeAndReplace(remote);
  }

  test(
    'modifiche contemporanee a campi diversi sopravvivono entrambe',
    () async {
      final (phone, setPhoneClock) = await device();
      final (laptop, setLaptopClock) = await device();
      final created = await phone.createCharacter('Minsc');
      await syncInto(phone, laptop);

      // Offline, ciascuno modifica la propria parte della scheda.
      setPhoneClock(DateTime.utc(2026, 3, 1, 13));
      final onPhone = (await phone.getCharacter(created.id))!;
      await phone.saveCharacterEdits(
        onPhone.copy()
          ..fields['HP'] = '31'
          ..comments['HP'] = 'Dopo il riposo breve',
        onPhone,
      );
      setLaptopClock(DateTime.utc(2026, 3, 1, 14));
      final onLaptop = (await laptop.getCharacter(created.id))!;
      await laptop.saveCharacterEdits(
        onLaptop.copy()
          ..fields['STR'] = '18'
          ..locked = true,
        onLaptop,
      );

      await syncInto(laptop, phone);
      await syncInto(phone, laptop);

      for (final repository in [phone, laptop]) {
        final merged = (await repository.getCharacter(created.id))!;
        expect(merged.fields['HP'], '31');
        expect(merged.comments['HP'], 'Dopo il riposo breve');
        expect(merged.fields['STR'], '18');
        expect(merged.locked, isTrue);
      }
      expect(
        (await phone.getCharacter(created.id))!.toJson(),
        (await laptop.getCharacter(created.id))!.toJson(),
      );
    },
  );

  test('sullo stesso campo vince la modifica più recente', () async {
    final (phone, setPhoneClock) = await device();
    final (laptop, setLaptopClock) = await device();
    final created = await phone.createCharacter('Minsc');
    await syncInto(phone, laptop);

    setLaptopClock(DateTime.utc(2026, 3, 1, 14));
    final onLaptop = (await laptop.getCharacter(created.id))!;
    await laptop.saveCharacterEdits(
      onLaptop.copy()..fields['HP'] = '12',
      onLaptop,
    );
    // Il telefono salva per ultimo, ma ha modificato il campo prima.
    setPhoneClock(DateTime.utc(2026, 3, 1, 13));
    final onPhone = (await phone.getCharacter(created.id))!;
    await phone.saveCharacterEdits(
      onPhone.copy()..fields['HP'] = '31',
      onPhone,
    );

    await syncInto(phone, laptop);
    expect((await laptop.getCharacter(created.id))!.fields['HP'], '12');
  });

  test('svuotare un campo dopo una modifica altrove lo svuota', () async {
    final (phone, setPhoneClock) = await device();
    final (laptop, setLaptopClock) = await device();
    final created = await phone.createCharacter('Minsc');
    final withHp = created.copy()..fields['HP'] = '31';
    await phone.saveCharacterEdits(withHp, created);
    await syncInto(phone, laptop);

    setLaptopClock(DateTime.utc(2026, 3, 1, 15));
    final onLaptop = (await laptop.getCharacter(created.id))!;
    await laptop.saveCharacterEdits(
      onLaptop.copy()..fields.remove('HP'),
      onLaptop,
    );
    setPhoneClock(DateTime.utc(2026, 3, 1, 14));
    final onPhone = (await phone.getCharacter(created.id))!;
    await phone.saveCharacterEdits(
      onPhone.copy()..fields['AC'] = '16',
      onPhone,
    );

    await syncInto(laptop, phone);
    final merged = (await phone.getCharacter(created.id))!;
    expect(merged.fields.containsKey('HP'), isFalse);
    expect(merged.fields['AC'], '16');
  });

  test('chi modifica dopo aver ricevuto una scheda vince anche con '
      'l\'orologio indietro', () async {
    final (phone, setPhoneClock) = await device();
    final (laptop, setLaptopClock) = await device();
    // Il portatile ha l'orologio avanti di un'ora.
    setLaptopClock(DateTime.utc(2026, 3, 1, 13));
    final created = await laptop.createCharacter('Minsc');
    final edited = created.copy()..fields['HP'] = '12';
    await laptop.saveCharacterEdits(edited, created);
    await syncInto(laptop, phone);

    setPhoneClock(DateTime.utc(2026, 3, 1, 12, 5));
    final onPhone = (await phone.getCharacter(created.id))!;
    await phone.saveCharacterEdits(
      onPhone.copy()..fields['HP'] = '31',
      onPhone,
    );

    await syncInto(phone, laptop);
    expect((await laptop.getCharacter(created.id))!.fields['HP'], '31');
  });

  test('il merge è commutativo e unire una scheda con sé stessa non la '
      'cambia', () {
    final base = Character(
      id: 'shared',
      name: 'Minsc',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      locked: false,
      fields: {'CharacterName': 'Minsc'},
    );
    final a = base.copy()..fields['HP'] = '31';
    stampCharacterChanges(before: base, after: a, now: DateTime.utc(2026, 2));
    final b = base.copy()
      ..fields['STR'] = '18'
      ..comments['STR'] = 'Cintura';
    stampCharacterChanges(before: base, after: b, now: DateTime.utc(2026, 3));

    final ab = mergeCharacters(a, b);
    final ba = mergeCharacters(b, a);
    expect(ab.toJson(), ba.toJson());
    expect(mergeCharacters(ab, ab).toJson(), ab.toJson());
    expect(mergeCharacters(a, a).toJson(), a.toJson());
    expect(mergeCharacters(ab, a).toJson(), ab.toJson());
  });

  test('le schede senza orologi per campo ricadono su updatedAt', () {
    Character legacy(String name, DateTime updatedAt, Map<String, Object?> f) =>
        Character.fromJson({
          'id': 'legacy',
          'name': name,
          'createdAt': DateTime.utc(2026).toIso8601String(),
          'updatedAt': updatedAt.toIso8601String(),
          'locked': false,
          'fields': f,
        });
    final older = legacy('Vecchio', DateTime.utc(2026, 1, 1), {'HP': '10'});
    final newer = legacy('Nuovo', DateTime.utc(2026, 1, 2), {'AC': '15'});

    expect(older.clockFloor, older.updatedAt);
    final merged = mergeCharacters(older, newer);
    // Come il merge di prima, sull'intera scheda: vince la più recente.
    expect(merged.name, 'Nuovo');
    expect(merged.fields, {'AC': '15'});
  });

  test('gli orologi attraversano il backup su Drive', () {
    final character = Character(
      id: 'shared',
      name: 'Minsc',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      locked: false,
    );
    final edited = character.copy()..fields['HP'] = '31';
    stampCharacterChanges(
      before: character,
      after: edited,
      now: DateTime.utc(2026, 2),
    );
    final restored = ArchiveSyncData.fromJson(
      ArchiveSyncData(
        generatedAt: DateTime.utc(2026, 2),
        characters: [edited],
      ).toJson(),
    ).characters.single;

    expect(restored.clocks, {'field:HP': DateTime.utc(2026, 2)});
    expect(restored.clockFloor, DateTime.utc(2026));
    expect(restored.toJson(), edited.toJson());
  });
}
