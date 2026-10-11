import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/sheet_controller.dart';
import '../data/character_repository.dart';
import '../models/character.dart';
import '../models/sheet_field.dart';
import '../models/sheet_layout.dart';
import '../sync/google_drive_sync_service.dart';
import '../widgets/dice_roller_overlay.dart';
import '../widgets/sheet_page.dart';
import '../widgets/theme_mode_button.dart';
import '../theme/sheet_palette.dart';

class SheetScreen extends StatefulWidget {
  const SheetScreen({
    super.key,
    required this.character,
    required this.repository,
    required this.driveSync,
  });

  final Character character;
  final CharacterRepository repository;
  final GoogleDriveSyncService driveSync;

  @override
  State<SheetScreen> createState() => _SheetScreenState();
}

class _SheetScreenState extends State<SheetScreen> {
  late final SheetController _sheetController;
  late final Future<List<List<SheetFieldDef>>> _fields;
  bool _allowPop = false;
  bool _exiting = false;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _sheetController = SheetController(
      repository: widget.repository,
      character: widget.character,
    );
    _fields = SheetFieldDef.loadByPage();
  }

  Future<void> _exit() async {
    // La guardia va alzata prima di qualsiasi await: il pulsante indietro e il
    // gesto di sistema possono arrivare insieme, e due uscite concorrenti
    // farebbero due pop, chiudendo anche l'elenco dei personaggi.
    if (_allowPop || _exiting) return;
    // Un indietro con la tastiera aperta termina solo l'input, senza chiudere
    // il controller della scheda. Leggi le metriche correnti anche se il campo
    // ha già perso il focus al pointer-down sul pulsante Indietro.
    if (View.of(context).viewInsets.bottom > 0) {
      FocusScope.of(context).unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      return;
    }
    _exiting = true;
    try {
      await _sheetController.close();
    } catch (_) {
      _exiting = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Salvataggio non riuscito. Riprova tra poco.'),
          ),
        );
      }
      return;
    }
    // Le modifiche sono già al sicuro nell'archivio locale: il viaggio di rete
    // verso Drive non deve trattenere la navigazione.
    unawaited(widget.driveSync.syncPendingChanges());
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  Future<void> _toggleLock() async {
    try {
      await _sheetController.toggleLock();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Stato non ancora salvato: nuovo tentativo in corso.',
            ),
          ),
        );
      }
    }
  }

  void _changePage(int pageIndex) {
    if (pageIndex < 0 ||
        pageIndex >= sheetPageCount ||
        pageIndex == _pageIndex) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _pageIndex = pageIndex);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _exit();
    },
    child: Scaffold(
      backgroundColor: SheetPalette.of(context).workspace,
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Material(
          elevation: 3,
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Pagina precedente',
                  onPressed: _pageIndex > 0
                      ? () => _changePage(_pageIndex - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      'Pagina ${_pageIndex + 1} di $sheetPageCount',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Pagina successiva',
                  onPressed: _pageIndex < sheetPageCount - 1
                      ? () => _changePage(_pageIndex + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: FutureBuilder<List<List<SheetFieldDef>>>(
              future: _fields,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Card(
                      margin: const EdgeInsets.all(32),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Impossibile caricare il layout della scheda.\n'
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 64, 12, 88),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SheetPage(
                          key: ValueKey(_pageIndex),
                          pageIndex: _pageIndex,
                          fields: snapshot.data![_pageIndex],
                          controller: _sheetController,
                          // La pagina intera resta visibile anche quando la
                          // tastiera riduce l'area disponibile.
                          onFieldFocused: (_) {},
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'back',
                    onPressed: _exit,
                    tooltip: 'Indietro',
                    child: const Icon(Icons.arrow_back),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Material(
                        color: Theme.of(context).colorScheme.surface,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: const ThemeModeButton(),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<bool>(
                        valueListenable: _sheetController.lockedState,
                        builder: (context, locked, _) =>
                            FloatingActionButton.small(
                              heroTag: 'lock',
                              onPressed: _toggleLock,
                              tooltip: locked
                                  ? 'Sblocca scheda'
                                  : 'Blocca scheda',
                              child: Icon(
                                locked ? Icons.lock : Icons.lock_open,
                              ),
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Positioned.fill(child: DiceRollerOverlay()),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    unawaited(_closeAndDisposeController());
    super.dispose();
  }

  Future<void> _closeAndDisposeController() async {
    try {
      await _sheetController.close();
    } catch (_) {
      // The save was attempted; the route no longer has UI for reporting it.
    } finally {
      _sheetController.dispose();
    }
  }
}
