import 'package:dnd_sheet_archive/data/character_repository.dart';
import 'package:dnd_sheet_archive/data/local_archive_sync_store.dart';
import 'package:dnd_sheet_archive/data/sembast_character_repository.dart';
import 'package:dnd_sheet_archive/data/sheet_view_preferences.dart';
import 'package:dnd_sheet_archive/main.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:dnd_sheet_archive/models/sheet_field.dart';
import 'package:dnd_sheet_archive/screens/sheet_screen.dart';
import 'package:dnd_sheet_archive/sync/archive_sync_tracker.dart';
import 'package:dnd_sheet_archive/sync/google_drive_sync_service.dart';
import 'package:dnd_sheet_archive/theme/theme_preferences.dart';
import 'package:dnd_sheet_archive/widgets/scrollable_sheet_view.dart';
import 'package:dnd_sheet_archive/widgets/sheet_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('sheet view mode persists locally, including rapid changes', () async {
    final database = await databaseFactoryMemory.openDatabase('view-mode.db');
    addTearDown(database.close);
    final preferences = await SheetViewPreferences.open(database);
    addTearDown(preferences.dispose);
    expect(preferences.mode, SheetViewMode.pages);

    await Future.wait([
      preferences.setMode(SheetViewMode.pages),
      preferences.setMode(SheetViewMode.scroll),
      preferences.setMode(SheetViewMode.vertical),
    ]);
    final restored = await SheetViewPreferences.open(database);
    addTearDown(restored.dispose);
    expect(restored.mode, SheetViewMode.vertical);

    await preferences.setMode(SheetViewMode.scroll);
    final scrolled = await SheetViewPreferences.open(database);
    addTearDown(scrolled.dispose);
    expect(scrolled.mode, SheetViewMode.scroll);

    await preferences.setMode(SheetViewMode.pages);
    final paged = await SheetViewPreferences.open(database);
    addTearDown(paged.dispose);
    expect(paged.mode, SheetViewMode.pages);
  });

  test('unknown saved view mode falls back to pages', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'view-mode-unknown.db',
    );
    addTearDown(database.close);
    final store = StoreRef<String, String>('app_preferences');
    await store.record('sheet_view_mode').put(database, 'sconosciuto');
    final preferences = await SheetViewPreferences.open(database);
    addTearDown(preferences.dispose);
    expect(preferences.mode, SheetViewMode.pages);
  });

  test('view mode coexists with theme preference in app_preferences', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'view-and-theme.db',
    );
    addTearDown(database.close);
    final themePreferences = await ThemePreferences.open(database);
    final viewPreferences = await SheetViewPreferences.open(database);
    addTearDown(themePreferences.dispose);
    addTearDown(viewPreferences.dispose);

    await themePreferences.setTheme(AppTheme.darkColored);
    await viewPreferences.setMode(SheetViewMode.scroll);

    final restoredTheme = await ThemePreferences.open(database);
    final restoredView = await SheetViewPreferences.open(database);
    addTearDown(restoredTheme.dispose);
    addTearDown(restoredView.dispose);
    expect(restoredTheme.theme, AppTheme.darkColored);
    expect(restoredView.mode, SheetViewMode.scroll);
  });

  testWidgets(
    'chosen view mode persists across app restarts and sheets',
    (tester) async {
      final database = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('view-mode-restart.db'),
      ))!;
      addTearDown(() => tester.runAsync(database.close));
      final tracker = ArchiveSyncTracker.inMemory();
      addTearDown(tracker.dispose);
      final repository = SembastCharacterRepository(
        database,
        syncTracker: tracker,
      );
      final character = (await tester.runAsync(
        () => repository.createCharacter('Arannis'),
      ))!;
      final driveSync = GoogleDriveSyncService(
        LocalArchiveSyncStore(database),
        syncTracker: tracker,
      );
      await tester.runAsync(SheetFieldDef.loadByPage);

      Future<void> openCharacter() async {
        await tester.tap(find.text(character.name));
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          if (find.byType(SheetPage).evaluate().isNotEmpty) break;
        }
        await tester.pumpAndSettle();
        expect(find.byType(SheetScreen), findsOneWidget);
      }

      Future<void> chooseViewMode(SheetViewMode mode) async {
        await tester.tap(find.byTooltip('Visualizzazione scheda'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(CheckedPopupMenuItem<SheetViewMode>, mode.label),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
      }

      // Primo avvio: parte in modalità "A pagine" e passa a "A scorrimento".
      final firstTheme = (await tester.runAsync(
        () => ThemePreferences.open(database),
      ))!;
      final firstView = (await tester.runAsync(
        () => SheetViewPreferences.open(database),
      ))!;
      addTearDown(firstTheme.dispose);
      addTearDown(firstView.dispose);

      await tester.pumpWidget(
        DndSheetArchiveApp(
          repository: repository,
          driveSync: driveSync,
          themePreferences: firstTheme,
          sheetViewPreferences: firstView,
        ),
      );
      await tester.pumpAndSettle();
      await openCharacter();
      expect(find.byType(ScrollableSheetView), findsNothing);
      expect(find.byType(PageView), findsOneWidget);

      await chooseViewMode(SheetViewMode.scroll);
      expect(find.byType(ScrollableSheetView), findsOneWidget);
      expect(firstView.mode, SheetViewMode.scroll);

      // Riavvio simulato: nuovi servizi aperti dallo stesso database.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final secondTheme = (await tester.runAsync(
        () => ThemePreferences.open(database),
      ))!;
      final secondView = (await tester.runAsync(
        () => SheetViewPreferences.open(database),
      ))!;
      addTearDown(secondTheme.dispose);
      addTearDown(secondView.dispose);
      expect(secondView.mode, SheetViewMode.scroll);

      await tester.pumpWidget(
        DndSheetArchiveApp(
          repository: repository,
          driveSync: driveSync,
          themePreferences: secondTheme,
          sheetViewPreferences: secondView,
        ),
      );
      await tester.pumpAndSettle();
      await openCharacter();
      expect(find.byType(ScrollableSheetView), findsOneWidget);
      expect(find.byType(PageView), findsNothing);

      // Torna ad "A pagine" e verifica la persistenza al riavvio successivo.
      await chooseViewMode(SheetViewMode.pages);
      expect(find.byType(PageView), findsOneWidget);
      expect(find.byType(ScrollableSheetView), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      driveSync.dispose();
      final thirdView = (await tester.runAsync(
        () => SheetViewPreferences.open(database),
      ))!;
      addTearDown(thirdView.dispose);
      expect(thirdView.mode, SheetViewMode.pages);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'failed view mode save still applies in UI and reports a snackbar',
    (tester) async {
      final database = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('view-mode-error.db'),
      ))!;
      final preferences = (await tester.runAsync(
        () => SheetViewPreferences.open(database),
      ))!;
      addTearDown(preferences.dispose);
      final syncDb = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('view-mode-error-sync.db'),
      ))!;
      addTearDown(() => tester.runAsync(syncDb.close));
      final driveSync = GoogleDriveSyncService(
        LocalArchiveSyncStore(syncDb),
        syncTracker: ArchiveSyncTracker.inMemory(),
      );
      await tester.runAsync(SheetFieldDef.loadByPage);

      await tester.pumpWidget(
        SheetViewPreferenceScope(
          preferences: preferences,
          child: MaterialApp(
            home: SheetScreen(
              character: Character(
                id: 'character',
                name: 'Character',
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
                locked: false,
              ),
              repository: _FakeRepository(),
              driveSync: driveSync,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      // Chiudere il database fa fallire la scrittura della preferenza.
      await tester.runAsync(database.close);

      await tester.tap(find.byTooltip('Visualizzazione scheda'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          CheckedPopupMenuItem<SheetViewMode>,
          SheetViewMode.scroll.label,
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }

      expect(find.byType(ScrollableSheetView), findsOneWidget);
      expect(
        find.text('Visualizzazione applicata, ma non salvata. Riprova.'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      driveSync.dispose();
    },
  );
}

class _FakeRepository extends CharacterRepository {
  @override
  Future<void> saveCharacter(Character character) async {}

  @override
  Future<void> createSnapshot(Character character, String reason) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
