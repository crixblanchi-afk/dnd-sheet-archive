import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

/// Dove vive il refresh token del consenso Google su desktop.
///
/// Quel token dà accesso permanente all'`appDataFolder` dell'app: va tenuto
/// fuori dalla portata degli altri processi dell'utente quanto la piattaforma
/// permette.
abstract class DesktopCredentialStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// Il portachiavi del sistema: libsecret su Linux, Credential Manager su
/// Windows.
class KeyringCredentialStore implements DesktopCredentialStore {
  const KeyringCredentialStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _key = 'google_drive_credentials';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Il file nella cartella di supporto, leggibile dal solo proprietario.
///
/// È la riserva per i sistemi senza un servizio di portachiavi — una sessione
/// Linux minimale, un container — dove altrimenti il sync non sopravvivrebbe
/// alla chiusura dell'app.
class FileCredentialStore implements DesktopCredentialStore {
  FileCredentialStore(this.supportDirectory);

  static const fileName = 'google_drive_credentials.json';

  final Future<Directory> Function() supportDirectory;

  Future<File> _file() async =>
      File(p.join((await supportDirectory()).path, fileName));

  @override
  Future<String?> read() async {
    final file = await _file();
    return file.existsSync() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String value) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    // Restringere prima la directory chiude la finestra in cui il file appena
    // scritto è ancora leggibile da tutti secondo la umask. Su Windows la ACL
    // per utente di %APPDATA% copre già lo stesso scopo.
    await _restrictToOwner(file.parent.path, '700');
    await file.writeAsString(value, flush: true);
    await _restrictToOwner(file.path, '600');
  }

  @override
  Future<void> delete() async {
    final file = await _file();
    if (file.existsSync()) await file.delete();
  }

  static Future<void> _restrictToOwner(String path, String mode) async {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    final result = await Process.run(_chmod, [mode, path]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Impossibile restringere i permessi (${result.stderr}).',
        path,
      );
    }
  }

  /// Il percorso assoluto evita di dipendere dal `PATH` dell'ambiente per
  /// un'operazione che serve proprio a proteggere un segreto.
  static final _chmod = const [
    '/usr/bin/chmod',
    '/bin/chmod',
  ].firstWhere((path) => File(path).existsSync(), orElse: () => 'chmod');
}

/// Il portachiavi del sistema quando c'è, il file quando non c'è.
///
/// Un token lasciato sul disco da una versione precedente viene spostato nel
/// portachiavi alla prima lettura riuscita: la riserva non resta in chiaro
/// quando non serve più.
class SystemDesktopCredentialStore implements DesktopCredentialStore {
  SystemDesktopCredentialStore({required this.keyring, required this.file});

  final DesktopCredentialStore keyring;
  final DesktopCredentialStore file;

  @override
  Future<String?> read() async {
    try {
      final stored = await keyring.read();
      if (stored != null) {
        await file.delete();
        return stored;
      }
      final onDisk = await file.read();
      if (onDisk != null) {
        await keyring.write(onDisk);
        await file.delete();
      }
      return onDisk;
    } catch (_) {
      // Nessun servizio di portachiavi raggiungibile: resta il file.
      return file.read();
    }
  }

  @override
  Future<void> write(String value) async {
    try {
      await keyring.write(value);
      await file.delete();
    } catch (_) {
      await file.write(value);
    }
  }

  @override
  Future<void> delete() async {
    try {
      await keyring.delete();
    } catch (_) {
      // Quel che conta, se il portachiavi non risponde, è che il file sparisca.
    }
    await file.delete();
  }
}
