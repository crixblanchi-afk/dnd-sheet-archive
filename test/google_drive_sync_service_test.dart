import 'package:dnd_sheet_archive/data/local_archive_sync_store.dart';
import 'package:dnd_sheet_archive/sync/archive_sync_tracker.dart';
import 'package:dnd_sheet_archive/sync/google_drive_sync_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

class _RecordingSyncService extends GoogleDriveSyncService {
  _RecordingSyncService(super.localStore, {super.syncTracker});

  int syncRequests = 0;

  @override
  Future<bool> syncInBackground() async {
    syncRequests++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('le modifiche in sospeso da una sessione precedente '
      'partono all\'avvio', () async {
    final database = await databaseFactoryMemory.openDatabase('startup.db');
    fakeAsync((async) {
      final service = _RecordingSyncService(
        LocalArchiveSyncStore(database),
        syncTracker: ArchiveSyncTracker.inMemory(hasPendingChanges: true),
      );
      async.flushMicrotasks();

      expect(service.syncRequests, 1);

      service.dispose();
    });
    await database.close();
  });

  test('il sync periodico gira ogni 5 minuti', () async {
    final database = await databaseFactoryMemory.openDatabase('periodic.db');
    fakeAsync((async) {
      final service = _RecordingSyncService(
        LocalArchiveSyncStore(database),
        syncTracker: ArchiveSyncTracker.inMemory(),
      );
      async.flushMicrotasks();
      final startupRequests = service.syncRequests;

      async.elapse(const Duration(minutes: 4, seconds: 59));
      expect(service.syncRequests, startupRequests);

      async.elapse(const Duration(minutes: 5, seconds: 1));
      expect(service.syncRequests, startupRequests + 2);

      service.dispose();
    });
    await database.close();
  });

  test('l\'app che va in background fa partire il sync', () async {
    final database = await databaseFactoryMemory.openDatabase('pause.db');
    fakeAsync((async) {
      final service = _RecordingSyncService(
        LocalArchiveSyncStore(database),
        syncTracker: ArchiveSyncTracker.inMemory(hasPendingChanges: true),
      );
      async.flushMicrotasks();
      final startupRequests = service.syncRequests;

      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      async.flushMicrotasks();
      expect(service.syncRequests, startupRequests + 1);

      // Le transizioni che non congelano l'app non fanno partire il sync.
      service.didChangeAppLifecycleState(AppLifecycleState.inactive);
      async.flushMicrotasks();
      expect(service.syncRequests, startupRequests + 1);

      // Al ritorno in primo piano arrivano le modifiche fatte altrove.
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      async.flushMicrotasks();
      expect(service.syncRequests, startupRequests + 2);

      service.dispose();
    });
    await database.close();
  });

  test('in background il sync periodico si ferma e '
      'hidden seguito da paused sincronizza una volta', () async {
    final database = await databaseFactoryMemory.openDatabase('idle.db');
    fakeAsync((async) {
      final service = _RecordingSyncService(
        LocalArchiveSyncStore(database),
        syncTracker: ArchiveSyncTracker.inMemory(),
      );
      async.flushMicrotasks();
      final startupRequests = service.syncRequests;

      service.didChangeAppLifecycleState(AppLifecycleState.hidden);
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      async.flushMicrotasks();
      expect(service.syncRequests, startupRequests + 1);

      async.elapse(const Duration(minutes: 20));
      expect(service.syncRequests, startupRequests + 1);

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      async.flushMicrotasks();
      expect(service.syncRequests, startupRequests + 2);

      async.elapse(const Duration(minutes: 5));
      expect(service.syncRequests, startupRequests + 3);

      service.dispose();
    });
    await database.close();
  });

  test('un servizio creato con l\'app già in background '
      'non fa partire il sync periodico', () async {
    final database = await databaseFactoryMemory.openDatabase('late.db');
    final binding = WidgetsBinding.instance;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    addTearDown(() {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    fakeAsync((async) {
      final service = _RecordingSyncService(
        LocalArchiveSyncStore(database),
        syncTracker: ArchiveSyncTracker.inMemory(),
      );
      async.flushMicrotasks();
      final startupRequests = service.syncRequests;

      async.elapse(const Duration(minutes: 20));
      expect(service.syncRequests, startupRequests);

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      async.flushMicrotasks();
      expect(service.syncRequests, startupRequests + 1);

      service.dispose();
    });
    await database.close();
  });
}
