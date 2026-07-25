import 'package:flutter/material.dart';

import '../controllers/sheet_controller.dart';
import '../models/sheet_field.dart';
import '../models/sheet_layout.dart';
import 'checkbox_overlay.dart';
import 'image_field_overlay.dart';
import 'text_field_overlay.dart';

// I riquadri illustrati della pagina 2 non sono campi modulo del PDF, quindi
// non hanno una voce in fields.json: i loro limiti sono misurati a mano
// sull'artwork in assets/sheet/page-2.png.
const _imageFields = [
  // "Character Appearance", la colonna di sinistra.
  (
    name: 'CharacterAppearanceImage',
    page: 1,
    x: 31.0,
    y: 128.0,
    width: 172.0,
    height: 222.0,
  ),
  // Il riquadro del simbolo in "Allies & Organizations": la cornice va da
  // x 417.6 a 566.3 e da y 142 a 290, ma la parte alta è occupata dal campo
  // FactionName (fino a y 169.3) e il fondo dalla dicitura "SYMBOL".
  (
    name: 'FactionSymbolImage',
    page: 1,
    x: 420.0,
    y: 171.0,
    width: 143.0,
    height: 114.0,
  ),
];

class SheetPage extends StatelessWidget {
  const SheetPage({
    super.key,
    required this.pageIndex,
    required this.fields,
    required this.controller,
    required this.onFieldFocused,
  });

  final int pageIndex;
  final List<SheetFieldDef> fields;
  final SheetController controller;
  final ValueChanged<BuildContext> onFieldFocused;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: sheetPageWidth,
    height: sheetPageHeight,
    child: RepaintBoundary(
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/sheet/page-${pageIndex + 1}.png',
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
            ),
          ),
          for (final field in fields)
            Positioned(
              left: field.x,
              top: field.y,
              width: field.width,
              height: field.height,
              child: field.type == SheetFieldType.text
                  ? TextFieldOverlay(
                      key: ValueKey(field.name),
                      field: field,
                      sheetController: controller,
                      onFocused: onFieldFocused,
                    )
                  : CheckboxOverlay(
                      key: ValueKey(field.name),
                      field: field,
                      sheetController: controller,
                    ),
            ),
          for (final imageField in _imageFields)
            if (imageField.page == pageIndex)
              Positioned(
                left: imageField.x,
                top: imageField.y,
                width: imageField.width,
                height: imageField.height,
                child: ImageFieldOverlay(
                  key: ValueKey(imageField.name),
                  fieldName: imageField.name,
                  boxSize: Size(imageField.width, imageField.height),
                  sheetController: controller,
                ),
              ),
        ],
      ),
    ),
  );
}
