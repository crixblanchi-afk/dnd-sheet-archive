import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/sheet_controller.dart';
import '../models/daggerheart_card.dart';
import '../models/game_system.dart';
import '../theme/sheet_palette.dart';

enum _CardsViewTab { selected, catalog }

/// Pagina dedicata alle card di Daggerheart: mostra le card selezionate per il
/// personaggio e permette di sceglierle dal catalogo filtrabile e ricercabile.
class DaggerheartCardsPage extends StatefulWidget {
  const DaggerheartCardsPage({
    super.key,
    required this.controller,
    this.compactLayout = false,
  });

  final SheetController controller;
  final bool compactLayout;

  @override
  State<DaggerheartCardsPage> createState() => _DaggerheartCardsPageState();
}

class _DaggerheartCardsPageState extends State<DaggerheartCardsPage> {
  List<DaggerheartCardDef>? _catalog;
  Object? _catalogError;
  _CardsViewTab _tab = _CardsViewTab.selected;
  final _searchController = TextEditingController();
  String _query = '';
  DaggerheartCardCategory? _categoryFilter;
  String? _domainFilter;
  int? _levelFilter;
  bool _onlyClassRelevant = false;

  DaggerheartClass? get _characterClass =>
      widget.controller.character.daggerheartClass;

  bool get _hasSpecificClass =>
      _characterClass != null && _characterClass != DaggerheartClass.blank;

