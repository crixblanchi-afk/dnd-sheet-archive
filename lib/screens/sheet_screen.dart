import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/sheet_controller.dart';
import '../data/character_repository.dart';
import '../data/sheet_view_preferences.dart';
import '../models/character.dart';
import '../models/game_system.dart';
import '../models/sheet_document.dart';
import '../sync/google_drive_sync_service.dart';
import '../theme/sheet_palette.dart';
import '../widgets/daggerheart_cards_page.dart';
import '../widgets/daggerheart_vertical_sheet_view.dart';
import '../widgets/dice_roller_overlay.dart';
import '../widgets/scrollable_sheet_view.dart';
import '../widgets/sheet_page.dart';
import '../widgets/theme_mode_button.dart';
import '../widgets/vertical_sheet_view.dart';

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
  SheetDocumentDef? _loadedDocument;
  Object? _fieldsError;
  late final VoidCallback _removeExitTask;
  bool _allowPop = false;
  bool _exiting = false;
  int _pageIndex = 0;
  SheetViewPreferences? _viewPreferences;
  bool _initializedViewMode = false;
  SheetViewMode _viewMode = SheetViewMode.pages;
  bool _showOverlayCards = false;
  PageController _pageController = PageController();

  bool get _isDaggerheart => widget.character.system == GameSystem.daggerheart;

  int get _totalPageCount => _loadedDocument?.totalPageCount ?? 1;

  /// Le pagine della vista a pagine, costruite una volta per indice.
  ///
  /// Tutto lo schermo sta sotto un `LayoutBuilder`, che riparte a ogni
  /// variazione del viewport — l'animazione della tastiera, il
  /// ridimensionamento della finestra — e il `PageView` richiama il proprio
  /// builder ogni volta: riconsegnare la stessa istanza evita di ricostruire
  /// tutti i campi della pagina a ogni fotogramma.
  final _pagedPages = <int, Widget>{};
  SheetDocumentDef? _pagedDocument;

  Widget _pagedPage(SheetDocumentDef document, int page, bool compactLayout) {
    if (document.hasCardsPage && page == document.pdfPageCount) {
      return _KeepAlivePage(
        child: Semantics(
          label: 'Card',
          child: DaggerheartCardsPage(
            key: const ValueKey('daggerheart-cards-page'),
            controller: _sheetController,
            compactLayout: compactLayout,
          ),
        ),
      );
    }
    if (!identical(_pagedDocument, document)) {
      _pagedDocument = document;
      _pagedPages.clear();
    }
    final spec = document.pages[page];
    return _pagedPages[page] ??= _KeepAlivePage(
      child: Semantics(
        label: 'Pagina ${page + 1} di ${document.totalPageCount}',
        child: FittedBox(
          fit: BoxFit.contain,
          child: SheetPage(
            key: ValueKey(page),
            pageIndex: page,
            fields: spec.fields,
            lightAsset: spec.lightAsset,
            darkAsset: spec.darkAsset,
            imageFields: spec.imageFields,
            controller: _sheetController,
            onFieldFocused: (_) {},
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _sheetController = SheetController(
      repository: widget.repository,
      character: widget.character,
    );
    unawaited(
      SheetDocumentDef.loadFor(widget.character).then(
        (document) {
          _loadedDocument = document;
          if (!mounted) return;
          if (_viewMode != SheetViewMode.vertical) {
            _precacheArtwork();
            setState(() {});
          }
        },
        onError: (Object error) {
          _fieldsError = error;
          if (mounted && _viewMode != SheetViewMode.vertical) {
            setState(() {});
          }
        },
      ),
    );
    // Chiudere la finestra su desktop non passa dal pulsante indietro: la
    // sessione va salvata prima che il processo termini.
    _removeExitTask = widget.driveSync.addExitTask(
      () => _sheetController.finishEditingSession('session'),
    );
    // Chi apre una scheda vuole vederla aggiornata con le modifiche fatte su
    // un altro dispositivo, senza aspettare il prossimo giro del sync.
    unawaited(widget.driveSync.syncInBackground());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewPreferences = SheetViewPreferenceScope.maybeOf(context);
    _viewPreferences = viewPreferences;
    if (viewPreferences != null && _viewMode != viewPreferences.mode) {
      if (_initializedViewMode && viewPreferences.mode == SheetViewMode.pages) {
        _pageController.dispose();
        _pageController = PageController(initialPage: _pageIndex);
      }
      _viewMode = viewPreferences.mode;
    }
    _initializedViewMode = true;
    if (_viewMode != SheetViewMode.vertical) {
      _precacheArtwork();
    }
  }

  void _precacheArtwork() {
    final document = _loadedDocument;
    if (document == null) return;
    // Le pagine non ancora viste vanno decodificate prima dello swipe che le
    // porta in vista, altrimenti compaiono bianche per qualche fotogramma.
    // Gira di nuovo se cambiano tema o densità dello schermo, cioè l'artwork.
    for (var page = 0; page < document.pages.length; page++) {
      final spec = document.pages[page];
      unawaited(
        precacheImage(
          SheetArtwork.imageFor(
            context,
            page,
            lightAsset: spec.lightAsset,
            darkAsset: spec.darkAsset,
          ),
          context,
        ),
      );
    }
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
    unawaited(widget.driveSync.syncInBackground());
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
        pageIndex >= _totalPageCount ||
        pageIndex == _pageIndex) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _pageIndex = pageIndex);
  }

  void _goToPage(int pageIndex) {
    if (pageIndex < 0 ||
        pageIndex >= _totalPageCount ||
        pageIndex == _pageIndex) {
      return;
    }
    FocusScope.of(context).unfocus();
    if (_pageController.hasClients) {
      // Cambio secco in un solo fotogramma: evita frame intermedi su schermi E-Ink.
      _pageController.jumpToPage(pageIndex);
    } else {
      setState(() => _pageIndex = pageIndex);
    }
  }

  String _pageIndicatorLabel(SheetDocumentDef document) {
    final counter = '${_pageIndex + 1} / ${document.totalPageCount}';
    if (!_isDaggerheart) return counter;
    final label = _pageIndex < document.pages.length
        ? document.pages[_pageIndex].label
        : 'Card';
    return '$counter · $label';
  }

  Widget _pageNavigationButtons() {
    final document = _loadedDocument;
    if (document == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final total = document.totalPageCount;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      shape: StadiumBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Pagina precedente',
            onPressed: _pageIndex > 0 ? () => _goToPage(_pageIndex - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            _pageIndicatorLabel(document),
            style: theme.textTheme.labelLarge?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            tooltip: 'Pagina successiva',
            onPressed: _pageIndex < total - 1
                ? () => _goToPage(_pageIndex + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _cardsToggleButton() {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _sheetController,
      builder: (context, _) {
        final count = _sheetController.selectedCardCount;
        return Material(
          color: _showOverlayCards
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface,
          elevation: 2,
          shape: StadiumBorder(
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: InkWell(
            key: const ValueKey('dh-scroll-cards-toggle'),
            customBorder: const StadiumBorder(),
            onTap: () {
              FocusScope.of(context).unfocus();
              setState(() => _showOverlayCards = !_showOverlayCards);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showOverlayCards
                        ? Icons.description_outlined
                        : Icons.style_outlined,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _showOverlayCards ? 'Scheda' : 'Card ($count)',
                    style: theme.textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _setViewMode(SheetViewMode mode) async {
    if (_viewMode != mode) {
      FocusScope.of(context).unfocus();
      final previousMode = _viewMode;
      _viewMode = mode;
      if (mode == SheetViewMode.pages) {
        _showOverlayCards = false;
        _pageController.dispose();
        _pageController = PageController(initialPage: _pageIndex);
      }
      if (previousMode == SheetViewMode.vertical &&
          mode != SheetViewMode.vertical) {
        _precacheArtwork();
      }
      setState(() {});
    }
    final preferences = _viewPreferences;
    if (preferences == null) return;
    try {
      await preferences.setMode(mode);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Visualizzazione applicata, ma non salvata. Riprova.'),
        ),
      );
    }
  }

  Widget _viewModeButton() => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: const CircleBorder(),
    elevation: 2,
    child: PopupMenuButton<SheetViewMode>(
      tooltip: 'Visualizzazione scheda',
      initialValue: _viewMode,
      icon: Icon(switch (_viewMode) {
        SheetViewMode.pages => Icons.view_carousel_outlined,
        SheetViewMode.scroll => Icons.view_day_outlined,
        SheetViewMode.vertical => Icons.smartphone_outlined,
      }),
      onSelected: _setViewMode,
      itemBuilder: (_) => [
        for (final mode in SheetViewMode.values)
          CheckedPopupMenuItem(
            value: mode,
            checked: _viewMode == mode,
            child: Text(mode.label),
          ),
      ],
    ),
  );

  Widget _buildPdfSheetBody(BuildContext context, bool compactLayout) {
    final error = _fieldsError;
    if (error != null) {
      return Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Impossibile caricare il layout della scheda.\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final document = _loadedDocument;
    if (document == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viewMode == SheetViewMode.scroll) {
      if (document.hasCardsPage && _showOverlayCards) {
        return DaggerheartCardsPage(
          key: const ValueKey('daggerheart-cards-page-scroll'),
          controller: _sheetController,
          compactLayout: compactLayout,
        );
      }
      return ScrollableSheetView(
        controller: _sheetController,
        fields: document.fieldsByPage,
        pages: document.pages,
        initialPage: _pageIndex.clamp(0, document.pages.length - 1),
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
        // La pagina accanto viene preparata a gesto fermo,
        // non a metà dello swipe che la porta in vista.
        allowImplicitScrolling: true,
        itemCount: document.totalPageCount,
        onPageChanged: _changePage,
        itemBuilder: (context, page) =>
            _pagedPage(document, page, compactLayout),
      ),
    );
  }

  Widget _buildVerticalBody(bool compactLayout) {
    if (!_isDaggerheart) {
      return VerticalSheetView(
        controller: _sheetController,
        compactLayout: compactLayout,
      );
    }
    if (_showOverlayCards) {
      return DaggerheartCardsPage(
        key: const ValueKey('daggerheart-cards-page-vertical'),
        controller: _sheetController,
        compactLayout: compactLayout,
      );
    }
    return DaggerheartVerticalSheetView(
      controller: _sheetController,
      compactLayout: compactLayout,
      onManageCards: () {
        FocusScope.of(context).unfocus();
        setState(() => _showOverlayCards = true);
      },
    );
  }

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
                  child: _viewMode == SheetViewMode.vertical
                      ? _buildVerticalBody(compactLayout)
                      : _buildPdfSheetBody(context, compactLayout),
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
                          if (_isDaggerheart &&
                              _viewMode != SheetViewMode.pages) ...[
                            _cardsToggleButton(),
                            const SizedBox(width: 8),
                          ],
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
                    child: DiceRollerOverlay(showDualityRoll: _isDaggerheart),
                  ),
                ),
                if (_viewMode == SheetViewMode.pages && !compactLayout)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: _pageNavigationButtons(),
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
    _removeExitTask();
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

/// Una pagina della vista a pagine che resta viva quando esce di vista.
///
/// Ricostruirla a ogni swipe significherebbe ricreare centinaia di campi nel
/// fotogramma in cui il gesto comincia.
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
