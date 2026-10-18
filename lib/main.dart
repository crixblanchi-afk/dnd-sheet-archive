import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sembast/sembast.dart';

import 'data/app_database.dart';
import 'data/blob_store.dart';
import 'data/local_archive_sync_store.dart';
import 'data/sembast_character_repository.dart';
import 'screens/character_list_screen.dart';
import 'sync/archive_sync_tracker.dart';
import 'sync/google_drive_sync_service.dart';
import 'theme/sheet_palette.dart';
import 'theme/theme_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) unawaited(BrowserContextMenu.disableContextMenu());
  runApp(const _BootstrapApp());
}

/// L'archivio aperto, condiviso fra i tentativi di avvio.
///
/// Se a fallire è un passaggio successivo, «Riprova» riusa l'archivio invece
/// di riaprirlo: il lock dell'istanza è già di questo processo.
Future<Database>? _database;

Future<_AppServices> _openServices() async {
  final opening = _database ??= openAppDatabase();
  final Database database;
  try {
    database = await opening;
  } catch (_) {
    if (identical(_database, opening)) _database = null;
    rethrow;
  }
  final syncTracker = await ArchiveSyncTracker.open(database);
  // Le schede salvate prima dell'archivio dei blob portano ancora le immagini
  // dentro i campi: spostarle deduplica l'archivio locale, e il backup va
  // riscritto perché Drive riceva la stessa forma.
  if (await BlobStore(database).migrateInlineImages()) {
    await syncTracker.markChanged();
  }
  return _AppServices(
    themePreferences: await ThemePreferences.open(database),
    repository: SembastCharacterRepository(database, syncTracker: syncTracker),
    driveSync: GoogleDriveSyncService(
      LocalArchiveSyncStore(database),
      syncTracker: syncTracker,
    ),
  );
}

class _AppServices {
  const _AppServices({
    required this.repository,
    required this.driveSync,
    required this.themePreferences,
  });

  final SembastCharacterRepository repository;
  final GoogleDriveSyncService driveSync;
  final ThemePreferences themePreferences;
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  late Future<_AppServices> _services = _start();

  Future<_AppServices> _start() => _openServices().catchError((
    Object error,
    StackTrace stack,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'dnd_sheet_archive',
        context: ErrorDescription('durante l’apertura dell’archivio locale'),
      ),
    );
    return Future<_AppServices>.error(error, stack);
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<_AppServices>(
    future: _services,
    builder: (context, snapshot) {
      final services = snapshot.data;
      if (services != null) {
        return DndSheetArchiveApp(
          repository: services.repository,
          driveSync: services.driveSync,
          themePreferences: services.themePreferences,
        );
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _appTheme(Brightness.light),
        darkTheme: _appTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: Scaffold(
          body: Center(
            child: snapshot.hasError
                ? _OpenError(
                    error: snapshot.error!,
                    onRetry: () => setState(() => _services = _start()),
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
    },
  );
}

class _OpenError extends StatelessWidget {
  const _OpenError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final alreadyOpen = error is ArchiveAlreadyOpenException;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            alreadyOpen
                ? 'L’archivio è già aperto in un’altra finestra dell’app.'
                : 'Impossibile aprire l’archivio locale.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            alreadyOpen
                ? 'Chiudi l’altra finestra, poi riprova: due finestre sullo '
                      'stesso archivio si sovrascriverebbero le modifiche.'
                : '$error',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Riprova')),
        ],
      ),
    );
  }
}

class DndSheetArchiveApp extends StatelessWidget {
  const DndSheetArchiveApp({
    super.key,
    required this.repository,
    required this.driveSync,
    required this.themePreferences,
  });

  final SembastCharacterRepository repository;
  final GoogleDriveSyncService driveSync;
  final ThemePreferences themePreferences;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: themePreferences,
    builder: (context, _) => MaterialApp(
      title: 'Schede D&D 5e',
      debugShowCheckedModeBanner: false,
      theme: _appTheme(
        Brightness.light,
        colored: themePreferences.theme.colored,
      ),
      darkTheme: _appTheme(
        Brightness.dark,
        colored: themePreferences.theme.colored,
      ),
      themeMode: themePreferences.mode,
      builder: (context, child) =>
          ThemePreferenceScope(preferences: themePreferences, child: child!),
      home: CharacterListScreen(repository: repository, driveSync: driveSync),
    ),
  );
}

ThemeData _appTheme(Brightness brightness, {bool colored = false}) => ThemeData(
  brightness: brightness,
  extensions: [
    switch ((brightness, colored)) {
      (Brightness.light, false) => SheetPalette.light,
      (Brightness.dark, false) => SheetPalette.dark,
      (Brightness.light, true) => SheetPalette.lightColored,
      (Brightness.dark, true) => SheetPalette.darkColored,
    },
  ],
  colorScheme: ColorScheme.fromSeed(
    seedColor: brightness == Brightness.dark
        ? const Color(0xffe5bd78)
        : const Color(0xff7b1f1f),
    brightness: brightness,
  ),
  useMaterial3: true,
  visualDensity: VisualDensity.adaptivePlatformDensity,
);
