import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/character_repository.dart';
import '../models/character.dart';
import '../sync/google_drive_sync_service.dart';
import '../widgets/version_history_sheet.dart';
import 'sheet_screen.dart';

enum _CharacterAction { rename, history, delete }

enum _DriveAction { sync, signOut }

class CharacterListScreen extends StatefulWidget {
  const CharacterListScreen({
    super.key,
    required this.repository,
    required this.driveSync,
  });

  final CharacterRepository repository;
  final GoogleDriveSyncService driveSync;

  @override
  State<CharacterListScreen> createState() => _CharacterListScreenState();
}

class _CharacterListScreenState extends State<CharacterListScreen> {
  CharacterRepository get repository => widget.repository;

  @override
  void initState() {
    super.initState();
    widget.driveSync.addListener(_syncStateChanged);
  }

  @override
  void dispose() {
    widget.driveSync.removeListener(_syncStateChanged);
    super.dispose();
  }

  void _syncStateChanged() {
    if (mounted) setState(() {});
  }

  Future<String?> _askName(
    BuildContext context, {
    String initialValue = '',
    required String title,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nome'),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _open(BuildContext context, Character character) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SheetScreen(
          character: character,
          repository: repository,
          driveSync: widget.driveSync,
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final name = await _askName(context, title: 'Nuovo personaggio');
    if (name == null || !context.mounted) return;
    final character = await repository.createCharacter(name);
    if (context.mounted) await _open(context, character);
  }

  Future<void> _action(
    BuildContext context,
    CharacterSummary item,
    _CharacterAction action,
  ) async {
    switch (action) {
      case _CharacterAction.rename:
        final name = await _askName(
          context,
          initialValue: item.name,
          title: 'Rinomina personaggio',
        );
        if (name != null) await repository.renameCharacter(item.id, name);
      case _CharacterAction.history:
        if (!context.mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          constraints: const BoxConstraints(maxHeight: 620),
          builder: (_) =>
              VersionHistorySheet(characterId: item.id, repository: repository),
        );
      case _CharacterAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Eliminare il personaggio?'),
            content: Text(
              '“${item.name}” e tutta la sua cronologia verranno eliminati.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Elimina'),
              ),
            ],
          ),
        );
        if (confirmed == true) await repository.deleteCharacter(item.id);
    }
  }

  Future<void> _performDriveAction(_DriveAction action) async {
    if (action == _DriveAction.signOut) {
      await widget.driveSync.signOut();
      return;
    }
    try {
      final result = await widget.driveSync.sync();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Google Drive sincronizzato: ${result.characters} schede, '
            '${result.versions} versioni.',
          ),
        ),
      );
    } on GoogleDriveSignInRequired {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Accesso Google annullato.')),
      );
    } on GoogleDriveConfigurationMissing {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Configura Google Drive'),
          content: const Text(
            'Questa build non contiene il client OAuth Google. Consulta la '
            'sezione “Google Drive” del README e avvia la build con il '
            'relativo --dart-define.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.driveSync.errorMessage ??
                'Sincronizzazione con Google Drive non riuscita.',
          ),
        ),
      );
    }
  }

  Widget _driveAction() {
    if (widget.driveSync.state == GoogleDriveSyncState.syncing) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    final user = widget.driveSync.currentUser;
    final icon = switch (widget.driveSync.state) {
      GoogleDriveSyncState.success => Icons.cloud_done_outlined,
      GoogleDriveSyncState.error ||
      GoogleDriveSyncState.configurationMissing => Icons.cloud_off_outlined,
      _ => Icons.cloud_sync_outlined,
    };
    return PopupMenuButton<_DriveAction>(
      tooltip: 'Sincronizzazione Google Drive',
      icon: Icon(icon),
      onSelected: _performDriveAction,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _DriveAction.sync,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.sync),
            title: Text('Sincronizza ora'),
          ),
        ),
        if (widget.driveSync.isConnected) ...[
          if (user != null)
            PopupMenuItem<_DriveAction>(
              enabled: false,
              child: Text(user.email, overflow: TextOverflow.ellipsis),
            ),
          const PopupMenuItem(
            value: _DriveAction.signOut,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.logout),
              title: Text('Disconnetti Google'),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Schede D&D 5e'),
      actions: [_driveAction()],
    ),
    body: StreamBuilder<List<CharacterSummary>>(
      stream: repository.watchCharacters(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final characters = snapshot.data!;
        if (characters.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Nessun personaggio.\nTocca + per creare la prima scheda.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: characters.length,
          itemBuilder: (context, index) {
            final item = characters[index];
            return ListTile(
              leading: CircleAvatar(
                child: Icon(item.locked ? Icons.lock : Icons.person),
              ),
              title: Text(item.name),
              subtitle: Text(
                'Modificato il ${DateFormat('dd/MM/yyyy, HH:mm').format(item.updatedAt.toLocal())}',
              ),
              onTap: () async {
                final character = await repository.getCharacter(item.id);
                if (character != null && context.mounted) {
                  await _open(context, character);
                }
              },
              trailing: PopupMenuButton<_CharacterAction>(
                onSelected: (action) => _action(context, item, action),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _CharacterAction.rename,
                    child: Text('Rinomina'),
                  ),
                  PopupMenuItem(
                    value: _CharacterAction.history,
                    child: Text('Cronologia versioni'),
                  ),
                  PopupMenuItem(
                    value: _CharacterAction.delete,
                    child: Text('Elimina'),
                  ),
                ],
              ),
            );
          },
        );
      },
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () => _create(context),
      tooltip: 'Nuovo personaggio',
      child: const Icon(Icons.add),
    ),
  );
}
