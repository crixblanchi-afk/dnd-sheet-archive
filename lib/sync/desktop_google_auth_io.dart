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
  Future<void>? _restoreInProgress;
  Completer<auth.AutoRefreshingAuthClient>? _browserLaunch;

  bool get isConfigured => clientId.isNotEmpty && clientSecret.isNotEmpty;
  bool get isConnected => _client != null;
  bool get _isSupportedDesktop => Platform.isLinux || Platform.isWindows;

  /// Ricrea il client dalle credenziali salvate su disco, senza interazione.
  ///
  /// Se le credenziali salvate sono illeggibili o non coprono più gli scope
  /// richiesti vengono scartate: servirà un nuovo consenso interattivo.
  ///
  /// Le chiamate concorrenti condividono lo stesso tentativo: avvio del
  /// servizio e sincronizzazione manuale possono sovrapporsi, e due ripristini
  /// in parallelo lascerebbero un `http.Client` orfano.
  Future<void> restore() {
    final pending = _restoreInProgress;
    if (pending != null) return pending;
    final operation = _restore();
    _restoreInProgress = operation;
    return operation.whenComplete(() {
      if (identical(_restoreInProgress, operation)) _restoreInProgress = null;
    });
  }

  Future<void> _restore() async {
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
      final launch = Completer<auth.AutoRefreshingAuthClient>();
      _browserLaunch = launch;
      try {
        // Se il browser non parte, il consenso non arriverà mai: senza questa
        // corsa l'attesa resterebbe appesa a tempo indefinito.
        final client = await Future.any([
          auth.clientViaUserConsent(
            auth.ClientId(clientId, clientSecret),
            scopes,
            _openBrowser,
            customPostAuthPage: _successPage,
          ),
          launch.future,
        ]);
        _adopt(client);
        await _saveCredentials(client.credentials);
        return client;
      } finally {
        _browserLaunch = null;
      }
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
      // Il refresh token dà pieno accesso all'appDataFolder: va tenuto
      // leggibile soltanto dall'utente. Restringere prima la directory chiude
      // la finestra in cui il file appena scritto è ancora leggibile da tutti
      // secondo la umask. Su Windows la ACL per utente di %APPDATA% copre già
      // lo stesso scopo.
      await _restrictToOwner(file.parent.path, '700');
      await file.writeAsString(jsonEncode(credentials.toJson()), flush: true);
      await _restrictToOwner(file.path, '600');
    } catch (_) {
      // Un token che non si riesce a proteggere non va lasciato sul disco:
      // senza persistenza il sync resta comunque attivo in questa sessione.
      await _deleteStoredCredentials();
    }
  }

  Future<void> _restrictToOwner(String path, String mode) async {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    final result = await Process.run('chmod', [mode, path]);
    if (result.exitCode != 0) {
      throw DesktopGoogleAuthException(
        'Impossibile restringere i permessi di $path (${result.stderr}).',
      );
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
    final executable = Platform.isWindows ? 'rundll32' : 'xdg-open';
    final arguments = Platform.isWindows
        ? ['url.dll,FileProtocolHandler', authorizationUrl]
        : [authorizationUrl];
    // Avviare il browser può richiedere tempo e questa callback gira sul
    // thread della UI: l'esito viene raccolto in modo asincrono e, se il
    // lancio fallisce, interrompe l'attesa del consenso.
    unawaited(
      Process.run(executable, arguments).then(
        (result) {
          if (result.exitCode == 0) return;
          _failBrowserLaunch(
            'Impossibile aprire il browser predefinito (${result.stderr}).',
          );
        },
        onError: (Object error) => _failBrowserLaunch(
          'Impossibile aprire il browser predefinito ($error).',
        ),
      ),
    );
  }

  void _failBrowserLaunch(String message) {
    final launch = _browserLaunch;
    if (launch == null || launch.isCompleted) return;
    launch.completeError(DesktopGoogleAuthException(message));
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
