import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:dnd_sheet_archive/data/local_archive_sync_store.dart';
import 'package:dnd_sheet_archive/data/sembast_character_repository.dart';
import 'package:dnd_sheet_archive/models/archive_sync_data.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:dnd_sheet_archive/sync/archive_sync_tracker.dart';
import 'package:dnd_sheet_archive/sync/desktop_google_auth.dart';
import 'package:dnd_sheet_archive/sync/google_drive_sync_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var databaseIndex = 0;
  late Database database;
  late ArchiveSyncTracker tracker;
  late SembastCharacterRepository repository;
  late _FakeDrive drive;
  GoogleDriveSyncService? service;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    database = await databaseFactoryMemory.openDatabase(
      'drive-concurrency-${databaseIndex++}.db',
    );
    tracker = ArchiveSyncTracker.inMemory();
    repository = SembastCharacterRepository(database, syncTracker: tracker);
    drive = _FakeDrive();
  });

  tearDown(() async {
    service?.dispose();
    service = null;
    tracker.dispose();
    await database.close();
    debugDefaultTargetPlatformOverride = null;
  });

  GoogleDriveSyncService build({bool connected = false}) =>
      service = GoogleDriveSyncService(
        LocalArchiveSyncStore(database),
        syncTracker: tracker,
        desktopAuth: _TestAuth(MockClient(drive.handle), connected: connected),
        syncTimeout: const Duration(seconds: 5),
      );

  /// Aspetta che il sync partito da solo, all'avvio, finisca.
  Future<void> settle(GoogleDriveSyncService sync) async {
    for (var i = 0; i < 500; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (sync.state != GoogleDriveSyncState.syncing &&
          sync.state != GoogleDriveSyncState.idle) {
        return;
      }
    }
    fail('Il sync non si è concluso.');
  }

  /// Gli id delle schede presenti in tutti i backup su Drive.
  Set<String> remoteCharacterIds() => {
    for (final file in drive.files.values)
      for (final character in file.content['characters'] as List)
        (character as Map)['id'] as String,
  };

  test('due dispositivi che caricano insieme non si sovrascrivono', () async {
    final local = await repository.createCharacter('Minsc');
    drive.put('backup', _archive([_character('a', 'Jaheira')]));
    // Mentre questo dispositivo prepara il proprio backup, un altro carica
    // il suo, che contiene una scheda in più.
    drive.beforeUpload = () {
      drive.beforeUpload = null;
      drive.put(
        'other',
        _archive([_character('a', 'Jaheira'), _character('b', 'Khalid')]),
      );
    };

    final result = await build().sync();

    // Nessun backup è stato riscritto: quello dell'altro dispositivo resta,
    // accanto al nuovo, e insieme contengono tutto.
    expect(drive.files.keys, containsAll(['other', 'new-1']));
    expect(drive.files.containsKey('backup'), isFalse);
    expect(remoteCharacterIds(), {local.id, 'a', 'b'});
    expect(result.characters, 2);
    expect(tracker.hasPendingChanges, isFalse);

    // Il giro successivo li riunisce in uno solo.
    await service!.sync();
    expect(drive.files, hasLength(1));
    expect(remoteCharacterIds(), {local.id, 'a', 'b'});
    expect(await repository.getCharacter('b'), isNotNull);
  });

  test('un backup aggiornato sul posto da una versione precedente non viene '
      'cancellato', () async {
    final local = await repository.createCharacter('Minsc');
    drive.put('backup', _archive([_character('a', 'Jaheira')]));
    // Le versioni precedenti dell'app aggiornano il file esistente: succede
    // dopo che questo sync l'ha scaricato, prima che lo cancelli.
    drive.beforeVersionCheck = () {
      drive.beforeVersionCheck = null;
      drive.put(
        'backup',
        _archive([_character('a', 'Jaheira'), _character('b', 'Khalid')]),
      );
    };

    await build().sync();

    expect(drive.files.keys, containsAll(['backup', 'new-1']));
    expect(remoteCharacterIds(), {local.id, 'a', 'b'});

    await service!.sync();
    expect(drive.files, hasLength(1));
    expect(remoteCharacterIds(), {local.id, 'a', 'b'});
  });

  test('due backup creati insieme vengono uniti in uno solo', () async {
    await repository.createCharacter('Minsc');
    drive.put('first', _archive([_character('a', 'Jaheira')]));
    drive.put('second', _archive([_character('b', 'Khalid')]));

    await build().sync();

    expect(drive.files.keys, ['new-1']);
    expect(drive.content('new-1')['characters'] as List, hasLength(3));
    expect(await repository.getCharacter('a'), isNotNull);
    expect(await repository.getCharacter('b'), isNotNull);
  });

  test('il sync in background riceve le modifiche fatte altrove e non '
      'scarica niente se il backup non è cambiato', () async {
    drive.put('backup', _archive([_character('a', 'Jaheira')]));
    final sync = build(connected: true);
    await settle(sync);
    expect(await repository.getCharacter('a'), isNotNull);
    expect(drive.downloads, 1);
    // Il backup conteneva già tutto: niente da ricaricare.
    expect(drive.uploads, 0);

    expect(await sync.syncInBackground(), isTrue);
    expect(drive.downloads, 1);

    // Un altro dispositivo carica il proprio backup e cancella quello che ha
    // unito.
    drive.files.clear();
    drive.put(
      'other',
      _archive([_character('a', 'Jaheira'), _character('b', 'Khalid')]),
    );
    expect(await sync.syncInBackground(), isTrue);
    expect(drive.downloads, 2);
    expect(await repository.getCharacter('b'), isNotNull);
  });

  test('chiudere l\'app salva le schede aperte e poi le spedisce', () async {
    final character = await repository.createCharacter('Minsc');
    final sync = build(connected: true);
    await settle(sync);
    final uploadsBefore = drive.uploads;
    final order = <String>[];
    final remove = sync.addExitTask(() async {
      order.add('save');
      final current = (await repository.getCharacter(character.id))!;
      await repository.saveCharacterEdits(
        current.copy()..fields['HP'] = '31',
        current,
      );
    });
    addTearDown(remove);

    expect(await sync.didRequestAppExit(), AppExitResponse.exit);

    expect(order, ['save']);
    expect(drive.uploads, uploadsBefore + 1);
    expect(drive.files, hasLength(1));
    final uploaded = drive.files.values.single.content['characters'] as List;
    expect(((uploaded.single as Map)['fields'] as Map)['HP'], '31');
    expect(tracker.hasPendingChanges, isFalse);
  });

  test('un lavoro di chiusura che fallisce non blocca l\'uscita', () async {
    final sync = build();
    sync.addExitTask(() async => throw StateError('disco pieno'));
    expect(await sync.didRequestAppExit(), AppExitResponse.exit);
  });
}

