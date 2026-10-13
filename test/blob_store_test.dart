import 'dart:convert';
import 'dart:typed_data';

import 'package:dnd_sheet_archive/data/blob_store.dart';
import 'package:dnd_sheet_archive/models/image_payload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

final _blobs = stringMapStoreFactory.store('blobs');
final _characters = stringMapStoreFactory.store('characters');
final _versions = stringMapStoreFactory.store('versions');

void main() {
  var databaseIndex = 0;
  late Database database;
  late BlobStore blobs;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'blob-store-${databaseIndex++}.db',
    );
    blobs = BlobStore(database);
    addTearDown(database.close);
  });

  test('lo stesso contenuto occupa un solo blob', () async {
    final portrait = _bytes(1);
    final symbol = _bytes(2);

    final first = await blobs.write(portrait);
    final second = await blobs.write(Uint8List.fromList(portrait));
    final other = await blobs.write(symbol);

    expect(second, first);
    expect(other, isNot(first));
    expect(await _blobs.count(database), 2);
    expect(await blobs.read(first), portrait);
    expect(await blobs.read(other), symbol);
  });

  test('un riferimento sconosciuto non restituisce byte', () async {
    expect(await blobs.read(blobReferenceFor(_bytes(3))), isNull);
  });

  test('la raccolta elimina i blob che nessuno cita più', () async {
    final live = await blobs.write(_bytes(1));
    final inVersion = await blobs.write(_bytes(2));
    final orphan = await blobs.write(_bytes(3));
    await _characters.record('alive').put(database, {
      'fields': {'CharacterAppearanceImage': live},
    });
    await _versions.record('snapshot').put(database, {
      'fields': {'FactionSymbolImage': inVersion},
    });

    await blobs.collectGarbage(database);

    expect(await blobs.read(live), isNotNull);
    // Un'immagine sostituita sulla scheda resta viva finché una versione la
    // mostra: la cronologia non deve svuotarsi da sola.
    expect(await blobs.read(inVersion), isNotNull);
    expect(await blobs.read(orphan), isNull);
  });

  test('la migrazione sposta le immagini dai campi ai blob', () async {
    final image = _bytes(1);
    final inline = base64Encode(image);
    await _characters.record('legacy').put(database, {
      'id': 'legacy',
      'fields': {'CharacterAppearanceImage': inline, 'STR': '18'},
    });
    await _versions.record('legacy-version').put(database, {
      'id': 'legacy-version',
      'fields': {'CharacterAppearanceImage': inline},
    });

    expect(await blobs.migrateInlineImages(), isTrue);

    final reference = blobReferenceFor(image);
    final character = (await _characters.record('legacy').get(database))!;
    final version = (await _versions.record('legacy-version').get(database))!;
    expect((character['fields'] as Map)['CharacterAppearanceImage'], reference);
    expect((character['fields'] as Map)['STR'], '18');
    expect((version['fields'] as Map)['CharacterAppearanceImage'], reference);
    // La scheda e la sua versione mostrano la stessa immagine: una copia sola.
    expect(await _blobs.count(database), 1);
    expect(await blobs.read(reference), image);
  });

  test('la migrazione non si ripete', () async {
    await _characters.record('legacy').put(database, {
      'fields': {'CharacterAppearanceImage': base64Encode(_bytes(1))},
    });
    final converted = await blobs.write(_bytes(2));
    await _characters.record('migrated').put(database, {
      'fields': {'FactionSymbolImage': converted},
    });

    expect(await blobs.migrateInlineImages(), isTrue);
    expect(await blobs.migrateInlineImages(), isFalse);
    // Un campo già convertito resta com'è: il riferimento non va reinterpretato
    // come payload base64.
    expect(
      ((await _characters.record('migrated').get(database))!['fields']
          as Map)['FactionSymbolImage'],
      converted,
    );
  });
}

/// Byte riconoscibili e diversi fra loro, senza passare da un vero codec.
Uint8List _bytes(int seed) =>
    Uint8List.fromList(List.generate(64, (index) => (index * seed) % 256));
