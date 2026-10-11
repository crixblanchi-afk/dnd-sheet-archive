import 'package:dnd_sheet_archive/data/character_repository.dart';
import 'package:dnd_sheet_archive/data/local_archive_sync_store.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:dnd_sheet_archive/models/sheet_field.dart';
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

  testWidgets('short keyboard viewports keep the active page visible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetViewInsets);
    final database = await databaseFactoryMemory.openDatabase(
      'sheet-screen-short-keyboard.db',
    );
    addTearDown(database.close);
    final driveSync = GoogleDriveSyncService(
      LocalArchiveSyncStore(database),
      syncTracker: ArchiveSyncTracker.inMemory(),
    );
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
          repository: _FakeRepository(),
          driveSync: driveSync,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Apri lanciadadi'));
    await tester.pumpAndSettle();
    final name = find.byKey(const ValueKey('CharacterName'));
    await tester.tapAt(tester.getCenter(name));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Arannis');
    tester.view.viewInsets = FakeViewPadding(
      bottom: 300 * tester.view.devicePixelRatio,
    );

    for (final width in [800.0, 320.0]) {
      await tester.binding.setSurfaceSize(Size(width, 400));
      await tester.pumpAndSettle();
      final pageRect = tester.getRect(find.byType(SheetPage));
      final fieldRect = tester.getRect(find.byType(TextField));
      final navigationTop = tester
          .getTopLeft(find.byTooltip('Pagina successiva'))
          .dy;
      expect(pageRect.width, greaterThan(0));
      expect(pageRect.height, greaterThan(0));
      expect(pageRect.top, greaterThanOrEqualTo(0));
      expect(pageRect.bottom, lessThanOrEqualTo(navigationTop));
      expect(fieldRect.width, greaterThan(0));
      expect(fieldRect.height, greaterThan(0));
      expect(fieldRect.top, greaterThanOrEqualTo(pageRect.top));
      expect(fieldRect.bottom, lessThanOrEqualTo(pageRect.bottom));
      expect(tester.testTextInput.isVisible, isTrue);
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.byTooltip('Chiudi lanciadadi'), findsNothing);
      expect(tester.takeException(), isNull);
    }

    // Returning to a roomy viewport restores the normal controls.
    tester.view.resetViewInsets();
    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Chiudi lanciadadi'), findsOneWidget);
    expect(character.fields['CharacterName'], 'Arannis');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    driveSync.dispose();
  });

  for (final locked in [false, true]) {
    testWidgets(
      'paged navigation fits the whole sheet without zoom and preserves edits, locked=$locked',
      (tester) async {
        final width = locked ? 1000.0 : 320.0;
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        addTearDown(tester.view.resetViewInsets);
        final database = await databaseFactoryMemory.openDatabase(
          'sheet-screen-pages-$locked.db',
        );
        addTearDown(database.close);
        final driveSync = GoogleDriveSyncService(
          LocalArchiveSyncStore(database),
          syncTracker: ArchiveSyncTracker.inMemory(),
        );
        final repository = _FakeRepository();
        final character = Character(
          id: 'character',
          name: 'Character',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          locked: locked,
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
        await tester.pumpAndSettle();

        final previous = find.byWidgetPredicate(
          (widget) =>
              widget is IconButton && widget.tooltip == 'Pagina precedente',
        );
        final next = find.byWidgetPredicate(
          (widget) =>
              widget is IconButton && widget.tooltip == 'Pagina successiva',
        );
        SheetPage currentPage() => tester.widget(find.byType(SheetPage));
        expect(find.byType(SheetPage), findsOneWidget);
        expect(currentPage().pageIndex, 0);
        expect(find.text('Pagina 1 di 3'), findsOneWidget);
        expect(tester.widget<IconButton>(previous).onPressed, isNull);
        expect(find.byType(InteractiveViewer), findsNothing);
        expect(find.byTooltip('Aumenta zoom'), findsNothing);
        expect(find.byTooltip('Riduci zoom'), findsNothing);
        void expectPageFits() {
          final rect = tester.getRect(find.byType(SheetPage));
          final navigationTop = tester.getTopLeft(next).dy;
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.top, greaterThanOrEqualTo(64));
          expect(rect.bottom, lessThanOrEqualTo(navigationTop));
          expect(rect.center.dx, closeTo(width / 2, .01));
        }

        expectPageFits();
        if (!locked) {
          final name = find.byKey(const ValueKey('CharacterName'));
          await tester.tapAt(tester.getCenter(name));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'Arannis');
          tester.view.viewInsets = FakeViewPadding(
            bottom: 300 * tester.view.devicePixelRatio,
          );
          await tester.pumpAndSettle();
          expect(tester.getBottomLeft(next).dy, lessThanOrEqualTo(500));
          expectPageFits();
        }
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        if (!locked) {
          expect(tester.testTextInput.isVisible, isFalse);
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
        }
        expect(find.byType(SheetPage), findsOneWidget);
        expect(currentPage().pageIndex, 1);
        expect(find.text('Pagina 2 di 3'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('CharacterAppearanceImage')),
          findsOneWidget,
        );
        if (!locked) {
          expect(
            currentPage().controller.valueFor('CharacterName 2'),
            'Arannis',
          );
        }

        final pageRect = tester.getRect(find.byType(SheetPage));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: pageRect.center,
            scrollDelta: const Offset(0, -1000),
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.dragFrom(pageRect.center, const Offset(-20, -20));
        final pinch1 = await tester.startGesture(
          pageRect.center - const Offset(20, 0),
        );
        final pinch2 = await tester.startGesture(
          pageRect.center + const Offset(20, 0),
          pointer: 2,
        );
        await pinch1.moveBy(const Offset(-40, 0));
        await pinch2.moveBy(const Offset(40, 0));
        await pinch1.up();
        await pinch2.up();
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(SheetPage)), pageRect);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(currentPage().pageIndex, 2);
        expect(find.text('Pagina 3 di 3'), findsOneWidget);
        expect(tester.widget<IconButton>(next).onPressed, isNull);
        expectPageFits();
        await tester.binding.setSurfaceSize(Size(width, 400));
        await tester.pumpAndSettle();
        expectPageFits();
        await tester.binding.setSurfaceSize(Size(width, 800));
        await tester.pumpAndSettle();

        await tester.tap(previous);
        await tester.pumpAndSettle();
        await tester.tap(previous);
        await tester.pumpAndSettle();
        expect(currentPage().pageIndex, 0);
        expect(currentPage().controller.locked, locked);
        if (!locked) {
          expect(currentPage().controller.valueFor('CharacterName'), 'Arannis');
          await tester.pump(const Duration(seconds: 1));
          expect(repository.savedCharacter?.fields['CharacterName'], 'Arannis');
        }
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        driveSync.dispose();
      },
    );
  }

  testWidgets(
    'a pointer starting outside the active field releases focus on the real sheet',
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
      expect(find.byType(SheetPage), findsOneWidget);
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

  for (final systemBack in [true, false]) {
    testWidgets(
      '${systemBack ? 'system' : 'button'} back hides the keyboard before leaving',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(612, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        addTearDown(tester.view.resetViewInsets);

        final database = await databaseFactoryMemory.openDatabase(
          'sheet-screen-back-$systemBack.db',
        );
        addTearDown(database.close);
        final driveSync = GoogleDriveSyncService(
          LocalArchiveSyncStore(database),
          syncTracker: ArchiveSyncTracker.inMemory(),
        );
        final character = Character(
          id: 'character',
          name: 'Character',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          locked: false,
        );
        final navigator = GlobalKey<NavigatorState>();
        await tester.runAsync(SheetFieldDef.loadByPage);
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('Character list')),
          ),
        );
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => SheetScreen(
              character: character,
              repository: _FakeRepository(),
              driveSync: driveSync,
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();

        final nameField = find.byKey(const ValueKey('CharacterName'));
        await tester.tapAt(tester.getCenter(nameField));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Updated name');
        tester.view.viewInsets = FakeViewPadding(
          bottom: 300 * tester.view.devicePixelRatio,
        );
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isTrue);

        Future<void> goBack() async {
          if (systemBack) {
            await tester.binding.handlePopRoute();
          } else {
            await tester.tap(find.byTooltip('Indietro'));
          }
          await tester.pumpAndSettle();
        }

        await goBack();
        expect(find.byType(SheetScreen), findsOneWidget);
        expect(tester.testTextInput.isVisible, isFalse);
        expect(find.byType(TextField), findsNothing);
        expect(character.fields['CharacterName'], 'Updated name');

        // Il sistema comunica la chiusura della tastiera tramite le metriche.
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await goBack();
        expect(find.byType(SheetScreen), findsNothing);
        expect(find.text('Character list'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        driveSync.dispose();
      },
    );
  }
}

class _FakeRepository extends CharacterRepository {
  Character? savedCharacter;

  @override
  Future<void> saveCharacter(Character character) async {
    savedCharacter = character.copy();
  }

  @override
  Future<void> createSnapshot(Character character, String reason) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
