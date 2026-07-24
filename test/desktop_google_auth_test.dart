import 'dart:convert';
import 'dart:io';

import 'package:dnd_sheet_archive/sync/desktop_google_auth_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  DesktopGoogleAuth? auth;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('desktop_auth_test');
  });

  tearDown(() async {
    auth?.dispose();
    auth = null;
    await tempDir.delete(recursive: true);
  });

  DesktopGoogleAuth buildAuth() => auth = DesktopGoogleAuth(
    clientId: 'client-id',
    clientSecret: 'client-secret',
    scopes: const ['scope-a'],
    supportDirectory: () async => tempDir,
  );

  File credentialsFile() =>
      File('${tempDir.path}/google_drive_credentials.json');

  Map<String, dynamic> credentialsJson({
    List<String> scopes = const ['scope-a'],
    bool withRefreshToken = true,
  }) => {
    'accessToken': {
      'type': 'Bearer',
      'data': 'access-token',
      'expiry': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String(),
    },
    if (withRefreshToken) 'refreshToken': 'refresh-token',
    'scopes': scopes,
  };

  test('restore ricrea il client dalle credenziali salvate', () async {
    credentialsFile().writeAsStringSync(jsonEncode(credentialsJson()));
    final auth = buildAuth();

    await auth.restore();

    expect(auth.isConnected, isTrue);
    expect(credentialsFile().existsSync(), isTrue);
  });

  test('restore senza credenziali salvate resta disconnesso', () async {
    final auth = buildAuth();

    await auth.restore();

    expect(auth.isConnected, isFalse);
  });

  test('restore scarta un file di credenziali corrotto', () async {
    credentialsFile().writeAsStringSync('non è json');
    final auth = buildAuth();

    await auth.restore();

    expect(auth.isConnected, isFalse);
    expect(credentialsFile().existsSync(), isFalse);
  });

  test('restore scarta credenziali senza refresh token', () async {
    credentialsFile().writeAsStringSync(
      jsonEncode(credentialsJson(withRefreshToken: false)),
    );
    final auth = buildAuth();

    await auth.restore();

    expect(auth.isConnected, isFalse);
    expect(credentialsFile().existsSync(), isFalse);
  });

  test('restore scarta credenziali con scope insufficienti', () async {
    credentialsFile().writeAsStringSync(
      jsonEncode(credentialsJson(scopes: const ['scope-b'])),
    );
    final auth = buildAuth();

    await auth.restore();

    expect(auth.isConnected, isFalse);
    expect(credentialsFile().existsSync(), isFalse);
  });

  test('signOut elimina le credenziali salvate', () async {
    credentialsFile().writeAsStringSync(jsonEncode(credentialsJson()));
    final auth = buildAuth();
    await auth.restore();
    expect(auth.isConnected, isTrue);

    await auth.signOut();

    expect(auth.isConnected, isFalse);
    expect(credentialsFile().existsSync(), isFalse);
  });
}
