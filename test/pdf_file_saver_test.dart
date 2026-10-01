import 'dart:io';
import 'dart:typed_data';

import 'package:dnd_sheet_archive/export/pdf_file_saver_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

class _Picker extends FilePicker {
  String? chosenPath;
  Uint8List? receivedBytes;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    expect(fileName, 'Arannis.pdf');
    expect(type, FileType.custom);
    expect(allowedExtensions, ['pdf']);
    receivedBytes = bytes;
    return chosenPath;
  }
}

void main() {
  test(
    'desktop saves the PDF bytes to the exact path chosen in the dialog',
    () async {
      final directory = await Directory.systemTemp.createTemp('dnd-pdf-save-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/chosen.pdf';
      final picker = _Picker()..chosenPath = path;
      FilePicker.platform = picker;
      final bytes = Uint8List.fromList('%PDF-test'.codeUnits);
      expect(await savePdfFile(bytes, 'Arannis.pdf'), isTrue);
      expect(await File(path).readAsBytes(), bytes);
      expect(picker.receivedBytes, bytes);
      expect(await Directory(directory.path).list().length, 1);
    },
  );

  test('cancelling the destination does not create a file', () async {
    FilePicker.platform = _Picker();
    expect(await savePdfFile(Uint8List(0), 'Arannis.pdf'), isFalse);
  });
}
