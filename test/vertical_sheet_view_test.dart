import 'package:dnd_sheet_archive/controllers/sheet_controller.dart';
import 'package:dnd_sheet_archive/data/character_repository.dart';
import 'package:dnd_sheet_archive/data/local_archive_sync_store.dart';
import 'package:dnd_sheet_archive/data/sheet_view_preferences.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:dnd_sheet_archive/models/sheet_field.dart';
import 'package:dnd_sheet_archive/models/vertical_sheet_schema.dart';
import 'package:dnd_sheet_archive/screens/sheet_screen.dart';
import 'package:dnd_sheet_archive/sync/archive_sync_tracker.dart';
import 'package:dnd_sheet_archive/sync/google_drive_sync_service.dart';
import 'package:dnd_sheet_archive/theme/sheet_palette.dart';
import 'package:dnd_sheet_archive/widgets/sheet_page.dart';
import 'package:dnd_sheet_archive/widgets/vertical_sheet_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'vertical schema maps every field in fields.json without duplicates',
    () async {
      final pages = await SheetFieldDef.loadByPage();
      final pdfFields = [for (final page in pages) ...page];
      final pdfByName = {for (final field in pdfFields) field.name: field};

      final mappedNames = allVerticalSheetFieldNames();
      expect(mappedNames.toSet().length, mappedNames.length);

      final mappedWithSyncedName = {...mappedNames, 'CharacterName 2'};
      expect(mappedWithSyncedName, pdfByName.keys.toSet());

      for (final skill in verticalSkills) {
        expect(
          pdfByName[skill.checkboxField]?.supportsExpertise,
          isTrue,
          reason: skill.checkboxField,
        );
        expect(
          pdfByName[skill.valueField]?.type,
          SheetFieldType.text,
          reason: skill.valueField,
        );
      }
      for (final ability in verticalAbilities) {
        expect(
          pdfByName[ability.saveCheckbox]?.supportsExpertise,
          isFalse,
          reason: ability.saveCheckbox,
        );
      }
      for (final level in verticalSpellLevels) {
        for (final slot in level.spells) {
          expect(pdfByName[slot.nameField]?.type, SheetFieldType.text);
          if (slot.preparedCheckbox != null) {
            expect(
              pdfByName[slot.preparedCheckbox!]?.type,
              SheetFieldType.checkbox,
            );
            expect(
              pdfByName[slot.preparedCheckbox!]?.supportsExpertise,
              isFalse,
            );
          }
        }
      }
    },
  );

  for (final size in [const Size(390, 844), const Size(320, 640)]) {
    testWidgets(
      'vertical sheet renders cleanly without overflow on ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final controller = SheetController(
          repository: _FakeRepository(),
          character: Character(
            id: 'c1',
            name: 'Arannis',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            locked: false,
            fields: {
              'CharacterName': 'Arannis',
              'ClassLevel': 'Mago 5',
              'AC': '15',
              'HPCurrent': '32',
              'HPMax': '32',
              'STR': '10',
              'STRmod': '+0',
            },
          ),
        );
        addTearDown(controller.dispose);

        for (final palette in [
          SheetPalette.lightColored,
          SheetPalette.darkColored,
        ]) {
          final brightness = palette == SheetPalette.darkColored
              ? Brightness.dark
              : Brightness.light;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness, extensions: [palette]),
              home: Scaffold(
                backgroundColor: palette.workspace,
                body: VerticalSheetView(controller: controller),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Identità'), findsOneWidget);
          expect(find.text('Combattimento'), findsOneWidget);
          expect(find.text('Incantesimi'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets(
    'editing, inline markdown, expertise checkboxes, comments, and lock work in vertical view',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final character = Character(
        id: 'c1',
        name: 'Arannis',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        locked: false,
        fields: {'CharacterName': 'Arannis'},
      );
      final controller = SheetController(
        repository: _FakeRepository(),
        character: character,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [SheetPalette.lightColored]),
          home: Scaffold(body: VerticalSheetView(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      // Modifica il nome e verifica la sincronizzazione di CharacterName e CharacterName 2.
      final nameField = find.byKey(const ValueKey('CharacterName'));
      await tester.tap(nameField);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Lyra');
      await tester.pump();
      expect(character.name, 'Lyra');
      expect(character.fields['CharacterName'], 'Lyra');
      expect(character.fields['CharacterName 2'], 'Lyra');

      // Modifica un campo con markdown inline e verifica il rendering a fuoco perso.
      final acField = find.byKey(const ValueKey('AC'));
      await tester.ensureVisible(acField);
      await tester.tap(acField);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '**18**');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(character.fields['AC'], '**18**');
      final richText = tester.widget<RichText>(
        find.descendant(of: acField, matching: find.byType(RichText)),
      );
      final plain = richText.text.toPlainText();
      expect(plain, '18');

      // Aggiunge un commento con pressione prolungata.
      await tester.longPress(acField);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Con scudo');
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();
      expect(controller.commentFor('AC'), 'Con scudo');

      // Tiro salvezza: 2 stati (unchecked -> proficient -> unchecked).
      final strSaveBox = find.byKey(const ValueKey('Check Box 11'));
      await tester.ensureVisible(strSaveBox);
      await tester.tap(strSaveBox);
      await tester.pump();
      expect(
        SheetCheckboxValue.fromStored(controller.valueFor('Check Box 11')),
        SheetCheckboxValue.proficient,
      );
      await tester.tap(strSaveBox);
      await tester.pump();
      expect(
        SheetCheckboxValue.fromStored(controller.valueFor('Check Box 11')),
        SheetCheckboxValue.unchecked,
      );

      // Abilità: 3 stati (unchecked -> proficient -> expertise -> unchecked).
      final acrobaticsBox = find.byKey(const ValueKey('Check Box 23'));
      await tester.ensureVisible(acrobaticsBox);
      await tester.tap(acrobaticsBox);
      await tester.pump();
      expect(
        SheetCheckboxValue.fromStored(controller.valueFor('Check Box 23')),
        SheetCheckboxValue.proficient,
      );
      await tester.tap(acrobaticsBox);
      await tester.pump();
      expect(
        SheetCheckboxValue.fromStored(controller.valueFor('Check Box 23')),
        SheetCheckboxValue.expertise,
      );
      await tester.tap(acrobaticsBox);
      await tester.pump();
      expect(
        SheetCheckboxValue.fromStored(controller.valueFor('Check Box 23')),
        SheetCheckboxValue.unchecked,
      );

      // Blocca la scheda: niente modifiche, ma le note restano leggibili.
      await controller.toggleLock();
      await tester.pumpAndSettle();
      await tester.tap(acrobaticsBox);
      await tester.pump();
      expect(
        SheetCheckboxValue.fromStored(controller.valueFor('Check Box 23')),
        SheetCheckboxValue.unchecked,
      );
      await tester.ensureVisible(acField);
      await tester.longPress(acField);
      await tester.pumpAndSettle();
      expect(find.text('Con scudo'), findsOneWidget);
      expect(find.text('Chiudi'), findsOneWidget);
      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('spell levels auto-expand when filled and can reveal all rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = SheetController(
      repository: _FakeRepository(),
      character: Character(
        id: 'c1',
        name: 'Elminster',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        locked: false,
        fields: {
          'SlotsTotal 21': '2',
          'SlotsRemaining 21': '1',
          'Spells 1048': 'Palla di fuoco',
          'Check Box 315': true,
        },
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VerticalSheetView(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    // Salta agli incantesimi tramite la barra superiore.
    final spellsTab = find.text('Incantesimi').first;
    await tester.ensureVisible(spellsTab);
    await tester.tap(spellsTab);
    await tester.pumpAndSettle();

    // Il livello 3 è già aperto perché contiene dati; mostra la riga piena e
    // la prima riga vuota, più il pulsante per mostrare tutte le 13 righe.
    final fireball = find.byKey(const ValueKey('Spells 1048'));
    await tester.ensureVisible(fireball);
    expect(fireball, findsOneWidget);
    expect(find.byKey(const ValueKey('Spells 1047')), findsOneWidget);
    expect(find.byKey(const ValueKey('Spells 1059')), findsNothing);

    final showAll = find.text('Mostra tutti gli spazi (13)');
    await tester.ensureVisible(showAll);
    await tester.tap(showAll);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('Spells 1059')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('SheetScreen switches to vertical view and preserves edits', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final database = (await tester.runAsync(
      () => databaseFactoryMemory.openDatabase('sheet-screen-vertical.db'),
    ))!;
    addTearDown(() => tester.runAsync(database.close));
    final driveSync = GoogleDriveSyncService(
      LocalArchiveSyncStore(database),
      syncTracker: ArchiveSyncTracker.inMemory(),
    );
    final preferences = SheetViewPreferences.inMemory();
    addTearDown(preferences.dispose);
    final character = Character(
      id: 'character',
      name: 'Arannis',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      locked: false,
      fields: {'CharacterName': 'Arannis'},
    );
    await tester.runAsync(SheetFieldDef.loadByPage);

    await tester.pumpWidget(
      SheetViewPreferenceScope(
        preferences: preferences,
        child: MaterialApp(
          home: SheetScreen(
            character: character,
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

    expect(find.byType(SheetPage), findsOneWidget);
    expect(find.byType(VerticalSheetView), findsNothing);

    // Passa alla vista verticale dal menù Visualizzazione scheda.
    await tester.tap(find.byTooltip('Visualizzazione scheda'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        CheckedPopupMenuItem<SheetViewMode>,
        SheetViewMode.vertical.label,
      ),
    );
    await tester.pumpAndSettle();

    expect(preferences.mode, SheetViewMode.vertical);
    expect(find.byType(VerticalSheetView), findsOneWidget);
    expect(find.byTooltip('Pagina successiva'), findsNothing);

    final acField = find.byKey(const ValueKey('AC'));
    await tester.ensureVisible(acField);
    await tester.tap(acField);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '17');
    await tester.pump();

    // Torna alla vista a pagine e verifica che il valore sia conservato.
    await tester.tap(find.byTooltip('Visualizzazione scheda'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        CheckedPopupMenuItem<SheetViewMode>,
        SheetViewMode.pages.label,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SheetPage), findsOneWidget);
    expect(
      tester
          .widget<SheetPage>(find.byType(SheetPage))
          .controller
          .valueFor('AC'),
      '17',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    driveSync.dispose();
  });
}

class _FakeRepository extends CharacterRepository {
  @override
  Future<void> saveCharacter(Character character) async {}

  @override
  Future<void> createSnapshot(Character character, String reason) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
