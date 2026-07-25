import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../controllers/sheet_controller.dart';

// Il ritratto viaggia in base64 dentro il JSON del personaggio, quindi viene
// riscritto a ogni salvataggio, duplicato in ogni snapshot e caricato su
// Drive. Con dieci versioni per personaggio un'immagine più grande di così
// farebbe superare il tetto di download del backup, rendendo la
// sincronizzazione irrecuperabile da dentro l'app. Il riquadro sulla scheda è
// di 172x222 punti: mezzo megabyte è già abbondante per riempirlo.
const _maxImageBytes = 512 * 1024;

class ImageFieldOverlay extends StatefulWidget {
  const ImageFieldOverlay({
    super.key,
    required this.fieldName,
    required this.sheetController,
  });

  final String fieldName;
  final SheetController sheetController;

  @override
  State<ImageFieldOverlay> createState() => _ImageFieldOverlayState();
}

class _ImageFieldOverlayState extends State<ImageFieldOverlay> {
  bool _busy = false;
  String? _decodedSource;
  Uint8List? _decodedBytes;

  /// Decodifica il ritratto una sola volta per valore memorizzato.
  ///
  /// `MemoryImage` confronta i byte per identità: restituire una `Uint8List`
  /// nuova a ogni build manderebbe a vuoto la cache delle immagini e
  /// costringerebbe a ridecodificare il ritratto di continuo.
  Uint8List? get _imageBytes {
    final stored = widget.sheetController.valueFor(widget.fieldName);
    final source = stored is String && stored.isNotEmpty ? stored : null;
    if (source == _decodedSource) return _decodedBytes;
    _decodedSource = source;
    _decodedBytes = source == null ? null : _tryDecode(source);
    return _decodedBytes;
  }

  Uint8List? _tryDecode(String source) {
    try {
      return base64Decode(source);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickImage() async {
    if (widget.sheetController.locked || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final files = result?.files ?? const [];
      final bytes = files.isEmpty ? null : files.first.bytes;
      if (bytes == null) return;
      if (bytes.length > _maxImageBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Immagine troppo grande: al massimo '
              '${_maxImageBytes ~/ 1024} KB.',
            ),
          ),
        );
        return;
      }
      widget.sheetController.setText(widget.fieldName, base64Encode(bytes));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearImage() {
    if (widget.sheetController.locked) return;
    widget.sheetController.setText(widget.fieldName, '');
    // Il valore vive nel controller, che non notifica i singoli campi: senza
    // questo rebuild il ritratto resterebbe a schermo dopo la rimozione.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: widget.sheetController.lockedState,
    builder: (context, locked, _) {
      final bytes = _imageBytes;
      return MouseRegion(
        cursor: locked ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: locked ? null : _pickImage,
          onLongPress: locked || bytes == null ? null : _clearImage,
          child: bytes == null
              ? const SizedBox.expand()
              : Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
        ),
      );
    },
  );
}
