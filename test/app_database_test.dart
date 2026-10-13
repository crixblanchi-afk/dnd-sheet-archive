import 'dart:io';

import 'package:dnd_sheet_archive/data/app_database_errors.dart';
import 'package:dnd_sheet_archive/data/app_database_io.dart';
import 'package:dnd_sheet_archive/data/local_archive_sync_store.dart';
import 'package:dnd_sheet_archive/data/sembast_character_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';

final _characters = stringMapStoreFactory.store('characters');

void main() {
  late Directory root;
  late Directory support;
  late Directory documents;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('app-database-test');
    support = Directory(p.join(root.path, 'support'));
    documents = Directory(p.join(root.path, 'Documents'));
    await documents.create();
  });

  tearDown(() async {
    await releaseDesktopArchiveLocks();
    await root.delete(recursive: true);
  });

  test('l\'archivio lasciato in Documenti viene spostato', () async {
    final legacyPath = p.join(documents.path, 'dnd_sheet_archive.db');
    final legacy = await databaseFactoryIo.openDatabase(legacyPath);
    await _characters.record('minsc').put(legacy, {'name': 'Minsc'});
    await legacy.close();

    final database = await openDesktopDatabase(
      directory: support,
      legacyDirectory: documents,
    );
    addTearDown(database.close);

    expect(await _characters.record('minsc').get(database), {'name': 'Minsc'});
    expect(File(legacyPath).existsSync(), isFalse);
    expect(
      File(p.join(support.path, 'dnd_sheet_archive.db')).existsSync(),
      isTrue,
    );
  });

  test(
    'un archivio già spostato non viene sostituito da quello vecchio',
    () async {
      final current = await databaseFactoryIo.openDatabase(
        p.join((await support.create()).path, 'dnd_sheet_archive.db'),
      );
      await _characters.record('current').put(current, {'name': 'Attuale'});
      await current.close();
      final legacy = await databaseFactoryIo.openDatabase(
        p.join(documents.path, 'dnd_sheet_archive.db'),
      );
      await _characters.record('legacy').put(legacy, {'name': 'Vecchio'});
      await legacy.close();

      final database = await openDesktopDatabase(
        directory: support,
        legacyDirectory: documents,
      );
      addTearDown(database.close);

      expect(await _characters.record('current').get(database), isNotNull);
      expect(await _characters.record('legacy').get(database), isNull);
    },
  );

  test('una seconda istanza non apre lo stesso archivio', () async {
    final database = await openDesktopDatabase(
      directory: support,
      legacyDirectory: documents,
    );
    addTearDown(database.close);

    await expectLater(
      openDesktopDatabase(directory: support, legacyDirectory: documents),
      throwsA(isA<ArchiveAlreadyOpenException>()),
    );
  });

  test('un\'apertura fallita non lascia il lock a «Riprova»', () async {
    final legacy = await databaseFactoryIo.openDatabase(
      p.join(documents.path, 'dnd_sheet_archive.db'),
    );
    await _characters.record('minsc').put(legacy, {'name': 'Minsc'});
    await legacy.close();
    // Una directory al posto dell'archivio fa fallire lo spostamento.
    final blocker = Directory(p.join(support.path, 'dnd_sheet_archive.db'));
    await File(p.join(blocker.path, 'occupato')).create(recursive: true);

    await expectLater(
      openDesktopDatabase(directory: support, legacyDirectory: documents),
      throwsA(isA<FileSystemException>()),
    );

    await blocker.delete(recursive: true);
    final database = await openDesktopDatabase(
      directory: support,
      legacyDirectory: documents,
    );
    addTearDown(database.close);
    expect(await _characters.record('minsc').get(database), isNotNull);
  });

  test('un record danneggiato non blocca l\'elenco né il sync', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'damaged-record.db',
    );
    addTearDown(database.close);
    final repository = SembastCharacterRepository(database);
    final healthy = await repository.createCharacter('Minsc');
    await _characters.record('damaged').put(database, {'name': 42});

    final summaries = await repository.watchCharacters().first;
    expect(summaries.map((summary) => summary.id), [healthy.id]);

    final archive = await LocalArchiveSyncStore(database).read();
    expect(archive.characters.map((character) => character.id), [healthy.id]);
    // Fuori dal merge, ma non cancellato: resta lì per un eventuale recupero.
    await LocalArchiveSyncStore(database).mergeAndReplace(archive);
    expect(await _characters.record('damaged').get(database), isNotNull);
  });
}
