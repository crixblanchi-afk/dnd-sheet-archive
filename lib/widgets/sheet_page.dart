import 'package:flutter/material.dart';

import '../controllers/sheet_controller.dart';
import '../models/sheet_field.dart';
import '../models/sheet_layout.dart';
import 'checkbox_overlay.dart';
import 'image_field_overlay.dart';
import 'text_field_overlay.dart';

// Position of the blank "Character Appearance" portrait box printed on
// page 2 of the official sheet artwork. It isn't a fillable PDF form field,
// so it has no entry in fields.json and its bounds are hand-measured from
// assets/sheet/page-2.png instead.
const _appearanceImageField = (
  page: 1,
  x: 31.0,
  y: 128.0,
  width: 172.0,
  height: 222.0,
);

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
          if (pageIndex == _appearanceImageField.page)
            Positioned(
              left: _appearanceImageField.x,
              top: _appearanceImageField.y,
              width: _appearanceImageField.width,
              height: _appearanceImageField.height,
              child: ImageFieldOverlay(
                key: const ValueKey('CharacterAppearanceImage'),
                fieldName: 'CharacterAppearanceImage',
                sheetController: controller,
              ),
            ),
        ],
      ),
    ),
  );
}
