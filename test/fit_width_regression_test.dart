import 'package:dnd_sheet_archive/data/character_repository.dart';
import 'package:dnd_sheet_archive/data/local_archive_sync_store.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:dnd_sheet_archive/models/sheet_field.dart';
import 'package:dnd_sheet_archive/screens/sheet_screen.dart';
import 'package:dnd_sheet_archive/sync/archive_sync_tracker.dart';
import 'package:dnd_sheet_archive/sync/google_drive_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  for (final width in [400.0, 800.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'fit width keeps horizontal bounds at $width in $brightness',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final database = await databaseFactoryMemory.openDatabase('fit.db');
          addTearDown(database.close);
          final tracker = ArchiveSyncTracker.inMemory();
          final sync = GoogleDriveSyncService(
            LocalArchiveSyncStore(database),
            syncTracker: tracker,
          );
          await tester.runAsync(SheetFieldDef.loadByPage);
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: SheetScreen(
                character: Character(
                  id: 'fit',
                  name: 'Fit',
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                  locked: true,
                ),
                repository: _Repository(),
                driveSync: sync,
              ),
            ),
          );
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 50));
          final controller = tester
              .widget<InteractiveViewer>(find.byType(InteractiveViewer))
              .transformationController!;

          // InteractiveViewer reads the maximum of all three scale axes.
          expect(
            controller.value.getMaxScaleOnAxis(),
            closeTo(controller.value.storage[0], .000001),
          );
          Future<void> finishAnimation() async {
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }

          await tester.tap(find.byTooltip('Aumenta zoom'));
          await finishAnimation();
          await tester.tap(
            find.byTooltip('Adatta alla larghezza della finestra'),
          );
          await finishAnimation();
          expect(controller.value.storage[0], closeTo(width / 612, .000001));
          expect(
            controller.value.getMaxScaleOnAxis(),
            closeTo(width / 612, .000001),
          );
          expect(controller.value.storage[12], closeTo(0, .01));

          final gesture = await tester.startGesture(Offset(width / 2, 400));
          for (final delta in [
            const Offset(-60, -30),
            const Offset(-40, -30),
            const Offset(80, -30),
          ]) {
            await gesture.moveBy(delta);
            await tester.pump(const Duration(milliseconds: 16));
            expect(controller.value.storage[12], closeTo(0, .01));
          }
          await gesture.up();
          await tester.pump(const Duration(seconds: 1));
          expect(controller.value.storage[12], closeTo(0, .01));
          expect(controller.value.storage[13], lessThan(0));
          expect(
            controller.value.getMaxScaleOnAxis(),
            closeTo(width / 612, .000001),
          );

          // Zooming back in must still permit horizontal movement.
          await tester.tap(find.byTooltip('Aumenta zoom'));
          await finishAnimation();
          await tester.dragFrom(Offset(width / 2, 400), const Offset(-60, 0));
          await tester.pump(const Duration(seconds: 1));
          expect(controller.value.storage[12], lessThan(-1));

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          sync.dispose();
          tracker.dispose();
        },
      );
    }
  }
}

class _Repository implements CharacterRepository {
  @override
  Future<void> saveCharacter(Character character) async {}
  @override
  Future<void> createSnapshot(Character character, String reason) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
