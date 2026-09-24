import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/app_database.dart';
import 'data/local_archive_sync_store.dart';
import 'data/sembast_character_repository.dart';
import 'screens/character_list_screen.dart';
import 'sync/archive_sync_tracker.dart';
import 'sync/google_drive_sync_service.dart';
import 'theme/theme_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) unawaited(BrowserContextMenu.disableContextMenu());
  runApp(const _BootstrapApp());
}

Future<_AppServices> _openServices() async {
  final database = await openAppDatabase();
  final syncTracker = await ArchiveSyncTracker.open(database);
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
  late final Future<_AppServices> _services = _openServices();

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
                ? const Text('Impossibile aprire l’archivio locale.')
                : const CircularProgressIndicator(),
          ),
        ),
      );
    },
  );
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
      theme: _appTheme(Brightness.light),
      darkTheme: _appTheme(Brightness.dark),
      themeMode: themePreferences.mode,
      builder: (context, child) =>
          ThemePreferenceScope(preferences: themePreferences, child: child!),
      home: CharacterListScreen(repository: repository, driveSync: driveSync),
    ),
  );
}

ThemeData _appTheme(Brightness brightness) => ThemeData(
  brightness: brightness,
  colorScheme: ColorScheme.fromSeed(
    seedColor: brightness == Brightness.dark
        ? const Color(0xffe5bd78)
        : const Color(0xff7b1f1f),
    brightness: brightness,
  ),
  useMaterial3: true,
  visualDensity: VisualDensity.adaptivePlatformDensity,
);
