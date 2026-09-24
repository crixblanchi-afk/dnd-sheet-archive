import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dnd_sheet_archive/controllers/sheet_controller.dart';
import 'package:dnd_sheet_archive/data/character_repository.dart';
import 'package:dnd_sheet_archive/models/character.dart';
import 'package:dnd_sheet_archive/models/sheet_field.dart';
import 'package:dnd_sheet_archive/theme/sheet_palette.dart';
import 'package:dnd_sheet_archive/widgets/image_field_overlay.dart';
import 'package:dnd_sheet_archive/widgets/sheet_page.dart';
import 'package:dnd_sheet_archive/widgets/text_field_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'theme change updates cached text, including the active editor',
    (tester) async {
      final character = _character({'Name': 'Arannis'});
      final controller = SheetController(
        character: character,
        repository: _Repository(),
      );
      final brightness = ValueNotifier(Brightness.light);
      addTearDown(brightness.dispose);
      const field = SheetFieldDef(
        name: 'Name',
        page: 0,
        type: SheetFieldType.text,
        x: 0,
        y: 0,
        width: 180,
        height: 30,
        multiline: false,
        align: 0,
      );
      await tester.pumpWidget(
        ValueListenableBuilder<Brightness>(
          valueListenable: brightness,
          builder: (_, value, _) => MaterialApp(
            theme: ThemeData(brightness: value),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 180,
                  height: 30,
                  child: TextFieldOverlay(
                    field: field,
                    sheetController: controller,
                    onFocused: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Color? idleColor() => tester
          .widget<RichText>(find.text('Arannis', findRichText: true))
          .text
          .style
          ?.color;
      expect(idleColor(), SheetPalette.light.text);
      brightness.value = Brightness.dark;
      await tester.pumpAndSettle();
      expect(idleColor(), SheetPalette.dark.text);
      await tester.tapAt(const Offset(30, 15));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).style?.color,
        SheetPalette.dark.text,
      );
      brightness.value = Brightness.light;
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).style?.color,
        SheetPalette.light.text,
      );
      expect(character.fields['Name'], 'Arannis');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'dark artwork preserves the actual rendered colors of uploads',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(612, 792));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final bytes = (await tester.runAsync(_colorImage))!;
      final character = _character({
        'CharacterAppearanceImage': base64Encode(bytes),
        'FactionSymbolImage': base64Encode(bytes),
      });
      final controller = SheetController(
        character: character,
        repository: _Repository(),
      );
      final boundary = GlobalKey();
      final brightness = ValueNotifier(Brightness.light);
      addTearDown(brightness.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<Brightness>(
          valueListenable: brightness,
          builder: (_, value, _) => MaterialApp(
            theme: ThemeData(brightness: value),
            home: Scaffold(
              body: RepaintBoundary(
                key: boundary,
                child: SheetPage(
                  pageIndex: 1,
                  fields: const [],
                  controller: controller,
                  onFieldFocused: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(SheetPage));
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage('assets/sheet/page-2.png'),
          context,
        );
        await precacheImage(MemoryImage(bytes), context);
      });
      await tester.pumpAndSettle();
      final light = await _capture(tester, boundary, 'light');
      brightness.value = Brightness.dark;
      await tester.pumpAndSettle();
      final dark = await _capture(tester, boundary, 'dark');
      expect(_pixel(light, 5, 5), [255, 255, 255, 255]);
      expect(_pixel(dark, 5, 5), [32, 35, 41, 255]);
      // Centro di ciascuna metà del ritratto e del simbolo: confronto dei
      // pixel finali, non soltanto delle proprietà del widget Image.
      for (final point in const [
        Offset(70, 230),
        Offset(155, 230),
        Offset(463, 220),
        Offset(520, 220),
      ]) {
        final before = _pixel(light, point.dx.toInt(), point.dy.toInt());
        expect(before, anyOf(equals([230, 40, 50, 255]), equals([30, 150, 220, 255])));
        expect(_pixel(dark, point.dx.toInt(), point.dy.toInt()), before);
      }
      expect(
        find.ancestor(
          of: find.byType(ImageFieldOverlay),
          matching: find.byType(ColorFiltered),
        ),
        findsNothing,
      );
      if (const bool.fromEnvironment('SAVE_THEME_PREVIEWS')) {
        await _previewPages(tester, controller, boundary);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('sheet values and annotations keep strong contrast on dark paper', () {
    double contrast(Color a, Color b) =>
        (a.computeLuminance() + .05) / (b.computeLuminance() + .05);
    expect(
      contrast(SheetPalette.dark.text, SheetPalette.dark.paper),
      greaterThan(10),
    );
    expect(
      contrast(SheetPalette.dark.comment, SheetPalette.dark.paper),
      greaterThan(4.5),
    );
  });
}

Character _character(Map<String, Object?> fields) => Character(
  id: 'dark-test',
  name: 'Arannis',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  locked: false,
  fields: fields,
);

Future<Uint8List> _colorImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 20, 40),
    Paint()..color = const Color(0xffe62832),
  );
  canvas.drawRect(
    const Rect.fromLTWH(20, 0, 20, 40),
    Paint()..color = const Color(0xff1e96dc),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(40, 40);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return png!.buffer.asUint8List();
}

Future<Uint8List> _capture(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async => (await tester.runAsync(() async {
  final image =
      await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
          .toImage(pixelRatio: 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (const bool.fromEnvironment('SAVE_THEME_PREVIEWS')) {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/theme-previews/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
  }
  image.dispose();
  return data!.buffer.asUint8List();
}))!;

List<int> _pixel(Uint8List pixels, int x, int y) =>
    pixels.sublist((y * 612 + x) * 4, (y * 612 + x) * 4 + 4);

class _Repository implements CharacterRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _previewPages(
  WidgetTester tester,
  SheetController controller,
  GlobalKey boundary,
) async {
  final fields = (await tester.runAsync(SheetFieldDef.loadByPage))!;
  await tester.runAsync(() async {
    final font = FontLoader('RobotoSlab')
      ..addFont(
        rootBundle.load('assets/fonts/RobotoSlab-VariableFont_wght.ttf'),
      );
    await font.load();
  });
  controller.character.fields.addAll({
    'CharacterName': 'Arannis',
    'ClassLevel': 'Ranger 5',
    'Background': 'Outlander',
    'PlayerName': 'Cristiano',
    'Race ': 'Elf',
    'Alignment': 'Neutral good',
    'STR': '12',
    'DEX': '18',
    'CON': '14',
    'INT': '10',
    'WIS': '16',
    'CHA': '10',
    'AC': '16',
    'Speed': '30',
    'HPMax': '44',
    'HPCurrent': '38',
    'PersonalityTraits': 'I listen before I speak. The forest is my home.',
    'Ideals': 'Protect those who cannot protect themselves.',
    'Bonds': 'My companions are my family.',
    'Flaws': 'I find it difficult to trust strangers.',
  });
  for (var page = 0; page < 3; page++) {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: SheetPage(
                key: ValueKey('$page-$brightness'),
                pageIndex: page,
                fields: fields[page],
                controller: controller,
                onFieldFocused: (_) {},
              ),
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(SheetPage));
      await tester.runAsync(
        () => precacheImage(
          AssetImage('assets/sheet/page-${page + 1}.png'),
          context,
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, boundary, 'page-${page + 1}-${brightness.name}');
    }
  }
}
