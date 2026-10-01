import 'dart:async';

import 'package:dnd_sheet_archive/controllers/sheet_controller.dart';
import 'package:dnd_sheet_archive/data/local_archive_sync_store.dart';
import 'package:dnd_sheet_archive/data/sembast_character_repository.dart';
import 'package:dnd_sheet_archive/models/archive_sync_data.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:dnd_sheet_archive/models/sheet_field.dart';
import 'package:dnd_sheet_archive/widgets/sheet_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late SembastCharacterRepository repository;
  late Character character;
  SheetController? controller;
  var now = DateTime.utc(2026, 9, 29, 10);

  setUp(() async {
    now = DateTime.utc(2026, 9, 29, 10);
    await databaseFactoryMemory.deleteDatabase('sheet-sync.db');
    database = await databaseFactoryMemory.openDatabase('sheet-sync.db');
    repository = SembastCharacterRepository(database, now: () => now);
    character = await repository.createCharacter('Minsc');
    character.fields['AC'] = '10';
    await repository.saveCharacter(character);
  });

  tearDown(() async {
    controller?.dispose();
    controller = null;
    await database.close();
  });

  SheetController open([SembastCharacterRepository? repo]) => controller =
      SheetController(repository: repo ?? repository, character: character);

  Future<void> receive(Character remote) async {
    now = now.add(const Duration(minutes: 1));
    remote.updatedAt = now;
    await LocalArchiveSyncStore(
      database,
    ).mergeAndReplace(ArchiveSyncData(generatedAt: now, characters: [remote]));
  }

  test(
    'an open clean sheet receives Drive values without becoming dirty',
    () async {
      final sheet = open();
      final updated = _when(sheet, () => sheet.valueFor('AC') == '20');
      final remote = character.copy()..fields['AC'] = '20';
      remote.comments['AC'] = 'Magic shield';
      await receive(remote);
      await updated;
      expect(sheet.commentFor('AC'), 'Magic shield');
      expect(sheet.dirtyState.value, isFalse);
      await sheet.close();
    },
  );

  test(
    'incoming Drive values preserve unsaved local fields and comments',
    () async {
      final remote = character.copy()
        ..fields['AC'] = '20'
        ..comments['AC'] = 'Remote shield';
      final sheet = open();
      sheet.setText('STR', '18');
      sheet.setComment('STR', 'Local strength');
      final updated = _when(sheet, () => sheet.valueFor('AC') == '20');
      await receive(remote);
      await updated;
      await sheet.close();
      final saved = (await repository.getCharacter(character.id))!;
      expect(saved.fields, containsPair('AC', '20'));
      expect(saved.fields, containsPair('STR', '18'));
      expect(saved.comments, {'AC': 'Remote shield', 'STR': 'Local strength'});
      final version = (await repository.listVersions(character.id)).single;
      expect((await repository.getVersion(version.id))!.fields['AC'], '20');
    },
  );

  test(
    'saving before a stream notification preserves the remote field',
    () async {
      final sheet = open(_UnwatchedRepository(database, now: () => now));
      final remote = character.copy()..fields['AC'] = '20';
      await receive(remote);
      sheet.setText('STR', '18');
      await sheet.flush();
      final saved = (await repository.getCharacter(character.id))!;
      expect(saved.fields['AC'], '20');
      expect(saved.fields['STR'], '18');
      expect(sheet.valueFor('AC'), '20');
      await sheet.close();
    },
  );

  test(
    'explicit local removal and same-field edit survive a Drive merge',
    () async {
      character.fields['STR'] = '12';
      character.comments['STR'] = 'Old comment';
      await repository.saveCharacter(character);
      final remote = character.copy()
        ..fields['STR'] = '14'
        ..fields['AC'] = '20'
        ..comments['STR'] = 'Remote comment';
      final sheet = open();
      sheet.setText('STR', '18');
      sheet.setComment('STR', '');
      final updated = _when(sheet, () => sheet.valueFor('AC') == '20');
      await receive(remote);
      await updated;
      await sheet.flush();
      final saved = (await repository.getCharacter(character.id))!;
      expect(saved.fields['STR'], '18');
      expect(saved.comments.containsKey('STR'), isFalse);
      await sheet.close();
    },
  );

  test('a remote deletion cannot be resurrected by an open editor', () async {
    final sheet = open();
    sheet.setText('STR', '18');
    final deleted = _when(sheet, () => sheet.locked);
    now = now.add(const Duration(minutes: 1));
    await LocalArchiveSyncStore(database).mergeAndReplace(
      ArchiveSyncData(generatedAt: now, deletions: {character.id: now}),
    );
    await deleted;
    sheet.setText('STR', '20');
    await sheet.close();
    expect(await repository.getCharacter(character.id), isNull);
    expect(await repository.listVersions(character.id), isEmpty);
    expect(sheet.dirtyState.value, isFalse);
  });

  test('an unnotified remote deletion rejects a stale save', () async {
    final sheet = open(_UnwatchedRepository(database));
    await repository.deleteCharacter(character.id);
    sheet.setText('STR', '18');
    await expectLater(sheet.flush(), throwsStateError);
    expect(await repository.getCharacter(character.id), isNull);
  });

  test(
    'input during an asynchronous save is kept for the next revision',
    () async {
      final blocking = _BlockingRepository(database, now: () => now);
      final sheet = open(blocking);
      sheet.setText('STR', '18');
      final saving = sheet.flush();
      await blocking.started.future;
      final concurrentSave = sheet.flush();
      sheet.setText('STR', '20');
      sheet.setText('DEX', '16');
      blocking.release.complete();
      await saving;
      await concurrentSave;
      final saved = (await repository.getCharacter(character.id))!;
      expect(saved.fields['STR'], '20');
      expect(saved.fields['DEX'], '16');
      expect(sheet.valueFor('STR'), '20');
      expect(sheet.dirtyState.value, isFalse);
      await sheet.close();
    },
  );

  test('editing either name updates the list and both sheet pages', () async {
    final sheet = open();
    sheet.setText('CharacterName 2', 'Boo');
    await sheet.flush();
    var saved = (await repository.getCharacter(character.id))!;
    expect(saved.name, 'Boo');
    expect(saved.fields['CharacterName'], 'Boo');
    expect(saved.fields['CharacterName 2'], 'Boo');
    final renamed = _when(sheet, () => character.name == 'Jaheira');
    await repository.renameCharacter(character.id, ' Jaheira ');
    await renamed;
    saved = (await repository.getCharacter(character.id))!;
    expect(saved.fields['CharacterName'], 'Jaheira');
    expect(saved.fields['CharacterName 2'], 'Jaheira');
    sheet.setText('CharacterName', '');
    await sheet.flush();
    saved = (await repository.getCharacter(character.id))!;
    expect(saved.name, '');
    expect(saved.fields.containsKey('CharacterName'), isFalse);
    expect(saved.fields.containsKey('CharacterName 2'), isFalse);
    await sheet.close();
  });

  testWidgets('Drive refreshes rendered fields while preserving active input', (
    tester,
  ) async {
    late SheetController sheet;
    await tester.runAsync(() async {
      sheet = open();
      await repository.watchCharacter(character.id).first;
    });
    const fields = [
      SheetFieldDef(
        name: 'AC',
        page: 0,
        type: SheetFieldType.text,
        x: 20,
        y: 20,
        width: 100,
        height: 30,
        multiline: false,
        align: 0,
      ),
      SheetFieldDef(
        name: 'STR',
        page: 0,
        type: SheetFieldType.text,
        x: 20,
        y: 70,
        width: 100,
        height: 30,
        multiline: false,
        align: 0,
      ),
      SheetFieldDef(
        name: 'Check Box 23',
        page: 0,
        type: SheetFieldType.checkbox,
        x: 150,
        y: 20,
        width: 20,
        height: 20,
        multiline: false,
        align: 0,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SheetPage(
              pageIndex: 0,
              fields: fields,
              controller: sheet,
              onFieldFocused: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/sheet/page-1.png'),
        tester.element(find.byType(SheetPage)),
      ),
    );
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('STR'))));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '18');
    final input = tester.widget<TextField>(find.byType(TextField)).controller!;
    input.selection = const TextSelection.collapsed(offset: 1);
    final remote = character.copy()
      ..fields['AC'] = '20'
      ..fields['Check Box 23'] = 'expertise';
    remote.comments['AC'] = 'Remote shield';
    await tester.runAsync(() => receive(remote));
    await tester.pump();
    expect(find.text('20', findRichText: true), findsOneWidget);
    expect(find.byIcon(Icons.circle), findsOneWidget);
    expect(sheet.commentStateFor('AC').value, isTrue);
    expect(input.text, '18');
    expect(input.selection.baseOffset, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(sheet.close);
  });
}

Future<void> _when(SheetController controller, bool Function() predicate) {
  if (predicate()) return Future<void>.value();
  final result = Completer<void>();
  void changed() {
    if (predicate()) {
      controller.removeListener(changed);
      result.complete();
    }
  }

  controller.addListener(changed);
  return result.future.timeout(const Duration(seconds: 5));
}

class _UnwatchedRepository extends SembastCharacterRepository {
  _UnwatchedRepository(super.database, {super.now});

  @override
  Stream<Character?> watchCharacter(String id) => const Stream.empty();
}

class _BlockingRepository extends SembastCharacterRepository {
  _BlockingRepository(super.database, {super.now});

  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<Character> saveCharacterEdits(
    Character character,
    Character base,
  ) async {
    final saved = await super.saveCharacterEdits(character, base);
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    return saved;
  }
}
