import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/character_repository.dart';
import '../models/character_version.dart';

class VersionHistorySheet extends StatefulWidget {
  const VersionHistorySheet({
    super.key,
    required this.characterId,
    required this.repository,
  });

  final String characterId;
  final CharacterRepository repository;

  @override
  State<VersionHistorySheet> createState() => _VersionHistorySheetState();
}

class _VersionHistorySheetState extends State<VersionHistorySheet> {
  late Future<List<VersionMeta>> _versions;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _versions = widget.repository.listVersions(widget.characterId);
  }

  String _reason(String value) => switch (value) {
    'lock' => 'blocco',
    'pre-restore' => 'prima del ripristino',
    _ => 'sessione',
  };

  Future<void> _restore(VersionMeta version) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ripristinare questa versione?'),
        content: const Text(
          'Lo stato corrente verrà conservato come nuova versione.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ripristina'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.restoreVersion(widget.characterId, version.id);
    if (!mounted) return;
    setState(_reload);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Versione ripristinata')));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Cronologia versioni',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Flexible(
            child: FutureBuilder<List<VersionMeta>>(
              future: _versions,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final versions = snapshot.data!;
                if (versions.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Nessuna versione salvata.'),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: versions.length,
                  itemBuilder: (context, index) {
                    final version = versions[index];
                    return ListTile(
                      title: Text(
                        DateFormat(
                          'dd/MM/yyyy, HH:mm',
                        ).format(version.createdAt.toLocal()),
                      ),
                      subtitle: Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(_reason(version.reason)),
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: () => _restore(version),
                        child: const Text('Ripristina'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
