import 'package:dnd_sheet_archive/controllers/sheet_controller.dart';
import 'package:dnd_sheet_archive/data/character_repository.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:dnd_sheet_archive/models/character_version.dart';
import 'package:dnd_sheet_archive/models/sheet_field.dart';
import 'package:dnd_sheet_archive/widgets/checkbox_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a failed autosave stays dirty and can be retried', (
    tester,
  ) async {
    final repository = _FakeRepository(failingSaves: 1);
    final controller = SheetController(
      repository: repository,
      character: _character(),
      autosaveDelay: const Duration(milliseconds: 10),
    );

    controller.setText('STR', '18');
    expect(controller.dirtyState.value, isTrue);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    expect(repository.saveAttempts, 1);
    expect(controller.dirtyState.value, isTrue);

    await controller.flush();
    expect(repository.saveAttempts, 2);
    expect(repository.savedCharacter!.fields['STR'], '18');
    expect(controller.dirtyState.value, isFalse);
    await controller.close();
    controller.dispose();
  });

  testWidgets('comment membership notifies only the affected field', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final controller = SheetController(
      repository: repository,
      character: _character(),
    );
    final armorClass = controller.commentStateFor('AC');
    final strength = controller.commentStateFor('STR');
    var armorNotifications = 0;
    var strengthNotifications = 0;
    armorClass.addListener(() => armorNotifications++);
    strength.addListener(() => strengthNotifications++);

    controller.setComment('AC', 'Include shield');
    controller.setComment('AC', 'Include magic shield');
    expect(armorNotifications, 1);
    expect(strengthNotifications, 0);

    controller.setComment('AC', '');
    expect(armorNotifications, 2);
    await controller.close();
    controller.dispose();
  });

  test('invalid sheet field types and pages are rejected', () {
    final valid = <String, Object?>{
      'name': 'Field',
      'page': 0,
      'type': 'text',
      'x': 0,
      'y': 0,
      'w': 10,
      'h': 10,
    };
    expect(
      () => SheetFieldDef.fromJson({...valid, 'type': 'typo'}),
      throwsFormatException,
    );
    expect(
      () => SheetFieldDef.fromJson({...valid, 'page': 1.5}),
      throwsFormatException,
    );
  });

  test('skill proficiency cycles through expertise', () {
    const skill = SheetFieldDef(
      name: 'Check Box 23',
      page: 0,
      type: SheetFieldType.checkbox,
      x: 0,
      y: 0,
      width: 10,
      height: 10,
      multiline: false,
      align: 0,
    );
    const savingThrow = SheetFieldDef(
      name: 'Check Box 11',
      page: 0,
      type: SheetFieldType.checkbox,
      x: 0,
      y: 0,
      width: 10,
      height: 10,
      multiline: false,
      align: 0,
    );

    expect(skill.supportsExpertise, isTrue);
    expect(savingThrow.supportsExpertise, isFalse);
    expect(
      SheetCheckboxValue.unchecked.next(allowExpertise: true),
      SheetCheckboxValue.proficient,
    );
    expect(
      SheetCheckboxValue.proficient.next(allowExpertise: true),
      SheetCheckboxValue.expertise,
    );
    expect(
      SheetCheckboxValue.expertise.next(allowExpertise: true),
      SheetCheckboxValue.unchecked,
    );
    expect(
      SheetCheckboxValue.proficient.next(allowExpertise: false),
      SheetCheckboxValue.unchecked,
    );
  });

  testWidgets('expertise is persisted distinctly from proficiency', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final character = _character();
    final controller = SheetController(
      repository: repository,
      character: character,
    );

    controller.setCheckbox('Check Box 23', SheetCheckboxValue.proficient);
    expect(character.fields['Check Box 23'], isTrue);
    controller.setCheckbox('Check Box 23', SheetCheckboxValue.expertise);
    expect(character.fields['Check Box 23'], 'expertise');
    controller.setCheckbox('Check Box 23', SheetCheckboxValue.unchecked);
    expect(character.fields.containsKey('Check Box 23'), isFalse);

    await controller.close();
    controller.dispose();
  });

  testWidgets('skill checkbox exposes all three states through taps', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final character = _character();
    final controller = SheetController(
      repository: repository,
      character: character,
    );
    const field = SheetFieldDef(
      name: 'Check Box 23',
      page: 0,
      type: SheetFieldType.checkbox,
      x: 0,
      y: 0,
      width: 10,
      height: 10,
      multiline: false,
      align: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 24,
            child: CheckboxOverlay(field: field, sheetController: controller),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(CheckboxOverlay));
    await tester.pump();
    expect(character.fields[field.name], isTrue);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(CheckboxOverlay));
    await tester.pump();
    expect(character.fields[field.name], 'expertise');
    expect(
      tester.widget<Icon>(find.byIcon(Icons.circle)).color,
      const Color(0xffc62828),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(CheckboxOverlay));
    await tester.pump();
    expect(character.fields.containsKey(field.name), isFalse);
    expect(tester.takeException(), isNull);

    await controller.close();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  test('invalid comment entries do not break character decoding', () {
    final json = _character().toJson();
    json['comments'] = {'AC': 'Shield', 'STR': null, 12: 'invalid key'};
    final character = Character.fromJson(json);
    expect(character.comments, {'AC': 'Shield'});
  });
}

Character _character() {
  final now = DateTime.utc(2026, 7, 13);
  return Character(
    id: 'character-id',
    name: 'Test',
    createdAt: now,
    updatedAt: now,
    locked: false,
  );
}

class _FakeRepository implements CharacterRepository {
  _FakeRepository({this.failingSaves = 0});

  final int failingSaves;
  int saveAttempts = 0;
  Character? savedCharacter;

  @override
  Future<void> saveCharacter(Character character) async {
    saveAttempts++;
    if (saveAttempts <= failingSaves) throw StateError('disk full');
    savedCharacter = character.copy();
  }

  @override
  Future<void> createSnapshot(Character character, String reason) async {}

  @override
  Future<Character> createCharacter(String name) => throw UnimplementedError();

  @override
  Future<void> deleteCharacter(String id) => throw UnimplementedError();

  @override
  Future<Character?> getCharacter(String id) => throw UnimplementedError();

  @override
  Future<CharacterVersion?> getVersion(String versionId) =>
      throw UnimplementedError();

  @override
  Future<List<VersionMeta>> listVersions(String characterId) =>
      throw UnimplementedError();

  @override
  Future<void> renameCharacter(String id, String newName) =>
      throw UnimplementedError();

  @override
  Future<void> restoreVersion(String characterId, String versionId) =>
      throw UnimplementedError();

  @override
  Stream<List<CharacterSummary>> watchCharacters() => const Stream.empty();
}
