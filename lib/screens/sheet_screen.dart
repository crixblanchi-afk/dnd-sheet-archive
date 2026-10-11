import 'dart:async';

import 'package:flutter/gestures.dart';
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
import '../widgets/scrollable_sheet_view.dart';
import '../widgets/theme_mode_button.dart';
import '../theme/sheet_palette.dart';

enum _SheetViewMode { pages, scroll }

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
  _SheetViewMode _viewMode = _SheetViewMode.pages;
  PageController _pageController = PageController();

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

  void _setViewMode(_SheetViewMode mode) {
    if (_viewMode == mode) return;
    FocusScope.of(context).unfocus();
    if (mode == _SheetViewMode.pages) {
      _pageController.dispose();
      _pageController = PageController(initialPage: _pageIndex);
    }
    setState(() => _viewMode = mode);
  }

  Widget _viewModeButton() => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: const CircleBorder(),
    elevation: 2,
    child: PopupMenuButton<_SheetViewMode>(
      tooltip: 'Visualizzazione scheda',
      initialValue: _viewMode,
      icon: Icon(
        _viewMode == _SheetViewMode.pages
            ? Icons.view_carousel_outlined
            : Icons.view_day_outlined,
      ),
      onSelected: _setViewMode,
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: _SheetViewMode.pages,
          checked: _viewMode == _SheetViewMode.pages,
          child: const Text('A pagine'),
        ),
        CheckedPopupMenuItem(
          value: _SheetViewMode.scroll,
          checked: _viewMode == _SheetViewMode.scroll,
          child: const Text('A scorrimento'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _exit();
    },
    child: Scaffold(
      backgroundColor: SheetPalette.of(context).workspace,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compactLayout = constraints.maxHeight < 240;
            return Stack(
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
                      if (_viewMode == _SheetViewMode.scroll) {
                        return ScrollableSheetView(
                          controller: _sheetController,
                          fields: snapshot.data!,
                          initialPage: _pageIndex,
                        );
                      }
                      return ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          dragDevices: {
                            ...ScrollConfiguration.of(context).dragDevices,
                            PointerDeviceKind.mouse,
                          },
                        ),
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: sheetPageCount,
                          onPageChanged: _changePage,
                          itemBuilder: (context, page) => Semantics(
                            label: 'Pagina ${page + 1} di $sheetPageCount',
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: SheetPage(
                                key: ValueKey(page),
                                pageIndex: page,
                                fields: snapshot.data![page],
                                controller: _sheetController,
                                onFieldFocused: (_) {},
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: compactLayout ? 0 : 12,
                  ),
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
                          _viewModeButton(),
                          const SizedBox(width: 8),
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
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: compactLayout ? 240 : constraints.maxHeight,
                  child: Offstage(
                    offstage: compactLayout,
                    child: const DiceRollerOverlay(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _pageController.dispose();
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
