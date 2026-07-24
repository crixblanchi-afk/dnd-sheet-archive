import 'package:dnd_sheet_archive/sync/archive_sync_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('changes made during a sync stay pending', () async {
    final tracker = ArchiveSyncTracker.inMemory();
    await tracker.markChanged();
    final syncingRevision = tracker.revision;

    await tracker.markChanged();
    await tracker.markSyncedThrough(syncingRevision);

    expect(tracker.hasPendingChanges, isTrue);
    await tracker.markSyncedThrough(tracker.revision);
    expect(tracker.hasPendingChanges, isFalse);
    tracker.dispose();
  });

  test('pending state survives application restarts', () async {
    final database = await databaseFactoryMemory.openDatabase('tracker.db');
    final tracker = await ArchiveSyncTracker.open(database);
    await tracker.markChanged();
    tracker.dispose();

    final reopened = await ArchiveSyncTracker.open(database);
    expect(reopened.hasPendingChanges, isTrue);
    await reopened.markSyncedThrough(reopened.revision);
    reopened.dispose();

    final synced = await ArchiveSyncTracker.open(database);
    expect(synced.hasPendingChanges, isFalse);
    synced.dispose();
    await database.close();
  });
}
