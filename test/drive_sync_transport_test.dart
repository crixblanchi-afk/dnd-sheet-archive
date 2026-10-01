import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  late Database database;
  late ArchiveSyncTracker tracker;
  late SembastCharacterRepository repository;
  GoogleDriveSyncService? service;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await databaseFactoryMemory.deleteDatabase('drive-transport.db');
    database = await databaseFactoryMemory.openDatabase('drive-transport.db');
    tracker = ArchiveSyncTracker.inMemory();
    repository = SembastCharacterRepository(database, syncTracker: tracker);
  });

  tearDown(() async {
    service?.dispose();
    service = null;
    tracker.dispose();
    await database.close();
    debugDefaultTargetPlatformOverride = null;
  });

  GoogleDriveSyncService build(
    MockClient client, {
    LocalArchiveSyncStore? store,
    int maxBytes = 20 * 1024 * 1024,
    Duration timeout = const Duration(seconds: 5),
  }) => service = GoogleDriveSyncService(
    store ?? LocalArchiveSyncStore(database),
    syncTracker: tracker,
    desktopAuth: _TestAuth(client),
    maxBackupBytes: maxBytes,
    syncTimeout: timeout,
  );

  test(
    'Drive download, merge and upload preserve local and remote data',
    () async {
      final character = await repository.createCharacter('Minsc');
      character.fields['STR'] = '18';
      await repository.saveCharacter(character);
      final remoteCharacter = character.copy()
        ..updatedAt = character.updatedAt.add(const Duration(minutes: 1))
        ..fields['AC'] = '20';
      final remote = ArchiveSyncData(
        generatedAt: DateTime.now().toUtc(),
        characters: [remoteCharacter],
      );
      var uploads = 0;
      final sync = build(
        MockClient((request) async {
          if (request.url.path.startsWith('/upload/')) {
            uploads++;
            final encoded = RegExp(
              r'Content-Transfer-Encoding: base64\r\n\r\n([A-Za-z0-9+/=]+)',
            ).firstMatch(request.body)!.group(1)!;
            final uploaded = jsonDecode(utf8.decode(base64Decode(encoded)));
            expect(uploaded['characters'][0]['fields']['STR'], '18');
            expect(uploaded['characters'][0]['fields']['AC'], '20');
            return _json({'id': 'remote'});
          }
          if (request.url.path.endsWith('/remote')) {
            return _json(remote.toJson());
          }
          return _json({
            'files': [
              {'id': 'remote'},
            ],
          });
        }),
      );
      final result = await sync.sync();
      expect(uploads, 1);
      expect(result.characters, 1);
      expect(tracker.hasPendingChanges, isFalse);
      expect(sync.state, GoogleDriveSyncState.success);
      expect((await repository.getCharacter(character.id))!.fields['AC'], '20');
    },
  );

  test(
    'an upload exceeding the UTF-8 limit is rejected before writing Drive',
    () async {
      final character = await repository.createCharacter('🧙' * 200);
      final backup = await LocalArchiveSyncStore(database).read();
      final byteCount = utf8.encode(jsonEncode(backup.toJson())).length;
      expect(byteCount, greaterThan(jsonEncode(backup.toJson()).length));
      var uploads = 0;
      final sync = build(
        MockClient((request) async {
          if (request.url.path.startsWith('/upload/')) {
            uploads++;
            return _json({'id': 'new'});
          }
          return _json({'files': []});
        }),
        store: _FixedStore(database, backup),
        maxBytes: byteCount - 1,
      );
      await expectLater(sync.sync(), throwsFormatException);
      expect(uploads, 0);
      expect(tracker.hasPendingChanges, isTrue);
      expect(sync.state, GoogleDriveSyncState.error);
      expect(await repository.getCharacter(character.id), isNotNull);
    },
  );

  test('an upload exactly at the byte limit remains downloadable', () async {
    await repository.createCharacter('Minsc');
    final backup = await LocalArchiveSyncStore(database).read();
    final byteCount = utf8.encode(jsonEncode(backup.toJson())).length;
    var uploads = 0;
    var downloads = 0;
    var exists = false;
    final sync = build(
      MockClient((request) async {
        if (request.url.path.startsWith('/upload/')) {
          uploads++;
          exists = true;
          return _json({'id': 'remote'});
        }
        if (request.url.path.endsWith('/remote')) {
          downloads++;
          return _json(backup.toJson());
        }
        return _json({
          'files': exists
              ? [
                  {'id': 'remote'},
                ]
              : [],
        });
      }),
      // Keep generatedAt fixed for the exact byte boundary on both runs.
      store: _FixedStore(database, backup),
      maxBytes: byteCount,
    );
    await sync.sync();
    await sync.sync();
    expect(uploads, 2);
    expect(downloads, 1);
    expect(sync.state, GoogleDriveSyncState.success);
  });

  test(
    'a merged backup exceeding the cap does not replace the Drive file',
    () async {
      final local = await repository.createCharacter('L' * 100);
      final remoteCharacter = _character('remote', 'R' * 100);
      final remote = ArchiveSyncData(
        generatedAt: DateTime.now().toUtc(),
        characters: [remoteCharacter],
      );
      final localBytes = utf8
          .encode(
            jsonEncode((await LocalArchiveSyncStore(database).read()).toJson()),
          )
          .length;
      final remoteBytes = utf8.encode(jsonEncode(remote.toJson())).length;
      var uploads = 0;
      final sync = build(
        MockClient((request) async {
          if (request.url.path.startsWith('/upload/')) {
            uploads++;
            return _json({'id': 'remote'});
          }
          if (request.url.path.endsWith('/remote')) {
            return _json(remote.toJson());
          }
          return _json({
            'files': [
              {'id': 'remote'},
            ],
          });
        }),
        maxBytes: localBytes > remoteBytes ? localBytes : remoteBytes,
      );
      await expectLater(sync.sync(), throwsFormatException);
      expect(uploads, 0);
      expect(tracker.hasPendingChanges, isTrue);
      expect(await repository.getCharacter(local.id), isNotNull);
      expect(await repository.getCharacter(remoteCharacter.id), isNotNull);
    },
  );

  test(
    'an oversized download is rejected without replacing local data',
    () async {
      final local = await repository.createCharacter('Minsc');
      final remote = ArchiveSyncData(
        generatedAt: DateTime.now().toUtc(),
        characters: [_character('remote', 'R' * 1000)],
      );
      var uploads = 0;
      final sync = build(
        MockClient((request) async {
          if (request.url.path.startsWith('/upload/')) uploads++;
          if (request.url.path.endsWith('/remote')) {
            return _json(remote.toJson());
          }
          return _json({
            'files': [
              {'id': 'remote'},
            ],
          });
        }),
        maxBytes: 500,
      );
      await expectLater(sync.sync(), throwsFormatException);
      expect(uploads, 0);
      expect(await repository.getCharacter(local.id), isNotNull);
      expect(await repository.getCharacter('remote'), isNull);
      expect(tracker.hasPendingChanges, isTrue);
    },
  );

  test(
    'a timed-out download cannot merge deletions after a successful retry',
    () async {
      final local = await repository.createCharacter('Minsc');
      final firstList = Completer<http.Response>();
      final lateDownload = Completer<void>();
      var lists = 0;
      var uploads = 0;
      final staleRemote = ArchiveSyncData(
        generatedAt: DateTime.now().toUtc(),
        deletions: {
          local.id: DateTime.now().toUtc().add(const Duration(minutes: 1)),
        },
      );
      final sync = build(
        MockClient((request) async {
          if (request.url.path.startsWith('/upload/')) {
            uploads++;
            return _json({'id': 'new'});
          }
          if (request.url.path.endsWith('/remote')) {
            lateDownload.complete();
            return _json(staleRemote.toJson());
          }
          lists++;
          return lists == 1 ? firstList.future : _json({'files': []});
        }),
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(sync.sync(), throwsA(isA<TimeoutException>()));
      expect(sync.state, GoogleDriveSyncState.error);
      expect(tracker.hasPendingChanges, isTrue);
      await sync.sync();
      firstList.complete(
        _json({
          'files': [
            {'id': 'remote'},
          ],
        }),
      );
      await lateDownload.future;
      // Let the abandoned download finish decoding and reach the token guard.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(uploads, 1);
      expect(await repository.getCharacter(local.id), isNotNull);
      expect(sync.state, GoogleDriveSyncState.success);
      expect(tracker.hasPendingChanges, isFalse);
    },
  );
  test(
    'desktop consent timeout releases syncing and permits another login',
    () => HttpOverrides.runZoned(() async {
      final directory = await Directory.systemTemp.createTemp(
        'drive-consent-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      var browsers = 0;
      final auth = DesktopGoogleAuth(
        clientId: 'test',
        clientSecret: 'test',
        scopes: const ['scope-a'],
        supportDirectory: () async => directory,
        consentTimeout: const Duration(milliseconds: 100),
        openBrowser: (url) async {
          browsers++;
          if (browsers == 1) return;
          final authorization = Uri.parse(url);
          final redirect = Uri.parse(
            authorization.queryParameters['redirect_uri']!,
          );
          final client = HttpClient();
          try {
            final request = await client.getUrl(
              redirect.replace(
                queryParameters: {
                  'state': authorization.queryParameters['state']!,
                  'error': 'access_denied',
                },
              ),
            );
            await (await request.close()).drain<void>();
          } finally {
            client.close(force: true);
          }
        },
      );
      final sync = service = GoogleDriveSyncService(
        LocalArchiveSyncStore(database),
        syncTracker: tracker,
        desktopAuth: auth,
      );
      await expectLater(
        sync.sync(),
        throwsA(isA<DesktopGoogleAuthException>()),
      );
      expect(sync.state, GoogleDriveSyncState.error);
      expect(sync.errorMessage, contains('scaduto'));
      await expectLater(sync.sync(), throwsA(isA<GoogleDriveSignInRequired>()));
      expect(sync.state, GoogleDriveSyncState.needsSignIn);
      expect(browsers, 2);
    }, createHttpClient: _RealHttpOverrides().createHttpClient),
  );
}

http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Character _character(String id, String name) => Character(
  id: id,
  name: name,
  createdAt: DateTime.utc(2026, 9, 29),
  updatedAt: DateTime.utc(2026, 9, 29),
  locked: false,
);

class _TestAuth extends DesktopGoogleAuth {
  _TestAuth(this.client)
    : super(clientId: 'test', clientSecret: 'test', scopes: []);
  final http.Client client;

  @override
  bool get isConfigured => true;

  @override
  bool get isConnected => false;

  @override
  Future<void> restore() async {}

  @override
  Future<http.Client> authenticatedClient() async => client;

  @override
  void dispose() => client.close();
}

// Allow only the loopback OAuth flow in this test to use real sockets.
class _RealHttpOverrides extends HttpOverrides {}

class _FixedStore extends LocalArchiveSyncStore {
  _FixedStore(super.database, this.backup);
  final ArchiveSyncData backup;

  @override
  Future<ArchiveSyncData> read() async => backup;

  @override
  Future<ArchiveSyncData> mergeAndReplace(
    ArchiveSyncData remote, {
    void Function()? beforeReplace,
  }) async {
    beforeReplace?.call();
    return backup;
  }
}
