import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as gauth;
import 'package:http/http.dart' as http;

import '../data/local_archive_sync_store.dart';
import '../models/archive_sync_data.dart';
import 'archive_sync_tracker.dart';
import 'desktop_google_auth.dart';

enum GoogleDriveSyncState {
  idle,
  syncing,
  success,
  needsSignIn,
  configurationMissing,
  error,
}

class DriveSyncSummary {
  const DriveSyncSummary({
    required this.characters,
    required this.versions,
    required this.completedAt,
  });

  final int characters;
  final int versions;
  final DateTime completedAt;
}

class GoogleDriveSignInRequired implements Exception {
  const GoogleDriveSignInRequired();
}

class GoogleDriveConfigurationMissing implements Exception {
  const GoogleDriveConfigurationMissing();
}

class GoogleDriveSyncService extends ChangeNotifier
    with WidgetsBindingObserver {
  GoogleDriveSyncService(
    this._localStore, {
    ArchiveSyncTracker? syncTracker,
    this.automaticSyncInterval = const Duration(minutes: 5),
    this.maxBackupBytes = 20 * 1024 * 1024,
    this.syncTimeout = const Duration(minutes: 2),
    this.exitTimeout = const Duration(seconds: 10),
    DesktopGoogleAuth? desktopAuth,
  }) : assert(maxBackupBytes > 0),
       _providedDesktopAuth = desktopAuth,
       _syncTracker = syncTracker ?? ArchiveSyncTracker.inMemory(),
       _ownsSyncTracker = syncTracker == null {
    _syncTracker.addListener(_localChangesChanged);
    _initialization = _initialize();
    _automaticSyncTimer = Timer.periodic(automaticSyncInterval, (_) {
      // In background nessuno guarda la scheda: svegliare la radio ogni cinque
      // minuti costa batteria senza mostrare niente, e al ritorno in primo
      // piano il sync parte comunque.
      if (!_inBackground) unawaited(syncInBackground());
    });
    // Modifiche rimaste in sospeso dalla sessione precedente, e quelle fatte
    // altrove mentre l'app era chiusa.
    _initialization.whenComplete(() => unawaited(syncInBackground()));
    // L'app può essere finita in background mentre l'avvio apriva l'archivio:
    // quella transizione è già passata e l'observer non la riceverà.
    _inBackground = switch (WidgetsBinding.instance.lifecycleState) {
      AppLifecycleState.hidden || AppLifecycleState.paused => true,
      _ => false,
    };
    WidgetsBinding.instance.addObserver(this);
  }

  static const _fileName = 'dnd-sheet-archive-sync-v1.json';
  static const _mimeType = 'application/json';
  static const _scopes = <String>[drive.DriveApi.driveAppdataScope];
  static const _webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const _androidServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
  static const _desktopClientId = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_ID',
  );
  static const _desktopClientSecret = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_SECRET',
  );
  final LocalArchiveSyncStore _localStore;
  final ArchiveSyncTracker _syncTracker;
  final bool _ownsSyncTracker;
  final Duration automaticSyncInterval;

  /// Lo stesso tetto vale per upload e download, inclusi i byte UTF-8.
  final int maxBackupBytes;
  final Duration syncTimeout;

  /// Quanto la chiusura dell'app desktop aspetta ciascuno dei lavori in
  /// sospeso — i salvataggi delle schede aperte, poi il sync.
  final Duration exitTimeout;
  final DesktopGoogleAuth? _providedDesktopAuth;
  late final GoogleSignIn _signIn = GoogleSignIn.instance;
  late final DesktopGoogleAuth _desktopAuth =
      _providedDesktopAuth ??
      DesktopGoogleAuth(
        clientId: _desktopClientId,
        clientSecret: _desktopClientSecret,
        scopes: _scopes,
      );
  late final Future<void> _initialization;
  late final Timer _automaticSyncTimer;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;
  GoogleSignInAccount? _currentUser;
  bool _signInInitialized = false;
  bool _hasAuthorization = false;
  String? _accessToken;
  GoogleDriveSyncState _state = GoogleDriveSyncState.idle;
  DateTime? _lastSyncAt;
  String? _errorMessage;
  Object? _activeSync;
  Future<void>? _runningSync;
  bool _disposed = false;

  /// Vero tra l'uscita dal primo piano (`hidden` o `paused`) e il ritorno.
  bool _inBackground = false;

  /// I backup su Drive, con le loro versioni, dopo l'ultimo sync riuscito.
  ///
  /// Il sync in background li confronta con quelli attuali per sapere, con
  /// una sola richiesta leggera, se un altro dispositivo ha caricato qualcosa.
  String? _lastSeenRemoteFiles;
  final List<Future<void> Function()> _exitTasks = [];

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  GoogleDriveSyncState get state => _state;
  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isConnected => _isDesktop
      ? _desktopAuth.isConnected
      : _currentUser != null || _hasAuthorization;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get errorMessage => _errorMessage;
  bool get hasPendingChanges => _syncTracker.hasPendingChanges;
  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows);
  bool get isConfigured {
    if (kIsWeb) return _webClientId.isNotEmpty;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => _androidServerClientId.isNotEmpty,
      TargetPlatform.linux => _desktopAuth.isConfigured,
      TargetPlatform.windows => _desktopAuth.isConfigured,
      _ => false,
    };
  }

  Future<void> _initialize() async {
    if (!isConfigured) {
      _state = GoogleDriveSyncState.configurationMissing;
      _errorMessage = 'Google Drive non è ancora configurato per questa build.';
      notifyListeners();
      return;
    }
    if (_isDesktop) {
      await _desktopAuth.restore();
      if (_desktopAuth.isConnected) notifyListeners();
      return;
    }
    try {
      await _signIn.initialize(
        clientId: kIsWeb ? _webClientId : null,
        serverClientId: kIsWeb ? null : _androidServerClientId,
      );
      _signInInitialized = true;
      _authSubscription = _signIn.authenticationEvents.listen(
        _handleAuthenticationEvent,
        onError: _handleAuthenticationError,
      );
      // On web this may display FedCM UI during startup. Authorization is
      // requested explicitly by the sync button instead, avoiding duplicate
      // account prompts before the user asks to use Drive.
      if (!kIsWeb) {
        final lightweight = _signIn.attemptLightweightAuthentication();
        final account = await lightweight;
        if (account != null) {
          _currentUser = account;
          notifyListeners();
        }
      }
    } catch (error) {
      _state = GoogleDriveSyncState.error;
      _errorMessage = _friendlyError(error);
      notifyListeners();
    }
  }

  void _handleAuthenticationEvent(GoogleSignInAuthenticationEvent event) {
    _currentUser = switch (event) {
      GoogleSignInAuthenticationEventSignIn() => event.user,
      GoogleSignInAuthenticationEventSignOut() => null,
    };
    if (_state == GoogleDriveSyncState.needsSignIn) {
      _state = GoogleDriveSyncState.idle;
      _errorMessage = null;
    }
    notifyListeners();
  }

  void _handleAuthenticationError(Object error) {
    _currentUser = null;
    _state = GoogleDriveSyncState.error;
    _errorMessage = _friendlyError(error);
    notifyListeners();
  }

  void _localChangesChanged() {
    if (hasPendingChanges && _state == GoogleDriveSyncState.success) {
      _state = GoogleDriveSyncState.idle;
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // L'app sta per finire in background, dove Android congela i timer:
    // ultima occasione per spedire le modifiche in sospeso. Al ritorno, quel
    // che è cambiato altrove nel frattempo.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Andando in background si passa da `hidden` e poi da `paused`: un solo
      // sync basta, il secondo rifarebbe la stessa richiesta a Drive.
      if (_inBackground) return;
      _inBackground = true;
      unawaited(syncInBackground());
    } else if (state == AppLifecycleState.resumed) {
      _inBackground = false;
      // Su desktop si torna in primo piano a ogni cambio di finestra: basta un
      // controllo al minuto.
      final lastSyncAt = _lastSyncAt;
      if (lastSyncAt == null ||
          DateTime.now().toUtc().difference(lastSyncAt) >
              const Duration(minutes: 1)) {
        unawaited(syncInBackground());
      }
    }
  }

  /// Registra un lavoro da completare prima che l'app desktop si chiuda, come
  /// il salvataggio di una scheda aperta; restituisce la funzione che lo
  /// toglie.
  ///
  /// Vive qui perché deve precedere l'ultimo sync: i lavori girano in ordine
  /// di registrazione, poi il sync spedisce quel che hanno salvato.
  VoidCallback addExitTask(Future<void> Function() task) {
    _exitTasks.add(task);
    return () => _exitTasks.remove(task);
  }

  /// Chiudere la finestra su desktop termina il processo: senza aspettare,
  /// l'autosalvataggio di una scheda aperta e il sync delle ultime modifiche
  /// andrebbero persi.
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    for (final task in List.of(_exitTasks)) {
      try {
        await task().timeout(exitTimeout);
      } catch (_) {
        // L'uscita non va bloccata: quel che resta in sospeso partirà al
        // prossimo avvio.
      }
    }
    try {
      await _flushToDrive().timeout(exitTimeout);
    } catch (_) {
      // Come sopra: le modifiche restano in sospeso nell'archivio locale.
    }
    return AppExitResponse.exit;
  }

  Future<void> _flushToDrive() async {
    final running = _runningSync;
    if (running != null) await running;
    if (hasPendingChanges) await syncInBackground();
  }

  /// Sincronizza senza chiedere nulla all'utente, se c'è un account collegato.
  ///
  /// Gira anche senza modifiche locali, per ricevere quelle fatte su un altro
  /// dispositivo: se la versione del backup su Drive è quella dell'ultimo
  /// sync, si ferma dopo una sola richiesta leggera.
  Future<bool> syncInBackground() async {
    if (_disposed ||
        _state == GoogleDriveSyncState.syncing ||
        !isConfigured ||
        !isConnected) {
      return false;
    }
    try {
      await _sync(interactive: false, onlyIfChanged: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<DriveSyncSummary> sync({bool interactive = true}) =>
      _sync(interactive: interactive, onlyIfChanged: false);

  Future<DriveSyncSummary> _sync({
    required bool interactive,
    required bool onlyIfChanged,
  }) async {
    await _initialization;
    if (_disposed) throw StateError('Il servizio Drive è stato chiuso.');
    if (!isConfigured) {
      throw const GoogleDriveConfigurationMissing();
    }
    if (!_isDesktop && !_signInInitialized) {
      throw StateError(
        _errorMessage ?? 'Inizializzazione di Google Drive non riuscita.',
      );
    }
    if (_state == GoogleDriveSyncState.syncing) {
      throw StateError('Sincronizzazione già in corso.');
    }

    _state = GoogleDriveSyncState.syncing;
    _errorMessage = null;
    notifyListeners();
    final token = Object();
    _activeSync = token;
    final running = Completer<void>();
    _runningSync = running.future;
    try {
      if (_isDesktop) {
        try {
          if (!interactive && !_desktopAuth.isConnected) {
            throw const GoogleDriveSignInRequired();
          }
          final client = await _desktopAuth.authenticatedClient();
          return await _syncWithClient(
            client,
            token,
            onlyIfChanged: onlyIfChanged,
          ).timeout(syncTimeout);
        } on drive.DetailedApiRequestError catch (error) {
          if (_isAuthorizationFailure(error)) {
            await _desktopAuth.signOut();
            throw const GoogleDriveSignInRequired();
          }
          rethrow;
        } on gauth.ServerRequestFailedException catch (error) {
          // Google ha respinto il refresh token (es. accesso revocato): il
          // client in cache e le credenziali salvate sono inutilizzabili.
          // Gli errori transitori (5xx, rete) mantengono il client per il
          // tentativo successivo.
          if (error.statusCode == 400 || error.statusCode == 401) {
            await _desktopAuth.signOut();
            throw const GoogleDriveSignInRequired();
          }
          rethrow;
        }
      }

      var user = _currentUser;
      if (user == null && interactive && _signIn.supportsAuthenticate()) {
        user = await _signIn.authenticate(scopeHint: _scopes);
        _currentUser = user;
      }
      if (user == null && !interactive && !_hasAuthorization) {
        throw const GoogleDriveSignInRequired();
      }

      // Web does not support authenticate() from a custom Flutter button. Its
      // authorization client can perform account selection and Drive consent
      // together in the single popup initiated by the sync action.
      final authorizationClient =
          user?.authorizationClient ?? _signIn.authorizationClient;
      final headers = await authorizationClient.authorizationHeaders(
        _scopes,
        promptIfNecessary: interactive,
      );
      if (headers == null) throw const GoogleDriveSignInRequired();
      final authorization = headers['Authorization'];
      const bearerPrefix = 'Bearer ';
      _accessToken =
          authorization != null && authorization.startsWith(bearerPrefix)
          ? authorization.substring(bearerPrefix.length)
          : null;
      _hasAuthorization = true;

      final client = _AuthorizedClient(http.Client(), headers);
      try {
        try {
          return await _syncWithClient(
            client,
            token,
            onlyIfChanged: onlyIfChanged,
          ).timeout(syncTimeout);
        } on drive.DetailedApiRequestError catch (error) {
          if (_isAuthorizationFailure(error)) {
            final accessToken = _accessToken;
            if (accessToken != null) {
              await authorizationClient.clearAuthorizationToken(
                accessToken: accessToken,
              );
            }
            _accessToken = null;
            _hasAuthorization = false;
          }
          rethrow;
        }
      } finally {
        client.close();
      }
    } on DesktopGoogleAuthCanceled {
      _state = GoogleDriveSyncState.needsSignIn;
      _errorMessage = 'Accesso Google annullato.';
      notifyListeners();
      throw const GoogleDriveSignInRequired();
    } on GoogleDriveSignInRequired {
      _state = GoogleDriveSyncState.needsSignIn;
      _errorMessage = 'Accedi con Google per sincronizzare le schede.';
      notifyListeners();
      rethrow;
    } catch (error) {
      _state = GoogleDriveSyncState.error;
      _errorMessage = _friendlyError(error);
      notifyListeners();
      rethrow;
    } finally {
      if (identical(_activeSync, token)) _activeSync = null;
      if (identical(_runningSync, running.future)) _runningSync = null;
      running.complete();
    }
  }

  /// Scarica e unisce tutti i backup su Drive, poi carica il risultato come
  /// file nuovo e cancella quelli che ha unito.
  ///
  /// Drive non offre scritture condizionate: sovrascrivere un file esistente,
  /// anche dopo averne ricontrollato la versione, lascerebbe sempre una
  /// finestra in cui due dispositivi scrivono uno sopra l'altro e le modifiche
  /// del primo spariscono. Così invece nessun backup viene mai sovrascritto:
  /// due sync concorrenti producono due file, e il merge — commutativo e
  /// idempotente — li riunisce al giro successivo. Cancellare un file già
  /// unito è sicuro, perché il suo contenuto è dentro quello appena caricato.
  Future<DriveSyncSummary> _syncWithClient(
    http.Client client,
    Object token, {
    required bool onlyIfChanged,
  }) async {
    final api = drive.DriveApi(client);
    final syncingRevision = _syncTracker.revision;
    final remoteFiles = await _findRemoteFiles(api);
    final remoteSignature = _signatureOf(remoteFiles);
    if (onlyIfChanged &&
        !_syncTracker.hasPendingChanges &&
        remoteFiles.isNotEmpty &&
        remoteSignature == _lastSeenRemoteFiles) {
      _checkActive(token);
      return _completeSync(token, syncingRevision, await _localStore.read());
    }

    ArchiveSyncData? remote;
    for (final file in remoteFiles) {
      final data = await _download(api, file.id!);
      remote = remote == null ? data : ArchiveSyncData.merge(remote, data);
    }
    _checkActive(token);
    final merged = remote == null
        ? await _localStore.read()
        : await _localStore.mergeAndReplace(
            remote,
            beforeReplace: () => _checkActive(token),
          );
    // Se l'unico backup contiene già tutto, ricaricarlo sprecherebbe banda e
    // farebbe scaricare inutilmente il backup agli altri dispositivi.
    if (remote != null &&
        remoteFiles.length == 1 &&
        ArchiveSyncData.sameContent(merged, remote)) {
      _checkActive(token);
      _lastSeenRemoteFiles = remoteSignature;
      return _completeSync(token, syncingRevision, merged);
    }

    // Serializzare l'archivio è il passaggio più caro del sync — fino al
    // tetto dei 20 MB, immagini comprese — e bloccherebbe la UI per secondi:
    // va in un isolate, come già fa l'export PDF.
    final bytes = await compute(
      _encodeArchive,
      merged,
      debugLabel: 'drive-backup-encode',
    );
    if (bytes.length > maxBackupBytes) {
      throw FormatException(
        'Il backup supera il limite di '
        '${maxBackupBytes ~/ (1024 * 1024)} MB. '
        'Riduci le immagini o il numero di schede prima di riprovare. '
        'I dati locali e il backup su Drive restano conservati.',
      );
    }
    // Un tentativo abbandonato dopo il timeout non deve più caricare niente:
    // non sovrascriverebbe nulla, ma cancellerebbe backup che nel frattempo un
    // tentativo più recente potrebbe non aver ancora unito.
    _checkActive(token);
    final uploaded = await api.files.create(
      drive.File()
        ..name = _fileName
        ..mimeType = _mimeType
        ..parents = const ['appDataFolder'],
      uploadMedia: drive.Media(
        Stream<List<int>>.value(bytes),
        bytes.length,
        contentType: _mimeType,
      ),
      $fields: 'id,version',
    );
    var allMergedRemoved = true;
    if (identical(_activeSync, token)) {
      for (final file in remoteFiles) {
        allMergedRemoved &= await _deleteMerged(api, file);
      }
    }
    if (identical(_activeSync, token)) {
      // Se qualche backup è rimasto, il prossimo giro lo scarica e lo unisce.
      _lastSeenRemoteFiles = allMergedRemoved ? _signatureOf([uploaded]) : null;
    }
    return _completeSync(token, syncingRevision, merged);
  }

  /// Cancella un backup già unito a quello appena caricato.
  ///
  /// Le versioni precedenti dell'app aggiornano invece il backup sul posto:
  /// se nel frattempo il file è cambiato contiene qualcosa che questo sync non
  /// ha unito, e resta lì per il prossimo. Restituisce `true` se il file non
  /// c'è più.
  Future<bool> _deleteMerged(drive.DriveApi api, drive.File file) async {
    try {
      final current = await api.files.get(file.id!, $fields: 'version');
      if (current is! drive.File || current.version != file.version) {
        return false;
      }
      await api.files.delete(file.id!);
      return true;
    } on drive.DetailedApiRequestError catch (error) {
      // Già cancellato da un altro dispositivo che l'aveva unito a sua volta.
      return error.status == 404;
    } catch (_) {
      // Resta un doppione, che il prossimo sync unirà di nuovo.
      return false;
    }
  }

  static String _signatureOf(Iterable<drive.File> files) =>
      (files.map((file) => '${file.id}:${file.version}').toList()..sort()).join(
        ',',
      );

  /// Chiude un sync riuscito, se nel frattempo non è stato abbandonato.
  Future<DriveSyncSummary> _completeSync(
    Object token,
    int syncingRevision,
    ArchiveSyncData merged,
  ) async {
    final completedAt = DateTime.now().toUtc();
    // Il timeout non annulla la richiesta sottostante: un tentativo
    // abbandonato può arrivare in fondo molto dopo, e non deve né dichiarare
    // riuscito un sync che l'utente ha visto fallire né marcare come inviate
    // revisioni appartenenti a un tentativo più recente.
    if (identical(_activeSync, token)) {
      await _syncTracker.markSyncedThrough(syncingRevision);
      _lastSyncAt = completedAt;
      _state = GoogleDriveSyncState.success;
      notifyListeners();
    }
    return DriveSyncSummary(
      characters: merged.characters.length,
      versions: merged.versions.length,
      completedAt: completedAt,
    );
  }

  bool _isAuthorizationFailure(drive.DetailedApiRequestError error) =>
      error.status == 401 ||
      error.errors.any(
        (detail) =>
            detail.reason == 'authError' ||
            detail.reason == 'invalidCredentials',
      );

  void _checkActive(Object token) {
    if (!identical(_activeSync, token)) {
      throw TimeoutException('Sincronizzazione Drive abbandonata.');
    }
  }

  /// I backup presenti su Drive, il più recente per primo.
  Future<List<drive.File>> _findRemoteFiles(drive.DriveApi api) async {
    final result = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_fileName' and trashed = false",
      orderBy: 'modifiedTime desc',
      pageSize: 100,
      $fields: 'files(id,name,modifiedTime,version)',
    );
    return result.files ?? const [];
  }

  Future<ArchiveSyncData> _download(drive.DriveApi api, String fileId) async {
    final response = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );
    if (response is! drive.Media) {
      throw const FormatException('Drive non ha restituito il backup.');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (builder.length + chunk.length > maxBackupBytes) {
        throw const FormatException('Il backup Drive è troppo grande.');
      }
      builder.add(chunk);
    }
    return compute(
      _decodeArchive,
      builder.takeBytes(),
      debugLabel: 'drive-backup-decode',
    );
  }

  Future<void> signOut() async {
    await _initialization;
    // Un altro account ha un altro backup: il prossimo sync lo scarica.
    _lastSeenRemoteFiles = null;
    if (_isDesktop) {
      await _desktopAuth.signOut();
      _state = GoogleDriveSyncState.idle;
      _errorMessage = null;
      notifyListeners();
      return;
    }
    if (!_signInInitialized) return;
    final accessToken = _accessToken;
    if (accessToken != null) {
      await (_currentUser?.authorizationClient ?? _signIn.authorizationClient)
          .clearAuthorizationToken(accessToken: accessToken);
    }
    if (_currentUser != null) await _signIn.signOut();
    _currentUser = null;
    _hasAuthorization = false;
    _accessToken = null;
    _state = GoogleDriveSyncState.idle;
    _errorMessage = null;
    notifyListeners();
  }

  String _friendlyError(Object error) {
    if (error is GoogleSignInException) {
      return switch (error.code) {
        GoogleSignInExceptionCode.canceled =>
          'Accesso Google interrotto. Se non hai annullato, verifica in Google '
              'Cloud il pacchetto Android e lo SHA-1 della firma dell’APK.',
        GoogleSignInExceptionCode.clientConfigurationError =>
          'Configurazione OAuth Google non valida.',
        _ => 'Accesso Google non riuscito.',
      };
    }
    if (error is TimeoutException) {
      return 'Google Drive non ha risposto in tempo. Riprova più tardi.';
    }
    if (error is FormatException) return error.message;
    if (error is StateError) return error.message;
    if (error is DesktopGoogleAuthException) return error.message;
    if (error is gauth.ServerRequestFailedException) {
      return 'Google Drive non è raggiungibile o l’autorizzazione è scaduta.';
    }
    if (error is drive.ApiRequestError) {
      return 'Google Drive non è raggiungibile o l’autorizzazione è scaduta.';
    }
    return 'Sincronizzazione con Google Drive non riuscita.';
  }

  @override
  void dispose() {
    _disposed = true;
    _activeSync = null;
    WidgetsBinding.instance.removeObserver(this);
    _automaticSyncTimer.cancel();
    _syncTracker.removeListener(_localChangesChanged);
    if (_ownsSyncTracker) _syncTracker.dispose();
    unawaited(_authSubscription?.cancel());
    _desktopAuth.dispose();
    super.dispose();
  }
}

Uint8List _encodeArchive(ArchiveSyncData data) =>
    utf8.encode(jsonEncode(data.toJson()));

ArchiveSyncData _decodeArchive(Uint8List bytes) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map) {
    throw const FormatException(
      'Il backup Drive non contiene un oggetto JSON.',
    );
  }
  return ArchiveSyncData.fromJson({
    for (final entry in decoded.entries)
      if (entry.key is String) entry.key as String: entry.value,
  });
}

class _AuthorizedClient extends http.BaseClient {
  _AuthorizedClient(this._inner, this._headers);

  final http.Client _inner;
  final Map<String, String> _headers;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
