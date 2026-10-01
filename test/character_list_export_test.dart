import 'dart:async';

import 'package:dnd_sheet_archive/data/character_repository.dart';
import 'package:dnd_sheet_archive/data/local_archive_sync_store.dart';
import 'package:dnd_sheet_archive/export/character_pdf_exporter.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:dnd_sheet_archive/screens/character_list_screen.dart';
import 'package:dnd_sheet_archive/sync/archive_sync_tracker.dart';
import 'package:dnd_sheet_archive/sync/google_drive_sync_service.dart';
import 'package:dnd_sheet_archive/widgets/character_export_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

class _Repository extends CharacterRepository {
  final characters = [
    for (final name in ['Arannis', 'Thorin'])
      Character(
        id: name,
        name: name,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        locked: false,
        fields: {'STR': name == 'Arannis' ? '18' : '12'},
      ),
  ];

  @override
  Stream<List<CharacterSummary>> watchCharacters() => Stream.value([
    for (final character in characters)
      CharacterSummary.fromJson(character.toJson()),
  ]);

  @override
  Future<Character?> getCharacter(String id) async =>
      characters.where((character) => character.id == id).firstOrNull?.copy();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Exporter extends CharacterPdfExporter {
  final calls = <List<Character>>[];
  bool result = true;
  bool fail = false;
  Completer<bool>? pending;

  @override
  Future<bool> exportCharacters(List<Character> characters) async {
    calls.add(characters);
    if (fail) throw StateError('disk full');
    return pending?.future ?? result;
  }
}

Future<GoogleDriveSyncService> _show(
  WidgetTester tester,
  _Repository repository,
  _Exporter exporter,
) async {
  final database = await databaseFactoryMemory.openDatabase('list-export.db');
  addTearDown(database.close);
  final tracker = ArchiveSyncTracker.inMemory();
  addTearDown(tracker.dispose);
  final drive = GoogleDriveSyncService(
    LocalArchiveSyncStore(database),
    syncTracker: tracker,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: CharacterListScreen(
        repository: repository,
        driveSync: drive,
        pdfExporter: exporter,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return drive;
}

Future<void> _openExport(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Esporta schede in PDF'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(CharacterExportDialog), findsOneWidget);
}

void main() {
  testWidgets('empty archive reports that there is nothing to export', (
    tester,
  ) async {
    final repository = _Repository()..characters.clear();
    final exporter = _Exporter();
    final drive = await _show(tester, repository, exporter);
    await tester.tap(find.byTooltip('Esporta schede in PDF'));
    await tester.pumpAndSettle();
    expect(find.text('Nessuna scheda da esportare.'), findsOneWidget);
    expect(exporter.calls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    drive.dispose();
  });

  testWidgets('selection fits a compact phone viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final drive = await _show(tester, _Repository(), _Exporter());
    await _openExport(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    drive.dispose();
  });

  testWidgets(
    'selects one or several characters, preserving list order and values',
    (tester) async {
      final exporter = _Exporter();
      final drive = await _show(tester, _Repository(), exporter);
      await _openExport(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Esporta (0)'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('export-Thorin')));
      await tester.pump();
      await tester.tap(find.text('Esporta (1)'));
      await tester.pumpAndSettle();
      expect(exporter.calls.single.single.name, 'Thorin');
      expect(exporter.calls.single.single.fields['STR'], '12');
      expect(find.text('Scheda esportata in PDF compilabile.'), findsOneWidget);

      await _openExport(tester);
      await tester.tap(find.text('Seleziona tutte'));
      await tester.pump();
      await tester.tap(find.text('Esporta (2)'));
      await tester.pumpAndSettle();
      expect(exporter.calls.last.map((character) => character.name), [
        'Arannis',
        'Thorin',
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
      drive.dispose();
    },
  );

  testWidgets('select all toggles off and cancel does not export', (
    tester,
  ) async {
    final exporter = _Exporter();
    final drive = await _show(tester, _Repository(), exporter);
    await _openExport(tester);
    await tester.tap(find.text('Seleziona tutte'));
    await tester.pump();
    expect(find.text('Esporta (2)'), findsOneWidget);
    await tester.tap(find.text('Seleziona tutte'));
    await tester.pump();
    expect(find.text('Esporta (0)'), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(exporter.calls, isEmpty);
    expect(find.byTooltip('Esporta schede in PDF'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    drive.dispose();
  });

  testWidgets(
    'row menu exports directly and blocks duplicate exports while saving',
    (tester) async {
      final exporter = _Exporter()..pending = Completer<bool>();
      final drive = await _show(tester, _Repository(), exporter);
      final row = find.ancestor(
        of: find.text('Arannis'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.more_vert)).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Esporta PDF'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(exporter.calls.single.single.name, 'Arannis');
      expect(find.byType(CharacterExportDialog), findsNothing);
      expect(find.byTooltip('Esporta schede in PDF'), findsNothing);
      exporter.pending!.complete(true);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Esporta schede in PDF'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      drive.dispose();
    },
  );

  testWidgets('save cancellation and errors leave export available', (
    tester,
  ) async {
    final exporter = _Exporter()..result = false;
    final drive = await _show(tester, _Repository(), exporter);
    await _openExport(tester);
    await tester.tap(find.text('Seleziona tutte'));
    await tester.pump();
    await tester.tap(find.text('Esporta (2)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('esportate in PDF'), findsNothing);
    exporter.fail = true;
    await _openExport(tester);
    await tester.tap(find.text('Seleziona tutte'));
    await tester.pump();
    await tester.tap(find.text('Esporta (2)'));
    await tester.pumpAndSettle();
    expect(
      find.text('Esportazione PDF non riuscita. Riprova.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Esporta schede in PDF'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    drive.dispose();
  });

  testWidgets(
    'a character deleted during selection cannot silently disappear from export',
    (tester) async {
      final repository = _Repository();
      final exporter = _Exporter();
      final drive = await _show(tester, repository, exporter);
      await _openExport(tester);
      await tester.tap(find.text('Seleziona tutte'));
      await tester.pump();
      repository.characters.removeLast();
      await tester.tap(find.text('Esporta (2)'));
      await tester.pumpAndSettle();
      expect(exporter.calls, isEmpty);
      expect(
        find.text('Esportazione PDF non riuscita. Riprova.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      drive.dispose();
    },
  );
}
