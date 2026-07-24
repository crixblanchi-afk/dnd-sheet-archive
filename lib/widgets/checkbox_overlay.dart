import 'package:flutter/material.dart';

import '../controllers/sheet_controller.dart';
import '../models/sheet_field.dart';
import 'comment_dialog.dart';

class CheckboxOverlay extends StatefulWidget {
  const CheckboxOverlay({
    super.key,
    required this.field,
    required this.sheetController,
  });

  final SheetFieldDef field;
  final SheetController sheetController;

  @override
  State<CheckboxOverlay> createState() => _CheckboxOverlayState();
}

class _CheckboxOverlayState extends State<CheckboxOverlay> {
  late SheetCheckboxValue _value;

  @override
  void initState() {
    super.initState();
    _value = SheetCheckboxValue.fromStored(
      widget.sheetController.valueFor(widget.field.name),
    );
  }

  void _showComment() => showFieldCommentDialog(
    context: context,
    fieldName: widget.field.name,
    initialValue: widget.sheetController.commentFor(widget.field.name),
    readOnly: widget.sheetController.locked,
    onSave: (value) =>
        widget.sheetController.setComment(widget.field.name, value),
  );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: widget.sheetController.lockedState,
    builder: (context, locked, _) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: locked
          ? null
          : () {
              setState(() {
                _value = _value.next(
                  allowExpertise: widget.field.supportsExpertise,
                );
              });
              widget.sheetController.setCheckbox(widget.field.name, _value);
            },
      onLongPress: _showComment,
      onSecondaryTapUp: (_) => _showComment(),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (_value != SheetCheckboxValue.unchecked)
            Icon(
              Icons.circle,
              color: _value == SheetCheckboxValue.expertise
                  ? const Color(0xffc62828)
                  : Colors.black,
              size:
                  (widget.field.width < widget.field.height
                      ? widget.field.width
                      : widget.field.height) *
                  .65,
            ),
          ValueListenableBuilder<bool>(
            valueListenable: widget.sheetController.commentStateFor(
              widget.field.name,
            ),
            builder: (context, hasComment, _) => hasComment
                ? const Align(
                    alignment: Alignment.topRight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xffd32f2f),
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox.square(dimension: 7),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    ),
  );
}
