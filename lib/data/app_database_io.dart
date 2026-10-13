import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

import 'app_database_errors.dart';

const _databaseFileName = 'dnd_sheet_archive.db';
const _lockFileName = 'dnd_sheet_archive.lock';

Future<Database> openAppDatabase() async {
  if (Platform.isLinux || Platform.isWindows) {
    return openDesktopDatabase(
      directory: await getApplicationSupportDirectory(),
      legacyDirectory: await getApplicationDocumentsDirectory(),
    );
  }
  // Su Android le regole di backup escludono proprio questa directory
  // (`app_flutter/`): spostare l'archivio le renderebbe inefficaci.
  final directory = await getApplicationDocumentsDirectory();
  await directory.create(recursive: true);
  return databaseFactoryIo.openDatabase(
    p.join(directory.path, _databaseFileName),
  );
}

/// Apre l'archivio desktop nella cartella dei dati dell'app.
///
/// Le versioni precedenti lo tenevano in [legacyDirectory], la cartella
/// Documenti: in vista dell'utente e, su Windows, spesso sincronizzata da
/// OneDrive, che può copiare o bloccare il file mentre sembast ci aggiunge
/// righe. Al primo avvio il file viene spostato.
///
/// sembast scrive in coda allo stesso file senza coordinarsi con altri
/// processi: due istanze aperte insieme si sovrascriverebbero i record a
/// vicenda. Un lock esclusivo, tenuto per tutta la vita del processo, fa
/// fallire la seconda con [ArchiveAlreadyOpenException].
Future<Database> openDesktopDatabase({
  required Directory directory,
  required Directory legacyDirectory,
  DatabaseFactory? factory,
}) async {
  await directory.create(recursive: true);
  final lockPath = await _lockArchive(directory);
  try {
    final path = p.join(directory.path, _databaseFileName);
    await _moveLegacyArchive(
      File(p.join(legacyDirectory.path, _databaseFileName)),
      File(path),
    );
    return await (factory ?? databaseFactoryIo).openDatabase(path);
  } catch (_) {
    // Un'apertura fallita non deve lasciare il lock a questo processo:
    // «Riprova» lo scambierebbe per un'altra istanza dell'app.
    await _releaseLock(lockPath);
    rethrow;
  }
}

/// I lock tenuti da questo processo, per percorso.
///
/// I lock POSIX valgono per processo: una seconda apertura dallo stesso
/// processo li otterrebbe di nuovo senza errori, quindi va riconosciuta qui.
final _heldLocks = <String, RandomAccessFile>{};

/// Prende il lock dell'archivio e restituisce il percorso del file di lock.
Future<String> _lockArchive(Directory directory) async {
  final path = p.join(directory.path, _lockFileName);
  if (_heldLocks.containsKey(path)) throw const ArchiveAlreadyOpenException();
  final file = await File(path).open(mode: FileMode.append);
  try {
    await file.lock(FileLock.exclusive);
  } on FileSystemException {
    await file.close();
    throw const ArchiveAlreadyOpenException();
  }
  _heldLocks[path] = file;
  return path;
}

Future<void> _releaseLock(String path) async {
  final file = _heldLocks.remove(path);
  if (file == null) return;
  await file.unlock();
  await file.close();
}

@visibleForTesting
Future<void> releaseDesktopArchiveLocks() async {
  for (final path in _heldLocks.keys.toList()) {
    await _releaseLock(path);
  }
}

Future<void> _moveLegacyArchive(File legacy, File target) async {
  if (await target.exists() || !await legacy.exists()) return;
  try {
    await legacy.rename(target.path);
  } on FileSystemException {
    // Cartelle su dischi diversi: si copia accanto alla destinazione e si
    // rinomina lì, così un'interruzione non lascia mai un archivio a metà.
    final partial = File('${target.path}.partial');
    await legacy.copy(partial.path);
    await partial.rename(target.path);
    await legacy.delete();
  }
}
