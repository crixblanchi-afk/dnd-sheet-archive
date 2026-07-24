import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DesktopGoogleAuthCanceled implements Exception {
  const DesktopGoogleAuthCanceled();
}

class DesktopGoogleAuthException implements Exception {
  const DesktopGoogleAuthException(this.message);

  final String message;
}

class DesktopGoogleAuth {
  DesktopGoogleAuth({
    required this.clientId,
    required String clientSecret,
    required this.scopes,
    Future<Directory> Function() supportDirectory =
        getApplicationSupportDirectory,
  }) : clientSecret = clientSecret.isNotEmpty
           ? clientSecret
           : Platform.environment['GOOGLE_DESKTOP_CLIENT_SECRET'] ?? '',
       _supportDirectory = supportDirectory;

  static const _credentialsFileName = 'google_drive_credentials.json';

  final String clientId;
  final String clientSecret;
  final List<String> scopes;
  final Future<Directory> Function() _supportDirectory;
  auth.AutoRefreshingAuthClient? _client;
  http.Client? _restoredBaseClient;
  StreamSubscription<auth.AccessCredentials>? _credentialUpdates;

  bool get isConfigured => clientId.isNotEmpty && clientSecret.isNotEmpty;
  bool get isConnected => _client != null;
  bool get _isSupportedDesktop => Platform.isLinux || Platform.isWindows;

  /// Ricrea il client dalle credenziali salvate su disco, senza interazione.
  ///
  /// Se le credenziali salvate sono illeggibili o non coprono più gli scope
  /// richiesti vengono scartate: servirà un nuovo consenso interattivo.
  Future<void> restore() async {
    if (_client != null || !_isSupportedDesktop || !isConfigured) return;
    try {
      final file = await _credentialsFile();
      if (!file.existsSync()) return;
      final decoded = jsonDecode(await file.readAsString());
      final credentials = auth.AccessCredentials.fromJson(
        (decoded as Map).cast<String, dynamic>(),
      );
      if (credentials.refreshToken == null ||
          !scopes.every(credentials.scopes.contains)) {
        throw const FormatException('Credenziali salvate non utilizzabili.');
      }
      final baseClient = http.Client();
      try {
        final client = auth.autoRefreshingClient(
          auth.ClientId(clientId, clientSecret),
          credentials,
          baseClient,
        );
        _restoredBaseClient = baseClient;
        _adopt(client);
      } catch (_) {
        baseClient.close();
        rethrow;
      }
    } catch (_) {
      await _deleteStoredCredentials();
    }
  }

  Future<http.Client> authenticatedClient() async {
    final existing = _client;
    if (existing != null) return existing;
    if (!_isSupportedDesktop) {
      throw UnsupportedError(
        'OAuth desktop è supportato soltanto su Linux e Windows.',
      );
    }
    if (!isConfigured) {
      throw const DesktopGoogleAuthException(
        'Manca il client secret OAuth Desktop.',
      );
    }
    await restore();
    final restored = _client;
    if (restored != null) return restored;

    try {
      final client = await auth.clientViaUserConsent(
        auth.ClientId(clientId, clientSecret),
        scopes,
        _openBrowser,
        customPostAuthPage: _successPage,
      );
      _adopt(client);
      await _saveCredentials(client.credentials);
      return client;
    } on auth.UserConsentException {
      throw const DesktopGoogleAuthCanceled();
    } on DesktopGoogleAuthException {
      rethrow;
    } catch (error) {
      throw DesktopGoogleAuthException(
        'Accesso OAuth desktop non riuscito: $error',
      );
    }
  }

  void _adopt(auth.AutoRefreshingAuthClient client) {
    _client = client;
    _credentialUpdates = client.credentialUpdates.listen(
      (credentials) => unawaited(_saveCredentials(credentials)),
    );
  }

  Future<File> _credentialsFile() async {
    final directory = await _supportDirectory();
    return File(p.join(directory.path, _credentialsFileName));
  }

  Future<void> _saveCredentials(auth.AccessCredentials credentials) async {
    if (credentials.refreshToken == null) return;
    try {
      final file = await _credentialsFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(credentials.toJson()), flush: true);
      // Il refresh token dà pieno accesso all'appDataFolder: va tenuto
      // leggibile soltanto dall'utente.
      if (Platform.isLinux) {
        await Process.run('chmod', ['600', file.path]);
      }
    } catch (_) {
      // Senza persistenza il sync resta comunque attivo in questa sessione.
    }
  }

  Future<void> _deleteStoredCredentials() async {
    try {
      final file = await _credentialsFile();
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Un file orfano verrà scartato dal prossimo restore().
    }
  }

  void _openBrowser(String authorizationUrl) {
    final result = Platform.isWindows
        ? Process.runSync('rundll32', [
            'url.dll,FileProtocolHandler',
            authorizationUrl,
          ])
        : Process.runSync('xdg-open', [authorizationUrl]);
    if (result.exitCode != 0) {
      throw DesktopGoogleAuthException(
        'Impossibile aprire il browser predefinito (${result.stderr}).',
      );
    }
  }

  Future<void> signOut() async {
    final client = _client;
    _client = null;
    await _credentialUpdates?.cancel();
    _credentialUpdates = null;
    await _deleteStoredCredentials();
    if (client == null) return;

    final token =
        client.credentials.refreshToken ?? client.credentials.accessToken.data;
    final revokeClient = http.Client();
    try {
      try {
        await revokeClient.post(
          Uri.https('oauth2.googleapis.com', '/revoke'),
          headers: const {'content-type': 'application/x-www-form-urlencoded'},
          body: {'token': token},
        );
      } catch (_) {
        // Signing out locally must still succeed when Google is unreachable.
      }
    } finally {
      revokeClient.close();
      client.close();
      _restoredBaseClient?.close();
      _restoredBaseClient = null;
    }
  }

  void dispose() {
    unawaited(_credentialUpdates?.cancel());
    _credentialUpdates = null;
    _client?.close();
    _client = null;
    _restoredBaseClient?.close();
    _restoredBaseClient = null;
  }

  static const _successPage = '''
<!doctype html>
<html lang="it">
  <head><meta charset="utf-8"><title>Accesso completato</title></head>
  <body style="font-family: sans-serif; text-align: center; padding: 3rem">
    <h2>Accesso a Google Drive completato</h2>
    <p>Puoi chiudere questa scheda e tornare all'applicazione.</p>
  </body>
</html>
''';
}
