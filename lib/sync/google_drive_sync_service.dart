import 'dart:async';
import 'dart:convert';

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
  }) : _syncTracker = syncTracker ?? ArchiveSyncTracker.inMemory(),
       _ownsSyncTracker = syncTracker == null {
    _syncTracker.addListener(_localChangesChanged);
    _initialization = _initialize();
    _automaticSyncTimer = Timer.periodic(
      automaticSyncInterval,
      (_) => unawaited(syncPendingChanges()),
    );
    // Modifiche rimaste in sospeso dalla sessione precedente.
    _initialization.whenComplete(() => unawaited(syncPendingChanges()));
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
  static const _maxDownloadBytes = 20 * 1024 * 1024;
  // Una richiesta che non risponde mai non deve lasciare lo stato bloccato su
  // "syncing", che rifiuterebbe ogni sincronizzazione successiva.
  static const _syncTimeout = Duration(minutes: 2);

  final LocalArchiveSyncStore _localStore;
  final ArchiveSyncTracker _syncTracker;
  final bool _ownsSyncTracker;
  final Duration automaticSyncInterval;
  late final GoogleSignIn _signIn = GoogleSignIn.instance;
  late final DesktopGoogleAuth _desktopAuth = DesktopGoogleAuth(
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
    // ultima occasione per spedire le modifiche in sospeso.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(syncPendingChanges());
    }
  }

  Future<bool> syncPendingChanges({bool interactive = false}) async {
    if (!hasPendingChanges ||
        _state == GoogleDriveSyncState.syncing ||
        !isConfigured ||
        (!interactive && !isConnected)) {
      return false;
    }
    try {
      await sync(interactive: interactive);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<DriveSyncSummary> sync({bool interactive = true}) async {
    await _initialization;
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
    try {
      if (_isDesktop) {
        try {
          if (!interactive && !_desktopAuth.isConnected) {
            throw const GoogleDriveSignInRequired();
          }
          final client = await _desktopAuth.authenticatedClient();
          return await _syncWithClient(client).timeout(_syncTimeout);
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
          return await _syncWithClient(client).timeout(_syncTimeout);
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
    }
  }

  Future<DriveSyncSummary> _syncWithClient(http.Client client) async {
    final syncingRevision = _syncTracker.revision;
    final api = drive.DriveApi(client);
    final remoteFile = await _findRemoteFile(api);
    final remote = remoteFile == null
        ? null
        : await _download(api, remoteFile.id!);
    final merged = remote == null
        ? await _localStore.read()
        : await _localStore.mergeAndReplace(remote);
    final bytes = utf8.encode(jsonEncode(merged.toJson()));
    final media = drive.Media(
      Stream<List<int>>.value(bytes),
      bytes.length,
      contentType: _mimeType,
    );
    if (remoteFile == null) {
      await api.files.create(
        drive.File()
          ..name = _fileName
          ..mimeType = _mimeType
          ..parents = const ['appDataFolder'],
        uploadMedia: media,
        $fields: 'id',
      );
    } else {
      await api.files.update(
        drive.File()..mimeType = _mimeType,
        remoteFile.id!,
        uploadMedia: media,
        $fields: 'id',
      );
    }
    await _syncTracker.markSyncedThrough(syncingRevision);
    final completedAt = DateTime.now().toUtc();
    _lastSyncAt = completedAt;
    _state = GoogleDriveSyncState.success;
    notifyListeners();
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

  Future<drive.File?> _findRemoteFile(drive.DriveApi api) async {
    final result = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_fileName' and trashed = false",
      orderBy: 'modifiedTime desc',
      pageSize: 1,
      $fields: 'files(id,name,modifiedTime)',
    );
    final files = result.files;
    return files == null || files.isEmpty ? null : files.first;
  }

  Future<ArchiveSyncData> _download(drive.DriveApi api, String fileId) async {
    final response = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );
    if (response is! drive.Media) {
      throw const FormatException('Drive non ha restituito il backup.');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      if (bytes.length > _maxDownloadBytes) {
        throw const FormatException('Il backup Drive è troppo grande.');
      }
    }
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

  Future<void> signOut() async {
    await _initialization;
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
        GoogleSignInExceptionCode.canceled => 'Accesso Google annullato.',
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
    WidgetsBinding.instance.removeObserver(this);
    _automaticSyncTimer.cancel();
    _syncTracker.removeListener(_localChangesChanged);
    if (_ownsSyncTracker) _syncTracker.dispose();
    unawaited(_authSubscription?.cancel());
    _desktopAuth.dispose();
    super.dispose();
  }
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
