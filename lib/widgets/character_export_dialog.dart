import 'package:flutter/material.dart';

import '../models/character.dart';

class CharacterExportDialog extends StatefulWidget {
  const CharacterExportDialog({super.key, required this.characters});

  final List<CharacterSummary> characters;

  @override
  State<CharacterExportDialog> createState() => _CharacterExportDialogState();
}

class _CharacterExportDialogState extends State<CharacterExportDialog> {
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Esporta schede'),
    content: SizedBox(
      width: 440,
      height: 360,
      child: ListView(
        children: [
          const Text(
            'Seleziona una o più schede. Verranno salvate in un unico PDF '
            'compilabile, con tre pagine per personaggio.',
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Seleziona tutte'),
            tristate: true,
            value: _selected.isEmpty
                ? false
                : _selected.length == widget.characters.length
                ? true
                : null,
            onChanged: (_) => setState(() {
              if (_selected.length == widget.characters.length) {
                _selected.clear();
              } else {
                _selected.addAll(widget.characters.map((item) => item.id));
              }
            }),
          ),
          for (final item in widget.characters)
            CheckboxListTile(
              key: ValueKey('export-${item.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(item.name),
              value: _selected.contains(item.id),
              onChanged: (checked) => setState(() {
                if (checked == true) {
                  _selected.add(item.id);
                } else {
                  _selected.remove(item.id);
                }
              }),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.pop(
                context,
                widget.characters
                    .where((item) => _selected.contains(item.id))
                    .map((item) => item.id)
                    .toList(),
              ),
        child: Text('Esporta (${_selected.length})'),
      ),
    ],
  );
}
