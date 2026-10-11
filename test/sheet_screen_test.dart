import 'package:dnd_sheet_archive/data/character_repository.dart';
import 'package:dnd_sheet_archive/data/local_archive_sync_store.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:dnd_sheet_archive/models/sheet_field.dart';
import 'package:dnd_sheet_archive/models/sheet_layout.dart';
import 'package:dnd_sheet_archive/screens/sheet_screen.dart';
import 'package:dnd_sheet_archive/sync/archive_sync_tracker.dart';
import 'package:dnd_sheet_archive/sync/google_drive_sync_service.dart';
import 'package:dnd_sheet_archive/widgets/sheet_page.dart';
import 'package:dnd_sheet_archive/widgets/scrollable_sheet_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> chooseViewMode(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Visualizzazione scheda'));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate(
              (widget) => widget is PopupMenuItem,
            ),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

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
      const visibleBottom = 400.0 - 300.0;
      expect(pageRect.width, greaterThan(0));
      expect(pageRect.height, greaterThan(0));
      expect(pageRect.top, greaterThanOrEqualTo(0));
      expect(pageRect.bottom, lessThanOrEqualTo(visibleBottom));
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
    await chooseViewMode(tester, 'A scorrimento');
    await tester.tapAt(tester.getCenter(name));
    await tester.pumpAndSettle();
    tester.view.viewInsets = FakeViewPadding(
      bottom: 300 * tester.view.devicePixelRatio,
    );
    await tester.binding.setSurfaceSize(const Size(800, 400));
    await tester.pumpAndSettle();
    final scrollingField = tester.getRect(find.byType(TextField));
    expect(scrollingField.bottom, lessThanOrEqualTo(100));
    expect(scrollingField.top, greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
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

        Future<void> swipePage(bool forward) async {
          await tester.drag(
            find.byType(PageView),
            Offset((forward ? -1 : 1) * width * .8, 0),
          );
          await tester.pumpAndSettle();
        }

        SheetPage currentPage() => tester.widget(find.byType(SheetPage));
        expect(find.byType(SheetPage), findsOneWidget);
        expect(currentPage().pageIndex, 0);
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar,
          isNull,
        );
        expect(find.byTooltip('Pagina successiva'), findsNothing);
        expect(find.byTooltip('Pagina precedente'), findsNothing);
        expect(find.byType(InteractiveViewer), findsNothing);
        expect(find.byTooltip('Aumenta zoom'), findsNothing);
        expect(find.byTooltip('Riduci zoom'), findsNothing);
        void expectPageFits() {
          final rect = tester.getRect(find.byType(SheetPage));
          final pagerRect = tester.getRect(find.byType(PageView));
          final scale =
              (pagerRect.width / sheetPageWidth) <
                  (pagerRect.height / sheetPageHeight)
              ? pagerRect.width / sheetPageWidth
              : pagerRect.height / sheetPageHeight;
          expect(rect.width, closeTo(sheetPageWidth * scale, .01));
          expect(rect.height, closeTo(sheetPageHeight * scale, .01));
          expect(rect.left, greaterThanOrEqualTo(pagerRect.left - .01));
          expect(rect.right, lessThanOrEqualTo(pagerRect.right + .01));
          expect(rect.top, greaterThanOrEqualTo(pagerRect.top - .01));
          expect(rect.bottom, lessThanOrEqualTo(pagerRect.bottom + .01));
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
          expectPageFits();
        }
        await swipePage(true);
        expect(find.byType(TextField), findsNothing);
        if (!locked) {
          expect(tester.testTextInput.isVisible, isFalse);
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
        }
        expect(find.byType(SheetPage), findsOneWidget);
        expect(currentPage().pageIndex, 1);

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

        await chooseViewMode(tester, 'A scorrimento');
        expect(find.byType(ScrollableSheetView), findsOneWidget);
        expect(find.byType(SheetPage), findsNWidgets(sheetPageCount));
        expect(find.byType(InteractiveViewer), findsOneWidget);
        expect(find.byTooltip('Aumenta zoom'), findsOneWidget);
        if (!locked) {
          expect(
            tester
                .widget<SheetPage>(find.byType(SheetPage).first)
                .controller
                .valueFor('CharacterName'),
            'Arannis',
          );
        }
        await chooseViewMode(tester, 'A pagine');
        expect(currentPage().pageIndex, 1);
        expect(find.byType(InteractiveViewer), findsNothing);
        expectPageFits();

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
        await swipePage(true);
        expect(currentPage().pageIndex, 2);
        await swipePage(true);
        expect(currentPage().pageIndex, 2);
        expectPageFits();
        await tester.binding.setSurfaceSize(Size(width, 400));
        await tester.pumpAndSettle();
        expectPageFits();
        await tester.binding.setSurfaceSize(Size(width, 800));
        await tester.pumpAndSettle();

        await swipePage(false);
        await swipePage(false);
        expect(currentPage().pageIndex, 0);
        await swipePage(false);
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

      await chooseViewMode(tester, 'A scorrimento');
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
