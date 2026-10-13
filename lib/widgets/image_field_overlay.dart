import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../controllers/sheet_controller.dart';

// Le immagini non stanno più dentro il campo: il personaggio ne tiene un
// riferimento e il contenuto vive una volta sola nell'archivio dei blob,
// condiviso fra le versioni della scheda e il backup su Drive. Resta però
// un'immagine da disegnare e da spedire, quindi viene ridotta al proprio
// riquadro alla densità di uno schermo hidpi, che è quanto serve per vederla
// nitida.
const _sheetImagePixelRatio = 2;

// Rete di sicurezza sul file scelto: serve solo a non tentare di decodificare
// in memoria qualcosa di assurdo, non a limitare le foto normali.
const _maxSourceImageBytes = 32 * 1024 * 1024;

// Abbastanza alta perché un ritratto resti pulito alla dimensione del
// riquadro, abbastanza bassa perché pesi una frazione del PNG equivalente.
const _jpegQuality = 88;

/// Riduce l'immagine al riquadro che la ospita, se lo eccede.
///
/// Restituisce i byte originali quando l'immagine è già abbastanza piccola o
/// quando la ricodifica risulterebbe più pesante — cosa normale partendo da un
/// JPEG già compresso.
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
      final recoded = await _encodeCompact(frame.image);
      return recoded != null && recoded.length < bytes.length ? recoded : bytes;
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

/// Il formato più compatto che conserva l'immagine così com'è.
Future<Uint8List?> _encodeCompact(ui.Image image) async {
  final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (raw != null) {
    final jpeg = await compute(
      _encodeOpaqueJpeg,
      _RawPixels(raw.buffer.asUint8List(), image.width, image.height),
      debugLabel: 'sheet-image-encode',
    );
    if (jpeg != null) return jpeg;
  }
  // Il simbolo di una fazione arriva spesso come PNG con il fondo
  // trasparente: il JPEG lo appiattirebbe, e i pixel premoltiplicati di
  // `rawRgba` andrebbero srotolati a mano. Il PNG di dart:ui fa già entrambe
  // le cose nel modo giusto.
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return png?.buffer.asUint8List();
}

class _RawPixels {
  const _RawPixels(this.rgba, this.width, this.height);

  final Uint8List rgba;
  final int width;
  final int height;
}

/// JPEG dei pixel ricevuti, o `null` se l'immagine ha delle trasparenze.
Uint8List? _encodeOpaqueJpeg(_RawPixels pixels) {
  for (var index = 3; index < pixels.rgba.length; index += 4) {
    if (pixels.rgba[index] != 0xff) return null;
  }
  return img.encodeJpg(
    img.Image.fromBytes(
      width: pixels.width,
      height: pixels.height,
      bytes: pixels.rgba.buffer,
      numChannels: 4,
    ),
    quality: _jpegQuality,
  );
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
  String? _requestedValue;
  Uint8List? _bytes;
  int _requestId = 0;

  SheetController get _controller => widget.sheetController;

  /// Risolve il valore del campo nei byte da disegnare.
  ///
  /// Il valore memorizzato è un riferimento, quindi leggerlo è asincrono: la
  /// richiesta parte una volta sola per valore e, finché i byte nuovi non
  /// arrivano, resta a schermo l'immagine precedente invece di un lampo vuoto.
  Uint8List? get _imageBytes {
    final stored = _controller.valueFor(widget.fieldName);
    final value = stored is String && stored.isNotEmpty ? stored : null;
    if (value != _requestedValue) {
      _requestedValue = value;
      _requestId++;
      if (value == null) {
        _bytes = null;
      } else {
        unawaited(_load(value, _requestId));
      }
    }
    return _bytes;
  }

  Future<void> _load(String value, int requestId) async {
    final bytes = await _controller.repository.readImage(value);
    if (!mounted || requestId != _requestId) return;
    setState(() => _bytes = bytes);
  }

  Future<void> _pickImage() async {
    if (_controller.locked || _busy) return;
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
      final value = await _controller.repository.storeImage(stored);
      if (!mounted) return;
      // I byte sono già in mano: annunciarli subito evita di rileggerli
      // dall'archivio solo per ridisegnare ciò che l'utente ha appena scelto.
      _requestId++;
      _requestedValue = value;
      _bytes = stored;
      _controller.setText(widget.fieldName, value);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearImage() {
    if (_controller.locked) return;
    _controller.setText(widget.fieldName, '');
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
    valueListenable: _controller.lockedState,
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
