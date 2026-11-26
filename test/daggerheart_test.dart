import 'dart:convert';

import 'package:dnd_sheet_archive/data/local_archive_sync_store.dart';
import 'package:dnd_sheet_archive/data/sembast_character_repository.dart';
import 'package:dnd_sheet_archive/data/sheet_view_preferences.dart';
import 'package:dnd_sheet_archive/export/character_pdf_exporter.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:dnd_sheet_archive/models/character_merge.dart';
import 'package:dnd_sheet_archive/models/daggerheart_card.dart';
import 'package:dnd_sheet_archive/models/game_system.dart';
import 'package:dnd_sheet_archive/models/sheet_document.dart';
import 'package:dnd_sheet_archive/screens/character_list_screen.dart';
import 'package:dnd_sheet_archive/screens/sheet_screen.dart';
import 'package:dnd_sheet_archive/sync/archive_sync_tracker.dart';
import 'package:dnd_sheet_archive/sync/google_drive_sync_service.dart';
import 'package:dnd_sheet_archive/widgets/daggerheart_cards_page.dart';
import 'package:dnd_sheet_archive/widgets/daggerheart_vertical_sheet_view.dart';
import 'package:dnd_sheet_archive/widgets/sheet_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads all 269 Daggerheart cards and class sheet documents', () async {
    final catalog = await DaggerheartCardDef.loadCatalog();
    expect(catalog.length, 269);
    expect(catalog.map((c) => c.id).toSet().length, 269);
    expect(
      catalog.where((c) => c.category == DaggerheartCardCategory.ancestry),
      hasLength(18),
    );
    expect(
      catalog.where((c) => c.category == DaggerheartCardCategory.community),
      hasLength(9),
    );
    expect(
      catalog.where((c) => c.category == DaggerheartCardCategory.subclass),
      hasLength(54),
    );
    expect(
      catalog.where((c) => c.category == DaggerheartCardCategory.domain),
      hasLength(188),
    );

    final expectedPdfPages = <DaggerheartClass, int>{
      DaggerheartClass.bard: 2,
      DaggerheartClass.druid: 4,
      DaggerheartClass.guardian: 2,
      DaggerheartClass.ranger: 3,
      DaggerheartClass.rogue: 2,
      DaggerheartClass.seraph: 2,
      DaggerheartClass.sorcerer: 2,
      DaggerheartClass.warrior: 2,
      DaggerheartClass.wizard: 2,
      DaggerheartClass.blank: 1,
    };
    for (final entry in expectedPdfPages.entries) {
      final doc = await SheetDocumentDef.loadFor(
        Character(
          id: 'dh-${entry.key.id}',
          name: 'Test',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          locked: false,
          system: GameSystem.daggerheart,
          daggerheartClass: entry.key,
        ),
      );
      expect(doc.pdfPageCount, entry.value);
      expect(doc.hasCardsPage, isTrue);
      expect(doc.totalPageCount, entry.value + 1);
      expect(doc.pages.first.fields, isNotEmpty);
    }
  });

  test(
    'repository, snapshots, and CRDT merge preserve Daggerheart data and cards',
    () async {
      final db = await databaseFactoryMemory.openDatabase('dh-repo-merge.db');
      addTearDown(db.close);
      final repo = SembastCharacterRepository(db);

      final created = await repo.createCharacter(
        'Lyra',
        system: GameSystem.daggerheart,
        daggerheartClass: DaggerheartClass.bard,
      );
      expect(created.system, GameSystem.daggerheart);
      expect(created.daggerheartClass, DaggerheartClass.bard);
      expect(created.fields['CharacterName'], 'Lyra');
      expect(created.fields.containsKey('CharacterName 2'), isFalse);

      final summaries = await repo.watchCharacters().first;
      expect(summaries.single.system, GameSystem.daggerheart);
      expect(summaries.single.daggerheartClass, DaggerheartClass.bard);
      expect(summaries.single.systemSubtitle, 'Daggerheart · Bard');

      // Simulate two devices concurrently editing different fields & selecting different cards.
      final deviceA = created.copy()
        ..fields['DH_Evasion'] = '11'
        ..fields[daggerheartCardFieldKey('core_001')] = true;
      stampCharacterChanges(
        before: created,
        after: deviceA,
        now: DateTime.utc(2026, 1, 1, 10),
      );

      final deviceB = created.copy()
        ..fields['DH_Level'] = '2'
        ..fields[daggerheartCardFieldKey('core_073')] = true;
      stampCharacterChanges(
        before: created,
        after: deviceB,
        now: DateTime.utc(2026, 1, 1, 10, 5),
      );

      final merged = mergeCharacters(deviceA, deviceB);
      expect(merged.system, GameSystem.daggerheart);
      expect(merged.daggerheartClass, DaggerheartClass.bard);
      expect(merged.fields['DH_Evasion'], '11');
      expect(merged.fields['DH_Level'], '2');
      expect(selectedDaggerheartCardsFromFields(merged.fields).keys.toSet(), {
        'core_001',
        'core_073',
      });
    },
  );

  test(
    'exports a Daggerheart character with fillable fields and selected cards to PDF',
    () async {
      final character = Character(
        id: 'dh-export',
        name: 'Lyra',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        locked: false,
        system: GameSystem.daggerheart,
        daggerheartClass: DaggerheartClass.bard,
        fields: {
          'CharacterName': 'Lyra',
          'DH_Pronouns': 'lei',
          'DH_Evasion': '10',
          'DH_HP_1': true,
          'DH_Hope_1': true,
          daggerheartCardFieldKey('core_001'): true,
          daggerheartCardFieldKey('core_073'): true,
        },
      );
      String? savedFilename;
      final exporter = CharacterPdfExporter(
        saveFile: (bytes, filename) async {
          savedFilename = filename;
          expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
          expect(bytes.length, greaterThan(100000));
          return true;
        },
      );
      expect(await exporter.exportCharacters([character]), isTrue);
      expect(savedFilename, 'Lyra.pdf');
      expect(
        CharacterPdfExporter.filenameFor([character, character]),
        'schede-daggerheart.pdf',
      );
    },
  );

  testWidgets(
    'creating a new character lets the user choose D&D 5e or Daggerheart + class',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final db = await databaseFactoryMemory.openDatabase('dh-create-ui.db');
      addTearDown(db.close);
      final repo = SembastCharacterRepository(db);
      final drive = GoogleDriveSyncService(
        LocalArchiveSyncStore(db),
        syncTracker: ArchiveSyncTracker.inMemory(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CharacterListScreen(repository: repo, driveSync: drive),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Nuovo personaggio'));
      await tester.pumpAndSettle();

      // Default is D&D 5e: class selector should not be visible yet.
      expect(
        find.byKey(const ValueKey('new-character-dh-class')),
        findsNothing,
      );

      // Switch to Daggerheart.
      await tester.tap(find.text('Daggerheart'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('new-character-dh-class')),
        findsOneWidget,
      );

      // Pick Ranger class.
      await tester.tap(find.byKey(const ValueKey('new-character-dh-class')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Ranger').last);
      await tester.pumpAndSettle();

      // Pre-load Ranger sheet definition so the real isolate does not stall pumpAndSettle.
      await tester.runAsync(
        () => SheetDocumentDef.loadFor(
          Character(
            id: 'preload',
            name: 'Preload',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            locked: false,
            system: GameSystem.daggerheart,
            daggerheartClass: DaggerheartClass.ranger,
          ),
        ),
      );

      // Enter character name and save.
      await tester.enterText(
        find.byKey(const ValueKey('new-character-name')),
        'Kaelen',
      );
      await tester.tap(find.text('Salva'));
      // Sembast writes asynchronously before SheetScreen mounts and loads assets.
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        if (find.text('1 / 4 · Scheda').evaluate().isNotEmpty) break;
      }

      // Opens directly into SheetScreen with 4 pages (Main, Companion, Guide, Cards).
      expect(find.byType(SheetScreen), findsOneWidget);
      expect(find.text('1 / 4 · Scheda'), findsOneWidget);

      final saved = (await tester.runAsync(
        () => repo.watchCharacters().first,
      ))!;
      expect(saved.single.name, 'Kaelen');
      expect(saved.single.system, GameSystem.daggerheart);
      expect(saved.single.daggerheartClass, DaggerheartClass.ranger);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      drive.dispose();
    },
  );

  testWidgets(
    'Daggerheart sheet allows editing fields and selecting cards on the dedicated Cards page',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final db = await databaseFactoryMemory.openDatabase('dh-sheet-cards.db');
      addTearDown(db.close);
      final repo = SembastCharacterRepository(db);
      final drive = GoogleDriveSyncService(
        LocalArchiveSyncStore(db),
        syncTracker: ArchiveSyncTracker.inMemory(),
      );
      final character = (await tester.runAsync(
        () => repo.createCharacter(
          'Lyra',
          system: GameSystem.daggerheart,
          daggerheartClass: DaggerheartClass.bard,
        ),
      ))!;
      final viewPrefs = SheetViewPreferences.inMemory(
        mode: SheetViewMode.pages,
      );

      await tester.runAsync(() => SheetDocumentDef.loadFor(character));
      await tester.runAsync(DaggerheartCardDef.loadCatalog);

      await tester.pumpWidget(
        SheetViewPreferenceScope(
          preferences: viewPrefs,
          child: MaterialApp(
            home: SheetScreen(
              character: character,
              repository: repo,
              driveSync: drive,
            ),
          ),
        ),
      );
      for (var attempt = 0; attempt < 50; attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        if (find.byType(SheetPage).evaluate().isNotEmpty) break;
      }

      // Page 1: Fillable Bard sheet.
      expect(find.byType(SheetPage), findsOneWidget);
      expect(find.text('1 / 3 · Scheda'), findsOneWidget);

      // Edit a fillable text field (Pronouns) and check a checkbox (HP 1).
      final pronounsField = find.byKey(const ValueKey('DH_Pronouns'));
      await tester.tapAt(tester.getCenter(pronounsField));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'lei');
      await tester.pumpAndSettle();
      expect(character.fields['DH_Pronouns'], 'lei');

      final hp1 = find.byKey(const ValueKey('DH_HP_1'));
      await tester.tapAt(tester.getCenter(hp1));
      await tester.pumpAndSettle();
      expect(character.fields['DH_HP_1'], isTrue);

      // Navigate to page 2 (Guide) then page 3 (Cards).
      await tester.tap(find.byTooltip('Pagina successiva'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3 · Guida & Livelli'), findsOneWidget);

      await tester.tap(find.byTooltip('Pagina successiva'));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3 · Card'), findsOneWidget);
      expect(find.byType(DaggerheartCardsPage), findsOneWidget);
      expect(find.text('Nessuna card selezionata'), findsOneWidget);

      // Switch to catalog, filter by search, and select Highborne (core_073).
      await tester.tap(find.byKey(const ValueKey('dh-open-catalog-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('dh-cards-search')),
        'Highborne',
      );
      await tester.pumpAndSettle();

      final highborne = find.byKey(const ValueKey('dh-card-core_073'));
      expect(highborne, findsOneWidget);
      await tester.tap(highborne);
      await tester.pumpAndSettle();

      expect(character.fields[daggerheartCardFieldKey('core_073')], isTrue);
      expect(find.text('Le mie card (1)'), findsOneWidget);

      // Switch back to "Le mie card" and verify Highborne is shown.
      await tester.tap(find.text('Le mie card (1)'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dh-card-core_073')), findsOneWidget);

      // Switch to Scroll view and verify Card toggle button works.
      await tester.tap(find.byTooltip('Visualizzazione scheda'));
      await tester.pumpAndSettle();
      expect(find.text('Verticale'), findsOneWidget);
      await tester.tap(
        find
            .ancestor(
              of: find.text('A scorrimento'),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dh-scroll-cards-toggle')),
        findsOneWidget,
      );
      expect(find.text('Card (1)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('dh-scroll-cards-toggle')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('daggerheart-cards-page-scroll')),
        findsOneWidget,
      );

      // Switch to Vertical view and verify fields, edits, and Cards access work.
      await tester.tap(find.byKey(const ValueKey('dh-scroll-cards-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Visualizzazione scheda'));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('Verticale'),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(DaggerheartVerticalSheetView), findsOneWidget);
      expect(find.text('lei', findRichText: true), findsOneWidget);

      // Edit Evasion in vertical view and verify it persists.
      await tester.tap(find.byKey(const ValueKey('DH_Evasion')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '12');
      await tester.pumpAndSettle();
      expect(character.fields['DH_Evasion'], '12');

      // Open Cards from vertical view via the top toggle.
      await tester.tap(find.byKey(const ValueKey('dh-scroll-cards-toggle')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('daggerheart-cards-page-vertical')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('dh-card-core_073')), findsOneWidget);

      // Wait for debounced autosave and let Sembast finish writing.
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      final persisted = await tester.runAsync(
        () => repo.getCharacter(character.id),
      );
      expect(persisted?.fields['DH_Pronouns'], 'lei');
      expect(persisted?.fields['DH_Evasion'], '12');
      expect(persisted?.fields['DH_HP_1'], isTrue);
      expect(persisted?.fields[daggerheartCardFieldKey('core_073')], isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      drive.dispose();
    },
  );

  testWidgets('Daggerheart vertical view renders cleanly on 390x844 phone viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = await databaseFactoryMemory.openDatabase('dh-vertical-phone.db');
    addTearDown(db.close);
    final repo = SembastCharacterRepository(db);
    final drive = GoogleDriveSyncService(
      LocalArchiveSyncStore(db),
      syncTracker: ArchiveSyncTracker.inMemory(),
    );
    final character = (await tester.runAsync(
      () => repo.createCharacter(
        'Kaelen',
        system: GameSystem.daggerheart,
        daggerheartClass: DaggerheartClass.ranger,
      ),
    ))!;
    character.fields[daggerheartCardFieldKey('core_073')] = true;
    await tester.runAsync(() => repo.saveCharacter(character));
    final viewPrefs = SheetViewPreferences.inMemory(
      mode: SheetViewMode.vertical,
    );

    await tester.runAsync(DaggerheartCardDef.loadCatalog);
    await tester.pumpWidget(
      SheetViewPreferenceScope(
        preferences: viewPrefs,
        child: MaterialApp(
          home: SheetScreen(
            character: character,
            repository: repo,
            driveSync: drive,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DaggerheartVerticalSheetView), findsOneWidget);
    expect(find.text('Compagno'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Jump to Tratti: empty experience rows are hidden until added, Gold steppers update checkboxes.
    await tester.ensureVisible(find.text('Tratti'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tratti'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('DH_Experience_1')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('dh-add-experience')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dh-add-experience')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('DH_Experience_1')), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('dh-gold-handful-inc')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dh-gold-handful-inc')));
    await tester.pumpAndSettle();
    expect(character.fields['DH_GoldHandful_1'], isTrue);

    // Jump to Zaino: Inventory is a single multiline box synced with DH_Inventory_1..5.
    await tester.ensureVisible(find.text('Zaino'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zaino'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('DH_Inventory_Multiline')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Torcia\nCorda 15m');
    await tester.pumpAndSettle();
    expect(character.fields['DH_Inventory_1'], 'Torcia');
    expect(character.fields['DH_Inventory_2'], 'Corda 15m');

    // Jump to Guida: Background Questions start collapsed.
    await tester.ensureVisible(find.text('Guida'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guida'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('DH_Background_1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dh-section-background')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('DH_Background_1')), findsOneWidget);

    // Jump to the Card section chip at the end of the sheet: tapping a card zooms it,
    // while the Modifica button stays available to manage the card list.
    await tester.ensureVisible(find.text('Card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('dh-vertical-manage-cards')),
      findsOneWidget,
    );
    expect(find.text('Modifica'), findsOneWidget);
    final cardTile = find.byKey(const ValueKey('dh-vertical-card-core_073'));
    await tester.ensureVisible(cardTile);
    await tester.pumpAndSettle();
    await tester.tap(cardTile);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('dh-card-preview-dialog')),
      findsOneWidget,
    );
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('Chiudi'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
    drive.dispose();
  });
}
