import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

class ArchiveSyncTracker extends ChangeNotifier {
  ArchiveSyncTracker.inMemory({bool hasPendingChanges = false})
    : _database = null,
      _revision = hasPendingChanges ? 1 : 0,
      _syncedRevision = 0;

  ArchiveSyncTracker._(this._database, this._revision, this._syncedRevision);

  static final _metadata = stringMapStoreFactory.store('sync_metadata');
  static final _characters = stringMapStoreFactory.store('characters');
  static final _versions = stringMapStoreFactory.store('versions');
  static final _tombstones = stringMapStoreFactory.store('sync_tombstones');
  static const _statusKey = 'status';

  final Database? _database;
  int _revision;
  int _syncedRevision;
  Future<void> _writeTail = Future<void>.value();

  int get revision => _revision;
  bool get hasPendingChanges => _revision > _syncedRevision;

  static Future<ArchiveSyncTracker> open(Database database) async {
    final saved = await _metadata.record(_statusKey).get(database);
    final revision = saved?['revision'];
    final syncedRevision = saved?['syncedRevision'];
    if (revision is int && syncedRevision is int) {
      return ArchiveSyncTracker._(
        database,
        revision,
        syncedRevision.clamp(0, revision),
      );
    }

    final hasExistingData =
        await _characters.count(database) > 0 ||
        await _versions.count(database) > 0 ||
        await _tombstones.count(database) > 0;
    final tracker = ArchiveSyncTracker._(database, hasExistingData ? 1 : 0, 0);
    await tracker._persist();
    return tracker;
  }

  Future<void> markChanged() async {
    final wasPending = hasPendingChanges;
    _revision++;
    if (!wasPending) notifyListeners();
    await _persist();
  }

  Future<void> markSyncedThrough(int revision) async {
    final boundedRevision = revision.clamp(0, _revision);
    if (boundedRevision <= _syncedRevision) return;
    final wasPending = hasPendingChanges;
    _syncedRevision = boundedRevision;
    if (wasPending != hasPendingChanges) notifyListeners();
    await _persist();
  }

  Future<void> _persist() {
    final database = _database;
    if (database == null) return Future<void>.value();
    final revision = _revision;
    final syncedRevision = _syncedRevision;
    _writeTail = _writeTail.then(
      (_) => _writeSnapshot(database, revision, syncedRevision),
      onError: (_) => _writeSnapshot(database, revision, syncedRevision),
    );
    return _writeTail;
  }

  static Future<void> _writeSnapshot(
    Database database,
    int revision,
    int syncedRevision,
  ) => _metadata.record(_statusKey).put(database, {
    'revision': revision,
    'syncedRevision': syncedRevision,
  });
}
