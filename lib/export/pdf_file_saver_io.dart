import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> savePdfFile(Uint8List bytes, String filename) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Esporta schede in PDF',
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    bytes: bytes,
  );
  if (path == null) return false;
  // Su Android/iOS il picker scrive già i byte nel documento scelto.
  if (!Platform.isAndroid && !Platform.isIOS) {
    await File(path).writeAsBytes(bytes, flush: true);
  }
  return true;
}
