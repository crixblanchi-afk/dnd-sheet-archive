import 'dart:convert';
import 'dart:typed_data';

import 'package:dnd_sheet_archive/data/blob_store.dart';
import 'package:dnd_sheet_archive/data/local_archive_sync_store.dart';
import 'package:dnd_sheet_archive/models/archive_sync_data.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:dnd_sheet_archive/models/character_version.dart';
import 'package:dnd_sheet_archive/models/image_payload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

final _characters = stringMapStoreFactory.store('characters');
final _versions = stringMapStoreFactory.store('versions');
final _blobs = stringMapStoreFactory.store('blobs');

void main() {
  var databaseIndex = 0;
  late Database database;
  late LocalArchiveSyncStore store;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'local-sync-store-${databaseIndex++}.db',
    );
    store = LocalArchiveSyncStore(database);
    addTearDown(database.close);
  });

  /// Le chiavi dei record toccati dal merge, per store.
  Map<String, List<String>> watchWrites() {
    final touched = <String, List<String>>{};
    for (final entry in {
      'characters': _characters,
      'versions': _versions,
    }.entries) {
      void listener(
        Transaction transaction,
        List<RecordChange<String, Map<String, Object?>>> changes,
      ) {
        touched
            .putIfAbsent(entry.key, () => [])
            .addAll(changes.map((change) => change.ref.key));
      }

      // Il listener resta attaccato per tutta la durata del test: sembast
      // confronta le callback su una firma dinamica e `removeOnChangesListener`
      // rifiuta quella tipizzata. Il database viene chiuso dal teardown.
      entry.value.addOnChangesListener(database, listener);
    }
    return touched;
  }

  test('un merge senza novità non scrive niente', () async {
    await _characters
        .record('unchanged')
        .put(database, _character('unchanged', DateTime.utc(2026)).toJson());
    final remote = await store.read();
    final writes = watchWrites();

    final merged = await store.mergeAndReplace(remote);

    // Prima ogni sync svuotava i tre store e li riscriveva da capo: era la
    // finestra in cui un processo ucciso lasciava l'archivio a metà.
    expect(writes, isEmpty);
    expect(merged.characters, hasLength(1));
  });

  test('il merge tocca soltanto i record cambiati', () async {
    await _characters
        .record('shared')
        .put(database, _character('shared', DateTime.utc(2026, 1, 1)).toJson());
    await _characters
        .record('local')
        .put(database, _character('local', DateTime.utc(2026, 1, 1)).toJson());
    final writes = watchWrites();

    await store.mergeAndReplace(
      ArchiveSyncData(
        generatedAt: DateTime.utc(2026, 1, 2),
        characters: [
          _character('shared', DateTime.utc(2026, 1, 2)),
          _character('remote', DateTime.utc(2026, 1, 2)),
        ],
      ),
    );

    expect(writes['characters'], unorderedEquals(['shared', 'remote']));
    expect(await _characters.count(database), 3);
  });

  test(
    'le immagini del backup arrivano nei blob e tornano nel payload',
    () async {
      final image = Uint8List.fromList(List.generate(48, (index) => index));
      final reference = blobReferenceFor(image);
      final character = _character('illustrated', DateTime.utc(2026, 1, 2));
      character.fields['CharacterAppearanceImage'] = reference;

      await store.mergeAndReplace(
        ArchiveSyncData(
          generatedAt: DateTime.utc(2026, 1, 2),
          characters: [character],
          blobs: {reference: base64Encode(image)},
        ),
      );

      expect(await BlobStore(database).read(reference), image);
      // Rileggere l'archivio locale rimette l'immagine nel backup una volta
      // sola, qualunque sia il numero di schede e versioni che la mostrano.
      final payload = await store.read();
      expect(payload.blobs, {reference: base64Encode(image)});
    },
  );

  test('un backup nel formato 1 viene normalizzato, non duplicato', () async {
    final image = Uint8List.fromList(List.generate(48, (index) => index * 3));
    final inline = base64Encode(image);
    final character = _character('legacy', DateTime.utc(2026, 1, 2));
    character.fields['CharacterAppearanceImage'] = inline;
    final version = CharacterVersion.fromCharacter(
      character,
      id: 'legacy-version',
      reason: 'session',
      createdAt: DateTime.utc(2026, 1, 2),
    );

    final merged = await store.mergeAndReplace(
      ArchiveSyncData(
        generatedAt: DateTime.utc(2026, 1, 2),
        characters: [character],
        versions: [version],
      ),
    );

    final reference = blobReferenceFor(image);
    expect(
      merged.characters.single.fields['CharacterAppearanceImage'],
      reference,
    );
    expect(
      merged.versions.single.fields['CharacterAppearanceImage'],
      reference,
    );
    expect(merged.blobs.keys, [reference]);
    expect(await _blobs.count(database), 1);
  });

  test('un\'immagine che nessuno cita più lascia l\'archivio', () async {
    final image = Uint8List.fromList(List.generate(48, (index) => index * 5));
    // Scritta da tempo: fuori dalla tregua concessa alle immagini nuove.
    final reference = await BlobStore(
      database,
      now: () => DateTime.utc(2025),
    ).write(image);
    await _characters
        .record('illustrated')
        .put(
          database,
          (_character(
            'illustrated',
            DateTime.utc(2026),
          )..fields['CharacterAppearanceImage'] = reference).toJson(),
        );

    await store.mergeAndReplace(
      ArchiveSyncData(
        generatedAt: DateTime.utc(2026, 1, 2),
        deletions: {'illustrated': DateTime.utc(2026, 1, 2)},
      ),
    );

    expect(await _characters.count(database), 0);
    expect(await _blobs.count(database), 0);
  });
}

Character _character(String id, DateTime updatedAt) => Character(
  id: id,
  name: id,
  createdAt: DateTime.utc(2025),
  updatedAt: updatedAt,
  locked: false,
  fields: {'CharacterName': id},
);
