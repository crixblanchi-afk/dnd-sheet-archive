import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import '../controllers/sheet_controller.dart';
import '../models/sheet_field.dart';
import 'comment_dialog.dart';
import 'inline_markdown.dart';

// Flutter's paragraph engine stops producing smaller glyph advances below
// roughly one logical pixel, so this is the lowest effective fitting size.
const _minimumFieldFontSize = 1.0;
const _textFitSafetyFactor = .8;

class TextFieldOverlay extends StatefulWidget {
  const TextFieldOverlay({
    super.key,
    required this.field,
    required this.sheetController,
    required this.onFocused,
  });

  final SheetFieldDef field;
  final SheetController sheetController;
  final ValueChanged<BuildContext> onFocused;

  @override
  State<TextFieldOverlay> createState() => _TextFieldOverlayState();
}

class _TextFieldOverlayState extends State<TextFieldOverlay> {
  TextEditingController? _textController;
  FocusNode? _focusNode;
  late String _value;
  bool _editing = false;
  bool _hasGlobalPointerRoute = false;

  @override
  void initState() {
    super.initState();
    _value =
        widget.sheetController.valueFor(widget.field.name)?.toString() ?? '';
  }

  void _handleFocus() {
    if (_focusNode?.hasFocus ?? false) {
      if (!_hasGlobalPointerRoute) {
        GestureBinding.instance.pointerRouter.addGlobalRoute(
          _handleGlobalPointerEvent,
        );
        _hasGlobalPointerRoute = true;
      }
      widget.onFocused(context);
    } else if (_editing && mounted) {
      _removeGlobalPointerRoute();
      setState(() => _editing = false);
    }
  }

  void _handleGlobalPointerEvent(PointerEvent event) {
    if (event is! PointerDownEvent || !(_focusNode?.hasFocus ?? false)) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final localPosition = renderObject.globalToLocal(event.position);
    if (!(Offset.zero & renderObject.size).contains(localPosition)) {
      _focusNode?.unfocus();
    }
  }

  void _removeGlobalPointerRoute() {
    if (!_hasGlobalPointerRoute) return;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleGlobalPointerEvent,
    );
    _hasGlobalPointerRoute = false;
  }

  void _startEditing() {
    if (_editing || widget.sheetController.locked) return;
    _textController ??= TextEditingController(text: _value);
    _focusNode ??= FocusNode()..addListener(_handleFocus);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _focusNode?.requestFocus();
    });
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
  Widget build(BuildContext context) {
    final field = widget.field;
    final alignment = switch (field.align) {
      1 => TextAlign.center,
      2 => TextAlign.right,
      _ => TextAlign.left,
    };
    final baseTextStyle = TextStyle(
      color: Colors.black,
      fontFamily: 'RobotoSlab',
      fontSize: field.multiline ? 9.5 : (field.height * .62).clamp(7.0, 14.0),
      height: 1,
    );
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: _showComment,
      onSecondaryTapUp: (_) => _showComment(),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ValueListenableBuilder<bool>(
              valueListenable: widget.sheetController.lockedState,
              builder: (context, locked, _) => LayoutBuilder(
                builder: (context, constraints) {
                  final fittedStyle = _fittedTextStyle(
                    text: _value,
                    baseStyle: baseTextStyle,
                    maxWidth: constraints.maxWidth - 2,
                    maxHeight: constraints.maxHeight,
                    multiline: field.multiline,
                    textAlign: alignment,
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                    markdown: !_editing,
                  );
                  return _editing
                      ? TextField(
                          controller: _textController,
                          focusNode: _focusNode,
                          readOnly: locked,
                          textAlign: alignment,
                          textAlignVertical: field.multiline
                              ? TextAlignVertical.top
                              : TextAlignVertical.center,
                          maxLines: field.multiline ? null : 1,
                          expands: field.multiline,
                          style: fittedStyle,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 1),
                          ),
                          onChanged: (value) {
                            setState(() => _value = value);
                            widget.sheetController.setText(field.name, value);
                          },
                        )
                      : _IdleFieldValue(
                          value: _value,
                          field: field,
                          textAlign: alignment,
                          style: fittedStyle,
                          locked: locked,
                          onTap: _startEditing,
                        );
                },
              ),
            ),
          ),
          _CommentDot(
            listenable: widget.sheetController.commentStateFor(field.name),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _removeGlobalPointerRoute();
    _focusNode
      ?..removeListener(_handleFocus)
      ..dispose();
    _textController?.dispose();
    super.dispose();
  }
}

class _IdleFieldValue extends StatelessWidget {
  const _IdleFieldValue({
    required this.value,
    required this.field,
    required this.textAlign,
    required this.style,
    required this.locked,
    required this.onTap,
  });

  final String value;
  final SheetFieldDef field;
  final TextAlign textAlign;
  final TextStyle style;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final horizontalAlignment = switch (textAlign) {
      TextAlign.center => 0.0,
      TextAlign.right => 1.0,
      _ => -1.0,
    };
    return MouseRegion(
      cursor: locked ? MouseCursor.defer : SystemMouseCursors.text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: locked ? null : onTap,
        child: ClipRect(
          child: Align(
            alignment: Alignment(horizontalAlignment, field.multiline ? -1 : 0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: RichText(
                text: buildInlineMarkdownSpan(value, style),
                textAlign: textAlign,
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: field.multiline ? null : 1,
                overflow: TextOverflow.clip,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _fittedTextStyle({
  required String text,
  required TextStyle baseStyle,
  required double maxWidth,
  required double maxHeight,
  required bool multiline,
  required TextAlign textAlign,
  required TextDirection textDirection,
  required TextScaler textScaler,
  required bool markdown,
}) {
  final maximum = baseStyle.fontSize ?? 14;
  if (text.isEmpty || maxWidth <= 0 || maxHeight <= 0) return baseStyle;

  bool fits(double fontSize) {
    final style = baseStyle.copyWith(fontSize: fontSize);
    final span = markdown
        ? buildInlineMarkdownSpan(text, style)
        : TextSpan(text: text, style: style);
    final painter = TextPainter(
      text: span,
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: multiline ? null : 1,
    );

    if (multiline) {
      painter.layout(maxWidth: maxWidth);
    } else {
      // Measure a single line at its natural width. Laying it out directly at
      // maxWidth can hide horizontal overflow behind the maxLines constraint.
      painter.layout(maxWidth: double.infinity);
    }
    // A multiline paragraph must keep the complete field width so it wraps
    // naturally. Its font only needs to shrink when the wrapped lines exceed
    // the available height. Single-line fields instead need width headroom for
    // small font-metric differences and the editing cursor.
    final fitsWidth = multiline
        ? painter.width <= maxWidth + .01
        : painter.width <= maxWidth * _textFitSafetyFactor + .01;
    final effectiveMaxHeight = multiline
        ? maxHeight
        : maxHeight * _textFitSafetyFactor;
    return !painter.didExceedMaxLines &&
        fitsWidth &&
        painter.height <= effectiveMaxHeight + .01;
  }

  if (fits(maximum)) return baseStyle;

  var low = _minimumFieldFontSize;
  var high = maximum;
  if (!fits(low)) return baseStyle.copyWith(fontSize: low);
  for (var i = 0; i < 10; i++) {
    final middle = (low + high) / 2;
    if (fits(middle)) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return baseStyle.copyWith(fontSize: low);
}

class _CommentDot extends StatelessWidget {
  const _CommentDot({required this.listenable});
  final ValueListenable<bool> listenable;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: listenable,
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
  );
}
