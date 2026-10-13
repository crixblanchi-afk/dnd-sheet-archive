import 'dart:io';

import 'package:dnd_sheet_archive/sync/desktop_credential_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore file;
  late _FakeKeyring keyring;
  late SystemDesktopCredentialStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('credential_store_test');
    file = FileCredentialStore(() async => tempDir);
    keyring = _FakeKeyring();
    store = SystemDesktopCredentialStore(keyring: keyring, file: file);
    addTearDown(() => tempDir.delete(recursive: true));
  });

  File credentialsFile() =>
      File('${tempDir.path}/${FileCredentialStore.fileName}');

  test('il token va nel portachiavi e non sul disco', () async {
    await store.write('token');

    expect(keyring.value, 'token');
    expect(credentialsFile().existsSync(), isFalse);
    expect(await store.read(), 'token');
  });

  test('un token lasciato sul disco viene migrato nel portachiavi', () async {
    await file.write('vecchio-token');
    expect(credentialsFile().existsSync(), isTrue);

    expect(await store.read(), 'vecchio-token');

    expect(keyring.value, 'vecchio-token');
    expect(credentialsFile().existsSync(), isFalse);
  });

  test(
    'senza portachiavi il token resta sul disco, solo per il proprietario',
    () async {
      keyring.available = false;

      await store.write('token');

      expect(await store.read(), 'token');
      expect(credentialsFile().existsSync(), isTrue);
      expect(_permissions(credentialsFile()), '600');
      expect(_permissions(tempDir), '700');
    },
  );

  test('la disconnessione ripulisce portachiavi e disco', () async {
    await file.write('sul-disco');
    keyring.value = 'nel-portachiavi';

    await store.delete();

    expect(keyring.value, isNull);
    expect(credentialsFile().existsSync(), isFalse);
    expect(await store.read(), isNull);
  });

  test('un portachiavi che sparisce non porta via le credenziali', () async {
    keyring.available = false;
    await store.write('token');
    keyring.available = true;

    // Il portachiavi è tornato ma è vuoto: la riserva sul disco resta valida e
    // viene promossa, invece di costringere a un nuovo consenso.
    expect(await store.read(), 'token');
    expect(keyring.value, 'token');
  });
}

String _permissions(FileSystemEntity entity) =>
    (entity.statSync().mode & 0x1ff).toRadixString(8);

class _FakeKeyring implements DesktopCredentialStore {
  String? value;
  bool available = true;

  @override
  Future<String?> read() async {
    if (!available) throw const _NoKeyring();
    return value;
  }

  @override
  Future<void> write(String value) async {
    if (!available) throw const _NoKeyring();
    this.value = value;
  }

  @override
  Future<void> delete() async {
    if (!available) throw const _NoKeyring();
    value = null;
  }
}

class _NoKeyring implements Exception {
  const _NoKeyring();
}
