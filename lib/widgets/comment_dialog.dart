import 'package:flutter/material.dart';

Future<void> showFieldCommentDialog({
  required BuildContext context,
  required String fieldName,
  required String? initialValue,
  required bool readOnly,
  required ValueChanged<String> onSave,
}) async {
  final controller = TextEditingController(text: initialValue ?? '');
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(fieldName),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: controller,
          readOnly: readOnly,
          autofocus: !readOnly,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'Nota sul campo…',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        if (!readOnly && (initialValue?.isNotEmpty ?? false))
          TextButton(
            onPressed: () {
              onSave('');
              Navigator.pop(context);
            },
            child: const Text('Rimuovi'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(readOnly ? 'Chiudi' : 'Annulla'),
        ),
        if (!readOnly)
          FilledButton(
            onPressed: () {
              onSave(controller.text);
              Navigator.pop(context);
            },
            child: const Text('Salva'),
          ),
      ],
    ),
  );
  controller.dispose();
}
