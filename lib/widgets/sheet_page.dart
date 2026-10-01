import 'package:flutter/material.dart';

import '../controllers/sheet_controller.dart';
import '../models/sheet_field.dart';
import '../models/sheet_layout.dart';
import '../theme/sheet_palette.dart';
import 'checkbox_overlay.dart';
import 'image_field_overlay.dart';
import 'text_field_overlay.dart';

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
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => RepaintBoundary(
        child: Stack(
          children: [
            Positioned.fill(child: SheetArtwork(pageIndex: pageIndex)),
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
            for (final imageField in sheetImageFields)
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
    ),
  );
}