  @override
  void initState() {
    super.initState();
    _catalog = DaggerheartCardDef.cachedCatalog;
    if (_catalog == null) {
      unawaited(
        DaggerheartCardDef.loadCatalog().then(
          (cards) {
            if (!mounted) return;
            setState(() => _catalog = cards);
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() => _catalogError = error);
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DaggerheartCardDef> _filteredCatalog(List<DaggerheartCardDef> all) {
    final normalized = _query.trim().toLowerCase();
    final cls = _characterClass;
    return [
      for (final card in all)
        if (_matchesFilters(card, normalized, cls)) card,
    ];
  }

  bool _matchesFilters(
    DaggerheartCardDef card,
    String normalizedQuery,
    DaggerheartClass? cls,
  ) {
    if (_categoryFilter != null && card.category != _categoryFilter) {
      return false;
    }
    if (_onlyClassRelevant && cls != null && cls != DaggerheartClass.blank) {
      if (card.category == DaggerheartCardCategory.subclass &&
          card.className != cls.id) {
        return false;
      }
      if (card.category == DaggerheartCardCategory.domain &&
          !cls.domains.contains(card.domain)) {
        return false;
      }
    }
    if (_domainFilter != null) {
      if (card.category != DaggerheartCardCategory.domain ||
          card.domain != _domainFilter) {
        return false;
      }
    }
    if (_levelFilter != null) {
      if (card.category != DaggerheartCardCategory.domain ||
          card.level != _levelFilter) {
        return false;
      }
    }
    return card.matchesQuery(normalizedQuery);
  }

  Future<void> _showCardPreview(DaggerheartCardDef card) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: Listenable.merge([
          widget.controller,
          widget.controller.lockedState,
        ]),
        builder: (context, _) {
          final locked = widget.controller.locked;
          final state = widget.controller.cardStateFor(card.id);
          final isDomain = card.category == DaggerheartCardCategory.domain;
          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460, maxHeight: 740),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                card.title,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                card.subtitle,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Chiudi',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 3.5,
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 5 / 7,
                              child: Image.asset(
                                card.asset,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.medium,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (isDomain && state.isSelected)
                          OutlinedButton.icon(
                            onPressed: locked
                                ? null
                                : () => widget.controller.setCardState(
                                    card.id,
                                    state == DaggerheartCardState.vault
                                        ? DaggerheartCardState.loadout
                                        : DaggerheartCardState.vault,
                                  ),
                            icon: Icon(
                              state == DaggerheartCardState.vault
                                  ? Icons.bolt_outlined
                                  : Icons.inventory_2_outlined,
                            ),
                            label: Text(
                              state == DaggerheartCardState.vault
                                  ? 'Sposta in Loadout'
                                  : 'Sposta in Vault',
                            ),
                          ),
                        FilledButton.icon(
                          onPressed: locked
                              ? null
                              : () => widget.controller.toggleCard(card.id),
                          icon: Icon(
                            state.isSelected
                                ? Icons.remove_circle_outline
                                : Icons.add_circle_outline,
                          ),
                          label: Text(
                            state.isSelected ? 'Rimuovi' : 'Seleziona card',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final catalog = _catalog;
    final error = _catalogError;
    return ColoredBox(
      color: palette.paper,
      child: Column(
        children: [
          // Spazio riservato ai controlli fluttuanti in alto di SheetScreen.
          SizedBox(height: widget.compactLayout ? 48 : 64),
          Expanded(
            child: error != null
                ? Center(
                    child: Card(
                      margin: const EdgeInsets.all(24),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Impossibile caricare il catalogo delle card.\n$error',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                : catalog == null
                ? const Center(child: CircularProgressIndicator())
                : ListenableBuilder(
                    listenable: Listenable.merge([
                      widget.controller,
                      widget.controller.lockedState,
                    ]),
                    builder: (context, _) => _buildContent(context, catalog),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<DaggerheartCardDef> catalog) {
    final selectedMap = widget.controller.selectedCards;
    final locked = widget.controller.locked;
    final palette = SheetPalette.of(context);

    final selectedCards = <DaggerheartCardDef>[
      for (final card in catalog)
        if (selectedMap.containsKey(card.id)) card,
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  SegmentedButton<_CardsViewTab>(
                    key: const ValueKey('dh-cards-tab-switcher'),
                    segments: [
                      ButtonSegment<_CardsViewTab>(
                        value: _CardsViewTab.selected,
                        icon: const Icon(Icons.style),
                        label: Text('Le mie card (${selectedCards.length})'),
                      ),
                      ButtonSegment<_CardsViewTab>(
                        value: _CardsViewTab.catalog,
                        icon: const Icon(Icons.library_add_outlined),
                        label: Text('Catalogo (${catalog.length})'),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (selection) {
                      setState(() => _tab = selection.first);
                    },
                  ),
                  if (locked)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: palette.ink.withValues(alpha: .7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Scheda bloccata',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: palette.ink.withValues(alpha: .7),
                              ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (_tab == _CardsViewTab.catalog) _buildFilterBar(context),
            Expanded(
              child: _tab == _CardsViewTab.selected
                  ? _buildSelectedView(
                      context,
                      selectedCards,
                      selectedMap,
                      locked,
                    )
                  : _buildCatalogGrid(
                      context,
                      _filteredCatalog(catalog),
                      selectedMap,
                      locked,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    final cls = _characterClass;
    final showDomainControls =
        _categoryFilter == null ||
        _categoryFilter == DaggerheartCardCategory.domain;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('dh-cards-search'),
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Cerca card per nome, dominio, classe o testo…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Pulisci ricerca',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_hasSpecificClass && cls != null)
                FilterChip(
                  key: const ValueKey('dh-filter-class'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text(
                    'Solo ${cls.label} (${cls.domains.map((d) => daggerheartDomainLabels[d] ?? d).join(' & ')})',
                  ),
                  selected: _onlyClassRelevant,
                  onSelected: (value) => setState(() {
                    _onlyClassRelevant = value;
                    if (value &&
                        _domainFilter != null &&
                        !cls.domains.contains(_domainFilter)) {
                      _domainFilter = null;
                    }
                  }),
                ),
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                label: const Text('Tutte'),
                selected: _categoryFilter == null,
                onSelected: (_) => setState(() => _categoryFilter = null),
              ),
              for (final category in DaggerheartCardCategory.values)
                ChoiceChip(
                  key: ValueKey('dh-filter-cat-${category.id}'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text(category.label),
                  selected: _categoryFilter == category,
                  onSelected: (_) => setState(() {
                    _categoryFilter = category;
                    if (category != DaggerheartCardCategory.domain) {
                      _domainFilter = null;
                      _levelFilter = null;
                    }
                  }),
                ),
            ],
          ),
          if (showDomainControls) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: const Text('Tutti i domini'),
                  selected: _domainFilter == null,
                  onSelected: (_) => setState(() => _domainFilter = null),
                ),
                for (final entry in daggerheartDomainLabels.entries)
                  if (!_onlyClassRelevant ||
                      !_hasSpecificClass ||
                      (cls?.domains.contains(entry.key) ?? true))
                    ChoiceChip(
                      key: ValueKey('dh-filter-domain-${entry.key}'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      label: Text(entry.value),
                      selected: _domainFilter == entry.key,
                      onSelected: (_) => setState(() {
                        _domainFilter = _domainFilter == entry.key
                            ? null
                            : entry.key;
                        if (_domainFilter != null) {
                          _categoryFilter = DaggerheartCardCategory.domain;
                        }
                      }),
                    ),
                DropdownButton<int?>(
                  key: const ValueKey('dh-filter-level'),
                  value: _levelFilter,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Tutti i livelli'),
                    ),
                    for (var lv = 1; lv <= 10; lv++)
                      DropdownMenuItem<int?>(
                        value: lv,
                        child: Text('Livello $lv'),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _levelFilter = value;
                    if (value != null) {
                      _categoryFilter = DaggerheartCardCategory.domain;
                    }
                  }),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedView(
    BuildContext context,
    List<DaggerheartCardDef> selectedCards,
    Map<String, DaggerheartCardState> selectedMap,
    bool locked,
  ) {
    final palette = SheetPalette.of(context);
    if (selectedCards.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.style_outlined,
                size: 56,
                color: palette.ink.withValues(alpha: .45),
              ),
              const SizedBox(height: 12),
              Text(
                'Nessuna card selezionata',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: palette.ink),
              ),
              const SizedBox(height: 6),
              Text(
                'Seleziona Ancestry, Community, Subclass e carte Domain '
                'dal catalogo Daggerheart.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.ink.withValues(alpha: .72),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('dh-open-catalog-button'),
                onPressed: () => setState(() => _tab = _CardsViewTab.catalog),
                icon: const Icon(Icons.library_add_outlined),
                label: Text(locked ? 'Sfoglia catalogo' : 'Seleziona card'),
              ),
            ],
          ),
        ),
      );
    }

    final identityCards = <DaggerheartCardDef>[];
    final loadoutDomainCards = <DaggerheartCardDef>[];
    final vaultDomainCards = <DaggerheartCardDef>[];
    for (final card in selectedCards) {
      if (card.category != DaggerheartCardCategory.domain) {
        identityCards.add(card);
      } else if (selectedMap[card.id] == DaggerheartCardState.vault) {
        vaultDomainCards.add(card);
      } else {
        loadoutDomainCards.add(card);
      }
    }

    return CustomScrollView(
      slivers: [
        if (identityCards.isNotEmpty) ...[
          _sectionHeader(
            context,
            'Ancestry, Community & Subclass (${identityCards.length})',
          ),
          _cardSliverGrid(
            identityCards,
            selectedMap,
            locked,
            catalogMode: false,
          ),
        ],
        if (loadoutDomainCards.isNotEmpty) ...[
          _sectionHeader(
            context,
            'Domain · Loadout (${loadoutDomainCards.length})',
          ),
          _cardSliverGrid(
            loadoutDomainCards,
            selectedMap,
            locked,
            catalogMode: false,
          ),
        ],
        if (vaultDomainCards.isNotEmpty) ...[
          _sectionHeader(
            context,
            'Domain · Vault (${vaultDomainCards.length})',
          ),
          _cardSliverGrid(
            vaultDomainCards,
            selectedMap,
            locked,
            catalogMode: false,
          ),
        ],
        SliverPadding(
          padding: EdgeInsets.only(bottom: widget.compactLayout ? 16 : 92),
        ),
      ],
    );
  }

  Widget _buildCatalogGrid(
    BuildContext context,
    List<DaggerheartCardDef> cards,
    Map<String, DaggerheartCardState> selectedMap,
    bool locked,
  ) {
    if (cards.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nessuna card corrisponde ai filtri selezionati.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: SheetPalette.of(context).ink.withValues(alpha: .72),
            ),
          ),
        ),
      );
    }
    return CustomScrollView(
      slivers: [
        _cardSliverGrid(cards, selectedMap, locked, catalogMode: true),
        SliverPadding(
          padding: EdgeInsets.only(bottom: widget.compactLayout ? 16 : 92),
        ),
      ],
    );
  }

  SliverPadding _sectionHeader(BuildContext context, String title) =>
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        sliver: SliverToBoxAdapter(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontFamily: 'RobotoSlab',
              fontWeight: FontWeight.w700,
              color: SheetPalette.of(context).ink,
            ),
          ),
        ),
      );

  SliverPadding _cardSliverGrid(
    List<DaggerheartCardDef> cards,
    Map<String, DaggerheartCardState> selectedMap,
    bool locked, {
    required bool catalogMode,
  }) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    sliver: SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        final state = selectedMap[card.id] ?? DaggerheartCardState.none;
        return _CardTile(
          key: ValueKey('dh-card-${card.id}'),
          card: card,
          state: state,
          locked: locked,
          catalogMode: catalogMode,
          onTap: () {
            if (catalogMode && !locked) {
              widget.controller.toggleCard(card.id);
            } else {
              unawaited(_showCardPreview(card));
            }
          },
          onZoom: () => unawaited(_showCardPreview(card)),
          onRemove: locked
              ? null
              : () => widget.controller.setCardState(
                  card.id,
                  DaggerheartCardState.none,
                ),
        );
      },
    ),
  );
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    super.key,
    required this.card,
    required this.state,
    required this.locked,
    required this.catalogMode,
    required this.onTap,
    required this.onZoom,
    this.onRemove,
  });

  final DaggerheartCardDef card;
  final DaggerheartCardState state;
  final bool locked;
  final bool catalogMode;
  final VoidCallback onTap;
  final VoidCallback onZoom;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = state.isSelected;
    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: selected ? 2.4 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    card.asset,
                    fit: BoxFit.cover,
                    cacheWidth: 360,
                    filterQuality: FilterQuality.medium,
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Material(
                      color: Colors.black.withValues(alpha: .58),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onZoom,
                        child: const Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(
                            Icons.zoom_in,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (catalogMode && selected)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.check,
                            size: 16,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    )
                  else if (!catalogMode && !locked && onRemove != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Material(
                        color: Colors.black.withValues(alpha: .58),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onRemove,
                          child: const Padding(
                            padding: EdgeInsets.all(5),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (state == DaggerheartCardState.vault)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            'Vault',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    card.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