class _RemoteFile {
  _RemoteFile(this.version, this.content);

  final int version;
  final Map<String, Object?> content;
}

/// Un `appDataFolder` in memoria, con le versioni che Drive incrementa a ogni
/// scrittura.
class _FakeDrive {
  final files = <String, _RemoteFile>{};
  int _version = 0;
  int _created = 0;
  int uploads = 0;
  int downloads = 0;
  void Function()? beforeVersionCheck;
  void Function()? beforeUpload;

  void put(String id, Map<String, Object?> content) {
    files.remove(id);
    files[id] = _RemoteFile(++_version, content);
  }

  Map<String, Object?> content(String id) => files[id]!.content;

  Future<http.Response> handle(http.Request request) async {
    final segments = request.url.pathSegments;
    if (segments.first == 'upload') {
      beforeUpload?.call();
      uploads++;
      final encoded = RegExp(
        r'Content-Transfer-Encoding: base64\r\n\r\n([A-Za-z0-9+/=]+)',
      ).firstMatch(request.body)!.group(1)!;
      final content =
          jsonDecode(utf8.decode(base64Decode(encoded)))
              as Map<String, Object?>;
      final id = segments.last == 'files' ? 'new-${++_created}' : segments.last;
      put(id, content);
      return _json({'id': id, 'version': '${files[id]!.version}'});
    }
    if (segments.last == 'files') {
      // Il più recente per primo, come `orderBy: modifiedTime desc`.
      return _json({
        'files': [
          for (final entry in files.entries.toList().reversed)
            {'id': entry.key, 'version': '${entry.value.version}'},
        ],
      });
    }
    final id = segments.last;
    if (request.method == 'DELETE') {
      files.remove(id);
      return http.Response('', 204);
    }
    if (request.url.queryParameters['alt'] == 'media') {
      downloads++;
      return _json(files[id]!.content);
    }
    beforeVersionCheck?.call();
    return _json({'id': id, 'version': '${files[id]!.version}'});
  }
}

Map<String, Object?> _archive(List<Character> characters) => ArchiveSyncData(
  generatedAt: DateTime.utc(2026, 3),
  characters: characters,
).toJson();

http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Character _character(String id, String name) => Character(
  id: id,
  name: name,
  createdAt: DateTime.utc(2026, 3),
  updatedAt: DateTime.utc(2026, 3),
  locked: false,
);

class _TestAuth extends DesktopGoogleAuth {
  _TestAuth(this.client, {required this.connected})
    : super(clientId: 'test', clientSecret: 'test', scopes: []);

  final http.Client client;
  final bool connected;

  @override
  bool get isConfigured => true;

  @override
  bool get isConnected => connected;

  @override
  Future<void> restore() async {}

  @override
  Future<http.Client> authenticatedClient() async => client;

  @override
  void dispose() => client.close();
}
