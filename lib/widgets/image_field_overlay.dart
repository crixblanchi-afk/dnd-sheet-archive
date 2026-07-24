import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../controllers/sheet_controller.dart';

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

  Uint8List? get _imageBytes {
    final stored = widget.sheetController.valueFor(widget.fieldName);
    if (stored is! String || stored.isEmpty) return null;
    try {
      return base64Decode(stored);
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
      if (bytes != null) {
        widget.sheetController.setText(widget.fieldName, base64Encode(bytes));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearImage() {
    if (widget.sheetController.locked) return;
    widget.sheetController.setText(widget.fieldName, '');
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
              : Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
        ),
      );
    },
  );
}
