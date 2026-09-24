import 'package:dnd_sheet_archive/data/local_archive_sync_store.dart';
import 'package:dnd_sheet_archive/data/sembast_character_repository.dart';
import 'package:dnd_sheet_archive/main.dart';
import 'package:dnd_sheet_archive/models/sheet_field.dart';
import 'package:dnd_sheet_archive/screens/sheet_screen.dart';
import 'package:dnd_sheet_archive/sync/archive_sync_tracker.dart';
import 'package:dnd_sheet_archive/sync/google_drive_sync_service.dart';
import 'package:dnd_sheet_archive/theme/theme_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  testWidgets(
    'appearance updates an open sheet and follows system brightness',
    (tester) async {
      final database = await databaseFactoryMemory.openDatabase('theme-app.db');
      addTearDown(database.close);
      final tracker = ArchiveSyncTracker.inMemory();
      final repository = SembastCharacterRepository(
        database,
        syncTracker: tracker,
      );
      final character = await repository.createCharacter('Arannis');
      final driveSync = GoogleDriveSyncService(
        LocalArchiveSyncStore(database),
        syncTracker: tracker,
      );
      final preferences = ThemePreferences.inMemory(mode: ThemeMode.light);
      addTearDown(preferences.dispose);
      addTearDown(driveSync.dispose);
      addTearDown(tracker.dispose);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.runAsync(SheetFieldDef.loadByPage);
      await tester.pumpWidget(
        DndSheetArchiveApp(
          repository: repository,
          driveSync: driveSync,
          themePreferences: preferences,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(character.name));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SheetScreen), findsOneWidget);
      Future<void> choose(String label) async {
        await tester.tap(find.byTooltip('Aspetto'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await choose('Scuro');
      expect(
        Theme.of(tester.element(find.byType(SheetScreen))).brightness,
        Brightness.dark,
      );
      expect(find.byType(SheetScreen), findsOneWidget);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await choose('Sistema');
      expect(
        Theme.of(tester.element(find.byType(SheetScreen))).brightness,
        Brightness.light,
      );
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(SheetScreen))).brightness,
        Brightness.dark,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
