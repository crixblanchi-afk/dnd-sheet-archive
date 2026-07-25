import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dnd_sheet_archive/widgets/image_field_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// I due riquadri illustrati della scheda, in punti.
const _portraitBox = Size(172, 222);
const _symbolBox = Size(143, 114);

void main() {
  // La codifica e la decodifica delle immagini sono lavoro vero del motore:
  // dentro la zona fake-async di `testWidgets` non verrebbero mai completate.

  testWidgets('un\'immagine grande viene ridotta al riquadro', (tester) async {
    await tester.runAsync(() async {
      final source = await _encodedImage(1600, 1200);

      final fitted = await fitImageToBox(source, _portraitBox);
      final size = await _decodedSize(fitted);

      // Il fattore 2 tiene la nitidezza su schermi hidpi senza gonfiare il
      // backup: nessun lato può superare il proprio limite.
      expect(size.width, lessThanOrEqualTo(_portraitBox.width * 2));
      expect(size.height, lessThanOrEqualTo(_portraitBox.height * 2));
      expect(fitted.length, lessThan(source.length));
      expect(size.width / size.height, closeTo(1600 / 1200, .02));
    });
  });

  testWidgets('un\'immagine già piccola non viene ingrandita', (tester) async {
    await tester.runAsync(() async {
      final source = await _encodedImage(64, 48);

      final size = await _decodedSize(
        await fitImageToBox(source, _portraitBox),
      );

      expect(size, const Size(64, 48));
    });
  });

  testWidgets('il riquadro del simbolo conserva meno pixel del ritratto', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = await _encodedImage(1600, 1200);

      final portrait = await _decodedSize(
        await fitImageToBox(source, _portraitBox),
      );
      final symbol = await _decodedSize(
        await fitImageToBox(source, _symbolBox),
      );

      expect(symbol.width, lessThan(portrait.width));
      expect(symbol.width, lessThanOrEqualTo(_symbolBox.width * 2));
    });
  });

  testWidgets('dei byte non decodificabili sollevano un errore', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await expectLater(
        fitImageToBox(Uint8List.fromList([1, 2, 3, 4]), _portraitBox),
        throwsA(anything),
      );
    });
  });
}

/// PNG con un gradiente, così il peso del file dipende davvero dal numero di
/// pixel invece di comprimersi a nulla come farebbe una tinta piatta.
Future<Uint8List> _encodedImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(width.toDouble(), height.toDouble()),
        const [Color(0xff000000), Color(0xffff0000), Color(0xffffffff)],
        const [0, .5, 1],
      ),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<Size> _decodedSize(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final size = Size(
    frame.image.width.toDouble(),
    frame.image.height.toDouble(),
  );
  frame.image.dispose();
  codec.dispose();
  return size;
}
