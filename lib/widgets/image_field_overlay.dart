import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../controllers/sheet_controller.dart';

// Le immagini viaggiano in base64 dentro il JSON del personaggio, quindi
// vengono riscritte a ogni salvataggio, duplicate in ognuna delle dieci
// versioni e caricate su Drive. Una foto da telefono farebbe superare il tetto
// di download del backup, rendendo la sincronizzazione irrecuperabile da
// dentro l'app: viene quindi ridotta al proprio riquadro alla densità di uno
// schermo hidpi, che è quanto serve per disegnarla nitida.
const _sheetImagePixelRatio = 2;

// Rete di sicurezza sul file scelto: serve solo a non tentare di decodificare
// in memoria qualcosa di assurdo, non a limitare le foto normali.
const _maxSourceImageBytes = 32 * 1024 * 1024;

/// Riduce l'immagine al riquadro che la ospita, se lo eccede.
///
/// Restituisce i byte originali quando l'immagine è già abbastanza piccola o
/// quando il PNG rigenerato risulterebbe più pesante — cosa normale partendo
/// da un JPEG già compresso.
Future<Uint8List> fitImageToBox(Uint8List bytes, Size box) async {
  final maxWidth = box.width * _sheetImagePixelRatio;
  final maxHeight = box.height * _sheetImagePixelRatio;
  final codec = await ui.instantiateImageCodecWithSize(
    await ui.ImmutableBuffer.fromUint8List(bytes),
    getTargetSize: (width, height) {
      final scale = math.min(maxWidth / width, maxHeight / height);
      // Ingrandire costerebbe byte senza aggiungere dettaglio.
      if (scale >= 1) return ui.TargetImageSize(width: width, height: height);
      return ui.TargetImageSize(
        width: math.max(1, (width * scale).round()),
        height: math.max(1, (height * scale).round()),
      );
    },
  );
  try {
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      final resized = data?.buffer.asUint8List();
      return resized != null && resized.length < bytes.length ? resized : bytes;
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

class ImageFieldOverlay extends StatefulWidget {
  const ImageFieldOverlay({
    super.key,
    required this.fieldName,
    required this.boxSize,
    required this.sheetController,
  });

  final String fieldName;

  /// Dimensione del riquadro sulla scheda, in punti: determina la risoluzione
  /// alla quale l'immagine scelta viene conservata.
  final Size boxSize;

  final SheetController sheetController;

  @override
  State<ImageFieldOverlay> createState() => _ImageFieldOverlayState();
}

class _ImageFieldOverlayState extends State<ImageFieldOverlay> {
  bool _busy = false;
  String? _decodedSource;
  Uint8List? _decodedBytes;

  /// Decodifica l'immagine una sola volta per valore memorizzato.
  ///
  /// `MemoryImage` confronta i byte per identità: restituire una `Uint8List`
  /// nuova a ogni build manderebbe a vuoto la cache delle immagini e
  /// costringerebbe a ridecodificarla di continuo.
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
      if (bytes.length > _maxSourceImageBytes) {
        _report(
          'Immagine troppo grande: al massimo '
          '${_maxSourceImageBytes ~/ (1024 * 1024)} MB.',
        );
        return;
      }
      final Uint8List stored;
      try {
        stored = await fitImageToBox(bytes, widget.boxSize);
      } catch (_) {
        _report('Formato immagine non riconosciuto.');
        return;
      }
      widget.sheetController.setText(widget.fieldName, base64Encode(stored));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearImage() {
    if (widget.sheetController.locked) return;
    widget.sheetController.setText(widget.fieldName, '');
    // Il valore vive nel controller, che non notifica i singoli campi: senza
    // questo rebuild l'immagine resterebbe a schermo dopo la rimozione.
    setState(() {});
  }

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
