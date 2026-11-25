import 'package:flutter/material.dart';

Future<void> showFieldCommentDialog({
  required BuildContext context,
  required String fieldName,
  required String? initialValue,
  required bool readOnly,
  required ValueChanged<String> onSave,
}) => showDialog<void>(
  context: context,
  builder: (context) => _FieldCommentDialog(
    fieldName: fieldName,
    initialValue: initialValue,
    readOnly: readOnly,
    onSave: onSave,
  ),
);

class _FieldCommentDialog extends StatefulWidget {
  const _FieldCommentDialog({
    required this.fieldName,
    required this.initialValue,
    required this.readOnly,
    required this.onSave,
  });

  final String fieldName;
  final String? initialValue;
  final bool readOnly;
  final ValueChanged<String> onSave;

  @override
  State<_FieldCommentDialog> createState() => _FieldCommentDialogState();
}

class _FieldCommentDialogState extends State<_FieldCommentDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.fieldName),
    content: SizedBox(
      width: 420,
      child: TextField(
        controller: _controller,
        readOnly: widget.readOnly,
        autofocus: !widget.readOnly,
        minLines: 3,
        maxLines: 8,
        decoration: const InputDecoration(
          hintText: 'Nota sul campo…',
          border: OutlineInputBorder(),
        ),
      ),
    ),
    actions: [
      if (!widget.readOnly && (widget.initialValue?.isNotEmpty ?? false))
        TextButton(
          onPressed: () {
            widget.onSave('');
            Navigator.pop(context);
          },
          child: const Text('Rimuovi'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.readOnly ? 'Chiudi' : 'Annulla'),
      ),
      if (!widget.readOnly)
        FilledButton(
          onPressed: () {
            widget.onSave(_controller.text);
            Navigator.pop(context);
          },
          child: const Text('Salva'),
        ),
    ],
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
