import 'package:dnd_sheet_archive/data/character_repository.dart';
import 'package:dnd_sheet_archive/data/local_archive_sync_store.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:dnd_sheet_archive/models/sheet_field.dart';
import 'package:dnd_sheet_archive/models/sheet_layout.dart';
import 'package:dnd_sheet_archive/screens/sheet_screen.dart';
import 'package:dnd_sheet_archive/sync/archive_sync_tracker.dart';
import 'package:dnd_sheet_archive/sync/google_drive_sync_service.dart';
import 'package:dnd_sheet_archive/widgets/sheet_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a pan starting outside the active field releases focus on the real sheet',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(612, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final database = await databaseFactoryMemory.openDatabase(
        'sheet-screen-focus.db',
      );
      addTearDown(database.close);
      final driveSync = GoogleDriveSyncService(
        LocalArchiveSyncStore(database),
        syncTracker: ArchiveSyncTracker.inMemory(hasPendingChanges: true),
      );
      final repository = _FakeRepository();
      final character = Character(
        id: 'character',
        name: 'Character',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        locked: false,
      );
      await tester.runAsync(SheetFieldDef.loadByPage);

      await tester.pumpWidget(
        MaterialApp(
          home: SheetScreen(
            character: character,
            repository: repository,
            driveSync: driveSync,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final loadError = find.textContaining('Impossibile caricare');
      if (loadError.evaluate().isNotEmpty) {
        fail(tester.widget<Text>(loadError).data!);
      }
      expect(find.byType(SheetPage), findsNWidgets(3));
      expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
      final characterName = find.byKey(const ValueKey('CharacterName'));
      expect(characterName, findsOneWidget);
      await tester.tapAt(tester.getCenter(characterName));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 550));
      expect(find.byType(TextField), findsOneWidget);

      final pan = await tester.startGesture(const Offset(500, 760));
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      await pan.moveBy(const Offset(-20, -20));
      await pan.up();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      driveSync.dispose();
    },
  );

  testWidgets(
    'la scheda resta centrata e lo zoom manuale annulla il ripristino fit-width',
    (tester) async {
      const viewportWidth = 1000.0;
      await tester.binding.setSurfaceSize(const Size(viewportWidth, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final database = await databaseFactoryMemory.openDatabase(
        'sheet-screen-centering.db',
      );
      addTearDown(database.close);
      final driveSync = GoogleDriveSyncService(
        LocalArchiveSyncStore(database),
        syncTracker: ArchiveSyncTracker.inMemory(),
      );
      await tester.runAsync(SheetFieldDef.loadByPage);

      await tester.pumpWidget(
        MaterialApp(
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
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final matrix = viewer.transformationController!.value;
      final scale = matrix.getMaxScaleOnAxis();
      expect(
        matrix.storage[12],
        closeTo(sheetCenterOffset(viewportWidth, sheetPageWidth * scale), .01),
      );
      expect(matrix.storage[12], greaterThan(0));

      final controller = viewer.transformationController!;
      final fit = find.byTooltip('Adatta alla larghezza della finestra');
      final restore = find.byTooltip('Ripristina lo zoom precedente');
      Future<void> finishZoom() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
      }

      await tester.tap(fit);
      await finishZoom();
      expect(controller.value.getMaxScaleOnAxis(), closeTo(1000 / 612, .001));
      expect(restore, findsOneWidget);
      controller.value = controller.value.clone()
        ..translateByDouble(0, -50, 0, 1);
      await tester.pump();
      expect(restore, findsOneWidget);
      await tester.tap(restore);
      await finishZoom();
      expect(controller.value.getMaxScaleOnAxis(), closeTo(scale, .001));

      for (final tooltip in ['Aumenta zoom', 'Riduci zoom']) {
        await tester.tap(fit);
        await finishZoom();
        await tester.tap(find.byTooltip(tooltip));
        await finishZoom();
        expect(fit, findsOneWidget);
        expect(restore, findsNothing);
      }

      // Una modifica esterna durante l'animazione (come un pinch) deve vincere.
      await tester.tap(fit);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      controller.value = controller.value.clone()..scaleByDouble(.9, .9, 1, 1);
      final manualScale = controller.value.getMaxScaleOnAxis();
      await finishZoom();
      expect(fit, findsOneWidget);
      expect(controller.value.getMaxScaleOnAxis(), closeTo(manualScale, .001));

      await tester.tap(fit);
      await finishZoom();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(500, 400),
          scrollDelta: Offset(0, -80),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(fit, findsOneWidget);
      expect(restore, findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      driveSync.dispose();
    },
  );
}

class _FakeRepository implements CharacterRepository {
  @override
  Future<void> saveCharacter(Character character) async {}

  @override
  Future<void> createSnapshot(Character character, String reason) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
