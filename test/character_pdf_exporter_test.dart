import 'dart:convert';
import 'dart:io';

import 'package:dnd_sheet_archive/export/character_pdf_exporter.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Character _character(String id, String name) => Character(
  id: id,
  name: name,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  locked: true,
  fields: {'CharacterName': name, 'CharacterName 2': name},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exports populated, locked characters and delegates saving', () async {
    final first = _character('first', 'Éowyn – Guardiana');
    first.fields.addAll({
      'STR': '18',
      'AC': '16',
      'ClassLevel': 'Guerriera 5',
      'PersonalityTraits ': 'Coraggiosa e leale.\nDifende la sua compagnia.',
      'Features and Traits':
          'Attacco extra\nSecondo fiato: recupera 1d10 + 5 PF.',
      'Check Box 11': true,
      'Check Box 23': 'expertise',
      'Check Box 24': true,
      'Spellcasting Class 2': 'Bardo',
    });
    first.comments['STR'] = 'Bonus temporaneo: +2 durante la furia.';
    first.fields['CharacterAppearanceImage'] = base64Encode(
      (await rootBundle.load('assets/sheet/page-3.png')).buffer.asUint8List(),
    );
    final second = _character('second', 'Thorin');
    second.fields.addAll({'STR': '12', 'Check Box 23': true});
    var saves = 0;
    final exporter = CharacterPdfExporter(
      saveFile: (bytes, filename) async {
        saves++;
        expect(filename, 'schede-dnd.pdf');
        expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
        expect(bytes.length, greaterThan(100000));
        final previewPath = Platform.environment['PDF_EXPORT_PREVIEW'];
        if (previewPath != null) {
          await File(previewPath).parent.create(recursive: true);
          await File(previewPath).writeAsBytes(bytes);
        }
        return true;
      },
    );
    expect(await exporter.exportCharacters([first, second]), isTrue);
    expect(saves, 1);
    expect(first.locked, isTrue);
    expect(first.fields['Check Box 23'], 'expertise');
  });

  test('cancellation propagates without changing the character', () async {
    final character = _character('first', 'Arannis');
    final before = character.toJson();
    final exporter = CharacterPdfExporter(
      saveFile: (_, filename) async {
        expect(filename, 'Arannis.pdf');
        return false;
      },
    );
    expect(await exporter.exportCharacters([character]), isFalse);
    expect(character.toJson(), before);
  });

  test('rejects an empty selection before opening the file picker', () async {
    final exporter = CharacterPdfExporter(
      saveFile: (_, _) async {
        fail('No file should be written');
      },
    );
    await expectLater(exporter.exportCharacters([]), throwsArgumentError);
  });

  test('filenames are safe for desktop paths and preserve accented names', () {
    String filename(String name) =>
        CharacterPdfExporter.filenameFor([_character('id', name)]);
    expect(filename('Éowyn'), 'Éowyn.pdf');
    expect(filename('../A/B:*?'), '.._A_B___.pdf');
    expect(filename('  ... '), 'scheda-dnd.pdf');
    expect(filename('CON'), 'scheda-CON.pdf');
    expect(filename('NUL.txt'), 'scheda-NUL.txt.pdf');
  });
}
